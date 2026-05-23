import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:typst_flutter/src/compiler.dart';
import 'package:typst_flutter/src/files.dart';
import 'package:typst_flutter/src/fonts.dart';

/// A scrollable, multi-page viewer for a Typst document.
///
/// This widget compiles the Typst source **once** and lazily renders pages as
/// they are scrolled into view. By default it renders pages using vector SVG
/// graphics for crisp zooming, but can be configured to use rasterized images.
class TypstDocumentViewer extends StatefulWidget {
  /// Creates a [TypstDocumentViewer].
  const TypstDocumentViewer({
    required this.source,
    super.key,
    this.fonts,
    this.files,
    this.date,
    this.useSvg = true,
    this.pixelsPerPt = 2.0,
    this.loadingBuilder,
    this.errorBuilder,
    this.pageSpacing = 8.0,
    this.pageColor = Colors.white,
    this.pageElevation = 2.0,
  });

  /// The Typst markup source to compile and render.
  final String source;

  /// Font files to make available to the Typst compiler.
  final FontSource? fonts;

  /// Virtual files (images, data, includes) the markup may reference.
  final FileSource? files;

  /// The date to inject for `#datetime.today()`.
  final DateTime? date;

  /// If true, renders pages as scalable SVG. If false, renders as raster images
  final bool useSvg;

  /// Density for raster rendering (only used if [useSvg] is false).
  final double pixelsPerPt;

  /// Builder for the loading state shown while the compiler is running.
  final WidgetBuilder? loadingBuilder;

  /// Builder for the error state shown when compilation fails.
  final Widget Function(BuildContext context, Object error)? errorBuilder;

  /// Spacing between pages in the list.
  final double pageSpacing;

  /// Background color of the pages.
  final Color pageColor;

  /// Elevation of the page cards.
  final double pageElevation;

  @override
  State<TypstDocumentViewer> createState() => _TypstDocumentViewerState();
}

class _TypstDocumentViewerState extends State<TypstDocumentViewer> {
  TypstCompiler? _compiler;
  bool _loading = true;
  Object? _error;
  int _pageCount = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_compileDocument());
  }

  @override
  void didUpdateWidget(TypstDocumentViewer old) {
    super.didUpdateWidget(old);
    if (widget.source != old.source ||
        widget.fonts != old.fonts ||
        widget.files != old.files ||
        widget.date != old.date) {
      unawaited(_compileDocument());
    }
  }

  Future<void> _compileDocument() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      _compiler ??= await TypstCompiler.create(
        fonts: widget.fonts ?? FontSource.none(),
      );

      final count = await _compiler!.compileDocument(
        source: widget.source,
        files: widget.files,
        date: widget.date,
      );

      if (!mounted) return;

      setState(() {
        _pageCount = count;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return widget.loadingBuilder?.call(context) ??
          const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return widget.errorBuilder?.call(context, _error!) ??
          Center(
            child: Text(
              _error.toString(),
              style: const TextStyle(color: Colors.red),
            ),
          );
    }

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: widget.pageSpacing),
      itemCount: _pageCount,
      separatorBuilder: (context, index) =>
          SizedBox(height: widget.pageSpacing),
      itemBuilder: (context, index) {
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: widget.pageSpacing),
          child: Card(
            elevation: widget.pageElevation,
            color: widget.pageColor,
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.zero,
            child: _TypstPageRenderer(
              compiler: _compiler!,
              pageIndex: index,
              useSvg: widget.useSvg,
              pixelsPerPt: widget.pixelsPerPt,
            ),
          ),
        );
      },
    );
  }
}

class _TypstPageRenderer extends StatefulWidget {
  const _TypstPageRenderer({
    required this.compiler,
    required this.pageIndex,
    required this.useSvg,
    required this.pixelsPerPt,
  });

  final TypstCompiler compiler;
  final int pageIndex;
  final bool useSvg;
  final double pixelsPerPt;

  @override
  State<_TypstPageRenderer> createState() => _TypstPageRendererState();
}

class _TypstPageRendererState extends State<_TypstPageRenderer> {
  String? _svgString;
  ui.Image? _image;
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_render());
  }

  @override
  void didUpdateWidget(_TypstPageRenderer old) {
    super.didUpdateWidget(old);
    if (widget.useSvg != old.useSvg ||
        widget.pixelsPerPt != old.pixelsPerPt ||
        widget.pageIndex != old.pageIndex ||
        widget.compiler != old.compiler) {
      unawaited(_render());
    }
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _render() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      if (widget.useSvg) {
        final svg = await widget.compiler.renderCachedPageAsSvg(
          pageIndex: widget.pageIndex,
        );
        if (!mounted) return;
        setState(() {
          _svgString = svg;
          _image?.dispose();
          _image = null;
          _loading = false;
        });
      } else {
        final result = await widget.compiler.renderCachedPage(
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
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        height: 400,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return SizedBox(
        height: 400,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _error.toString(),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (widget.useSvg && _svgString != null) {
      return SvgPicture.string(_svgString!);
    } else if (_image != null) {
      return RawImage(image: _image, fit: BoxFit.contain);
    }

    return const SizedBox(height: 400);
  }
}
