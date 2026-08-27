import 'package:flutter/material.dart';

class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.width,
    this.height,
  });

  final double? width;
  final double? height;

  static const String darkAsset = 'assets/images/Main LOGO(white).png';

  @override
  Widget build(BuildContext context) {
    final fallbackSize = height ?? (width != null ? width! * 0.28 : 28);

    return ClipRRect(
      child: Image(
        image: const AssetImage(darkAsset),
        width: width,
        height: height,
        fit: BoxFit.contain,
        opacity: const AlwaysStoppedAnimation(1.0),
        filterQuality: FilterQuality.medium,
        errorBuilder: (context, error, stackTrace) {
          return Text(
            'LOOPI',
            style: TextStyle(
              fontSize: fallbackSize * 0.72,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              height: 1,
              color: Colors.white,
            ),
          );
        },
      ),
    );
  }
}
