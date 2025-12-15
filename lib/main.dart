import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import 'splash_screen.dart';
import 'home/home_page.dart';
import 'auth/login_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ===========================================================
  //        REQUEST ALL PERMISSIONS IN ONE BATCH (STARTUP)
  // ===========================================================

  // Camera → QR scanner (VoidBetPage)
  await Permission.camera.request();

  // Bluetooth (Android 11 and below)
  await Permission.bluetooth.request();

  // Bluetooth (Android 12+)
  await Permission.bluetoothScan.request();
  await Permission.bluetoothConnect.request();

  // Required for Bluetooth scanning on Huawei devices & older Android
  await Permission.locationWhenInUse.request();

  // ===========================================================

  runApp(const GACArenaApp());
}

class GACArenaApp extends StatelessWidget {
  const GACArenaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'D - OCBS',
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
