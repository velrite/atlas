import 'dart:async';
import 'package:flutter/material.dart';
import '../shared/widgets/velrite_wordmark.dart';
import 'root_shell.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const RootShell()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF0A1128), // brand navy — wordmark's real background
      body: Center(
        child: VelriteWordmark(variant: WordmarkVariant.white, height: 48),
      ),
    );
  }
}
