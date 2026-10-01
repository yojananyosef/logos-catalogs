import 'package:archive/archive.dart';

/// How a module's two archive entries are written.
///
/// This lives here rather than in `tool/build_module.dart` so the determinism rule can be
/// tested without a USFM source archive and a four-minute build. A rule that can only be
/// checked by producing an eleven-megabyte artefact is a rule that will be broken
/// silently.
///
/// The rule: **two builds of the same content produce the same bytes.**
///
/// `ArchiveFile` defaults `lastModTime` to the current wall clock, so a module assembled
/// with its defaults gets a different digest on every build. That is not cosmetic. A
/// `sha256` nobody can reproduce cannot be checked by anybody — not by a rebuild, not by a
/// CI double build, not by a user comparing a downloaded module against the catalog index.
/// It becomes a value that has to be taken on faith, and an integrity guarantee that is
/// only a guarantee by faith is worse than none, because it looks like one.
///
/// The upstream catalog's own CI does a double build and compares digests precisely
/// because of this; a tool that stamps its archives with the clock cannot pass that check,
/// and would fail it for the least interesting reason available.
class AmfArchive {
  const AmfArchive._();

  /// Packed DOS date-time for 1980-01-01 00:00:00, the earliest a ZIP can represent.
  ///
  /// `archive` stores this as a packed integer rather than a `DateTime`: the year sits in
  /// the top seven bits and every other field below it, so all-zero is the epoch.
  static const int dosEpoch = 0;

  /// One entry with its timestamp pinned.
  static ArchiveFile entry(String name, List<int> content) =>
      ArchiveFile(name, content.length, content)..lastModTime = dosEpoch;

  /// Packs [manifest] and [content] into a module archive.
  ///
  /// Exactly two entries, in the order the format fixes. A third would be a
  /// `schemaVersion` change, not a build flag.
  static List<int>? encode(List<int> manifest, List<int> content) => ZipEncoder().encode(
        Archive()
          ..addFile(entry('manifest.json', manifest))
          ..addFile(entry('content.db', content)),
      );
}
