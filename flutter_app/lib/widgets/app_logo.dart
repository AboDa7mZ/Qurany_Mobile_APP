import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../config/theme.dart';

/// Brand logo used in splash, login, and app header.
class AppLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const AppLogo({
    super.key,
    this.size = 120,
    this.color,
  });

  static const assetPath = 'assets/logo_ragel.svg';

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
      colorFilter: ColorFilter.mode(
        color ?? QuranyTheme.primaryGreen,
        BlendMode.srcIn,
      ),
    );
  }
}
