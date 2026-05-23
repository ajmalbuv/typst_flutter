import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:typst_flutter/typst_flutter.dart';

void main() {
  runApp(const MaterialApp(home: ExampleApp()));
}

/// Example app demonstrating the typst_flutter package.
class ExampleApp extends StatefulWidget {
  /// Creates the example app.
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  late Future<TypstCompiler> _compilerFuture;
  final _controller = TextEditingController(
    text: r'''
#set page(width: 148mm, height: 210mm, margin: 1cm)
#set text(font: "Libertinus Serif", size: 12pt)

= Hello Typst!

This document was compiled *natively* inside a Flutter app using
the Typst compiler via Rust FFI.

== Features
- *Fast*: Sub-100ms compilation (now stateful!)
- *Beautiful*: Professional typography bundled in
- *Native*: No WASM or WebView overhead

== Math Support
Typst has first-class math support. Here is the quadratic formula:

$ x = (-b plus.minus sqrt(b^2 - 4a c)) / (2a) $

And some calculus:
$ integral_0^infinity e^(-x^2) dif x = sqrt(pi) / 2 $
''',
  );

  ui.Image? _renderedImage;
  String? _error;
  bool _isCompiling = false;
  bool _isCompilerReady = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initCompiler());
  }

  Future<void> _initCompiler() async {
    try {
      debugPrint('Initializing Typst Compiler...');
      _compilerFuture = TypstCompiler.create();
      await _compilerFuture;
      debugPrint('Typst Compiler Ready!');
      if (mounted) {
        setState(() => _isCompilerReady = true);
        await _compile(); // Auto-compile first test
      }
    } on Object catch (e, stack) {
      debugPrint('Compiler Init Error: $e\n$stack');
      if (mounted) {
        setState(() => _error = 'Compiler Init Error: $e');
      }
    }
  }

  Future<void> _compile() async {
    if (!_isCompilerReady) {
      debugPrint('Cannot compile: compiler not ready.');
      return;
    }

    setState(() {
      _isCompiling = true;
      _error = null;
    });

    try {
      debugPrint('Compiling Typst source...');
      final compiler = await _compilerFuture;
      final result = await compiler.renderPage(source: _controller.text);
      debugPrint('Compilation success! Rendering to image...');
      final image = await result.toImage();
      debugPrint('Image rendered: ${image.width}x${image.height}');

      if (mounted) {
        setState(() {
          _renderedImage = image;
        });
      }
    } on Object catch (e, stack) {
      debugPrint('Compile Error: $e\n$stack');
      if (mounted) {
        setState(() {
          _error = e.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCompiling = false;
        });
      }
    }
  }

  Future<void> _handleExport(String format) async {
    if (!_isCompilerReady) return;

    setState(() => _isCompiling = true);

    try {
      final compiler = await _compilerFuture;
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);

      if (format == 'pdf') {
        final doc = await compiler.compile(source: _controller.text);
        messenger.showSnackBar(
          SnackBar(
            content: Text('PDF Generated: ${doc.pdf.length} bytes'),
            backgroundColor: const Color(0xFFA6E3A1),
          ),
        );
      } else if (format == 'svg') {
        final doc = await compiler.compileSvg(source: _controller.text);
        messenger.showSnackBar(
          SnackBar(
            content: Text('SVG Generated: ${doc.svgs.length} page(s)'),
            backgroundColor: const Color(0xFFFAB387),
          ),
        );
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _isCompiling = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Typst Flutter'),
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: const Color(0xFFCDD6F4),
        actions: [
          if (_isCompilerReady) ...[
            IconButton(
              onPressed: _isCompiling ? null : _compile,
              icon: const Icon(Icons.play_arrow),
              tooltip: 'Compile',
            ),
            PopupMenuButton<String>(
              onSelected: _handleExport,
              icon: const Icon(Icons.download),
              tooltip: 'Export',
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'pdf',
                  child: ListTile(
                    leading: Icon(Icons.picture_as_pdf),
                    title: Text('Export PDF'),
                  ),
                ),
                const PopupMenuItem(
                  value: 'svg',
                  child: ListTile(
                    leading: Icon(Icons.code),
                    title: Text('Export SVG'),
                  ),
                ),
              ],
            ),
          ],
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
              child: _buildPreview(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFF89B4FA),
        onPressed: (_isCompilerReady && !_isCompiling) ? _compile : null,
        child: (!_isCompilerReady || _isCompiling)
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Icon(Icons.refresh, color: Color(0xFF1E1E2E)),
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: SelectableText(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF38BA8), fontSize: 14),
            ),
          ),
        ),
      );
    }

    if (!_isCompilerReady) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFF89B4FA)),
            SizedBox(height: 16),
            Text(
              'Initializing Typst Compiler...',
              style: TextStyle(color: Color(0xFFCDD6F4)),
            ),
          ],
        ),
      );
    }

    if (_renderedImage == null) {
      return const Center(
        child: Text(
          'Press compile to see preview',
          style: TextStyle(color: Color(0xFFBAC2DE)),
        ),
      );
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(
          elevation: 8,
          shadowColor: Colors.black54,
          clipBehavior: Clip.antiAlias,
          child: RawImage(image: _renderedImage),
        ),
      ),
    );
  }
}
