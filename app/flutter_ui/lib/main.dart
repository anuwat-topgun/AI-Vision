import 'package:flutter/material.dart';

void main() => runApp(const AiVisionApp());

class AiVisionApp extends StatelessWidget {
  const AiVisionApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'AI Vision',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
        home: const HomeScreen(),
      );
}

/// Home: File and Live Capture visibly separate (README §11.2). File Input is
/// permanent (ADR-0003, AC-004) — do not hide behind a debug flag.
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('AI Vision — EN/JA → ไทย')),
      body: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > 700;
        final tiles = [
          _ModeTile(
            key: const Key('tile_file'),
            icon: Icons.video_file_outlined,
            title: 'Video File / ไฟล์วิดีโอ',
            subtitle: 'MP4 / MOV / MKV (where supported)',
            onTap: () => _todo(context, 'File adapter not implemented (E02)'),
          ),
          _ModeTile(
            key: const Key('tile_live'),
            icon: Icons.usb,
            title: 'Live Capture / จับภาพสด',
            subtitle: 'UVC capture card — qualified devices only',
            onTap: () => _todo(context, 'UVC adapter not implemented (E06–E08)'),
          ),
        ];
        return Padding(
          padding: const EdgeInsets.all(16),
          child: wide
              ? Row(children: tiles.map((t) => Expanded(child: t)).toList())
              : Column(children: tiles),
        );
      }),
      bottomNavigationBar: const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Offline mode · Cloud off', textAlign: TextAlign.center),
      ),
    );
  }

  void _todo(BuildContext context, String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.all(8),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 56, semanticLabel: title),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 4),
              Text(subtitle, textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
}
