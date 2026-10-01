// Builds an AMF `.amod` from a USFM source archive.
//
// This is the step that was missing: the format contract, the extractor and the engine
// reader all existed, and every one of the catalog's eighteen `sha256` values was still
// `PLACEHOLDER_*` because nothing could turn a source text into a module. Without it the
// reader, the FTS5 search and the reference parser have only ever been exercised against
// four-verse English fixtures.
//
// Usage:
//
//     dart run tool/build_module.dart \
//       --usfm eng-kjv2006_usfm.zip \
//       --id KJV --name "King James Version" --language en \
//       --out dist/ \
//       --xrefs ../bible-cross-references/tsv/crossreferences_kjv.tsv
//
// `--xrefs` is optional: most translations have no cross-reference set of their own. When
// one is given, a row the parser cannot read stops the build rather than being dropped —
// see `_writeCrossReferences`.
//
// Prints the module's sha256, which is what `catalog.json` needs to become real instead
// of a placeholder.
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart';

import '../lib/usfm_extractor.dart';
import '../lib/xref_ingest.dart';

/// The canonical OSIS identifier, testament and order for each of the 66 books.
///
/// Needed because a USFM archive does not use OSIS codes. eBible's KJV archive, for
/// example, labels Genesis `GEN` and John `JHN`, where OSIS and the engine both say `Gen`
/// and `John`. Keyed on the English book name from the `\id` header, which every source
/// carries, so the mapping does not depend on whichever private abbreviation an archive
/// happens to use.
///
/// Getting this wrong is not cosmetic: the reader looks books up by OSIS code, and the
/// reference parser resolves `Jn 3:16` against them. A module built with `JHN` is a module
/// the engine cannot address.
const _osisBooks = <String, (String osis, String testament, int order)>{
  'genesis': ('Gen', 'OT', 1),
  'exodus': ('Exod', 'OT', 2),
  'leviticus': ('Lev', 'OT', 3),
  'numbers': ('Num', 'OT', 4),
  'deuteronomy': ('Deut', 'OT', 5),
  'joshua': ('Josh', 'OT', 6),
  'judges': ('Judg', 'OT', 7),
  'ruth': ('Ruth', 'OT', 8),
  '1 samuel': ('1Sam', 'OT', 9),
  '2 samuel': ('2Sam', 'OT', 10),
  '1 kings': ('1Kgs', 'OT', 11),
  '2 kings': ('2Kgs', 'OT', 12),
  '1 chronicles': ('1Chr', 'OT', 13),
  '2 chronicles': ('2Chr', 'OT', 14),
  'ezra': ('Ezra', 'OT', 15),
  'nehemiah': ('Neh', 'OT', 16),
  'esther': ('Esth', 'OT', 17),
  'job': ('Job', 'OT', 18),
  'psalms': ('Ps', 'OT', 19),
  'proverbs': ('Prov', 'OT', 20),
  'ecclesiastes': ('Eccl', 'OT', 21),
  'song of solomon': ('Song', 'OT', 22),
  'isaiah': ('Isa', 'OT', 23),
  'jeremiah': ('Jer', 'OT', 24),
  'lamentations': ('Lam', 'OT', 25),
  'ezekiel': ('Ezek', 'OT', 26),
  'daniel': ('Dan', 'OT', 27),
  'hosea': ('Hos', 'OT', 28),
  'joel': ('Joel', 'OT', 29),
  'amos': ('Amos', 'OT', 30),
  'obadiah': ('Obad', 'OT', 31),
  'jonah': ('Jonah', 'OT', 32),
  'micah': ('Mic', 'OT', 33),
  'nahum': ('Nah', 'OT', 34),
  'habakkuk': ('Hab', 'OT', 35),
  'zephaniah': ('Zeph', 'OT', 36),
  'haggai': ('Hag', 'OT', 37),
  'zechariah': ('Zech', 'OT', 38),
  'malachi': ('Mal', 'OT', 39),
  'matthew': ('Matt', 'NT', 40),
  'mark': ('Mark', 'NT', 41),
  'luke': ('Luke', 'NT', 42),
  'john': ('John', 'NT', 43),
  'acts': ('Acts', 'NT', 44),
  'romans': ('Rom', 'NT', 45),
  '1 corinthians': ('1Cor', 'NT', 46),
  '2 corinthians': ('2Cor', 'NT', 47),
  'galatians': ('Gal', 'NT', 48),
  'ephesians': ('Eph', 'NT', 49),
  'philippians': ('Phil', 'NT', 50),
  'colossians': ('Col', 'NT', 51),
  '1 thessalonians': ('1Thess', 'NT', 52),
  '2 thessalonians': ('2Thess', 'NT', 53),
  '1 timothy': ('1Tim', 'NT', 54),
  '2 timothy': ('2Tim', 'NT', 55),
  'titus': ('Titus', 'NT', 56),
  'philemon': ('Phlm', 'NT', 57),
  'hebrews': ('Heb', 'NT', 58),
  'james': ('Jas', 'NT', 59),
  '1 peter': ('1Pet', 'NT', 60),
  '2 peter': ('2Pet', 'NT', 61),
  '1 john': ('1John', 'NT', 62),
  '2 john': ('2John', 'NT', 63),
  '3 john': ('3John', 'NT', 64),
  'jude': ('Jude', 'NT', 65),
  'revelation': ('Rev', 'NT', 66),
};

/// The English book name from the `\id` header, whose second field is the name.
String? _englishName(String usfm) {
  final m = RegExp(r'^\\id\s+\S+\s+(.+)$', multiLine: true).firstMatch(usfm);
  return m?.group(1)?.trim();
}

/// The book's short title, from its `\toc2` header.
///
/// Preferred over `\h`, which carries the source's long heading ("The First Book of
/// Moses, called Genesis") rather than the name a reader would look for.
String? _toc2(String usfm) {
  final m = RegExp(r'^\\toc2\s+(.+)$', multiLine: true).firstMatch(usfm);
  final name = m?.group(1)?.trim();
  return (name == null || name.isEmpty) ? null : name;
}

/// The key used to look a book up in [_osisBooks].
///
/// `\toc2` first, because it is the translation's own short title ("Matthew", "1 Samuel")
/// and it is stable across the whole canon. The `\id` name is the fallback, but it cannot
/// be relied on alone: the New Testament books in this source name themselves "The Gospel
/// According to Matthew" and "Paul's Letter to the Romans", so keying on `\id` alone
/// silently matched only the thirty-three Old Testament books.
String? _bookKey(String usfm) {
  final toc2 = _toc2(usfm);
  if (toc2 != null) return toc2.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  final id = _englishName(usfm);
  return id?.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

/// Removes what [UsfmExtractor] does not handle.
///
/// The extractor strips USFM markers but not their attributes, which every Strong's-tagged
/// source carries: `\w God|strong="H0430"\w*` would otherwise reach the reader as
/// `God|strong="H0430"`. Stripping here rather than in the extractor keeps the extractor
/// a pure USFM parser, and the pilcrow goes because it is a paragraph mark, not text.
String _prepare(String usfm) => usfm
    .replaceAll(RegExp(r'\|[a-zA-Z0-9_-]+="[^"]*"'), '')
    .replaceAll('¶', ' ')
    .replaceAll(' ', ' ');

/// Writes the `crossReferences` rows from a TSK export.
///
/// Returns the number of rows written, or null when no file was given — which is the
/// normal case, since most translations have no cross-reference set of their own.
///
/// Every reference whose *source* verse the module does not contain is dropped, and so is
/// every *target* that names a book the module lacks. Both are counted, and a non-zero
/// count is reported rather than logged quietly: dropping a reference because the module
/// was built from a partial source is correct, dropping four hundred of them because a
/// version prefix was read as a book is a bug, and only the number tells the two apart.
///
/// Rows whose anchor is not present in the source verse's text are *kept*. The reader
/// falls back to placing the reference at the end of the verse, which is worse than placing
/// it exactly but still lets the reader follow it; discarding it would lose a real link
/// because of a wording difference between two editions of the same translation.
Future<int?> _writeCrossReferences(
  Database db,
  Map<String, int> bookIds,
  String? path,
) async {
  if (path == null) return null;

  final file = File(path);
  if (!file.existsSync()) {
    throw CrossReferenceFileMissing(path);
  }

  final parsed = parseXrefs(await file.readAsString());
  if (!parsed.isClean) {
    // Stopped rather than warned: a rejected row is a reference the reader will never show,
    // and shipping a module that quietly has fewer references than its source is the exact
    // failure this repository keeps finding in others.
    throw UnreadableCrossReferenceRows(parsed.rejected);
  }

  // Which passages the module actually has, so a reference that points nowhere is dropped
  // rather than written as a link that cannot be followed. Checked at verse granularity for
  // the source and chapter granularity for the target: a target verse that is merely absent
  // is a wording difference between versifications, and refusing the whole reference over it
  // would lose links the reader could have followed.
  final presentVerses = <String>{};
  final presentChapters = <String>{};
  for (final row in db.select('SELECT bookId, chapter, verse FROM verses')) {
    presentVerses.add('${row['bookId']}:${row['chapter']}:${row['verse']}');
    presentChapters.add('${row['bookId']}:${row['chapter']}');
  }

  final insert = db.prepare(
    'INSERT INTO crossReferences (fromBookId, fromChapter, fromVerse, toBookId, '
    'toChapter, toVerse, toVerseEnd, anchor, sortOrder) VALUES (?,?,?,?,?,?,?,?,?)',
  );
  final sortOrder = <String, int>{};

  var written = 0;
  var dropped = 0;

  for (final ref in parsed.references) {
    final fromId = bookIds[ref.fromBook];
    if (fromId == null ||
        !presentVerses.contains('${fromId}:${ref.fromChapter}:${ref.fromVerse}')) {
      dropped++;
      continue;
    }
    for (final target in ref.targets) {
      final toId = bookIds[target.book];
      if (toId == null || !presentChapters.contains('$toId:${target.chapter}')) {
        dropped++;
        continue;
      }
      // Two targets under one phrase share a sortOrder block so the reader renders them in
      // the order the source listed them, next to each other.
      final key = '$fromId:${ref.fromChapter}:${ref.fromVerse}:${ref.anchor}';
      final next = (sortOrder[key] ?? -1) + 1;
      sortOrder[key] = next;
      insert.execute([
        fromId,
        ref.fromChapter,
        ref.fromVerse,
        toId,
        target.chapter,
        target.verse,
        target.verseEnd,
        ref.anchor,
        next,
      ]);
      written++;
    }
  }

  stdout.writeln('cross-references: $written written'
      '${dropped == 0 ? '' : ', $dropped dropped (the module has no such passage)'}');
  return written;
}

/// The `--xrefs` file was named but is not there.
class CrossReferenceFileMissing implements Exception {
  CrossReferenceFileMissing(this.path);
  final String path;
  String get message => 'cross-reference file not found: $path';
}

/// The `--xrefs` file has rows this parser cannot read.
class UnreadableCrossReferenceRows implements Exception {
  UnreadableCrossReferenceRows(this.rejected);
  final List<RejectedXrefRow> rejected;
  String get message =>
      'cross-reference file has ${rejected.length} unreadable rows. The first is '
      'line ${rejected.first.line}: ${rejected.first.reason}';
}

Future<int> run(List<String> args) async {
  /// The value following `--name`, or null when the flag is absent.
  String? arg(String name) {
    final i = args.indexOf('--$name');
    if (i < 0 || i + 1 >= args.length) return null;
    return args[i + 1];
  }

  final usfm = arg('usfm');
  final id = arg('id');
  final name = arg('name');
  final language = arg('language') ?? 'en';
  final outDir = arg('out') ?? 'dist';
  final publisher = arg('publisher') ?? '';
  final license = arg('license') ?? 'PublicDomain';
  final source = arg('source') ?? '';
  final attribution = arg('attribution') ?? '';

  /// The TSK cross-reference export to fold in, or null for a translation with none.
  final xrefFile = arg('xrefs');

  if (usfm == null || id == null || name == null) {
    stderr.writeln('usage: build_module --usfm <zip> --id <ID> --name <NAME> '
        '[--language es] [--out dist]');
    return 64;
  }

  final archive = ZipDecoder().decodeBytes(
    await File(usfm).readAsBytes(),
  );

  // `NN-OSIS...usfm`: the numeric prefix is the canonical book order, which is what
  // `books.bookOrder` must carry for the reader's book list to come out in order.
  final sources = archive.files
      .where((f) => f.name.toLowerCase().endsWith('.usfm'))
      .map((f) {
        final text = utf8.decode(f.content as List<int>);
        final key = _bookKey(text);
        if (key == null) return null;
        final entry = _osisBooks[key];
        if (entry == null) return null;
        return (
          osis: entry.$1,
          testament: entry.$2,
          order: entry.$3,
          name: _toc2(text) ?? entry.$1,
          text: text,
        );
      })
      .whereType<({String osis, String testament, int order, String name, String text})>()
      .toList()
    ..sort((a, b) => a.order.compareTo(b.order));

  if (sources.isEmpty) {
    stderr.writeln('no .usfm files matched in $usfm');
    return 65;
  }

  final extractor = UsfmExtractor();
  final books =
      <({String osis, String testament, int order, String name, int chapters, List<UsfmVerse> verses})>[];
  for (final s in sources) {
    final verses = extractor.extract(_prepare(s.text));
    if (verses.isEmpty) continue;
    books.add((
      osis: s.osis,
      testament: s.testament,
      order: s.order,
      name: s.name,
      chapters: verses.map((v) => v.chapter).reduce((a, b) => a > b ? a : b),
      verses: verses,
    ));
  }

  stdout.writeln('books: ${books.length}, verses: '
      '${books.fold<int>(0, (n, b) => n + b.verses.length)}');

  final work = File('${Directory.systemTemp.path}/build-$id.db');
  if (work.existsSync()) work.deleteSync();
  final db = sqlite3.open(work.path);

  void exec(List<String> statements) {
    for (final s in statements) {
      db.execute(s);
    }
  }

  // Schema, pragmas and FTS5 configuration are byte-for-byte what the engine's reader
  // expects. `application_id` is what distinguishes an AMF module from any other SQLite
  // file, so it is set before anything is written.
  exec([
    'PRAGMA application_id = 1095585604',
    'PRAGMA user_version = 1',
    'PRAGMA journal_mode = DELETE',
    '''CREATE TABLE books (
      bookId INTEGER PRIMARY KEY, osisCode TEXT NOT NULL UNIQUE, name TEXT NOT NULL,
      abbreviation TEXT NOT NULL, testament TEXT NOT NULL CHECK (testament IN ('OT','NT')),
      bookOrder INTEGER NOT NULL, chapterCount INTEGER NOT NULL
    ) WITHOUT ROWID''',
    '''CREATE TABLE verses (
      bookId INTEGER NOT NULL, chapter INTEGER NOT NULL, verse INTEGER NOT NULL,
      verseEnd INTEGER, text TEXT NOT NULL, UNIQUE (bookId, chapter, verse)
    )''',
    '''CREATE VIRTUAL TABLE verses_fts USING fts5(
      text, bookId UNINDEXED, chapter UNINDEXED, verse UNINDEXED, verseEnd UNINDEXED,
      content='verses', content_rowid='rowid',
      tokenize='unicode61 remove_diacritics 2'
    )''',
    '''CREATE TRIGGER verses_ai AFTER INSERT ON verses BEGIN
      INSERT INTO verses_fts(rowid, text, bookId, chapter, verse, verseEnd)
      VALUES (new.rowid, new.text, new.bookId, new.chapter, new.verse, new.verseEnd);
    END''',
    // The DDL is byte-for-byte what the engine's `CrossReferenceSchema.create` declares.
    // The two repositories cannot share a Dart file — this one has no dependency on the
    // application — so the duplication is real and the engine is where it is checked:
    // `real_modules_test.dart` reads this table out of a module this tool built.
    '''CREATE TABLE IF NOT EXISTS crossReferences (
      fromBookId INTEGER NOT NULL,
      fromChapter INTEGER NOT NULL,
      fromVerse INTEGER NOT NULL,
      toBookId INTEGER NOT NULL,
      toChapter INTEGER NOT NULL,
      toVerse INTEGER NOT NULL,
      toVerseEnd INTEGER,
      anchor TEXT NOT NULL,
      sortOrder INTEGER NOT NULL
    )''',
    '''CREATE INDEX IF NOT EXISTS crossReferences_from ON
      crossReferences (fromBookId, fromChapter, fromVerse)''',
  ]);

  final insertBook = db.prepare(
    'INSERT INTO books (bookId, osisCode, name, abbreviation, testament, bookOrder, '
    'chapterCount) VALUES (?,?,?,?,?,?,?)',
  );
  final insertVerse = db.prepare(
    'INSERT INTO verses (bookId, chapter, verse, verseEnd, text) VALUES (?,?,?,?,?)',
  );

  var bookId = 0;
  final bookIds = <String, int>{};
  for (final b in books) {
    bookId++;
    bookIds[b.osis] = bookId;
    insertBook.execute([
      bookId,
      b.osis,
      b.name,
      // The OSIS code is the abbreviation: it is unambiguous, and a second spelling
      // invented here would be a name the source never used.
      b.osis,
      b.testament,
      b.order,
      b.chapters,
    ]);
    for (final v in b.verses) {
      insertVerse.execute([bookId, v.chapter, v.verse, v.verseEnd, v.text]);
    }
  }

  // The FTS5 index is populated by the insert trigger, so it must be compacted into its
  // own consistent state before the file is closed. Without this the module opens and
  // searches an index that is missing rows the tables contain.
  exec(['INSERT INTO verses_fts(verses_fts) VALUES (\'optimize\')']);

  // Every module gets the table; only a module that was given a cross-reference file has
  // anything in it. The flag records the latter, so a reader can tell "this translation
  // ships no cross-references" from "the reader cannot show them".
  final features = <String, bool>{
    'hasStrongs': false,
    'hasMorphology': false,
    'hasFootnotes': false,
    'hasHeadings': false,
    'hasCrossReferences': false,
  };

  final int? xrefs;
  try {
    xrefs = await _writeCrossReferences(db, bookIds, xrefFile);
  } on CrossReferenceFileMissing catch (e) {
    // Named but absent. Reported before the module is finished, because a module written
    // without its cross-references would look complete and be published.
    stderr.writeln(e.message);
    db.dispose();
    work.deleteSync();
    return 66;
  } on UnreadableCrossReferenceRows catch (e) {
    stderr.writeln(e.message);
    db.dispose();
    work.deleteSync();
    return 65;
  }
  if (xrefs != null && xrefs > 0) {
    features['hasCrossReferences'] = true;
  }

  db.dispose();

  final manifest = utf8.encode(jsonEncode({
    'amf': 1,
    'schemaVersion': 1,
    'minReaderVersion': 1,
    'id': id,
    'type': 'bible',
    'name': name,
    'shortName': id,
    'language': language,
    'direction': 'ltr',
    'version': '1.0.0',
    'publisher': publisher,
    'license': license,
    'copyright': attribution,
    'source': source,
    'attribution': attribution,
    'features': features,
    'dependencies': <String>[],
  }));

  final content = work.readAsBytesSync();
  work.deleteSync();

  final zip = ZipEncoder().encode(
    Archive()
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest))
      ..addFile(ArchiveFile('content.db', content.length, content)),
  );
  // `encode` returns null only when the archive is empty, which cannot happen here: two
  // entries were just added. Guarded rather than asserted so a future optional entry
  // cannot produce a module written as a zero-byte file.
  if (zip == null) {
    stderr.writeln('zip encoding produced no bytes');
    return 70;
  }

  final out = Directory(outDir)..createSync(recursive: true);
  final module = File('${out.path}/$id.amod')..writeAsBytesSync(zip);

  stdout.writeln('wrote ${module.path} (${module.lengthSync()} bytes)');
  stdout.writeln('sha256: ${sha256.convert(zip)}');
  return 0;
}

Future<void> main(List<String> args) async {
  exitCode = await run(args);
}