import 'package:flutter/material.dart';

import '../../theme/evolup_theme.dart';

/// Background with two soft halos and a discreet dot grid (build guide
/// §1.2), in the colors of the current palette. Purely decorative and static.
class EvolupBackground extends StatelessWidget {
  const EvolupBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = EvolupColors.of(context);
    return ColoredBox(
      color: colors.background,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _Halo(
                    alignment: const Alignment(-1.1, -0.85),
                    color: colors.haloPrimary,
                    opacity: colors.haloOpacity,
                  ),
                  _Halo(
                    alignment: const Alignment(1.15, 0.9),
                    color: colors.haloSecondary,
                    opacity: colors.haloOpacity,
                  ),
                  CustomPaint(painter: _DotGridPainter(colors.dot)),
                ],
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _Halo extends StatelessWidget {
  const _Halo({
    required this.alignment,
    required this.color,
    required this.opacity,
  });

  final Alignment alignment;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: alignment,
        radius: 0.9,
        colors: [
          color.withValues(alpha: opacity),
          color.withValues(alpha: opacity * 0.27),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ),
    ),
  );
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter(this.color);

  final Color color;

  static const _spacing = 22.0;
  static const _radius = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (var y = _spacing / 2; y < size.height; y += _spacing) {
      for (var x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => oldDelegate.color != color;
}
