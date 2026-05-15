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
    text: '''
#set page(width: 148mm, height: 210mm, margin: 1cm)
#set text(font: "Linux Libertine", size: 12pt)

= Hello Typst!

This document was compiled *natively* inside a Flutter app using
the Typst compiler via Rust FFI.

== Features
- *Fast*: Sub-100ms compilation
- *Beautiful*: Professional typography
- *Native*: No WASM or WebView overhead
''',
  );

  ui.Image? _renderedImage;
  String? _error;
  bool _isCompiling = false;

  @override
  void initState() {
    super.initState();
    _compilerFuture = TypstCompiler.create();
  }

  Future<void> _compile() async {
    setState(() {
      _isCompiling = true;
      _error = null;
    });

    try {
      final compiler = await _compilerFuture;
      final result = await compiler.renderPage(
        source: _controller.text,
      );
      final image = await result.toImage();
      setState(() {
        _renderedImage = image;
      });
    } on Exception catch (e) {
      setState(() {
        _error = e.toString();
      });
    } finally {
      setState(() {
        _isCompiling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Typst Flutter Example'),
        actions: [
          IconButton(
            onPressed: _isCompiling ? null : _compile,
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Compile',
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
                  fontSize: 12,
                ),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Enter Typst markup…',
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ColoredBox(
              color: Colors.grey.shade200,
              child: _buildPreview(),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isCompiling ? null : _compile,
        child: _isCompiling
            ? const CircularProgressIndicator(color: Colors.white)
            : const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildPreview() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _error!,
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    if (_renderedImage == null) {
      return const Center(child: Text('Press compile to see preview'));
    }

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Card(elevation: 4, child: RawImage(image: _renderedImage)),
      ),
    );
  }
}
