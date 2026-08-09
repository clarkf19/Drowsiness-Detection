import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/start_screen.dart';

/// Points 9 & 21: App entry point
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force portrait orientation for driver monitoring
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  runApp(const DrowsinessApp());
}

class DrowsinessApp extends StatelessWidget {
  const DrowsinessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Driver Drowsiness Monitor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0F172A),
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.amber,
          surface: Color(0xFF1E293B),
        ),
        useMaterial3: true,
        fontFamily: 'Roboto',
      ),
      home: const StartScreen(),
    );
  }
}
