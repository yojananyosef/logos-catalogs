/// Extraction of scripture from USFM into a verse list.
///
/// This is where the upstream catalog had its most serious defect. Its RawText
/// reader indexed a chapter's lines as `lines[verse - 1]`, but in the SWORD RawText
/// layout the first line of a chapter chunk is the chapter marker, so verse N lives at
/// `lines[N]`. Every chapter's first verse was therefore lost — 260 chapters in the
/// ASV and KJV modules, including John 1:1 — and the end-to-end test missed it because
/// it read Genesis 1:1, which is in the Old Testament and unaffected.
class UsfmExtractor {
  UsfmExtractor({this.defaultVerseStartsAtOne = true});

  /// USFM omits an explicit `\v 1` at the start of a chapter because verse 1 is the
  /// default. The text after `\c` and before the first `\v` is therefore verse 1 and
  /// must be captured, not dropped.
  final bool defaultVerseStartsAtOne;

  /// Parses a USFM book body into `[chapter, verse, text]` triples.
  List<UsfmVerse> extract(String usfm) {
    final verses = <UsfmVerse>[];
    var chapter = 0;
    var verse = 0;
    int? verseEnd;
    final buffer = StringBuffer();

    void flush() {
      if (chapter == 0 || verse == 0) return;
      final text = _normalise(buffer.toString());
      if (text.isNotEmpty) {
        verses.add(UsfmVerse(
          chapter: chapter,
          verse: verse,
          verseEnd: verseEnd,
          text: text,
        ));
      }
      buffer.clear();
      verseEnd = null;
    }

    for (final rawLine in usfm.split('\n')) {
      final line = rawLine.trimRight();

      // A new chapter closes the previous verse. Text accumulated since the last
      // `\c` or `\v` belongs to the current verse, including the implicit verse 1.
      if (line.startsWith('\\c ')) {
        flush();
        final rest = line.substring(3).trim();
        final num = RegExp(r'^\d+').firstMatch(rest)?.group(0);
        chapter = int.tryParse(num ?? '') ?? chapter;
        verse = defaultVerseStartsAtOne ? 1 : 0;
        // USFM sometimes puts the first verse's text on the chapter line itself.
        final inline = rest.replaceFirst(RegExp(r'^\d+'), '').trim();
        if (inline.isNotEmpty) _append(buffer, inline);
        continue;
      }

      if (line.startsWith('\\v ')) {
        flush();
        final spec = line.substring(3).trim();
        // Handles ranges and lists: `\v 1-3`, `\v 1,2,3` take the first number, and
        // whatever follows the number on the same line is this verse's text.
        final match = RegExp(r'^(\d+)').firstMatch(spec);
        if (match != null) {
          verse = int.tryParse(match.group(1)!) ?? verse;

          // A range `35-36` is one run of text covering both verses, so the last number
          // in the spec is where the entry ends. Recorded rather than dropped.
          final numbers = RegExp(r'\d+')
              .allMatches(spec)
              .map((m) => int.tryParse(m.group(0)!) ?? 0)
              .toList();
          final last = numbers.isEmpty ? verse : numbers.last;
          verseEnd = last > verse ? last : null;

          // Drop the range spec before taking text.
          final inline =
              spec.substring(match.end).replaceFirst(RegExp(r'^[\d\s,\-]+'), '').trim();
          if (inline.isNotEmpty) _append(buffer, inline);
        }
        continue;
      }

      if (line.startsWith('\\') || line.startsWith('\\c') || line.startsWith('\\v')) {
        // Other markers (ide, mt, us, rem, ...) contribute no verse text.
        continue;
      }

      if (line.trim().isEmpty) continue;
      _append(buffer, line.trim());
    }

    flush();
    return verses;
  }

  static void _append(StringBuffer buffer, String text) {
    buffer.write(text);
    buffer.write(' ');
  }

  /// Strips USFM inline formatting and collapses whitespace.
  ///
  /// Done with one regex rather than a list of literals: the marker set grows, closers
  /// carry an asterisk (`\add*`), and a list silently misses whichever marker was added
  /// last — which is how stray `*` characters end up in the rendered text.
  static String _normalise(String raw) {
    var s = raw.trim();

    // Character data blocks: \add ... \add*
    s = s.replaceAll(RegExp(r'\\[a-zA-Z0-9]+\*'), '');
    // Character formatting, with or without a trailing asterisk: \add, \q1, \em, \li...
    s = s.replaceAll(RegExp(r'\\[a-zA-Z0-9]+\*?'), '');
    // Nested character sets: {GEN 1:1}
    s = s.replaceAll(RegExp(r'\{[^}]*\}'), '');

    s = s.replaceAll(RegExp(r'\s+'), ' ');
    // Removing a marker leaves a space where it stood, which can land before
    // punctuation: "Word \add*," would otherwise become "Word ,".
    s = s.replaceAllMapped(
      RegExp(r'\s+([,.;:!?])'),
      (m) => m.group(1)!,
    );
    return s.trim();
  }
}

class UsfmVerse {
  const UsfmVerse({
    required this.chapter,
    required this.verse,
    required this.text,
    this.verseEnd,
  });

  final int chapter;
  final int verse;
  final String text;

  /// Last verse this entry covers, when the source spanned several.
  ///
  /// USFM writes a range as one marker with one run of text: `\\v 35-36` followed by
  /// the words of both verses. Taking only the first number and discarding the rest puts
  /// 17:36's text under 17:35 with no record that it was ever spoken for, so a lookup of
  /// the second verse finds nothing while its words sit one line above.
  ///
  /// This is not hypothetical: the upstream WEB module has exactly this in Luke 17,
  /// Acts 8, Acts 15 and Acts 24, and leaves `verseEnd` NULL. Recording the span is what
  /// makes the addressing honest; the reader then has to honour it too.
  final int? verseEnd;

  bool get spansVerses => verseEnd != null && verseEnd! > verse;
}
