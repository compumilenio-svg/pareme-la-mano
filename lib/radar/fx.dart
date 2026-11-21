import 'dart:math';
import 'package:flutter/material.dart';
import 'engine.dart';

/// Datos de una animación de disparo (mío hacia arriba / del rival hacia abajo).
class FxInfo {
  final bool incoming;
  final int cell; // casilla que recibe el disparo
  Outcome? outcome;
  FxInfo(this.incoming, this.cell, [this.outcome]);

  bool get heavy => (outcome?.sunk ?? -1) >= 0;
}

/// Fondo de océano: degradado y olas suaves que se mueven.
class OceanPainter extends CustomPainter {
  final Animation<double> t;
  OceanPainter(this.t) : super(repaint: t);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0E3A66), Color(0xFF082447), Color(0xFF04132A)],
        ).createShader(rect),
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    for (var i = 0; i < 7; i++) {
      final y0 = size.height * (i + 0.5) / 7;
      p.color = Colors.lightBlueAccent.withOpacity(0.08 + 0.02 * (i % 3));
      final path = Path()..moveTo(0, y0);
      for (double x = 0; x <= size.width; x += 6) {
        final y = y0 +
            sin((x / size.width) * 2 * pi * 2 + t.value * 2 * pi + i) * 4.0 +
            sin((x / size.width) * 2 * pi * 5 - t.value * 2 * pi * 2 + i * 2) * 1.5;
        path.lineTo(x, y);
      }
      canvas.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant OceanPainter old) => false;
}

/// Capa de efectos sobre los dos tableros: cañones circulares en el centro de
/// cada tablero, misil con estela en arco, mira, e impactos.
class FxPainter extends CustomPainter {
  final FxInfo? fx;
  final Animation<double> flight;
  final Animation<double> impact;
  final Animation<double> pulse;
  final double cell;
  final double side;
  final Offset enemyO; // esquina superior izquierda del tablero enemigo
  final Offset myO; // esquina superior izquierda de mi tablero

  FxPainter({
    required this.fx,
    required this.flight,
    required this.impact,
    required this.pulse,
    required this.cell,
    required this.side,
    required this.enemyO,
    required this.myO,
  }) : super(repaint: Listenable.merge([flight, impact, pulse]));

  Offset _centerOf(Offset o) => o + Offset(side / 2, side / 2);
  Offset _pt(Offset o, int c) =>
      o + Offset((c % kN + 0.5) * cell, (c ~/ kN + 0.5) * cell);

  Offset _bez(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return Offset(u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
        u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy);
  }

  void _glowLine(Canvas canvas, Offset a, Offset b, Color col, double w, double alpha) {
    canvas.drawLine(
        a,
        b,
        Paint()
          ..color = col.withOpacity(alpha * 0.35)
          ..strokeWidth = w * 3
          ..strokeCap = StrokeCap.round
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawLine(
        a,
        b,
        Paint()
          ..color = Color.lerp(col, Colors.white, 0.6)!.withOpacity(alpha)
          ..strokeWidth = w
          ..strokeCap = StrokeCap.round);
  }

  void _cannon(Canvas canvas, Offset c, double angle, Color ring, double glow) {
    final r = cell * 0.34;
    // base
    canvas.drawCircle(
        c,
        r + 3,
        Paint()
          ..color = ring.withOpacity(0.25 + 0.5 * glow)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(angle);
    // cañón (tubo)
    final barrel = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, -r * 0.3, r * 1.5, r * 0.6), Radius.circular(r * 0.2));
    canvas.drawRRect(barrel, Paint()..color = const Color(0xFF263238));
    canvas.drawRRect(
        barrel,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = ring);
    canvas.restore();
    // torreta circular
    canvas.drawCircle(c, r, Paint()..color = const Color(0xFF37474F));
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = ring);
    canvas.drawCircle(c, r * 0.35, Paint()..color = ring.withOpacity(0.9));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final f = fx;
    final myC = _centerOf(myO);
    final enC = _centerOf(enemyO);
    const myCol = Color(0xFF18FFFF);
    const enCol = Color(0xFFFF5252);

    if (f == null) {
      _cannon(canvas, myC, -pi / 2, myCol, 0);
      _cannon(canvas, enC, pi / 2, enCol, 0);
      return;
    }

    final flightT = flight.value;
    final done = flightT >= 0.999;
    final S = f.incoming ? enC : myC;
    final T = f.incoming ? _pt(myO, f.cell) : _pt(enemyO, f.cell);
    final col = f.incoming ? enCol : myCol;
    final d = T - S;
    final len = d.distance == 0 ? 1.0 : d.distance;
    final n = Offset(-d.dy / len, d.dx / len);
    final bend = (f.incoming ? -1.0 : 1.0) * len * 0.28;
    final C = Offset((S.dx + T.dx) / 2 + n.dx * bend, (S.dy + T.dy) / 2 + n.dy * bend);

    // cañones: el que dispara apunta al blanco y destella al salir
    final aim = (C - S).direction;
    final muzzle = (1 - (flightT * 5)).clamp(0.0, 1.0).toDouble();
    if (f.incoming) {
      _cannon(canvas, myC, -pi / 2, myCol, 0);
      _cannon(canvas, enC, aim, enCol, muzzle);
    } else {
      _cannon(canvas, enC, pi / 2, enCol, 0);
      _cannon(canvas, myC, aim, myCol, muzzle);
    }
    if (muzzle > 0) {
      final tip = S + Offset(cos(aim), sin(aim)) * cell * 0.7;
      canvas.drawCircle(
          tip,
          cell * 0.35 * muzzle,
          Paint()
            ..color = Colors.white.withOpacity(0.9 * muzzle)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    }

    // --- misil en vuelo (arco con estela) ---
    final p = Curves.easeInQuad.transform(flightT.clamp(0.0, 1.0));
    if (!done) {
      const seg = 22;
      final t0 = max(0.0, p - 0.4);
      var prev = _bez(S, C, T, t0);
      for (var k = 1; k <= seg; k++) {
        final t = t0 + (p - t0) * k / seg;
        final cur = _bez(S, C, T, t);
        final fade = k / seg;
        _glowLine(canvas, prev, cur, col, 1.2 + 3.0 * fade, fade * 0.95);
        prev = cur;
      }
      final head = _bez(S, C, T, p);
      canvas.drawCircle(
          head,
          cell * 0.4,
          Paint()
            ..color = col.withOpacity(0.5)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      canvas.drawCircle(head, cell * 0.16, Paint()..color = Colors.white);
      canvas.drawCircle(head, cell * 0.09, Paint()..color = col);
    }

    // --- mira de blanco mientras llega el resultado ---
    if (done && f.outcome == null) {
      final k = 0.75 + 0.25 * sin(pulse.value * 2 * pi);
      final r = cell * 0.5 * k + cell * 0.12;
      final pr = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = col.withOpacity(0.95);
      canvas.drawCircle(T, r, pr);
      for (final dir in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
        canvas.drawLine(T + dir * (r - 3), T + dir * (r + 6), pr);
      }
    }

    // --- impacto ---
    final o = f.outcome;
    final u = impact.value;
    if (o == null || !done || u <= 0) return;
    switch (o.res) {
      case kHit:
      case kDecoy:
        _boom(canvas, T, u, const Color(0xFFFF6D00), o.sunk >= 0 ? 1.9 : 1.0);
        if (o.sunk >= 0) {
          for (final c in o.sunkCells) {
            final q = _pt(f.incoming ? myO : enemyO, c);
            _boom(canvas, q, u, const Color(0xFFFF3D00), 1.0);
          }
        }
        break;
      case kShield:
        for (var k = 0; k < 2; k++) {
          final uu = (u * 1.2 - k * 0.2).clamp(0.0, 1.0).toDouble();
          if (uu <= 0) continue;
          canvas.drawCircle(
              T,
              cell * (0.3 + 1.0 * uu),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3.5 * (1 - uu) + 0.6
                ..color = const Color(0xFF18FFFF).withOpacity((1 - uu) * 0.95));
        }
        canvas.drawCircle(
            T,
            cell * 0.55,
            Paint()
              ..color = const Color(0xFF00E5FF).withOpacity((1 - u) * 0.35)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        break;
      default: // agua
        for (var k = 0; k < 2; k++) {
          final uu = (u * 1.2 - k * 0.25).clamp(0.0, 1.0).toDouble();
          if (uu <= 0) continue;
          canvas.drawCircle(
              T,
              cell * (0.15 + 0.85 * uu),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.2 * (1 - uu) + 0.5
                ..color = Colors.white.withOpacity((1 - uu) * 0.85));
        }
        for (var k = 0; k < 6; k++) {
          final ang = -pi / 2 + (k - 2.5) * 0.35;
          final r = cell * 0.9 * sin(u * pi);
          final q = T + Offset(cos(ang) * r * 0.8, sin(ang) * r - u * cell * 0.2);
          canvas.drawCircle(
              q, cell * 0.07, Paint()..color = Colors.lightBlueAccent.withOpacity(1 - u));
        }
    }
  }

  void _boom(Canvas canvas, Offset c, double u, Color col, double scale) {
    // destello blanco inicial
    if (u < 0.25) {
      canvas.drawCircle(c, cell * 0.9 * scale * (1 - u * 2),
          Paint()..color = Colors.white.withOpacity(0.9 * (1 - u * 4)));
    }
    // bola de fuego
    final r = cell * (0.25 + 0.75 * u) * scale;
    final rect = Rect.fromCircle(center: c, radius: max(r, 1.0));
    canvas.drawCircle(
        c,
        max(r, 1.0),
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.yellowAccent.withOpacity((1 - u) * 0.95),
            col.withOpacity((1 - u) * 0.8),
            col.withOpacity(0),
          ], stops: const [0, 0.55, 1]).createShader(rect));
    // onda expansiva
    canvas.drawCircle(
        c,
        cell * (0.4 + 1.5 * u) * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5 * (1 - u) + 0.5
          ..color = col.withOpacity((1 - u) * 0.9));
    // chispas
    for (var k = 0; k < 10; k++) {
      final ang = k * 2 * pi / 10 + 0.2;
      final r0 = cell * (0.3 + 0.4 * u) * scale;
      final r1 = cell * (0.5 + 1.3 * u) * scale;
      canvas.drawLine(
          c + Offset(cos(ang), sin(ang)) * r0,
          c + Offset(cos(ang), sin(ang)) * r1,
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = Colors.orangeAccent.withOpacity((1 - u) * 0.95));
    }
  }

  @override
  bool shouldRepaint(covariant FxPainter old) => true;
}
