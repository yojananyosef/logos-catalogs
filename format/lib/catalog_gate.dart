import 'amf_contract.dart';

/// A problem that makes a catalog or one of its resources unshippable.
class GateViolation {
  GateViolation(this.resourceId, this.rule, this.message);

  final String resourceId;
  final String rule;
  final String message;

  @override
  String toString() => '[$rule] $resourceId: $message';
}

/// The validation that decides whether a catalog may be distributed.
///
/// This lives in the build path rather than in documentation on purpose. A checklist
/// is not a control: a missing attribution found at review time is found too late.
/// A build that fails is a control.
///
/// Every rule traces to a specific licensing finding:
///
///  * unresolved licence — the catalog's own status cannot be established
///  * missing attribution — CC BY obliges the redistributor to carry it
///  * non-commercial in a commercial build — CC BY-NC forbids the use
///  * share-alike in a closed target — the obligation is contagious
///  * release date not reached — the work is still under copyright
///  * jurisdiction not cleared — a licence that is only clear in some territories
class CatalogGate {
  CatalogGate({
    this.now,
    this.commercial = true,
    this.closedDistribution = true,
    this.jurisdiction,
  });

  final DateTime? now;
  final bool commercial;
  final bool closedDistribution;

  /// The territory the build targets, e.g. `CL` or `US`.
  final String? jurisdiction;

  DateTime get _today => now ?? DateTime.now().toUtc();

  /// Returns every violation. An empty list means the catalog may ship.
  List<GateViolation> validate(AmfCatalog catalog) {
    final violations = <GateViolation>[];

    if (catalog.format != amfCatalogFormat) {
      violations.add(GateViolation(
        '<catalog>',
        'format',
        'format is "${catalog.format}", expected "$amfCatalogFormat"',
      ));
    }

    if (!amfSupportedContractMajors.contains(catalog.contractMajor)) {
      violations.add(GateViolation(
        '<catalog>',
        'contract',
        'contract major ${catalog.contractMajor} is not supported by this build '
            '(supported: ${amfSupportedContractMajors.join(', ')})',
      ));
    }

    final seenIds = <String>{};
    for (final entry in catalog.entries) {
      violations.addAll(_validateEntry(entry, catalog));

      if (!seenIds.add(entry.id)) {
        violations.add(GateViolation(
          entry.id,
          'duplicate-id',
          'resource id appears more than once in the catalog',
        ));
      }
    }

    // Share-alike propagates to the catalog as a whole, so it is checked once
    // globally rather than per resource.
    if (closedDistribution && catalog.isShareAlike) {
      final culprits = catalog.entries
          .where((e) => e.license.license.isShareAlike)
          .map((e) => e.id)
          .join(', ');
      violations.add(GateViolation(
        '<catalog>',
        'share-alike',
        'catalog mixes share-alike content into a closed-distribution target. '
            'The obligation is contagious across derived data. Offending: $culprits',
      ));
    }

    return violations;
  }

  List<GateViolation> _validateEntry(AmfResourceEntry e, AmfCatalog catalog) {
    final out = <GateViolation>[];
    final lic = e.license;

    if (lic.license.forbidsRedistribution) {
      out.add(GateViolation(
        e.id,
        'no-redistribution',
        'licence is ${lic.license.name}; licensed content may never enter a '
            'distributable catalog',
      ));
    }

    if (!lic.isDistributableOn(_today)) {
      final when = lic.releaseDate.toIso8601String().substring(0, 10);
      out.add(GateViolation(
        e.id,
        'release-date',
        'not distributable until $when (copyright still in force)',
      ));
    }

    if (lic.license.requiresAttribution && lic.attribution.trim().isEmpty) {
      out.add(GateViolation(
        e.id,
        'attribution',
        'licence ${lic.license.name} requires an attribution string and none is set',
      ));
    }

    if (commercial && lic.license.forbidsCommercial) {
      out.add(GateViolation(
        e.id,
        'non-commercial',
        'licence ${lic.license.name} forbids commercial distribution',
      ));
    }

    final country = jurisdiction;
    if (country != null && !lic.allowsCommercialIn(country)) {
      out.add(GateViolation(
        e.id,
        'jurisdiction',
        'not cleared for $country'
            '${lic.jurisdictions.isEmpty ? '' : ' (cleared: ${lic.jurisdictions.join(', ')})'}',
      ));
    }

    if (lic.sourceUrl.trim().isEmpty) {
      out.add(GateViolation(e.id, 'provenance', 'source URL is required'));
    }

    // Public-domain claims have to be justified. An expiry analysis or a dedication
    // is what distinguishes a documented public-domain claim from an assumption.
    if (lic.isPublicDomain && (lic.basis == null || lic.basis!.trim().isEmpty)) {
      out.add(GateViolation(
        e.id,
        'basis',
        'public-domain claim has no recorded basis (expiry analysis or dedication)',
      ));
    }

    if (e.sha256 == null || e.sha256!.isEmpty) {
      out.add(GateViolation(
        e.id,
        'integrity',
        'no sha256 recorded; distribution integrity cannot be verified',
      ));
    }

    if (e.downloadUrl == null || e.downloadUrl!.isEmpty) {
      out.add(GateViolation(e.id, 'distribution', 'no download URL'));
    }

    return out;
  }
}
