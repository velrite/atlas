import 'package:flutter/material.dart';
import 'root_shell.dart';

class AtlasOperatorApp extends StatelessWidget {
  const AtlasOperatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atlas Operator',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2C3E63), // deep slate blue, per visual-system.md
        useMaterial3: true,
      ),
      home: const RootShell(),
    );
  }
}
