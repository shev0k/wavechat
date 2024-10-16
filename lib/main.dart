// main.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.black,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp, // Lock orientation to portrait mode
  ]).then((_) {
    runApp(const WalkieTalkieApp());
  });
}

class WalkieTalkieApp extends StatelessWidget {
  const WalkieTalkieApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Walkie Talkie',
      debugShowCheckedModeBanner: false, // Hide debug banner
      theme: ThemeData(
        brightness: Brightness.dark, // Black and white theme
        fontFamily: 'RetroFont', // Use the retro font
      ),
      home: const WalkieTalkieHome(),
    );
  }
}
