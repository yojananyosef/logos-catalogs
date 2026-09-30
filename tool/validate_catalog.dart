#!/usr/bin/env dart
// Validates a catalog index against the licensing gate.
//
//   dart run tool/validate_catalog.dart catalog/catalog.json
//     [--jurisdiction=CL] [--non-commercial] [--open-distribution]
//     [--now=2027-01-01]
//
// Exits non-zero when the catalog may not ship, so it can be wired into CI. The
// date can be overridden to check what a build will look like after a licence
// expires.
import 'dart:io';

import 'package:logos_catalogs/validator.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/validate_catalog.dart <catalog.json> '
        '[--jurisdiction=CL] [--non-commercial] [--open-distribution] [--now=YYYY-MM-DD]');
    exit(64);
  }

  final path = args.first;
  String? jurisdiction;
  var commercial = true;
  var closed = true;
  DateTime? now;

  for (final arg in args.skip(1)) {
    if (arg.startsWith('--jurisdiction=')) {
      jurisdiction = arg.split('=').last.toUpperCase();
    } else if (arg == '--non-commercial') {
      commercial = false;
    } else if (arg == '--open-distribution') {
      closed = false;
    } else if (arg.startsWith('--now=')) {
      now = DateTime.tryParse(arg.split('=').last);
      if (now == null) {
        stderr.writeln('invalid --now value');
        exit(64);
      }
    }
  }

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('catalog not found: $path');
    exit(66);
  }

  final catalog = readCatalogFile(file);
  final report = CatalogValidator(
    catalog: catalog,
    now: now ?? DateTime.now().toUtc(),
    commercial: commercial,
    closedDistribution: closed,
    jurisdiction: jurisdiction,
  ).run();

  stdout.writeln('catalog ${catalog.version} — ${report.checkedResources} modules');
  stdout.writeln('target: ${commercial ? 'commercial' : 'non-commercial'} '
      '${closed ? 'closed' : 'open'} distribution'
      '${jurisdiction == null ? '' : ', jurisdiction $jurisdiction'}');

  if (report.canShip) {
    stdout.writeln('\nOK — catalog may be distributed.');
    exit(0);
  }

  stderr.writeln('\nBLOCKED — ${report.violations.length} violation(s):\n');
  for (final v in report.violations) {
    stderr.writeln('  $v');
  }
  exit(1);
}
