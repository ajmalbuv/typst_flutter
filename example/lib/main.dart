import 'package:flutter/material.dart';
import 'package:typst_flutter/typst_flutter.dart';

/// The main entry point for the example app.
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

== Date Injection
Today's date injected from Flutter: #datetime.today().display()
''',
  );

  String _currentSource = '';
  bool _useSvg = true;

  @override
  void initState() {
    super.initState();
    _currentSource = _controller.text;
  }

  void _compile() {
    setState(() {
      _currentSource = _controller.text;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Typst Flutter'),
        backgroundColor: const Color(0xFF1E1E2E),
        foregroundColor: const Color(0xFFCDD6F4),
        actions: [
          Row(
            children: [
              const Text('SVG Mode', style: TextStyle(fontSize: 12)),
              Switch(
                value: _useSvg,
                activeTrackColor: const Color(0xFF89B4FA),
                onChanged: (val) => setState(() => _useSvg = val),
              ),
            ],
          ),
          IconButton(
            onPressed: _compile,
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
                useSvg: _useSvg,
                date: DateTime.now(), // Inject current date from Flutter
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
        child: const Icon(Icons.refresh, color: Color(0xFF1E1E2E)),
      ),
    );
  }
}
