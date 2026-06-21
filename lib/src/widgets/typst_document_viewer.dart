import 'dart:async';

import 'package:flutter/material.dart';
import 'package:typst_flutter/src/compiler.dart';
import 'package:typst_flutter/src/document.dart';
import 'package:typst_flutter/src/exceptions.dart';
import 'package:typst_flutter/src/files.dart';
import 'package:typst_flutter/src/fonts.dart';
import 'package:typst_flutter/src/widgets/typst_compiler_provider.dart';
import 'package:typst_flutter/src/widgets/typst_view.dart';

/// A scrollable, multi-page viewer for a Typst document.
///
/// This widget compiles the Typst source **once** and lazily renders pages as
/// they are scrolled into view.
///
/// There are two ways to use this widget:
///
/// **1. Self-managed compilation** (simple / standalone):
/// ```dart
/// TypstDocumentViewer(
///   source: myMarkup,
///   fonts: FontSource.assets(['assets/fonts/Roboto.ttf']),
/// )
/// ```
///
/// **2. Pre-compiled document** (shared compiler, zero per-widget cost):
/// ```dart
/// final compiler = await TypstCompiler.create(fonts: ...);
/// final doc = await compiler.compile(source: myMarkup);
///
/// TypstDocumentViewer.document(document: doc)
/// ```
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
  }) : document = null;

  /// Creates a [TypstDocumentViewer] from an already-compiled
  /// [TypstDocument].
  ///
  /// This avoids creating a per-widget compiler and is the recommended
  /// approach when you already have a [TypstCompiler] instance.
  const TypstDocumentViewer.document({
    required this.document,
    super.key,
    this.renderMode = TypstRenderMode.svg,
    this.pixelsPerPt = 2.0,
    this.loadingBuilder,
    this.errorBuilder,
    this.pageSpacing = 8.0,
    this.pageColor = Colors.white,
    this.pageElevation = 2.0,
  }) : source = null,
       fonts = null,
       files = null,
       date = null;

  /// The compiled document to render (if using [TypstDocumentViewer.document]).
  final TypstDocument? document;

  /// The Typst markup source to compile and render.
  final String? source;

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

  /// Builder for the error state shown when an error occurs.
  ///
  /// Receives the [BuildContext] and the [TypstException] that caused the
  /// failure. Inspect the concrete type to distinguish between compile
  /// errors ([TypstCompileException]) and render errors
  /// ([TypstRenderException]).
  final Widget Function(BuildContext context, TypstException error)?
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
  bool _ownsCompiler = false;
  bool _loading = true;
  TypstException? _error;
  TypstDocument? _ownedDocument;

  TypstDocument? get _activeDocument => widget.document ?? _ownedDocument;

  bool _didInit = false;

  @override
  void initState() {
    super.initState();
    if (widget.document != null) {
      // Pre-compiled document: no compilation needed.
      _loading = false;
      _didInit = true; // prevent didChangeDependencies from compiling
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didInit) {
      _didInit = true;
      unawaited(_compileDocument());
    }
  }

  @override
  void didUpdateWidget(TypstDocumentViewer old) {
    super.didUpdateWidget(old);

    // Document-mode: re-render if the document handle changed.
    if (widget.document != null) {
      if (widget.document != old.document) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    // Source-mode: recompile if inputs changed.
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
      unawaited(_compileDocument());
    }
  }

  @override
  void dispose() {
    _ownedDocument?.dispose();
    if (_ownsCompiler) {
      _compiler?.dispose();
    }
    super.dispose();
  }

  Future<void> _compileDocument() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
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
      final doc = await _compiler!.compile(
        source: widget.source!,
        files: widget.files,
        date: widget.date,
      );

      // If the widget was disposed while we were compiling, release the
      // newly compiled document immediately and bail out.
      if (!mounted) {
        doc.dispose();
        return;
      }

      previousDoc?.dispose();
      setState(() {
        _ownedDocument = doc;
        _loading = false;
      });
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

    final doc = _activeDocument;
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
