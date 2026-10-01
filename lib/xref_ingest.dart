/// One cross-reference: a phrase in a verse, and the passages that phrase points to.
///
/// The anchor is what makes this phrase-level rather than verse-level. TSK gives every
/// reference a phrase it hangs off — `Gen 1:1` "beginning" points at `Prov 8:22-24`, while
/// the same verse's "God" points at fifty-four other passages. Collapsing both to
/// "Gen 1:1 has 55 references" would throw away the only information the source has, and
/// the reader would then have to guess where in the verse to draw each link.
class CrossReference {
  const CrossReference({
    required this.fromBook,
    required this.fromChapter,
    required this.fromVerse,
    required this.anchor,
    required this.targets,
  });

  /// OSIS code of the book the reference is anchored in.
  final String fromBook;
  final int fromChapter;
  final int fromVerse;

  /// The phrase in the verse this reference follows.
  final String anchor;

  final List<CrossReferenceTarget> targets;
}

/// One passage a reference points at. A range keeps both ends.
///
/// `Ps 33:6,9` is two targets, not one target with a comma in it: the reader can follow
/// each, and a comma inside a single string would have to be reparsed at every use.
class CrossReferenceTarget {
  const CrossReferenceTarget({
    required this.book,
    required this.chapter,
    required this.verse,
    this.verseEnd,
  });

  final String book;
  final int chapter;
  final int verse;

  /// The last verse of a range such as `John 1:1-3`, or null for a single verse.
  final int? verseEnd;

  /// How the reference renders itself in the reader, e.g. `Jn 1:1-3`.
  String get label => verseEnd == null || verseEnd == verse
      ? '$book $chapter:$verse'
      : '$book $chapter:$verse-$verseEnd';
}

/// The 66 OSIS codes, which are also the abbreviations this source uses.
///
/// The identity entries matter as much as the aliases. TSK's own key list is a *second*
/// naming scheme — `ge`, `ex`, `le`, `1sa`, `ob` — published alongside the three-letter
/// forms, and a source file may use either. Both are keyed here; anything else is a
/// rejected row rather than a guess.
const _osisCodes = <String>[
  'Gen', 'Exod', 'Lev', 'Num', 'Deut', 'Josh', 'Judg', 'Ruth', '1Sam', '2Sam',
  '1Kgs', '2Kgs', '1Chr', '2Chr', 'Ezra', 'Neh', 'Esth', 'Job', 'Ps', 'Prov',
  'Eccl', 'Song', 'Isa', 'Jer', 'Lam', 'Ezek', 'Dan', 'Hos', 'Joel', 'Amos',
  'Obad', 'Jonah', 'Mic', 'Nah', 'Hab', 'Zeph', 'Hag', 'Zech', 'Mal', 'Matt',
  'Mark', 'Luke', 'John', 'Acts', 'Rom', '1Cor', '2Cor', 'Gal', 'Eph', 'Phil',
  'Col', '1Thess', '2Thess', '1Tim', '2Tim', 'Titus', 'Phlm', 'Heb', 'Jas',
  '1Pet', '2Pet', '1John', '2John', '3John', 'Jude', 'Rev',
];

/// TSK's short-form key list, mapped onto OSIS.
///
/// Every entry here is from the key list TSK itself publishes. Two entries look
/// contradictory and are not: `jud` is Judges and `jude` is Jude. Reading them as the same
/// book would send every reference from one to the other, which is invisible in a spot
/// check and wrong across a Bible — so they are kept apart, and the abbreviated `oba` is
/// filed under Obadiah because Obadiah is one chapter long and cannot be confused.
const _tskAliases = <String, String>{
  'ge': 'Gen',
  'ex': 'Exod',
  'le': 'Lev',
  'nu': 'Num',
  'de': 'Deut',
  'jos': 'Josh',
  'jud': 'Judg',
  'ru': 'Ruth',
  '1sa': '1Sam',
  '2sa': '2Sam',
  '1ki': '1Kgs',
  '2ki': '2Kgs',
  '1ch': '1Chr',
  '2ch': '2Chr',
  'ezr': 'Ezra',
  'ne': 'Neh',
  'est': 'Esth',
  'ps': 'Ps',
  'pro': 'Prov',
  'ecc': 'Eccl',
  'so': 'Song',
  'son': 'Song',
  'lam': 'Lam',
  'eze': 'Ezek',
  'dan': 'Dan',
  'joe': 'Joel',
  'amo': 'Amos',
  'oba': 'Obad',
  'ob': 'Obad',
  'ob1': 'Obad',
  'jon': 'Jonah',
  'nam': 'Nah',
  'zec': 'Zech',
  'mat': 'Matt',
  'mt': 'Matt',
  'mr': 'Mark',
  'mrk': 'Mark',
  'lu': 'Luke',
  'luk': 'Luke',
  'joh': 'John',
  'jhn': 'John',
  'ac': 'Acts',
  'act': 'Acts',
  'ro': 'Rom',
  '1co': '1Cor',
  '2co': '2Cor',
  'ga': 'Gal',
  'php': 'Phil',
  '1th': '1Thess',
  '1the': '1Thess',
  '2th': '2Thess',
  '2the': '2Thess',
  '1ti': '1Tim',
  '2ti': '2Tim',
  'phm': 'Phlm',
  'jame': 'Jas',
  '1pe': '1Pet',
  '2pe': '2Pet',
  '1jo': '1John',
  '2jo': '2John',
  '3jo': '3John',
  're': 'Rev',
};

/// Every abbreviation this class accepts, lower-cased, mapped to an OSIS code.
///
/// Built once from [_osisCodes] and [_tskAliases] rather than hand-written as one literal,
/// because a hand-written list is where `jud` and `jude` end up colliding — and the
/// compiler cannot catch that, since a duplicate key in a `const` map is legal right up
/// until it is a duplicate *meaning*.
final Map<String, String> _tskBooks = {
  for (final code in _osisCodes) code.toLowerCase(): code,
  ..._tskAliases,
};

/// A row of the TSK TSV that could not be turned into references.
class RejectedXrefRow {
  const RejectedXrefRow({
    required this.line,
    required this.reason,
    required this.raw,
  });

  /// 1-based line number in the source file, so a report points at something findable.
  final int line;
  final String reason;
  final String raw;
}

/// The outcome of reading a cross-reference file.
class XrefParseResult {
  const XrefParseResult({required this.references, required this.rejected});

  final List<CrossReference> references;

  /// Rows that were skipped, with the reason.
  ///
  /// Kept rather than counted. A file that loses a thousand rows to an unknown book
  /// abbreviation produces a reader that silently shows fewer references than the source
  /// has, and nobody would know to look.
  final List<RejectedXrefRow> rejected;

  bool get isClean => rejected.isEmpty;
}

/// Parses the TSK cross-reference TSV.
///
/// The file is five tab-separated columns — `book`, `chapter`, `verse`, `anchor`,
/// `references` — where `references` is a pipe-separated list of
/// `Book chapter:verse[-verse][,verse…]` entries.
///
/// Rows whose book is not in [_tskBooks], or whose references name a book the map does not
/// know, are rejected rather than dropped. Both are ways this data goes wrong quietly, and
/// a rejection list is what lets a build fail loudly instead of shipping a Bible with holes
/// in its cross-references.
XrefParseResult parseXrefs(String tsv, {String? sourceName}) {
  final references = <CrossReference>[];
  final rejected = <RejectedXrefRow>[];
  final lines = tsv.split('\n');

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    if (raw.trim().isEmpty) continue;
    final line = i + 1;

    // The header names the columns; it is not data.
    if (line == 1 && raw.startsWith('book\t')) continue;

    final columns = raw.split('\t');
    if (columns.length < 5) {
      rejected.add(RejectedXrefRow(
        line: line,
        reason: 'expected 5 tab-separated columns, found ${columns.length}',
        raw: raw,
      ));
      continue;
    }

    // Looked up without whitespace, for the same reason targets are: the source spells a
    // numbered book both `1 Sam` and `1Sam`, and keying on only one form silently drops
    // every reference from 1 Samuel.
    final fromBook = _tskBooks[
      columns[0].replaceAll(RegExp(r'\s+'), '').toLowerCase()
    ];
    final fromChapter = int.tryParse(columns[1].trim());
    final fromVerse = int.tryParse(columns[2].trim());
    final anchor = columns[3].trim();

    if (fromBook == null) {
      rejected.add(RejectedXrefRow(
        line: line,
        reason: 'unknown source book "${columns[0].trim()}"',
        raw: raw,
      ));
      continue;
    }
    if (fromChapter == null || fromChapter < 1 || fromVerse == null || fromVerse < 1) {
      rejected.add(RejectedXrefRow(
        line: line,
        reason: 'chapter and verse must be positive integers, '
            'found "${columns[1].trim()}" and "${columns[2].trim()}"',
        raw: raw,
      ));
      continue;
    }
    if (anchor.isEmpty) {
      rejected.add(RejectedXrefRow(
        line: line,
        reason: 'the anchor phrase is empty, so there is nothing to attach the reference to',
        raw: raw,
      ));
      continue;
    }

    final targets = <CrossReferenceTarget>[];
    String? badTarget;
    for (final entry in columns[4].split('|')) {
      final parsed = _parseTarget(entry);
      if (parsed == null) {
        badTarget = entry;
        break;
      }
      targets.addAll(parsed);
    }

    if (badTarget != null) {
      rejected.add(RejectedXrefRow(
        line: line,
        reason: 'unreadable target reference "$badTarget"',
        raw: raw,
      ));
      continue;
    }

    references.add(CrossReference(
      fromBook: fromBook,
      fromChapter: fromChapter,
      fromVerse: fromVerse,
      anchor: anchor,
      targets: targets,
    ));
  }

  return XrefParseResult(references: references, rejected: rejected);
}

/// The targets one `Book chapter:verse…` entry names, or null when it cannot be read.
///
/// A comma inside the verse part means several single verses in one book and chapter —
/// `Ps 33:6,9`, `Gen 1:10,12,18` — so each becomes its own target. The alternative is
/// carrying `"6,9"` as a verse number, which no module can address: the reference would be
/// stored, and following it would go nowhere.
///
/// A hyphen means a range and stays one target carrying both ends, because `John 1:1-3` is
/// read as a span rather than as three separate passages.
List<CrossReferenceTarget>? _parseTarget(String entry) {
  final trimmed = entry.trim();
  if (trimmed.isEmpty) return null;

  // The *first* colon separates the chapter from the verse. Using the last one would break
  // on any reference that carried a colon in the book part, and taking the first is also
  // what lets `Gen 1:10,12,18` keep its single book and chapter.
  final colon = trimmed.indexOf(':');
  if (colon < 0) return null;

  final bookPart = trimmed.substring(0, colon).trim();
  // A book name may itself contain a space — `1 Chr`, `2 Thess` — so the number after the
  // last space is the chapter and everything before it is the book. Splitting on the first
  // space would read `1` as the book of `1 Chr 16:26`.
  final space = bookPart.lastIndexOf(RegExp(r'\s'));
  if (space < 0) return null;

  // Looked up without whitespace, because the source spells a numbered book two ways:
  // `1 Cor` with a space and `1Cor` without. Keying on the spaced form only would reject
  // half the New Testament.
  final book = _tskBooks[
    bookPart.substring(0, space).replaceAll(RegExp(r'\s+'), '').toLowerCase()
  ];
  final chapter = int.tryParse(bookPart.substring(space + 1).trim());
  if (book == null || chapter == null || chapter < 1) return null;

  final verses = trimmed.substring(colon + 1).trim();
  if (verses.isEmpty) return null;

  final out = <CrossReferenceTarget>[];
  for (final part in verses.split(',')) {
    final range = part.trim().split('-');
    if (range.length > 2) return null;
    final first = int.tryParse(range.first.trim());
    if (first == null || first < 1) return null;
    if (range.length == 1) {
      out.add(CrossReferenceTarget(book: book, chapter: chapter, verse: first));
      continue;
    }
    final last = int.tryParse(range[1].trim());
    if (last == null || last < first) return null;
    out.add(CrossReferenceTarget(
      book: book,
      chapter: chapter,
      verse: first,
      verseEnd: last,
    ));
  }

  return out.isEmpty ? null : out;
}

/// Every OSIS code the TSK abbreviation map can produce.
///
/// Exposed so a build can assert that every book named in a cross-reference file is one the
/// module actually contains. A reference to a book the module lacks is a link that goes
/// nowhere, and it is the module's contents — not the reference file — that decide.
Iterable<String> get tskKnownBooks => _tskBooks.values.toSet();
