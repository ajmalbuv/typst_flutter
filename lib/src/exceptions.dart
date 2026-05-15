/// Thrown when the Typst compiler fails to compile a document.
class TypstCompileException implements Exception {
  /// Creates a [TypstCompileException] with the given [message].
  const TypstCompileException(this.message);

  /// The error message from the compiler.
  final String message;

  @override
  String toString() => 'TypstCompileException: $message';
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
