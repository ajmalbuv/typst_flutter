import 'dart:async';

import 'package:flutter/material.dart';
import 'package:typst_flutter/src/compiler.dart';
import 'package:typst_flutter/src/document.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/files.dart';
import 'package:typst_flutter/src/fonts.dart';
import 'package:typst_flutter/src/widgets/typst_view.dart';

/// A scrollable, multi-page viewer for a Typst document.
///
/// This widget compiles the Typst source **once** and lazily renders pages as
/// they are scrolled into view.
class TypstDocumentViewer extends StatefulWidget {
  /// Creates a [TypstDocumentViewer] that manages its own compilation.
  const TypstDocumentViewer({
    required this.source,
    super.key,
    this.fonts,
    this.files,
    this.date,
    this.renderMode = TypstRenderMode.svg,
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

  /// The rendering mode (SVG or Raster).
  final TypstRenderMode renderMode;

  /// Density for raster rendering (only used if [renderMode] is raster).
  final double pixelsPerPt;

  /// Builder for the loading state shown while the compiler is running.
  final WidgetBuilder? loadingBuilder;

  /// Builder for the error state shown when compilation fails.
  ///
  /// Receives the [BuildContext] and the thrown [TypstCompileException].
  final Widget Function(BuildContext context, TypstCompileException error)?
  errorBuilder;

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
  TypstCompileException? _error;
  TypstDocument? _document;

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
      if (widget.fonts != old.fonts) {
        _compiler?.dispose();
        _compiler = null;
      }
      unawaited(_compileDocument());
    }
  }

  @override
  void dispose() {
    _compiler?.dispose();
    super.dispose();
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

      final doc = await _compiler!.compile(
        source: widget.source,
        files: widget.files,
        date: widget.date,
      );

      if (!mounted) return;

      setState(() {
        _document = doc;
        _loading = false;
      });
    } on TypstCompileException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = TypstCompileException(e.toString());
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

    final doc = _document;
    if (doc == null) return const SizedBox.shrink();

    return ListView.separated(
      padding: EdgeInsets.symmetric(vertical: widget.pageSpacing),
      itemCount: doc.pageCount,
      separatorBuilder: (context, index) =>
          SizedBox(height: widget.pageSpacing),
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.symmetric(horizontal: widget.pageSpacing),
        child: Card(
          elevation: widget.pageElevation,
          color: widget.pageColor,
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: TypstView(
            document: doc,
            pageIndex: index,
            renderMode: widget.renderMode,
            pixelsPerPt: widget.pixelsPerPt,
          ),
        ),
      ),
    );
  }
}
