import 'dart:ui';

import 'package:flutter/material.dart';

import '../../../theme/auth_theme.dart';

/// Discreet translucent "liquid glass" surface (build guide §1.5): a light
/// blur of what is behind, a faint gradient fill and a thin border.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.radius = 24,
    this.blur = 18,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final double blur;

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: shape,
            border: Border.all(color: AuthColors.glassBorder),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [AuthColors.glassFillTop, AuthColors.glassFillBottom],
            ),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
