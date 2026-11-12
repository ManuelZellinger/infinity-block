import 'package:flutter/material.dart';
import 'screens/pixel_runner_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InfinityBlockApp());
}

class InfinityBlockApp extends StatelessWidget {
  const InfinityBlockApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Infinity Block',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00BCD4),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1220),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Infinity Block',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'GitHub-Stand – lokal erst nach git pull',
                  style: TextStyle(color: Colors.white.withOpacity(0.55)),
                ),
                const SizedBox(height: 40),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PixelRunnerScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.directions_run_rounded),
                  label: const Text('Infinity Run'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(220, 52),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
