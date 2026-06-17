// Filters FRB-generated files from lcov.info before Codecov upload.
// Usage: dart run tool/filter_lcov.dart [lcov_path]
//
// Removes coverage entries for files matching lib/src/rust/ (the
// flutter_rust_bridge generated bridge code) so they don't dilute
// the coverage percentage.

import 'dart:io';

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : 'coverage/lcov.info';
  final file = File(path);

  if (!file.existsSync()) {
    stderr.writeln('lcov file not found: $path');
    exit(1);
  }

  final lines = file.readAsLinesSync();
  final output = <String>[];
  var skipping = false;

  for (final line in lines) {
    if (line.startsWith('SF:')) {
      // Normalise path separators for Windows
      final filePath = line.substring(3).replaceAll(r'\', '/');
      if (filePath.contains('lib/src/rust/')) {
        skipping = true;
        continue;
      }
    }
    if (line == 'end_of_record') {
      if (skipping) {
        skipping = false;
        continue;
      }
    }
    if (!skipping) {
      output.add(line);
    }
  }

  file.writeAsStringSync(output.join('\n'));
  stdout.writeln(
    'Filtered lcov: kept ${output.where((l) => l.startsWith('SF:')).length}'
    'source files',
  );
}
