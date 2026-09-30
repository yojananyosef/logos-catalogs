import 'package:test/test.dart';

import 'package:amf_format/amf_contract.dart';
import 'package:amf_format/catalog_gate.dart';

AmfLicenseInfo _lic({
  AmfLicense license = AmfLicense.publicDomain,
  String attribution = '',
  String source = 'https://example.org/source',
  DateTime? release,
  Set<String> jurisdictions = const {},
  String? basis = 'Author died 1911; life+70 expired. Published 1890, pre-1931 in the US.',
}) =>
    AmfLicenseInfo(
      license: license,
      attribution: attribution,
      sourceUrl: source,
      releaseDate: release ?? DateTime.utc(1970),
      jurisdictions: jurisdictions,
      basis: basis,
    );

AmfResourceEntry _entry(String id, {AmfLicenseInfo? lic, String? sha}) =>
    AmfResourceEntry(
      id: id,
      type: 'bible',
      name: 'Test $id',
      shortName: id,
      language: 'en',
      version: '1.0.0',
      license: lic ?? _lic(),
      sha256: sha ?? 'a' * 64,
      sizeBytes: 1024,
      downloadUrl: 'https://example.org/$id.amod',
    );

AmfCatalog _catalog(List<AmfResourceEntry> entries) => AmfCatalog(
      format: amfCatalogFormat,
      version: '1.0.0',
      entries: entries,
    );

void main() {
  final beforeRelease = DateTime.utc(2026, 9, 29);

  group('CatalogGate', () {
    test('a clean public-domain catalog passes', () {
      final gate = CatalogGate(now: beforeRelease);
      expect(gate.validate(_catalog([_entry('ASV')])), isEmpty);
    });

    test('fails when the licence cannot be established', () {
      final gate = CatalogGate(now: beforeRelease);
      final bad = _entry('X', lic: _lic(basis: null));
      // A public-domain claim without a recorded basis is not a licence decision.
      final violations = gate.validate(_catalog([bad]));
      expect(violations.map((v) => v.rule), contains('basis'));
    });

    test('fails a CC BY resource with no attribution', () {
      final gate = CatalogGate(now: beforeRelease);
      final bad = _entry(
        'OSHB',
        lic: _lic(
          license: AmfLicense.ccBy,
          attribution: '',
          basis: 'Upstream dedicates the tagging under CC BY 4.0.',
        ),
      );
      final violations = gate.validate(_catalog([bad]));
      expect(violations.map((v) => v.rule), contains('attribution'));
    });

    test('fails non-commercial content in a commercial build', () {
      final gate = CatalogGate(now: beforeRelease, commercial: true);
      final bad = _entry(
        'STEP',
        lic: _lic(
          license: AmfLicense.ccByNc,
          attribution: 'Tyndale House',
          basis: 'Upstream publishes its own datasets under CC BY-NC.',
        ),
      );
      final violations = gate.validate(_catalog([bad]));
      expect(violations.map((v) => v.rule), contains('non-commercial'));
    });

    test('share-alike in a closed catalog is reported once, globally', () {
      final gate = CatalogGate(now: beforeRelease, closedDistribution: true);
      final bad = _entry(
        'RCA',
        lic: _lic(
          license: AmfLicense.ccBySa,
          attribution: 'CrossWire Bible Society',
          basis: 'CrossWire publishes its file under CC BY-SA 3.0.',
        ),
      );
      final violations = gate.validate(_catalog([bad]));
      final shareAlike = violations.where((v) => v.rule == 'share-alike');
      expect(shareAlike, hasLength(1));
      expect(shareAlike.first.message, contains('RCA'));
    });

    test('share-alike is allowed in an open catalog', () {
      final gate = CatalogGate(now: beforeRelease, closedDistribution: false);
      final bad = _entry(
        'RCA',
        lic: _lic(
          license: AmfLicense.ccBySa,
          attribution: 'CrossWire Bible Society',
          basis: 'CrossWire publishes its file under CC BY-SA 3.0.',
        ),
      );
      final violations = gate.validate(_catalog([bad]));
      expect(violations.map((v) => v.rule), isNot(contains('share-alike')));
    });

    test('a resource under copyright is not distributable before its date', () {
      final gate = CatalogGate(now: beforeRelease);
      final platense = _entry(
        'PLATENSE',
        lic: _lic(
          basis: 'Straubinger d. 1956; life+70 (Ley 17.336 art. 10, Chile).',
          release: DateTime.utc(2027),
        ),
      );
      final violations = gate.validate(_catalog([platense]));
      expect(violations.map((v) => v.rule), contains('release-date'));
      expect(violations.first.message, contains('2027-01-01'));
    });

    test('the same resource is distributable on and after its date', () {
      final gate = CatalogGate(now: DateTime.utc(2027, 1, 1));
      final platense = _entry(
        'PLATENSE',
        lic: _lic(
          basis: 'Straubinger d. 1956; life+70 (Ley 17.336 art. 10, Chile).',
          release: DateTime.utc(2027),
        ),
      );
      expect(gate.validate(_catalog([platense])), isEmpty);
    });

    test('fails a resource cleared only in other jurisdictions', () {
      final gate = CatalogGate(now: beforeRelease, jurisdiction: 'US');
      final pd = _entry('ASV', lic: _lic(jurisdictions: {'CL', 'ES'}));
      final violations = gate.validate(_catalog([pd]));
      expect(violations.map((v) => v.rule), contains('jurisdiction'));
    });

    test('proprietary content never enters a distributable catalog', () {
      final gate = CatalogGate(now: beforeRelease);
      final bad = _entry('RVR60', lic: _lic(license: AmfLicense.proprietary));
      final violations = gate.validate(_catalog([bad]));
      expect(violations.map((v) => v.rule), contains('no-redistribution'));
    });

    test('rejects a duplicate resource id', () {
      final gate = CatalogGate(now: beforeRelease);
      final violations = gate.validate(_catalog([_entry('ASV'), _entry('ASV')]));
      expect(violations.map((v) => v.rule), contains('duplicate-id'));
    });

    test('rejects an unsupported contract major', () {
      final gate = CatalogGate(now: beforeRelease);
      final catalog = AmfCatalog(
        format: amfCatalogFormat,
        version: '1.0.0',
        contractMajor: 99,
        entries: [_entry('ASV')],
      );
      final violations = gate.validate(catalog);
      expect(violations.map((v) => v.rule), contains('contract'));
    });

    test('requires a sha256 for every resource', () {
      final gate = CatalogGate(now: beforeRelease);
      final violations = gate.validate(_catalog([_entry('ASV', sha: '')]));
      expect(violations.map((v) => v.rule), contains('integrity'));
    });
  });

  group('licence rules', () {
    test('public domain and CC0 need no attribution', () {
      expect(AmfLicense.publicDomain.requiresAttribution, isFalse);
      expect(AmfLicense.cc0.requiresAttribution, isFalse);
    });

    test('CC BY requires attribution but is not share-alike', () {
      expect(AmfLicense.ccBy.requiresAttribution, isTrue);
      expect(AmfLicense.ccBy.isShareAlike, isFalse);
      expect(AmfLicense.ccBy.forbidsCommercial, isFalse);
    });

    test('CC BY-SA is share-alike', () {
      expect(AmfLicense.ccBySa.isShareAlike, isTrue);
    });
  });
}
