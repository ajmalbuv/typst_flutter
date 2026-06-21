import 'package:flutter/widgets.dart';
import 'package:typst_flutter/src/compiler.dart';

/// An [InheritedWidget] that provides a shared [TypstCompiler] to its
/// descendants.
///
/// This avoids the overhead of creating and initializing a new [TypstCompiler]
/// (and its underlying Rust Isolate) for every `TypstView.source()` or
/// `TypstDocumentViewer` in the widget tree.
///
/// Note: The provided [compiler] should be disposed manually when the
/// provider itself is removed from the tree.
class TypstCompilerProvider extends InheritedWidget {
  /// Creates a [TypstCompilerProvider] that provides [compiler] to [child].
  const TypstCompilerProvider({
    required this.compiler,
    required super.child,
    super.key,
  });

  /// The shared compiler instance.
  final TypstCompiler compiler;

  /// Returns the nearest [TypstCompiler] provided by a [TypstCompilerProvider]
  /// ancestor, or `null` if none exists.
  static TypstCompiler? maybeOf(BuildContext context) {
    final provider = context
        .dependOnInheritedWidgetOfExactType<TypstCompilerProvider>();
    return provider?.compiler;
  }

  /// Returns the nearest [TypstCompiler] provided by a [TypstCompilerProvider]
  /// ancestor. Throws if none exists.
  static TypstCompiler of(BuildContext context) {
    final compiler = maybeOf(context);
    assert(compiler != null, 'No TypstCompilerProvider found in context');
    return compiler!;
  }

  @override
  bool updateShouldNotify(TypstCompilerProvider oldWidget) =>
      compiler != oldWidget.compiler;
}
