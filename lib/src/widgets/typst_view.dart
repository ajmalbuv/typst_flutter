import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:typst_flutter/src/compiler.dart';
import 'package:typst_flutter/src/document.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/files.dart';
import 'package:typst_flutter/src/fonts.dart';
import 'package:typst_flutter/src/rust/api/typst.dart' as api;
import 'package:typst_flutter/src/widgets/typst_compiler_provider.dart';

/// How the Typst document should be rendered.
enum TypstRenderMode {
  /// Render as a scalable vector graphic (SVG). Crisp at any zoom.
  svg,

  /// Render as a rasterized pixel image.
  raster,
}

/// A widget that renders a single page of a Typst document.
///
/// If [document] is provided, it renders directly from that handle.
/// If [source] is provided, it manages its own compilation lifecycle.
class TypstView extends StatefulWidget {
  /// Creates a [TypstView] from an already-compiled [TypstDocument].
  const TypstView({
    required this.document,
    super.key,
    this.pageIndex = 0,
    this.renderMode = TypstRenderMode.svg,
    this.pixelsPerPt = 2.0,
    this.fit = BoxFit.contain,
    this.loadingBuilder,
    this.errorBuilder,
  }) : source = null,
       fonts = null,
       files = null,
       date = null;

  /// Creates a [TypstView] that compiles and renders the given [source].
  ///
  /// This constructor maintains its own internal compiler.
  const TypstView.source({
    required this.source,
    super.key,
    this.fonts,
    this.files,
    this.date,
    this.pageIndex = 0,
    this.renderMode = TypstRenderMode.svg,
    this.pixelsPerPt = 2.0,
    this.fit = BoxFit.contain,
    this.loadingBuilder,
    this.errorBuilder,
  }) : document = null;

  /// The compiled document to render.
  final TypstDocument? document;

  /// The source markup (if not providing a compiled document).
  final String? source;

  /// Font files for compilation (if providing [source]).
  final FontSource? fonts;

  /// Virtual files for compilation (if providing [source]).
  final FileSource? files;

  /// The date to inject for `#datetime.today()` (if providing [source]).
  final DateTime? date;

  /// The 0-based index of the page to render.
  final int pageIndex;

  /// The rendering mode (SVG or Raster).
  final TypstRenderMode renderMode;

  /// Pixel density for raster rendering.
  final double pixelsPerPt;

  /// How the image/SVG should be inscribed into the available space.
  final BoxFit fit;

  /// Builder for the loading state.
  final WidgetBuilder? loadingBuilder;

  /// Builder for the error state.
  ///
  /// Receives the [BuildContext] and the [TypstException] that caused the
  /// failure. Inspect the concrete type to distinguish between compile
  /// errors ([TypstCompileException]) and render errors
  /// ([TypstRenderException]).
  final Widget Function(BuildContext context, TypstException error)?
  errorBuilder;

  @override
  State<TypstView> createState() => _TypstViewState();
}

class _TypstViewState extends State<TypstView> {
  // If managing our own compiler:
  TypstCompiler? _compiler;
  bool _ownsCompiler = false;
  TypstDocument? _ownedDocument;

  // Render state:
  ui.Image? _image;
  String? _svgString;
  api.PageInfo? _pageInfo;

  bool _loading = true;
  TypstException? _error;

  bool _didInit = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      unawaited(_prepareAndRender());
    }
  }

  @override
  void didUpdateWidget(TypstView old) {
    super.didUpdateWidget(old);
    var needsRender = false;

    if (widget.document != null) {
      if (widget.document != old.document ||
          widget.pageIndex != old.pageIndex ||
          widget.renderMode != old.renderMode ||
          widget.pixelsPerPt != old.pixelsPerPt) {
        needsRender = true;
      }
    } else if (widget.source != null) {
      if (widget.source != old.source ||
          widget.fonts != old.fonts ||
          widget.files != old.files ||
          widget.date != old.date) {
        if (widget.fonts != old.fonts) {
          if (_ownsCompiler) {
            _compiler?.dispose();
          }
          _compiler = null;
          _ownsCompiler = false;
        }
        needsRender = true;
      } else if (widget.pageIndex != old.pageIndex ||
          widget.renderMode != old.renderMode ||
          widget.pixelsPerPt != old.pixelsPerPt) {
        needsRender = true;
      }
    }

    if (needsRender) {
      unawaited(_prepareAndRender());
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    _ownedDocument?.dispose();
    if (_ownsCompiler) {
      _compiler?.dispose();
    }
    super.dispose();
  }

  Future<void> _prepareAndRender() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      TypstDocument doc;
      if (widget.document != null) {
        doc = widget.document!;
      } else {
        final providedCompiler = TypstCompilerProvider.maybeOf(context);
        if (providedCompiler != null) {
          if (_ownsCompiler) {
            _compiler?.dispose();
            _ownsCompiler = false;
          }
          _compiler = providedCompiler;
          if (widget.fonts != null && widget.fonts != const FontSource.none()) {
            await _compiler!.addFonts(widget.fonts!);
          }
        } else {
          if (_compiler == null) {
            _compiler = await TypstCompiler.create(
              fonts: widget.fonts ?? const FontSource.none(),
            );
            _ownsCompiler = true;
          }
        }
        // Capture the previous document before the async gap so we can
        // dispose it after the new one is safely stored.
        final previousDoc = _ownedDocument;
        final compiledDoc = await _compiler!.compile(
          source: widget.source!,
          files: widget.files,
          date: widget.date,
        );
        // If the widget was disposed while we were compiling, release the
        // newly compiled document immediately and bail out.
        if (!mounted) {
          compiledDoc.dispose();
          return;
        }
        previousDoc?.dispose();
        _ownedDocument = compiledDoc;
        doc = compiledDoc;
      }

      if (widget.pageIndex >= doc.pageCount) {
        throw const TypstCompileException('Page index out of bounds');
      }

      final pageInfo = doc.pageInfo(widget.pageIndex);
      if (!mounted) return;
      setState(() {
        _pageInfo = pageInfo;
      });

      if (widget.renderMode == TypstRenderMode.svg) {
        final svg = await doc.renderSvg(widget.pageIndex);
        if (!mounted) return;
        setState(() {
          _svgString = svg;
          _image?.dispose();
          _image = null;
          _loading = false;
        });
      } else {
        final result = await doc.renderRaster(
          pageIndex: widget.pageIndex,
          pixelsPerPt: widget.pixelsPerPt,
        );
        final image = await result.toImage();
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
          _svgString = null;
          _loading = false;
        });
      }
    } on TypstException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TypstRenderException(e.toString());
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _image == null && _svgString == null) {
      return _buildWrapper(
        child:
            widget.loadingBuilder?.call(context) ??
            const Center(child: CircularProgressIndicator()),
      );
    }

    final error = _error;
    if (error != null && _image == null && _svgString == null) {
      return _buildWrapper(
        child:
            widget.errorBuilder?.call(context, error) ??
            Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error.toString(),
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
      );
    }

    return _buildWrapper(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.renderMode == TypstRenderMode.svg && _svgString != null)
            SvgPicture.string(_svgString!, fit: widget.fit)
          else if (_image != null)
            RawImage(image: _image, fit: widget.fit),
          if (_loading)
            const Positioned(
              right: 8,
              bottom: 8,
              child: _SmallLoadingIndicator(),
            ),
          if (error != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                color: Colors.red.withValues(alpha: 0.9),
                padding: const EdgeInsets.all(8),
                child: Text(
                  error.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildWrapper({required Widget child}) {
    if (_pageInfo != null) {
      return AspectRatio(
        aspectRatio: _pageInfo!.widthPt / _pageInfo!.heightPt,
        child: child,
      );
    }
    return SizedBox(height: 400, child: child);
  }
}

class _SmallLoadingIndicator extends StatelessWidget {
  const _SmallLoadingIndicator();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(6),
    decoration: BoxDecoration(
      color: Colors.black54,
      borderRadius: BorderRadius.circular(4),
    ),
    child: const SizedBox(
      width: 12,
      height: 12,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    ),
  );
}
