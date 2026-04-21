import 'package:flutter/material.dart';
import 'dart:math';

class RoutePainter extends CustomPainter {
  final List<List<double>> coords;
  RoutePainter(this.coords);

  @override
  void paint(Canvas canvas, Size size) {
    if (coords.length < 2) return;
    final paint = Paint()
      ..color = const Color(0xFF1976D2)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    double minLng = coords.map((c) => c[0]).reduce(min);
    double maxLng = coords.map((c) => c[0]).reduce(max);
    double minLat = coords.map((c) => c[1]).reduce(min);
    double maxLat = coords.map((c) => c[1]).reduce(max);

    final rangeX = (maxLng - minLng).abs();
    final rangeY = (maxLat - minLat).abs();
    if (rangeX == 0 || rangeY == 0) return;

    const pad = 12.0;
    final path = Path();
    for (int i = 0; i < coords.length; i++) {
      final x = pad + (coords[i][0] - minLng) / rangeX * (size.width  - pad * 2);
      final y = pad + (maxLat - coords[i][1]) / rangeY * (size.height - pad * 2);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(path, paint);

    const startPaint = Paint()..color = Colors.green;
    const endPaint   = Paint()..color = Colors.red;

    final start = coords.first;
    final end   = coords.last;
    final sx = pad + (start[0] - minLng) / rangeX * (size.width  - pad * 2);
    final sy = pad + (maxLat - start[1]) / rangeY * (size.height - pad * 2);
    final ex = pad + (end[0]   - minLng) / rangeX * (size.width  - pad * 2);
    final ey = pad + (maxLat - end[1])   / rangeY * (size.height - pad * 2);
    canvas.drawCircle(Offset(sx, sy), 5, startPaint);
    canvas.drawCircle(Offset(ex, ey), 5, endPaint);
  }

  @override
  bool shouldRepaint(covariant RoutePainter old) {
    if (old.coords.length != coords.length) return true;
    for (int i = 0; i < coords.length; i++) {
      if (old.coords[i][0] != coords[i][0] ||
          old.coords[i][1] != coords[i][1]) return true;
    }
    return false;
  }
}
