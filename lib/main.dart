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
          seedColor: const Color(0xFF00ACC1),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const PixelRunnerScreen(),
    );
  }
}
