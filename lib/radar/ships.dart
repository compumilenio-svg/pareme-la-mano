import 'dart:math';
import 'package:flutter/material.dart';
import 'engine.dart';

/// Un barco para dibujar (vista desde arriba).
class ShipSpec {
  final int kind; // 0 portaaviones, 1 acorazado, 2 crucero, 3 submarino, 4 destructor
  final List<int> cells;
  final bool shield;
  final int hits;
  final bool sunk;
  final int? sinkAtMs; // instante en que se hundió (null = ya estaba hundido)
  const ShipSpec(this.kind, this.cells, this.shield, this.hits, this.sunk, this.sinkAtMs);
}

/// Una columna de humo sobre una casilla (nivel 1 a 3).
class SmokeSrc {
  final int cell;
  final int level;
  const SmokeSrc(this.cell, this.level);
}

/// Dibuja los barcos, las marcas de quemadura y el humo sobre el tablero.
class ShipsPainter extends CustomPainter {
  final List<ShipSpec> ships;
  final List<SmokeSrc> smokes;
  final Set<int> burns;
  final double cell;
  ShipsPainter({
    required this.ships,
    required this.smokes,
    required this.burns,
    required this.cell,
    required Listenable tick,
  }) : super(repaint: tick);

  @override
  void paint(Canvas canvas, Size size) {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final sec = nowMs / 1000.0;
    for (final s in ships) {
      _ship(canvas, s, nowMs, sec);
    }
    for (final c in burns) {
      final cx = (c % kN + 0.5) * cell, cy = (c ~/ kN + 0.5) * cell;
      canvas.drawCircle(Offset(cx, cy), cell * 0.22, Paint()..color = Colors.black.withOpacity(0.35));
      final fl = 0.55 + 0.3 * sin(sec * 9 + c);
      canvas.drawCircle(
          Offset(cx, cy), cell * 0.11, Paint()..color = const Color(0xFFFF6D00).withOpacity(fl));
    }
    for (final sm in smokes) {
      _smoke(canvas, sm.cell, sm.level, sec);
    }
  }

  void _smoke(Canvas canvas, int idx, int level, double sec) {
    final cx = (idx % kN + 0.5) * cell, cy = (idx ~/ kN + 0.5) * cell;
    final n = 3 + level * 2;
    for (var i = 0; i < n; i++) {
      final phase = (sec * (0.45 + 0.1 * level) + i / n + idx * 0.137) % 1.0;
      final rise = cell * (0.5 + 0.6 * level) * phase;
      final dx = sin(phase * 5 + i * 1.7 + idx) * cell * 0.18 * (0.5 + phase);
      final rad = cell * (0.1 + 0.2 * phase) * (0.75 + 0.15 * level);
      final alpha = ((1 - phase) * (0.22 + 0.12 * level)).clamp(0.0, 0.6).toDouble();
      final col = Color.lerp(const Color(0xFF263238), const Color(0xFFB0BEC5), phase)!;
      canvas.drawCircle(Offset(cx + dx, cy - cell * 0.1 - rise), rad,
          Paint()..color = col.withOpacity(alpha));
    }
  }

  void _ship(Canvas canvas, ShipSpec s, int nowMs, double sec) {
    final cells = s.cells;
    final len = cells.length;
    final horiz = len < 2 ? true : cells[1] - cells[0] == 1;
    final first = cells.first;
    final r0 = first ~/ kN, c0 = first % kN;
    final w = (horiz ? len : 1) * cell;
    final h = (horiz ? 1 : len) * cell;
    final rect = Rect.fromLTWH(c0 * cell, r0 * cell, w, h);
    final center = rect.center;

    var p = 0.0;
    if (s.sunk) {
      p = s.sinkAtMs == null ? 1.0 : ((nowMs - s.sinkAtMs!) / 1700).clamp(0.0, 1.0).toDouble();
    }
    final dark = s.sunk ? 0.2 + 0.6 * p : min(0.4, 0.1 * s.hits).toDouble();

    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (!horiz) canvas.rotate(pi / 2);
    if (s.sunk) {
      canvas.rotate(0.10 * p);
      canvas.scale(1 - 0.14 * p);
    }
    canvas.translate(-len * cell / 2, -cell / 2);
    canvas.scale(cell);
    _hull(canvas, s.kind, len.toDouble(), dark);
    canvas.restore();

    if (s.sunk) {
      // el agua va cubriendo el casco
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect.deflate(1), Radius.circular(cell * 0.3)),
          Paint()..color = const Color(0xFF0A2A4D).withOpacity(0.55 * p));
      if (p < 1) {
        for (var k = 0; k < 2; k++) {
          final uu = (p * 1.4 - k * 0.3).clamp(0.0, 1.0).toDouble();
          if (uu <= 0) continue;
          canvas.drawOval(
              Rect.fromCenter(
                  center: center, width: w * (0.9 + 0.5 * uu), height: h * (0.9 + 0.5 * uu) + 4),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = Colors.white.withOpacity((1 - uu) * 0.6));
        }
        for (var k = 0; k < 6; k++) {
          final ph = (p * 2 + k / 6) % 1.0;
          final bx = rect.left + w * ((k * 0.37 + 0.1) % 1.0);
          final by = center.dy - ph * cell * 0.5;
          canvas.drawCircle(Offset(bx, by), cell * 0.06,
              Paint()..color = Colors.white.withOpacity((1 - ph) * 0.7));
        }
      }
    } else if (s.shield) {
      final pulse = 0.5 + 0.5 * sin(sec * 3);
      final rr = RRect.fromRectAndRadius(rect.inflate(0.5), Radius.circular(cell * 0.45));
      canvas.drawRRect(rr, Paint()..color = const Color(0xFF18FFFF).withOpacity(0.12 + 0.1 * pulse));
      canvas.drawRRect(
          rr,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF18FFFF).withOpacity(0.7 + 0.3 * pulse));
    }
  }

  void _turret(Canvas canvas, double x, double y, double dark) {
    Color c(Color b) => Color.lerp(b, Colors.black, dark)!;
    canvas.drawLine(
        Offset(x, y),
        Offset(x + 0.4, y),
        Paint()
          ..strokeWidth = 0.07
          ..strokeCap = StrokeCap.round
          ..color = c(const Color(0xFF263238)));
    canvas.drawCircle(Offset(x, y), 0.14, Paint()..color = c(const Color(0xFF607D8B)));
    canvas.drawCircle(
        Offset(x, y),
        0.14,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.035
          ..color = c(const Color(0xFF263238)));
  }

  /// Dibuja el barco en coordenadas de casilla (x: 0 ..L a lo largo, y: 0 ..1); proa a la derecha.
  void _hull(Canvas canvas, int kind, double L, double dark) {
    Color c(Color b) => Color.lerp(b, Colors.black, dark)!;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.04
      ..color = c(const Color(0xFF263238));

    if (kind == 3) {
      // submarino
      final body = RRect.fromRectAndRadius(
          Rect.fromLTWH(0.06, 0.26, L - 0.12, 0.48), const Radius.circular(0.24));
      canvas.drawRRect(body, Paint()..color = c(const Color(0xFF37474F)));
      canvas.drawRRect(body, line);
      canvas.drawLine(Offset(0.3, 0.5), Offset(L - 0.3, 0.5),
          Paint()..strokeWidth = 0.03 ..color = c(const Color(0xFF546E7A)));
      canvas.drawCircle(Offset(L * 0.46, 0.5), 0.17, Paint()..color = c(const Color(0xFF546E7A)));
      canvas.drawCircle(Offset(L * 0.46, 0.5), 0.17, line);
      canvas.drawLine(Offset(L * 0.46, 0.5), Offset(L * 0.46 + 0.16, 0.5),
          Paint()..strokeWidth = 0.05 ..strokeCap = StrokeCap.round..color = c(const Color(0xFF263238)));
      return;
    }

    final base = const [
      Color(0xFF78909C),
      Color(0xFF8D9AA3),
      Color(0xFF90A4AE),
      Color(0xFF455A64),
      Color(0xFF9FB0BA),
    ][kind];
    final hull = Path()
      ..moveTo(0.05, 0.22)
      ..lineTo(L - 0.75, 0.14)
      ..quadraticBezierTo(L - 0.22, 0.2, L - 0.03, 0.5)
      ..quadraticBezierTo(L - 0.22, 0.8, L - 0.75, 0.86)
      ..lineTo(0.05, 0.78)
      ..close();
    canvas.drawPath(hull, Paint()..color = c(base));
    canvas.drawPath(hull, line);
    // cubierta
    canvas.save();
    canvas.translate(L / 2, 0.5);
    canvas.scale((L - 0.4) / L, 0.7);
    canvas.translate(-L / 2, -0.5);
    canvas.drawPath(
        hull, Paint()..color = c(kind == 0 ? const Color(0xFF5F727C) : const Color(0xFFB0BEC5)));
    canvas.restore();

    switch (kind) {
      case 0: // portaaviones: pista, aviones y torre de mando
        for (var x = 0.3; x < L - 1.0; x += 0.4) {
          canvas.drawRect(Rect.fromLTWH(x, 0.485, 0.22, 0.03),
              Paint()..color = c(Colors.white70));
        }
        for (final x in [0.6, 1.1, 1.6]) {
          canvas.drawLine(Offset(x - 0.12, 0.32), Offset(x + 0.12, 0.32),
              Paint()..strokeWidth = 0.05 ..color = c(const Color(0xFF263238)));
          canvas.drawLine(Offset(x, 0.24), Offset(x, 0.4),
              Paint()..strokeWidth = 0.05 ..color = c(const Color(0xFF263238)));
        }
        final island = Rect.fromLTWH(L * 0.56, 0.66, 0.55, 0.2);
        canvas.drawRect(island, Paint()..color = c(const Color(0xFF455A64)));
        canvas.drawRect(island, line);
        break;
      case 1: // acorazado
        _turret(canvas, 0.8, 0.5, dark);
        _turret(canvas, 1.45, 0.5, dark);
        _turret(canvas, L - 0.9, 0.5, dark);
        final br = Rect.fromLTWH(L * 0.5 - 0.1, 0.38, 0.3, 0.24);
        canvas.drawRect(br, Paint()..color = c(const Color(0xFF546E7A)));
        canvas.drawRect(br, line);
        break;
      case 2: // crucero
        _turret(canvas, 0.65, 0.5, dark);
        _turret(canvas, L - 0.9, 0.5, dark);
        final br2 = Rect.fromLTWH(L * 0.5 - 0.1, 0.38, 0.28, 0.24);
        canvas.drawRect(br2, Paint()..color = c(const Color(0xFF546E7A)));
        canvas.drawRect(br2, line);
        break;
      default: // destructor
        _turret(canvas, 0.5, 0.5, dark);
        final br3 = Rect.fromLTWH(L - 1.0, 0.38, 0.28, 0.24);
        canvas.drawRect(br3, Paint()..color = c(const Color(0xFF546E7A)));
        canvas.drawRect(br3, line);
    }
    // chimenea
    if (kind != 0) {
      canvas.drawCircle(Offset(L * 0.5 + 0.35, 0.5), 0.09, Paint()..color = c(const Color(0xFF37474F)));
    }
  }

  @override
  bool shouldRepaint(covariant ShipsPainter old) => true;
}
