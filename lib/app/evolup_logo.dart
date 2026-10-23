import 'dart:math' as math;

import 'package:flutter/material.dart';

/// EVOLUP logo: an upward zigzag arrow with a blue-violet to cyan gradient.
///
/// This is the only place that draws the logo. To replace it with a final
/// asset, change the `build` method of this widget; callers only pass `size`.
class EvolupLogo extends StatelessWidget {
  const EvolupLogo({this.size = 44, super.key});

  final double size;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Logo EVOLUP',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: const CustomPaint(painter: _ZigzagArrowPainter()),
    ),
  );
}

class _ZigzagArrowPainter extends CustomPainter {
  const _ZigzagArrowPainter();

  static const _startColor = Color(0xFF6A5CFF);
  static const _endColor = Color(0xFF22D3EE);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // Low start, climb, partial drop, then a final upward climb.
    final points = [
      Offset(w * 0.08, h * 0.84),
      Offset(w * 0.40, h * 0.42),
      Offset(w * 0.58, h * 0.62),
      Offset(w * 0.90, h * 0.16),
    ];
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.bottomLeft,
        end: Alignment.topRight,
        colors: [_startColor, _endColor],
      ).createShader(Offset.zero & size)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }

    final tip = points.last;
    final direction = math.atan2(tip.dy - points[2].dy, tip.dx - points[2].dx);
    final headLength = w * 0.26;
    const spread = math.pi / 5;
    Offset wing(double angle) => Offset(
      tip.dx - headLength * math.cos(direction + angle),
      tip.dy - headLength * math.sin(direction + angle),
    );
    final head = Path()
      ..moveTo(wing(spread).dx, wing(spread).dy)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(wing(-spread).dx, wing(-spread).dy);

    canvas
      ..drawPath(line, paint)
      ..drawPath(head, paint);
  }

  @override
  bool shouldRepaint(_ZigzagArrowPainter oldDelegate) => false;
}
