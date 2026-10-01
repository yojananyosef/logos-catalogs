import 'dart:io';

import 'package:test/test.dart';

import '../lib/xref_ingest.dart';

void main() {
  group('parsing a TSK row', () {
    test('reads a verse with several targets', () {
      final result = parseXrefs(
        'Gen\t1\t1\tbeginning\tProv 8:22-24|Prov 16:4|Mark 13:19\n',
      );

      expect(result.isClean, isTrue, reason: '${result.rejected}');
      expect(result.references, hasLength(1));

      final ref = result.references.single;
      expect(ref.fromBook, 'Gen');
      expect(ref.fromChapter, 1);
      expect(ref.fromVerse, 1);
      expect(ref.anchor, 'beginning');
      expect(ref.targets, hasLength(3));
      expect(ref.targets.first.book, 'Prov');
      expect(ref.targets.first.chapter, 8);
      expect(ref.targets.first.verse, 22);
      expect(ref.targets.first.verseEnd, 24);
      expect(ref.targets[2].book, 'Mark');
      expect(ref.targets[2].verseEnd, isNull);
    });

    test('a comma means two passages, not one odd verse number', () {
      // `Ps 33:6,9` is the case that matters: parsing the whole tail as a verse number
      // yields "6,9", which no module can address, and the reference silently disappears.
      final result = parseXrefs('Ps\t33\t6\tcolours\tPs 33:6,9\n');

      final targets = result.references.single.targets;
      expect(targets, hasLength(2));
      expect(targets.map((t) => t.verse), [6, 9]);
      expect(targets.every((t) => t.book == 'Ps' && t.chapter == 33), isTrue);
    });

    test('a comma list may mix ranges and single verses', () {
      // `Gen 1:10,12,18,25,31` is the common shape, and every part has to survive.
      final result = parseXrefs('Gen\t1\t10\therb\tGen 1:11-12,26-28,29-31\n');

      expect(
        result.references.single.targets.map((t) => t.label),
        ['Gen 1:11-12', 'Gen 1:26-28', 'Gen 1:29-31'],
      );
    });

    test('a numbered book is read whether the source spaces it or not', () {
      // The source uses both `1 Sam` and `1Sam`. Keying on one form only loses half the
      // references from 1 Samuel, which no spot check would notice.
      final spaced = parseXrefs('Gen\t1\t1\tseed\t1 Sam 1:1\n');
      final tight = parseXrefs('Gen\t1\t1\tseed\t1Sam 1:1\n');

      expect(spaced.references.single.targets.single.book, '1Sam');
      expect(tight.references.single.targets.single.book, '1Sam');
    });

    test('the source book column is read with or without a space', () {
      expect(
        parseXrefs('1 Sam\t1\t1\tword\tJohn 1:1\n').references.single.fromBook,
        '1Sam',
      );
      expect(
        parseXrefs('1Sam\t1\t1\tword\tJohn 1:1\n').references.single.fromBook,
        '1Sam',
      );
    });

    test('maps the source abbreviations onto OSIS codes', () {
      final result = parseXrefs(
        '1John\t1\t9\tlife\tJohn 1:5|1 Cor 8:6|2 Pet 1:4\n',
      );

      expect(result.isClean, isTrue, reason: '${result.rejected}');
      expect(result.references.single.fromBook, '1John');
      expect(
        result.references.single.targets.map((t) => t.book),
        ['John', '1Cor', '2Pet'],
      );
    });

    test('the two Peters stay two books', () {
      // Filing every reference from 1 Peter under 2 Peter passes a spot check, so the
      // numbered books are checked explicitly.
      final result = parseXrefs('Jas\t1\t1\tbond\t1Pet 1:2|2Pet 1:2\n');

      expect(
        result.references.single.targets.map((t) => t.book),
        ['1Pet', '2Pet'],
      );
    });

    test('Judges and Jude are different books', () {
      // TSK's short list uses `jud` for Judges and `jude` for Jude. Collapsing them sends
      // every reference from one book to the other.
      expect(
        parseXrefs('Judg\t1\t1\tjudge\tjud 6:30\n')
            .references
            .single
            .targets
            .single
            .book,
        'Judg',
      );
      expect(
        parseXrefs('1Pet\t1\t1\tw\tjude 1:3\n')
            .references
            .single
            .targets
            .single
            .book,
        'Jude',
      );
    });

    test('skips the header row rather than rejecting it', () {
      final result = parseXrefs('book\tchapter\tverse\tanchor\treferences\n'
          'Gen\t1\t1\tbeginning\tJohn 1:1\n');

      expect(result.isClean, isTrue);
      expect(result.references, hasLength(1));
    });

    test('labels a range the way the reader will show it', () {
      final result = parseXrefs('Gen\t1\t1\tWord\tJohn 1:1-3\n');

      expect(result.references.single.targets.single.label, 'John 1:1-3');
    });
  });

  group('rejecting a row rather than dropping it', () {
    test('an unknown book is rejected with the line number', () {
      final result = parseXrefs('Gen\t1\t1\tbeginning\tJohn 1:1\n'
          'Apocrypha\t1\t1\tword\tJohn 1:1\n');

      expect(result.references, hasLength(1));
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.line, 2);
      expect(result.rejected.single.reason, contains('Apocrypha'));
    });

    test('an unreadable target is rejected', () {
      final result = parseXrefs('Gen\t1\t1\tbeginning\tJohn 1\n');

      expect(result.references, isEmpty);
      expect(result.rejected.single.reason, contains('unreadable target'));
    });

    test('an empty anchor is rejected because there is nothing to attach it to', () {
      final result = parseXrefs('Gen\t1\t1\t\tJohn 1:1\n');

      expect(result.references, isEmpty);
      expect(result.rejected.single.reason, contains('anchor'));
    });

    test('a row with too few columns is rejected', () {
      final result = parseXrefs('Gen\t1\t1\tbeginning\n');

      expect(result.rejected.single.reason, contains('5 tab-separated columns'));
    });

    test('a non-positive verse is rejected', () {
      final result = parseXrefs('Gen\t1\t0\tword\tJohn 1:1\n');

      expect(result.rejected.single.reason, contains('positive integers'));
    });

    test('a reversed range is rejected', () {
      final result = parseXrefs('Gen\t1\t1\tword\tJohn 5:3-2\n');

      expect(result.references, isEmpty);
      expect(result.rejected.single.reason, contains('unreadable target'));
    });
  });

  group('the real file', () {
    // Parsing the whole KJV file is the only way to find the abbreviations it uses that
    // this map does not know. A spot check of the first rows proves nothing about row
    // 40,000, and an unknown abbreviation is exactly the defect this file is for.
    //
    // Skipped when the file is absent, for the reason `real_modules_test.dart` skips: the
    // payload is 4.9 MB of third-party data and is not committed to this repository. The
    // skip reason carries the URL and the licence so anyone who wants the coverage can get
    // it in one step.
    const path = 'test/fixtures/crossreferences_kjv.tsv';
    final file = File(path);

    if (!file.existsSync()) {
      test(
        'the real cross-reference file is present',
        () {},
        skip: 'not fetched. Run:\n'
            '  curl -sL -o $path https://raw.githubusercontent.com/'
            'CrossReferences-org/bible-cross-references/main/tsv/'
            'crossreferences_kjv.tsv\n'
            'CC BY 4.0 over the public-domain TSK.',
      );
      return;
    }

    final result = parseXrefs(file.readAsStringSync());

    test('has no rejected rows', () {
      expect(result.rejected, isEmpty,
          reason: 'the first rejections are: '
              '${result.rejected.take(5).map((r) => 'line ${r.line}: ${r.reason}')}');
    });

    test('produces a substantial number of references', () {
      expect(result.references.length, greaterThan(50000));
    });

    test('every reference points at a book in the canon', () {
      final outside = <String>{};
      for (final ref in result.references) {
        for (final t in ref.targets) {
          if (!tskKnownBooks.contains(t.book)) outside.add(t.book);
        }
      }
      expect(outside, isEmpty);
    });

    test('the anchor for Gen 1:1 distinguishes the two phrases', () {
      // The whole reason this is phrase-level: the same verse has "beginning" and "God",
      // pointing at different passages.
      final gen11 = result.references
          .where((r) => r.fromBook == 'Gen' && r.fromChapter == 1 && r.fromVerse == 1)
          .map((r) => r.anchor)
          .toList();

      expect(gen11, contains('beginning'));
      expect(gen11, contains('God'));
    });

    test('John 1:1 has references', () {
      final john1_1 = result.references
          .where((r) => r.fromBook == 'John' && r.fromChapter == 1 && r.fromVerse == 1)
          .toList();

      expect(john1_1, isNotEmpty);
    });
  });
}
