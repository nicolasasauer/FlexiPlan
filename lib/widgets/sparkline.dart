import 'package:flutter/material.dart';

/// Schlanke Verlaufslinie ohne Chart-Paket: zeichnet [values] (älteste
/// zuerst) als 2px-Linie mit hervorgehobenem letztem Punkt. Skaliert
/// selbstständig auf die verfügbare Fläche.
///
/// Erwartet mindestens zwei Werte – bei weniger rendert der aufrufende
/// Screen stattdessen die Text-Zusammenfassung.
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    required this.color,
    this.height = 48,
  });

  final List<double> values;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparklinePainter(
          values: values,
          color: color,
          surface: Theme.of(context).colorScheme.surface,
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  _SparklinePainter({
    required this.values,
    required this.color,
    required this.surface,
  });

  final List<double> values;
  final Color color;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) {
      return;
    }
    const marginY = 8.0; // Platz für Punktradius oben/unten
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final span = maxV - minV;

    double x(int i) => size.width * i / (values.length - 1);
    double y(double v) {
      // Flache Reihe (span 0) mittig zeichnen.
      if (span == 0) {
        return size.height / 2;
      }
      final t = (v - minV) / span;
      return marginY + (1 - t) * (size.height - 2 * marginY);
    }

    final path = Path()..moveTo(x(0), y(values.first));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }

    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, line);

    // Zwischenpunkte dezent (Ring in Surface-Farbe), letzter Punkt voll.
    final ring = Paint()..color = surface;
    final ringStroke = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 0; i < values.length - 1; i++) {
      final c = Offset(x(i), y(values[i]));
      canvas.drawCircle(c, 3, ring);
      canvas.drawCircle(c, 3, ringStroke);
    }
    final lastCenter = Offset(x(values.length - 1), y(values.last));
    canvas.drawCircle(lastCenter, 5, ring);
    canvas.drawCircle(lastCenter, 4.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color || old.surface != surface;
}
