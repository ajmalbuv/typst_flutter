import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:typst_flutter/src/compiler.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/files.dart';
import 'package:typst_flutter/src/fonts.dart';

/// A Flutter widget that renders a Typst document page as an image.
///
/// [TypstView] compiles the given [source] markup and renders the result
/// inline. It **automatically re-renders** whenever [source], [fonts],
/// [files], [pageIndex], or [pixelsPerPt] changes — making it suitable for
/// live-preview editors.
///
/// Re-renders are debounced by [debounceDuration] (default 300 ms) so that
/// rapid changes during typing do not flood the native compiler.
///
/// ### Basic usage
/// ```dart
/// TypstView(
///   source: r'''
///     #set page(width: 148mm, height: 210mm, margin: 1cm)
///     = Hello, Typst!
///     This is rendered *natively* inside Flutter.
///   ''',
/// )
/// ```
///
/// ### With custom fonts and images
/// ```dart
/// TypstView(
///   source: r'#image("logo.png") Hello!',
///   fonts: FontSource.assets(['assets/fonts/Roboto.ttf']),
///   files: FileSource.assets({'logo.png': 'assets/images/logo.png'}),
///   pixelsPerPt: 2.0,
///   loadingBuilder: (context) => const CircularProgressIndicator(),
///   errorBuilder: (context, error) => Text(
///     error.toString(),
///     style: const TextStyle(color: Colors.red),
///   ),
/// )
/// ```
class TypstView extends StatefulWidget {
  /// Creates a [TypstView] that compiles and renders the given [source].
  const TypstView({
    required this.source,
    super.key,
    this.fonts,
    this.files,
    this.pageIndex = 0,
    this.pixelsPerPt = 2.0,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.loadingBuilder,
    this.errorBuilder,
    this.fit = BoxFit.contain,
  });

  /// The Typst markup source to compile and render.
  ///
  /// Changing this property triggers a debounced re-render.
  final String source;

  /// Font files to make available to the Typst compiler.
  ///
  /// Defaults to [FontSource.none] (Typst built-in fonts only).
  /// Changing this property triggers a re-render.
  final FontSource? fonts;

  /// Virtual files (images, data, includes) the markup may reference.
  ///
  /// The map key must match the path written in the markup exactly.
  /// For example, `FileSource.assets({'logo.png': 'assets/logo.png'})`
  /// makes `#image("logo.png")` work. Changing this triggers a re-render.
  final FileSource? files;

  /// Zero-based index of the page to render.
  ///
  /// Defaults to 0 (first page). Changing this triggers a re-render.
  final int pageIndex;

  /// Pixels per typographic point.
  ///
  /// A value of 2.0 produces crisp output on standard high-DPI displays.
  /// Higher values produce sharper images at the cost of more memory.
  /// Defaults to 2.0.
  final double pixelsPerPt;

  /// How long to wait after the last change before triggering a re-render.
  ///
  /// Defaults to 300 milliseconds. Set to [Duration.zero] to render
  /// immediately on every change (not recommended for live editors).
  final Duration debounceDuration;

  /// Builder for the loading state shown while the compiler is running.
  ///
  /// If null, a [CircularProgressIndicator] is shown.
  final WidgetBuilder? loadingBuilder;

  /// Builder for the error state shown when compilation fails.
  ///
  /// Receives the [BuildContext] and the thrown [TypstCompileException].
  /// If null, a red [Text] with the error message is shown.
  final Widget Function(BuildContext context, TypstCompileException error)?
  errorBuilder;

  /// How the rendered image should be inscribed into the space allocated
  /// for this widget. Defaults to [BoxFit.contain].
  final BoxFit fit;

  @override
  State<TypstView> createState() => _TypstViewState();
}

class _TypstViewState extends State<TypstView> {
  // ── State ──────────────────────────────────────────────────────────────────

  ui.Image? _image;
  TypstCompileException? _error;
  bool _loading = true;

  // ── Internal infrastructure ────────────────────────────────────────────────

  TypstCompiler? _compiler;
  Timer? _debounce;

  /// Tracks the render generation so stale renders from previous debounce
  /// fires are discarded.
  int _generation = 0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Intentionally not awaited: compiler init runs in the background and
    // updates state via setState() when it completes.
    unawaited(_initCompiler());
  }

  @override
  void didUpdateWidget(TypstView old) {
    super.didUpdateWidget(old);

    // Re-create the compiler if the font source changed.
    if (widget.fonts != old.fonts) {
      _compiler?.dispose();
      _compiler = null;
      _scheduleRender();
      return;
    }

    // Re-render if any render-affecting property changed.
    if (widget.source != old.source ||
        widget.files != old.files ||
        widget.pageIndex != old.pageIndex ||
        widget.pixelsPerPt != old.pixelsPerPt) {
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _image?.dispose();
    _compiler?.dispose();
    super.dispose();
  }

  // ── Rendering pipeline ─────────────────────────────────────────────────────

  Future<void> _initCompiler() async {
    try {
      _compiler = await TypstCompiler.create(
        fonts: widget.fonts ?? FontSource.none(),
      );
      _scheduleRender(immediate: true);
    } on TypstCompileException catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = TypstCompileException(e.toString());
          _loading = false;
        });
      }
    }
  }

  void _scheduleRender({bool immediate = false}) {
    _debounce?.cancel();

    if (immediate || widget.debounceDuration == Duration.zero) {
      // Intentionally not awaited: fire-and-forget render.
      unawaited(_render());
      return;
    }

    _debounce = Timer(widget.debounceDuration, _render);
  }

  Future<void> _render() async {
    if (!mounted) return;

    // Increment generation so any in-flight render from a previous call
    // can detect it has been superseded.
    final generation = ++_generation;

    setState(() {
      _loading = true;
      _error = null;
    });

    // Lazily create the compiler if fonts changed and it was cleared.
    _compiler ??= await TypstCompiler.create(
      fonts: widget.fonts ?? FontSource.none(),
    );

    if (!mounted || generation != _generation) return;

    try {
      final result = await _compiler!.renderPage(
        source: widget.source,
        pageIndex: widget.pageIndex,
        pixelsPerPt: widget.pixelsPerPt,
        files: widget.files,
      );

      if (!mounted || generation != _generation) return;

      final newImage = await result.toImage();

      if (!mounted || generation != _generation) {
        newImage.dispose();
        return;
      }

      setState(() {
        _image?.dispose();
        _image = newImage;
        _loading = false;
      });
    } on TypstCompileException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } on Object catch (e) {
      // Catches any unexpected non-TypstCompileException errors from the
      // Rust bridge (e.g. platform channel errors) and presents them as a
      // compile error rather than crashing the widget.
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = TypstCompileException(e.toString());
        _loading = false;
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading && _image == null) {
      return _buildLoading(context);
    }
    if (_error != null && _image == null) {
      return _buildError(context, _error!);
    }

    // Show the rendered image. If we're re-loading (e.g. source just
    // changed), keep the previous image visible while the new one compiles.
    return Stack(
      fit: StackFit.expand,
      children: [
        if (_image != null) RawImage(image: _image, fit: widget.fit),
        if (_loading)
          Positioned(right: 8, bottom: 8, child: _SmallLoadingIndicator()),
        if (_error != null && _image != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ErrorBanner(error: _error!),
          ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) => widget.loadingBuilder != null
      ? widget.loadingBuilder!(context)
      : const Center(child: CircularProgressIndicator());

  Widget _buildError(BuildContext context, TypstCompileException error) =>
      widget.errorBuilder != null
      ? widget.errorBuilder!(context, error)
      : _DefaultErrorView(error: error);
}

// ── Private helper widgets ─────────────────────────────────────────────────

/// A small spinner shown in the corner while a re-render is in progress
/// (i.e. the previous image is still visible).
class _SmallLoadingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(8),
    ),
    child: const SizedBox(
      width: 16,
      height: 16,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    ),
  );
}

/// A slim banner shown at the bottom of the widget when a re-render fails
/// but a previous image is still being displayed.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final TypstCompileException error;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.red.withValues(alpha: 0.85),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    child: Text(
      error.toString(),
      style: const TextStyle(color: Colors.white, fontSize: 12),
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
    ),
  );
}

/// Default full-widget error view used when there is no previous rendered
/// image to fall back on.
class _DefaultErrorView extends StatelessWidget {
  const _DefaultErrorView({required this.error});
  final TypstCompileException error;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: const Color(0xFFFFF3F3),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 32),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}
