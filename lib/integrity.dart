/// Data integrity of a built module.
///
/// Version-level navigation is the reason this is a correctness gate rather than a
/// nicety: a reader that cannot resolve `Jn 1:1` cannot do verse-level lookup, and a
/// missing first verse in every chapter is the kind of systematic defect that only
/// shows up once a user types a reference.
class IntegrityReport {
  IntegrityReport({
    required this.chaptersChecked,
    required this.versesChecked,
    required this.failures,
  });

  final int chaptersChecked;
  final int versesChecked;
  final List<String> failures;

  bool get isValid => failures.isEmpty;

  @override
  String toString() => isValid
      ? 'integrity OK — $chaptersChecked chapters, $versesChecked verses'
      : 'integrity FAILED — ${failures.length} problem(s)\n'
          '${failures.map((f) => '  $f').join('\n')}';
}
