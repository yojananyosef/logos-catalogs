/// The catalog contract shared between the catalogs repository and the engine.
///
/// This is the versioned boundary. The engine depends on these types and nothing
/// about how a catalog is stored, distributed or licensed, which is what allows a
/// catalog to be rebuilt — or replaced — without an application release.
library;

/// Bumped only for breaking changes. The application declares the range it accepts
/// and refuses anything outside it, rather than misreading a newer catalog.
const int amfCatalogContractMajor = 1;

/// The range of contract majors this build understands.
const amfSupportedContractMajors = <int>{1};

/// Format discriminator written into every catalog index.
const String amfCatalogFormat = 'amf-catalog';

/// "AMOD" in ASCII. The upstream specification printed this as the decimal
/// 1096035140, which is wrong; the implementation always used the correct value.
const int amfApplicationId = 0x414D4F44;

const int amfSchemaVersionV1 = 1;
const int amfSchemaVersionV11 = 2;

/// Licence classes a resource may declare.
enum AmfLicense {
  publicDomain,
  cc0,
  ccBy,
  ccBySa,
  ccByNc,
  proprietary,
}

/// Parses the licence string used in `manifest.json`.
AmfLicense amfLicenseFromString(String raw) {
  switch (raw.trim().toLowerCase()) {
    case 'publicdomain':
    case 'public domain':
      return AmfLicense.publicDomain;
    case 'cc0-1.0':
    case 'cc0':
      return AmfLicense.cc0;
    case 'cc-by-4.0':
    case 'cc-by':
      return AmfLicense.ccBy;
    case 'cc-by-sa-4.0':
    case 'cc-by-sa':
      return AmfLicense.ccBySa;
    case 'cc-by-nc-4.0':
    case 'cc-by-nc':
      return AmfLicense.ccByNc;
    case 'proprietary':
      return AmfLicense.proprietary;
    default:
      throw FormatException('unknown license "$raw"');
  }
}

extension AmfLicenseRules on AmfLicense {
  /// Whether redistribution must carry attribution.
  bool get requiresAttribution =>
      this != AmfLicense.publicDomain && this != AmfLicense.cc0;

  /// Whether derivatives inherit a release obligation. Contagious: one such resource
  /// taints the catalog containing it.
  bool get isShareAlike =>
      this == AmfLicense.ccBySa || this == AmfLicense.ccByNc;

  /// Whether commercial redistribution is forbidden.
  bool get forbidsCommercial => this == AmfLicense.ccByNc;

  /// Whether redistribution at all is forbidden.
  bool get forbidsRedistribution => this == AmfLicense.proprietary;
}

/// The licensing facts one resource must declare.
class AmfLicenseInfo {
  const AmfLicenseInfo({
    required this.license,
    required this.attribution,
    required this.sourceUrl,
    required this.releaseDate,
    this.jurisdictions = const <String>{},
    this.basis,
  });

  final AmfLicense license;
  final String attribution;
  final String sourceUrl;

  /// `YYYY-MM-DD`. Public-domain works use 1970-01-01 rather than null, so release
  /// gating is a total comparison and the manifest has no optional field.
  final DateTime releaseDate;

  /// ISO-3166 alpha-2 codes the resource is cleared for. Empty means worldwide.
  final Set<String> jurisdictions;

  /// Why the resource is permissible: an expiry analysis or a dedication.
  final String? basis;

  bool get isPublicDomain =>
      license == AmfLicense.publicDomain || license == AmfLicense.cc0;

  bool isDistributableOn(DateTime now) =>
      !license.forbidsRedistribution && !now.isBefore(releaseDate);

  bool allowsCommercialIn(String country) {
    if (license.forbidsCommercial) return false;
    if (jurisdictions.isEmpty) return true;
    return jurisdictions.contains(country.toUpperCase());
  }
}

/// One resource as declared by a catalog index.
class AmfResourceEntry {
  const AmfResourceEntry({
    required this.id,
    required this.type,
    required this.name,
    required this.shortName,
    required this.language,
    required this.version,
    required this.license,
    this.publisher,
    this.direction = 'ltr',
    this.sha256,
    this.sizeBytes = 0,
    this.downloadUrl,
    this.granularity = 'verse',
    this.genre,
  });

  final String id;
  final String type;
  final String name;
  final String shortName;
  final String language;
  final String direction;
  final String version;
  final AmfLicenseInfo license;
  final String? publisher;
  final String? sha256;
  final int sizeBytes;
  final String? downloadUrl;

  /// `verse`, `chapter` or `book`. Decides at what address a commentary's notes
  /// attach, and the reader must label it rather than implying per-verse notes.
  final String granularity;

  /// `critical`, `expository`, `homiletic` or `devotional`, so a reader cannot
  /// mistake a devotional for a critical commentary.
  final String? genre;
}

/// A catalog index.
class AmfCatalog {
  const AmfCatalog({
    required this.format,
    required this.version,
    required this.entries,
    this.contractMajor = amfCatalogContractMajor,
  });

  final String format;
  final String version;
  final int contractMajor;
  final List<AmfResourceEntry> entries;

  bool get isShareAlike =>
      entries.any((e) => e.license.license.isShareAlike);
}
