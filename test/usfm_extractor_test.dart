import 'package:test/test.dart';
import 'package:logos_catalogs/usfm_extractor.dart';

void main() {
  final extractor = UsfmExtractor();

  group('UsfmExtractor', () {
    test('keeps the first verse of a chapter', () {
      // This is the regression the upstream catalog failed. USFM writes `\c 1` and
      // then verse text with no explicit `\v 1`, because verse 1 is the default.
      const usfm = r'''
\id John
\c 1
In the beginning was the Word, and the Word was with God.
\v 2 He was in the beginning with God.
\v 3 All things were made through him.
''';

      final verses = extractor.extract(usfm);
      expect(verses.first.chapter, 1);
      expect(verses.first.verse, 1);
      expect(verses.first.text, startsWith('In the beginning was the Word'));
      expect(verses.map((v) => v.verse), [1, 2, 3]);
    });

    test('every chapter yields a verse 1', () {
      const usfm = r'''
\id Ruth
\c 1
Now when the judges ruled, there was a famine in the land.
\v 2 And a certain man of Bethlehem in Judah went to sojourn.
\c 2
And Naomi had a kinsman in Bethlehem whose name was Boaz.
\v 2 He was of the family of Elimelech.
''';

      final verses = extractor.extract(usfm);
      final chapterOnes = verses.where((v) => v.verse == 1).map((v) => v.chapter).toSet();
      expect(chapterOnes, {1, 2});
    });

    test('every extracted chapter is contiguous from 1', () {
      // A shape test that would have caught the upstream defect at build time.
      const usfm = r'''
\id Genesis
\c 1
In the beginning God created heaven and earth.
\v 2 And the earth was without form and void.
\c 2
And God said, Let there be light.
\v 2 And there was light.
\c 3
And God saw the light, that it was good.
''';

      final verses = extractor.extract(usfm);
      final byChapter = <int, List<int>>{};
      for (final v in verses) {
        byChapter.putIfAbsent(v.chapter, () => []).add(v.verse);
      }
      for (final entry in byChapter.entries) {
        expect(entry.value.first, 1,
            reason: 'chapter ${entry.key} must start at verse 1');
      }
      expect(byChapter.length, 3);
    });

    test('handles explicit verse one without duplicating it', () {
      const usfm = r'''
\id Psalms
\c 1
\v 1 Blessed is the man who walks not in the counsel of the wicked.
\v 2 For his delight is in the law of the LORD.
''';
      final verses = extractor.extract(usfm);
      expect(verses.map((v) => v.verse), [1, 2]);
      expect(verses.first.text, startsWith('Blessed is the man'));
    });

    test('strips inline markers and collapses whitespace', () {
      const usfm = r'''
\c 1
\v 1 In the beginning was the \add Word \add*, and the Word was
with God.
''';
      final verses = extractor.extract(usfm);
      expect(verses.single.text,
          'In the beginning was the Word, and the Word was with God.');
    });

    test('ignores non-verse markers', () {
      const usfm = r'''
\ide Gen
\c 1
\s1 The Creation
\v 1 In the beginning God created heaven and earth.
\r Genesis 1:1
''';
      final verses = extractor.extract(usfm);
      expect(verses, hasLength(1));
      expect(verses.single.text, 'In the beginning God created heaven and earth.');
    });

    test('records the end of a verse range rather than discarding it', () {
      // The upstream defect, in miniature. `\v 35-36` carries one run of text for both
      // verses; keeping only 35 hides 17:36's words under 17:35, so a lookup of 36 finds
      // nothing while its text is visible one line above. WEB has this in four chapters.
      const usfm = r'''
\c 17
\v 35-36 Two will be taken; one will be left.
\v 37 Where, Lord?
''';
      final verses = extractor.extract(usfm);

      expect(verses.first.verse, 35);
      expect(verses.first.verseEnd, 36);
      expect(verses.first.spansVerses, isTrue);
      expect(verses.first.text, contains('one will be left'));
      expect(verses[1].verse, 37);
      expect(verses[1].verseEnd, isNull, reason: 'a single verse has no end');
    });

    test('a list is treated as a span up to its last number', () {
      const usfm = r'''
\c 1
\v 1,2,3 Alpha beta gamma.
''';
      final verses = extractor.extract(usfm);
      expect(verses.single.verse, 1);
      expect(verses.single.verseEnd, 3);
    });

    test('a single verse number leaves no end', () {
      const usfm = r'''
\c 1
\v 5 Just this one.
''';
      final verses = extractor.extract(usfm);
      expect(verses.single.verse, 5);
      expect(verses.single.verseEnd, isNull);
      expect(verses.single.spansVerses, isFalse);
    });

    test('Strong\'s numbers in the verse text are not read as a span', () {
      // Every real archive is annotated; every fixture here was not. Scanning the whole
      // line for digits turned `strong="H8034"` into verseEnd 8034 and made 2 Samuel 23
      // fail the module's integrity check for a reason that had nothing to do with it.
      const usfm = r'''
\c 23
\v 8 These \add be\add* the \w names|strong="H8034"\w* of the mighty \w men|strong="H1121"\w*
\v 9 And \w after|strong="H0310"\w* him was \w Eleazar|strong="H0499"\w*
''';
      final verses = extractor.extract(usfm);

      expect(verses.map((v) => v.verse), [8, 9]);
      expect(verses.map((v) => v.verseEnd), everyElement(isNull));
      // Attributes are not the extractor's concern: `build_module.dart` strips
      // `|strong="..."` before extraction. What matters here is that the verse text
      // survives intact.
      expect(verses.first.text, contains('mighty'));
    });

    test('a real range is still recorded when the text is annotated', () {
      const usfm = r'''
\c 17
\v 35-36 And \w one|strong="H1520"\w* of \w them|strong="H3588"\w*
''';
      final verses = extractor.extract(usfm);
      expect(verses.single.verse, 35);
      expect(verses.single.verseEnd, 36);
    });
  });
}
