import 'package:flutter/material.dart';
import 'splash_screen.dart';
import 'home/home_page.dart';
import 'auth/login_page.dart';

void main() {
  runApp(const GACArenaApp());
}

class GACArenaApp extends StatelessWidget {
  const GACArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAC Arena',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.red,
        fontFamily: 'Orbitron',
      ),
      home: const SplashScreen(),
      routes: {
        '/home': (context) => const HomePage(),
        '/login': (context) => const LoginPage(),
      },
    );
  }
}
