import 'dart:math';
import 'package:flutter/material.dart';
import 'engine.dart';

/// Datos de una animación de ataque (misil que sale / misil que llega).
class FxInfo {
  final bool incoming;
  final RAction action;
  Outcome? outcome;
  FxInfo(this.incoming, this.action, [this.outcome]);

  bool get heavy {
    final o = outcome;
    if (o == null) return false;
    for (final s in o.shots) {
      if (s.result == kMine) return true;
      if (s.modDown && s.modKind >= 0 && s.modKind < kRealKinds) return true;
    }
    return false;
  }
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

/// Capa de efectos encima de la cuadrícula: misil con estela luminosa en arco,
/// mira de blanco, y el impacto (explosión, escudo, agua, trampa, baliza,
/// radar y onda).
class FxPainter extends CustomPainter {
  final FxInfo? fx;
  final Animation<double> flight;
  final Animation<double> impact;
  final Animation<double> pulse;
  final double cell;
  final double lab; // desplazamiento de las etiquetas (0 si no hay)

  FxPainter({
    required this.fx,
    required this.flight,
    required this.impact,
    required this.pulse,
    required this.cell,
    required this.lab,
  }) : super(repaint: Listenable.merge([flight, impact, pulse]));

  Offset _pt(int c) =>
      Offset(lab + (c % kN + 0.5) * cell, lab + (c ~/ kN + 0.5) * cell);

  Offset _bez(Offset a, Offset c, Offset b, double t) {
    final u = 1 - t;
    return Offset(u * u * a.dx + 2 * u * t * c.dx + t * t * b.dx,
        u * u * a.dy + 2 * u * t * c.dy + t * t * b.dy);
  }

  List<Offset> _targets(RAction a) {
    switch (a.kind) {
      case kScan:
        return [_pt(a.a)];
      case kWave:
        final side = lab + kN * cell;
        final mid = lab + (a.a + 0.5) * cell;
        return [a.b == 0 ? Offset(side / 2, mid) : Offset(mid, side / 2)];
      case kMissile:
        return [for (final c in plusOf(a.a)) _pt(c)];
      default:
        return [_pt(a.a)];
    }
  }

  Color _color(FxInfo f) {
    if (f.incoming) return const Color(0xFFFF5252);
    switch (f.action.kind) {
      case kScan:
        return const Color(0xFF69F0AE);
      case kWave:
        return const Color(0xFFFFEE58);
      case kMissile:
        return const Color(0xFFFFAB40);
      default:
        return const Color(0xFF18FFFF);
    }
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

  @override
  void paint(Canvas canvas, Size size) {
    final f = fx;
    if (f == null) return;
    final a = f.action;
    final col = _color(f);
    final targets = _targets(a);
    final flightT = flight.value;
    final done = flightT >= 0.999;
    final side = size.width;

    // --- Misil en vuelo (arco con estela) ---------------------------------
    final p = Curves.easeInQuad.transform(flightT.clamp(0.0, 1.0));
    for (var i = 0; i < targets.length; i++) {
      final T = targets[i];
      final S = f.incoming
          ? Offset(side * (0.9 - 0.04 * i), -side * 0.28)
          : Offset(side * (0.1 + 0.04 * i), side * 1.3);
      final d = T - S;
      final len = d.distance == 0 ? 1.0 : d.distance;
      final n = Offset(-d.dy / len, d.dx / len);
      final bend = (f.incoming ? -1.0 : 1.0) * len * 0.32;
      final C = Offset((S.dx + T.dx) / 2 + n.dx * bend, (S.dy + T.dy) / 2 + n.dy * bend);

      if (!done) {
        const seg = 22;
        final t0 = max(0.0, p - 0.4);
        var prev = _bez(S, C, T, t0);
        for (var k = 1; k <= seg; k++) {
          final t = t0 + (p - t0) * k / seg;
          final cur = _bez(S, C, T, t);
          final fade = k / seg;
          _glowLine(canvas, prev, cur, col, 1.2 + 3.2 * fade, fade * 0.95);
          prev = cur;
        }
        final head = _bez(S, C, T, p);
        canvas.drawCircle(
            head,
            cell * 0.42,
            Paint()
              ..color = col.withOpacity(0.5)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
        canvas.drawCircle(head, cell * 0.17, Paint()..color = Colors.white);
        canvas.drawCircle(head, cell * 0.1, Paint()..color = col);
      }
    }

    // --- Mira de blanco mientras llega el resultado -----------------------
    if (done && f.outcome == null) {
      final k = 0.75 + 0.25 * sin(pulse.value * 2 * pi);
      for (final T in targets) {
        final r = cell * 0.55 * k + cell * 0.15;
        final pr = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2
          ..color = col.withOpacity(0.95);
        canvas.drawCircle(T, r, pr);
        for (final dir in const [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1)]) {
          canvas.drawLine(T + dir * (r - 4), T + dir * (r + 7), pr);
        }
      }
    }

    // --- Impacto -----------------------------------------------------------
    final o = f.outcome;
    final u = impact.value;
    if (o == null || !done || u <= 0) return;

    if (a.kind == kScan) {
      final c = targets.first;
      for (var k = 0; k < 3; k++) {
        final uu = ((u * 1.3) - k * 0.18).clamp(0.0, 1.0);
        if (uu <= 0) continue;
        canvas.drawCircle(
            c,
            cell * (0.4 + 1.9 * uu),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3 * (1 - uu) + 0.5
              ..color = col.withOpacity((1 - uu) * 0.9));
      }
      final ang = u * 2 * pi * 1.2;
      _glowLine(canvas, c, c + Offset(cos(ang), sin(ang)) * cell * 1.9, col, 2.5, 1 - u);
      return;
    }
    if (a.kind == kWave) {
      final vertical = a.b == 1;
      final pos = u * (lab + kN * cell);
      final mid = lab + (a.a + 0.5) * cell;
      final span = lab + kN * cell;
      final fade = (1 - u).clamp(0.0, 1.0);
      // línea fija atenuándose
      final s0 = vertical ? Offset(mid, lab) : Offset(lab, mid);
      final s1 = vertical ? Offset(mid, span) : Offset(span, mid);
      _glowLine(canvas, s0, s1, col, 2.0, 0.35 + 0.4 * fade);
      // pulso que recorre la línea
      final h = vertical ? Offset(mid, pos) : Offset(pos, mid);
      canvas.drawCircle(
          h,
          cell * 0.6,
          Paint()
            ..color = col.withOpacity(0.7 * fade + 0.2)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
      return;
    }

    for (final s in o.shots) {
      final c = _pt(s.cell);
      switch (s.result) {
        case kHit:
          _boom(canvas, c, u, const Color(0xFFFF6D00), s.modDown ? 1.9 : 1.0);
          break;
        case kShield:
          for (var k = 0; k < 2; k++) {
            final uu = (u * 1.2 - k * 0.2).clamp(0.0, 1.0);
            if (uu <= 0) continue;
            canvas.drawCircle(
                c,
                cell * (0.3 + 1.0 * uu),
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 3.5 * (1 - uu) + 0.6
                  ..color = const Color(0xFF18FFFF).withOpacity((1 - uu) * 0.95));
          }
          canvas.drawCircle(
              c,
              cell * 0.55,
              Paint()
                ..color = const Color(0xFF00E5FF).withOpacity((1 - u) * 0.35)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
          break;
        case kMine:
          _boom(canvas, c, u, const Color(0xFFD500F9), 2.3);
          break;
        case kBeacon:
          for (var k = 0; k < 8; k++) {
            final ang = k * pi / 4 + 0.3;
            final r = cell * (0.2 + 1.1 * u);
            final q = c + Offset(cos(ang), sin(ang)) * r;
            canvas.drawCircle(q, cell * 0.12 * (1 - u) + 1.2,
                Paint()..color = const Color(0xFFFFD740).withOpacity(1 - u));
          }
          canvas.drawCircle(
              c,
              cell * 0.5,
              Paint()
                ..color = const Color(0xFFFFD740).withOpacity((1 - u) * 0.5)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
          break;
        case kMiss:
          for (var k = 0; k < 2; k++) {
            final uu = (u * 1.2 - k * 0.25).clamp(0.0, 1.0);
            if (uu <= 0) continue;
            canvas.drawCircle(
                c,
                cell * (0.15 + 0.85 * uu),
                Paint()
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2.2 * (1 - uu) + 0.5
                  ..color = Colors.white.withOpacity((1 - uu) * 0.85));
          }
          for (var k = 0; k < 6; k++) {
            final ang = -pi / 2 + (k - 2.5) * 0.35;
            final r = cell * 0.9 * sin(u * pi);
            final q = c + Offset(cos(ang) * r * 0.8, sin(ang) * r - u * cell * 0.2);
            canvas.drawCircle(q, cell * 0.07,
                Paint()..color = Colors.lightBlueAccent.withOpacity(1 - u));
          }
          break;
        default:
          break;
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
