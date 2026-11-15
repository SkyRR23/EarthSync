import 'package:flutter/material.dart';

class EarthSyncLogo extends StatelessWidget {
  const EarthSyncLogo({super.key, this.size = 36});
  final double size;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(size / 6),
    child: Image.asset(
      'assets/branding/earthsync-logo.png',
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'EarthSync logo',
    ),
  );
}
