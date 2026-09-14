import 'dart:async';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:typst_flutter/typst_flutter.dart';

/// The main entry point for the example app.
void main() {
  runApp(
    MaterialApp(
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF1E1E2E),
        primaryColor: const Color(0xFF89B4FA),
      ),
      home: const ExampleApp(),
    ),
  );
}

/// Example app demonstrating the typst_flutter package.
class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final _controller = TextEditingController(
    text: r'''
#set page(width: 148mm, height: 210mm, margin: 1cm)
#set text(font: "Libertinus Serif", size: 12pt)

= Hello Typst!

This document was compiled *natively* inside a Flutter app using
the Typst compiler via Rust FFI.

== Features
- *Fast*: Sub-100ms compilation
- *Beautiful*: Professional typography bundled in
- *Native*: No WASM or WebView overhead
- *FFI*: Peak performance via Rust

== Math Support
Typst has first-class math support. Here is the quadratic formula:

$ x = (-b plus.minus sqrt(b^2 - 4a c)) / (2a) $

And some calculus:
$ integral_0^infinity e^(-x^2) dif x = sqrt(pi) / 2 $

== Date Injection
Today's date injected from Flutter: #datetime.today().display()
''',
  );

  String _currentSource = '';
  TypstCompiler? _compiler;
  Object? _initError;

  @override
  void initState() {
    super.initState();
    _currentSource = _controller.text;
    unawaited(_initCompiler());
  }

  Future<void> _initCompiler() async {
    setState(() {
      _initError = null;
    });
    try {
      final compiler = await TypstCompiler.create();
      if (!mounted) {
        compiler.dispose();
        return;
      }
      setState(() {
        _compiler = compiler;
      });
    } on Object catch (e, st) {
      debugPrint('TypstCompiler init error: $e\n$st');
      if (mounted) {
        setState(() {
          _initError = e;
        });
      }
    }
  }

  @override
  void dispose() {
    _compiler?.dispose();
    super.dispose();
  }

  void _compile() {
    setState(() {
      _currentSource = _controller.text;
    });
  }

  Future<void> _showSvgOutput() async {
    if (_compiler == null) return;
    final doc = await _compiler!.compile(source: _controller.text);
    if (!mounted) {
      doc.dispose();
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Interactive SVG Output')),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: doc.pageCount,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) => Center(
                child: Card(
                  elevation: 4,
                  clipBehavior: Clip.antiAlias,
                  child: TypstView(document: doc, pageIndex: index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    doc.dispose();
  }

  Future<void> _showPdfPreview() async {
    if (_compiler == null) return;
    final doc = await _compiler!.compile(source: _controller.text);
    final pdfBytes = await doc.exportPdf();
    doc.dispose();

    await Printing.layoutPdf(onLayout: (format) async => pdfBytes);
  }

  Future<void> _savePdf() async {
    if (_compiler == null) return;
    final doc = await _compiler!.compile(source: _controller.text);
    final pdfBytes = await doc.exportPdf();
    doc.dispose();

    // Printing.sharePdf handles the native iOS "Save to Files" and
    // Android Share Sheet (which includes Save to Drive/Downloads)
    // without requiring explicit storage permissions.
    await Printing.sharePdf(bytes: pdfBytes, filename: 'typst_document.pdf');
  }

  @override
  Widget build(BuildContext context) {
    if (_compiler == null) {
      if (_initError != null) {
        return Scaffold(
          backgroundColor: const Color(0xFF1E1E2E),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    color: Colors.redAccent,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Failed to initialize Typst Compiler',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$_initError',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFBAC2DE),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => unawaited(_initCompiler()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return const Scaffold(
        backgroundColor: Color(0xFF1E1E2E),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF89B4FA)),
        ),
      );
    }

    return TypstCompilerProvider(
      compiler: _compiler!,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Typst Flutter'),
          backgroundColor: const Color(0xFF1E1E2E),
          foregroundColor: const Color(0xFFCDD6F4),
          actions: [
            PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'svg') unawaited(_showSvgOutput());
                if (val == 'pdf') unawaited(_showPdfPreview());
                if (val == 'save') unawaited(_savePdf());
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'svg',
                  child: ListTile(
                    leading: Icon(Icons.zoom_in),
                    title: Text('Interactive SVG'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf),
                    title: Text('Native PDF Preview'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'save',
                  child: ListTile(
                    leading: Icon(Icons.save_alt),
                    title: Text('Save / Share PDF'),
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: TextField(
                  controller: _controller,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 13,
                    color: Color(0xFFCDD6F4),
                  ),
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    fillColor: Color(0xFF1E1E2E),
                    filled: true,
                    hintText: 'Enter Typst markup…',
                  ),
                ),
              ),
            ),
            const Divider(height: 1, color: Color(0xFF45475A)),
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF181825),
                child: TypstDocumentViewer(
                  source: _currentSource,
                  loadingBuilder: (context) => const Center(
                    child: CircularProgressIndicator(color: Color(0xFF89B4FA)),
                  ),
                ),
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFF89B4FA),
          onPressed: _compile,
          child: const Icon(Icons.play_arrow, color: Color(0xFF1E1E2E)),
        ),
      ),
    );
  }
}
