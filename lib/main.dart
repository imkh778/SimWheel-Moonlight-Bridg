import 'package:flutter/material.dart';
import 'sunshine_settings.dart';
import 'sunshine_discovery_screen.dart';
import 'sunshine_stream_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await CacheService.initialize();
  runApp(const MoonlightSampleApp());
}

class MoonlightSampleApp extends StatelessWidget {
  const MoonlightSampleApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Moonlight Flutter Sample',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark), useMaterial3: true),
    home: const HomeScreen(),
  );
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Moonlight Sample')),
    body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.desktop_windows, size: 72, color: Colors.blueAccent),
      const SizedBox(height: 20),
      const Text('Stream from Sunshine', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('Pair with a Sunshine PC, then start a Moonlight stream.'),
      const SizedBox(height: 24),
      FilledButton.icon(onPressed: () async { final host = await Navigator.push(context, MaterialPageRoute(builder: (_) => const SunshineDiscoveryScreen())); if (host != null && context.mounted) Navigator.push(context, MaterialPageRoute(builder: (_) => const StreamScreen())); }, icon: const Icon(Icons.search), label: const Text('Find Sunshine PC')),
    ]))),
  );
}

class StreamScreen extends StatefulWidget { const StreamScreen({super.key}); @override State<StreamScreen> createState() => _StreamScreenState(); }
class _StreamScreenState extends State<StreamScreen> {
  late final SunshineStreamController controller = SunshineStreamController(initialOpacity: CacheService().getSunshineOpacity());
  @override void dispose() { controller.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(backgroundColor: Colors.black, appBar: AppBar(title: const Text('Moonlight Stream')), body: SunshineStreamView(controller: controller));
}
