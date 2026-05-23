import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:typst_flutter/src/compiler.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/files.dart';
import 'package:typst_flutter/src/fonts.dart';
import 'package:typst_flutter/src/widgets/typst_view.dart' show TypstView;
import 'package:typst_flutter/typst_flutter.dart' show TypstView;

/// A Flutter widget that renders a Typst document page as an SVG.
///
/// [TypstSvgView] is similar to [TypstView], but uses vector graphics
/// to keep the rendering razor-sharp at any zoom level without pixelation.
class TypstSvgView extends StatefulWidget {
  /// Creates a [TypstSvgView] that compiles and renders
  /// the given [source] as SVG.
  const TypstSvgView({
    required this.source,
    super.key,
    this.fonts,
    this.files,
    this.pageIndex = 0,
    this.date,
    this.debounceDuration = const Duration(milliseconds: 300),
    this.loadingBuilder,
    this.errorBuilder,
    this.fit = BoxFit.contain,
  });

  /// The Typst markup source to compile and render.
  final String source;

  /// Font files to make available to the Typst compiler.
  final FontSource? fonts;

  /// Virtual files (images, data, includes) the markup may reference.
  final FileSource? files;

  /// Zero-based index of the page to render.
  final int pageIndex;

  /// The date to inject for `#datetime.today()`.
  final DateTime? date;

  /// How long to wait after the last change before triggering a re-render.
  final Duration debounceDuration;

  /// Builder for the loading state shown while the compiler is running.
  final WidgetBuilder? loadingBuilder;

  /// Builder for the error state shown when compilation fails.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// How the rendered image should be inscribed into the space allocated.
  final BoxFit fit;

  @override
  State<TypstSvgView> createState() => _TypstSvgViewState();
}

class _TypstSvgViewState extends State<TypstSvgView> {
  String? _svgString;
  Object? _error;
  bool _loading = true;

  TypstCompiler? _compiler;
  Timer? _debounce;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_initCompiler());
  }

  @override
  void didUpdateWidget(TypstSvgView old) {
    super.didUpdateWidget(old);
    if (widget.fonts != old.fonts) {
      _compiler = null;
      _scheduleRender();
      return;
    }
    if (widget.source != old.source ||
        widget.files != old.files ||
        widget.pageIndex != old.pageIndex ||
        widget.date != old.date) {
      _scheduleRender();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _initCompiler() async {
    try {
      _compiler = await TypstCompiler.create(
        fonts: widget.fonts ?? FontSource.none(),
      );
      _scheduleRender(immediate: true);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _error = e;
          _loading = false;
        });
      }
    }
  }

  void _scheduleRender({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate || widget.debounceDuration == Duration.zero) {
      unawaited(_render());
      return;
    }
    _debounce = Timer(widget.debounceDuration, _render);
  }

  Future<void> _render() async {
    if (!mounted) return;
    final generation = ++_generation;

    setState(() {
      _loading = true;
      _error = null;
    });

    _compiler ??= await TypstCompiler.create(
      fonts: widget.fonts ?? FontSource.none(),
    );

    if (!mounted || generation != _generation) return;

    try {
      await _compiler!.compileDocument(
        source: widget.source,
        files: widget.files,
        date: widget.date,
      );

      if (!mounted || generation != _generation) return;

      final svg = await _compiler!.renderCachedPageAsSvg(
        pageIndex: widget.pageIndex,
      );

      if (!mounted || generation != _generation) return;

      setState(() {
        _svgString = svg;
        _loading = false;
      });
    } on TypstCompileException catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = TypstCompileException(e.toString());
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _svgString == null) {
      return _buildLoading(context);
    }
    if (_error != null && _svgString == null) {
      return _buildError(context, _error!);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_svgString != null) SvgPicture.string(_svgString!, fit: widget.fit),
        if (_loading)
          Positioned(right: 8, bottom: 8, child: _SmallLoadingIndicator()),
        if (_error != null && _svgString != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ErrorBanner(error: _error!),
          ),
      ],
    );
  }

  Widget _buildLoading(BuildContext context) {
    return widget.loadingBuilder != null
        ? widget.loadingBuilder!(context)
        : const Center(child: CircularProgressIndicator());
  }

  Widget _buildError(BuildContext context, Object error) {
    return widget.errorBuilder != null
        ? widget.errorBuilder!(context, error)
        : _DefaultErrorView(error: error);
  }
}

class _SmallLoadingIndicator extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
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
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Container(
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
}

class _DefaultErrorView extends StatelessWidget {
  const _DefaultErrorView({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
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
}
