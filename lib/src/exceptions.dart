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
  ///
  /// Each entry carries severity, the error message, optional hints,
  /// and — after FRB codegen — optional 1-based source location fields
  /// (`spanStart` / `spanEnd`) giving the exact line and column of
  /// the offending range in the Typst markup.
  final List<api.TypstDiagnostic> diagnostics;

  @override
  String toString() {
    if (diagnostics.isEmpty) return super.toString();

    final buffer = StringBuffer('Typst Compilation Errors:\n');
    for (final diag in diagnostics) {
      final severity = diag.severity.name.toUpperCase();
      final loc = diag.spanStart;
      final locStr = loc != null ? '${loc.line}:${loc.column} \u2014 ' : '';
      buffer.writeln('[$severity] $locStr${diag.message}');
      for (final hint in diag.hints) {
        buffer.writeln('  Hint: $hint');
      }
    }
    return buffer.toString().trim();
  }
}

/// Thrown when rendering or exporting a page of a compiled document fails.
///
/// This is distinct from [TypstCompileException]: a [TypstRenderException]
/// means compilation succeeded but a subsequent render or export operation
/// failed (e.g. an internal Typst SVG/PDF error).
///
/// Caller-side mistakes such as passing an invalid page index will throw a
/// [RangeError] instead, consistent with standard Dart collection behaviour.
class TypstRenderException extends TypstException {
  /// Creates a [TypstRenderException] with the given [message].
  const TypstRenderException(super.message);

  @override
  String toString() => 'TypstRenderException: $message';
}
