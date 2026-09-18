import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

enum WordmarkVariant { white, navy }

// White variant needs a dark background; navy variant needs a light one.
// Never place either on the wrong background (spec: no effects, no distortion).
class VelriteWordmark extends StatelessWidget {
  final WordmarkVariant variant;
  final double height;
  const VelriteWordmark({super.key, this.variant = WordmarkVariant.white, this.height = 32});

  @override
  Widget build(BuildContext context) {
    final asset = variant == WordmarkVariant.white
        ? 'assets/branding/velrite_wordmark_white.svg'
        : 'assets/branding/velrite_wordmark_navy.svg';
    return SvgPicture.asset(asset, height: height, fit: BoxFit.contain);
  }
}
