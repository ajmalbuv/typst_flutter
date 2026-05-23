import 'package:typst_flutter/src/rust/api/typst.dart' as api;

/// Base class for all Typst-related exceptions.
class TypstException implements Exception {
  /// Creates a [TypstException] with the given error [message].
  const TypstException(this.message);

  /// The error message describing the exception.
  final String message;
  @override
  String toString() => 'TypstException: $message';
}

/// Thrown when the Typst compiler fails to compile a document.
class TypstCompileException extends TypstException {
  /// Creates a [TypstCompileException] with the given [message].
  const TypstCompileException(super.message, {this.diagnostics = const []});

  /// Structured diagnostics from the Typst compiler.
  final List<api.TypstDiagnostic> diagnostics;

  @override
  String toString() {
    if (diagnostics.isEmpty) return super.toString();

    final buffer = StringBuffer('Typst Compilation Errors:\n');
    for (final diag in diagnostics) {
      buffer.writeln('[${diag.severity.toUpperCase()}] ${diag.message}');
      for (final hint in diag.hints) {
        buffer.writeln('  Hint: $hint');
      }
    }
    return buffer.toString().trim();
  }
}

/// Thrown when the native typst_flutter library cannot be loaded.
class TypstLibraryNotFoundException implements Exception {
  /// Creates a [TypstLibraryNotFoundException] with the given [message].
  const TypstLibraryNotFoundException(this.message);

  /// The error message detailing why the library was not found.
  final String message;

  @override
  String toString() => 'TypstLibraryNotFoundException: $message';
}
