import 'package:flutter/material.dart';
import 'splash_screen.dart';

class AtlasOperatorApp extends StatelessWidget {
  const AtlasOperatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atlas Operator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2F6FED), // real brand electric blue now
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
