import 'dart:convert';
import 'dart:io';

import 'package:amf_format/amf_contract.dart';
import 'package:amf_format/catalog_gate.dart';

/// Decides whether a catalog index may be distributed.
///
/// Deliberately a build step rather than a document. Every rule here exists because
/// a specific licensing failure was found during research — an unlicensed Spanish
/// commentary, a GPL-licensed Strong's file, a share-alike morphology scheme, a
/// work still under copyright until 2027 — and the point is that the next one fails
/// here rather than in a user's hands.
class CatalogValidator {
  CatalogValidator({
    required this.catalog,
    required this.now,
    this.commercial = true,
    this.closedDistribution = true,
    this.jurisdiction,
  });

  final AmfCatalog catalog;
  final DateTime now;
  final bool commercial;
  final bool closedDistribution;
  final String? jurisdiction;

  ValidationReport run() {
    final gate = CatalogGate(
      now: now,
      commercial: commercial,
      closedDistribution: closedDistribution,
      jurisdiction: jurisdiction,
    );
    return ValidationReport(
      violations: gate.validate(catalog),
      checkedResources: catalog.entries.length,
    );
  }
}

class ValidationReport {
  ValidationReport({required this.violations, required this.checkedResources});

  final List<GateViolation> violations;
  final int checkedResources;

  bool get canShip => violations.isEmpty;
}

/// Checks a built module's data integrity.
///
/// The upstream catalog had no such check, and its end-to-end test read Genesis 1:1
/// — an Old Testament verse, unaffected by the defect — so 260 New Testament
/// chapters shipped with no verse 1, John 1:1 among them. Reading the Old Testament
/// in a test while the New Testament was broken is exactly the gap this closes.
class ModuleIntegrityGate {
  const ModuleIntegrityGate();

  /// [chapters] maps a `bookOsis:chapter` key to its verse numbers.
  IntegrityResult check(Map<String, List<int>> chapters) {
    final failures = <String>[];
    for (final entry in chapters.entries) {
      final verses = entry.value;
      if (verses.isEmpty) {
        failures.add('${entry.key}: chapter has no verses');
        continue;
      }
      final sorted = [...verses]..sort();
      if (sorted.first != 1) {
        failures.add('${entry.key}: starts at verse ${sorted.first}, expected 1');
        continue;
      }
      for (var i = 1; i < sorted.length; i++) {
        if (sorted[i] != sorted[i - 1] + 1) {
          failures.add(
            '${entry.key}: gap between verse ${sorted[i - 1]} and ${sorted[i]}',
          );
          break;
        }
      }
    }
    return IntegrityResult(chapters: chapters.length, failures: failures);
  }
}

class IntegrityResult {
  IntegrityResult({required this.chapters, required this.failures});

  final int chapters;
  final List<String> failures;

  bool get isValid => failures.isEmpty;
}

/// Reads and parses a catalog index.
AmfCatalog readCatalogFile(File file) {
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  return AmfCatalog(
    format: decoded['format'] as String? ?? '',
    version: decoded['version'] as String? ?? '',
    contractMajor: decoded['contractMajor'] as int? ?? amfCatalogContractMajor,
    entries: (decoded['modules'] as List<dynamic>? ?? const [])
        .map((m) => _entry(m as Map<String, dynamic>))
        .toList(growable: false),
  );
}

AmfResourceEntry _entry(Map<String, dynamic> m) {
  final lic = m['license'] as Map<String, dynamic>? ?? const {};
  final jurisdictions = (lic['jurisdictions'] as List<dynamic>? ?? const [])
      .map((e) => e.toString().toUpperCase())
      .toSet();

  return AmfResourceEntry(
    id: m['id'] as String,
    type: m['type'] as String? ?? 'bible',
    name: m['name'] as String? ?? m['id'] as String,
    shortName: m['shortName'] as String? ?? m['id'] as String,
    language: m['language'] as String? ?? 'en',
    direction: m['direction'] as String? ?? 'ltr',
    version: m['version'] as String? ?? '0.0.0',
    publisher: m['publisher'] as String?,
    sha256: m['sha256'] as String?,
    sizeBytes: m['sizeBytes'] as int? ?? 0,
    downloadUrl: m['downloadUrl'] as String?,
    granularity: m['granularity'] as String? ?? 'verse',
    genre: m['genre'] as String?,
    license: AmfLicenseInfo(
      license: amfLicenseFromString(lic['id'] as String? ?? 'PublicDomain'),
      attribution: lic['attribution'] as String? ?? '',
      sourceUrl: lic['sourceUrl'] as String? ?? '',
      releaseDate:
          DateTime.tryParse(lic['releaseDate'] as String? ?? '') ??
              DateTime.utc(1970),
      jurisdictions: jurisdictions,
      basis: lic['basis'] as String?,
    ),
  );
}
