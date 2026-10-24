import 'package:flutter/material.dart';

import '../../theme/evolup_theme.dart';

/// Night-blue background with two soft halos and a discreet dot grid
/// (build guide §1.2). Purely decorative and static.
class EvolupBackground extends StatelessWidget {
  const EvolupBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: EvolupColors.background,
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ExcludeSemantics(
          child: RepaintBoundary(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _Halo(
                  alignment: Alignment(-1.1, -0.85),
                  color: EvolupColors.haloBlueViolet,
                ),
                _Halo(
                  alignment: Alignment(1.15, 0.9),
                  color: EvolupColors.haloCyan,
                ),
                CustomPaint(painter: _DotGridPainter()),
              ],
            ),
          ),
        ),
        child,
      ],
    ),
  );
}

class _Halo extends StatelessWidget {
  const _Halo({required this.alignment, required this.color});

  final Alignment alignment;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: RadialGradient(
        center: alignment,
        radius: 0.9,
        colors: [
          color.withValues(alpha: 0.30),
          color.withValues(alpha: 0.08),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.45, 1],
      ),
    ),
  );
}

class _DotGridPainter extends CustomPainter {
  const _DotGridPainter();

  static const _spacing = 22.0;
  static const _radius = 1.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = EvolupColors.dot;
    for (var y = _spacing / 2; y < size.height; y += _spacing) {
      for (var x = _spacing / 2; x < size.width; x += _spacing) {
        canvas.drawCircle(Offset(x, y), _radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DotGridPainter oldDelegate) => false;
}
