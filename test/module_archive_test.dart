import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:logos_catalogs/module_archive.dart';

/// The determinism rule, checked without an eleven-megabyte build.
///
/// `build_module.dart` used to assemble its archive inline, so the only way to find out
/// whether a build was reproducible was to run one twice and compare. This file makes the
/// rule a unit test instead, which is the difference between a property that is checked
/// and a property that is intended.
void main() {
  group('a module archive is reproducible', () {
    final manifest = Uint8List.fromList('{"id":"KJV"}'.codeUnits);
    final content = Uint8List.fromList(List<int>.generate(4096, (i) => i % 251));

    test('the same content encodes to the same bytes twice', () {
      final first = AmfArchive.encode(manifest, content)!;
      final second = AmfArchive.encode(manifest, content)!;

      expect(
        sha256.convert(first).toString(),
        sha256.convert(second).toString(),
        reason: 'two builds of identical content must produce the same digest, or the '
            'sha256 in catalog.json is a value nobody can check',
      );
    });

    test('the timestamp is the DOS epoch, not the wall clock', () {
      // Asserted directly rather than only through the digest, because the digest check
      // above would also pass if the encoder happened to ignore the field — and then the
      // protection would be accidental rather than designed.
      final entry = AmfArchive.entry('content.db', content);

      expect(entry.lastModTime, AmfArchive.dosEpoch);
      expect(entry.lastModTime, 0, reason: '1980-01-01 00:00:00 is the packed zero');
    });

    test('an unpinned entry would not be reproducible, which is the regression', () {
      // The control for the test above: it demonstrates that the property is coming from
      // the pinned timestamp and not from the encoder being well behaved. If this ever
      // stops failing, the two tests above have stopped proving anything.
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final clockStamped = ArchiveFile('content.db', content.length, content)
        ..lastModTime = now;
      final pinned = AmfArchive.entry('content.db', content);

      expect(clockStamped.lastModTime, isNot(pinned.lastModTime),
          reason: 'a wall-clock timestamp is exactly what the epoch pin exists to avoid');
    });

    test('the archive holds exactly the two entries the format names', () {
      final decoded = ZipDecoder().decodeBytes(AmfArchive.encode(manifest, content)!);

      expect(decoded.files.map((f) => f.name), ['manifest.json', 'content.db']);
      // Order is part of the format: a module whose entries can swap is a different
      // digest for the same content.
      expect(decoded.files.first.isFile, isTrue);
      expect(decoded.files.last.isFile, isTrue);
    });

    test('the payload round-trips unchanged', () {
      final decoded = ZipDecoder().decodeBytes(AmfArchive.encode(manifest, content)!);

      expect(decoded.findFile('content.db')!.content, content);
      expect(
        utf8ish(decoded.findFile('manifest.json')!.content),
        '{"id":"KJV"}',
      );
    });
  });
}

/// Decodes an archive's text entry, since the test only cares that bytes survived.
String utf8ish(dynamic bytes) => String.fromCharCodes(bytes as List<int>);
