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

/// Ilustración del menú: portaaviones de guerra al atardecer lanzando un misil.
class WarshipPainter extends CustomPainter {
  final Animation<double> t;
  WarshipPainter(this.t) : super(repaint: t);

  Offset _bez(Offset a, Offset c, Offset b, double k) {
    final u = 1 - k;
    return Offset(u * u * a.dx + 2 * u * k * c.dx + k * k * b.dx,
        u * u * a.dy + 2 * u * k * c.dy + k * k * b.dy);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final u = t.value;
    final rect = Offset.zero & size;

    // cielo de atardecer
    canvas.drawRect(
        rect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0A1633), Color(0xFF3A2A5C), Color(0xFFFF8A50)],
            stops: [0.0, 0.5, 0.72],
          ).createShader(rect));
    canvas.drawCircle(
        Offset(w * 0.18, h * 0.68),
        h * 0.16,
        Paint()
          ..color = const Color(0xFFFFD180).withOpacity(0.75)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14));
    canvas.drawCircle(Offset(w * 0.18, h * 0.68), h * 0.07, Paint()..color = const Color(0xFFFFE0B2));

    // mar
    final seaTop = h * 0.72;
    final seaRect = Rect.fromLTWH(0, seaTop, w, h - seaTop);
    canvas.drawRect(
        seaRect,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF1B4F7A), Color(0xFF06182E)],
          ).createShader(seaRect));
    final wl = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3;
    for (var i = 0; i < 5; i++) {
      final y0 = seaTop + (i + 0.6) * (h - seaTop) / 5.5;
      wl.color = Colors.lightBlueAccent.withOpacity(0.10 + 0.03 * (i % 2));
      final p = Path()..moveTo(0, y0);
      for (double x = 0; x <= w; x += 6) {
        p.lineTo(x, y0 + sin(x / w * 2 * pi * 3 + u * 2 * pi * 2 + i) * 2.2);
      }
      canvas.drawPath(p, wl);
    }

    // el barco
    final bob = sin(u * 2 * pi * 3) * h * 0.006;
    canvas.save();
    canvas.translate(0, bob);
    _carrier(canvas, w, h, u);
    canvas.restore();

    // agua por delante del casco (lo hunde un poco en el mar)
    canvas.drawRect(
        Rect.fromLTWH(w * 0.02, seaTop + h * 0.005, w * 0.96, h * 0.05),
        Paint()..color = const Color(0xFF123F66).withOpacity(0.78));
    // estela y espuma
    for (var k = 0; k < 7; k++) {
      final ph = (u * 3 + k / 7) % 1.0;
      canvas.drawCircle(Offset(w * (0.05 - 0.04 * ph), seaTop + h * 0.02 + k * 1.3),
          h * 0.012 * (1 - ph) + 1, Paint()..color = Colors.white.withOpacity((1 - ph) * 0.5));
      canvas.drawCircle(Offset(w * (0.97 + 0.03 * ph), seaTop + h * 0.025),
          h * 0.01 * (1 - ph) + 1, Paint()..color = Colors.white.withOpacity((1 - ph) * 0.5));
    }

    _missile(canvas, w, h, u);
  }

  void _carrier(Canvas canvas, double w, double h, double u) {
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF1C262B);

    // casco
    final hull = Path()
      ..moveTo(w * 0.06, h * 0.60)
      ..lineTo(w * 0.94, h * 0.60)
      ..lineTo(w * 0.985, h * 0.645)
      ..quadraticBezierTo(w * 0.95, h * 0.76, w * 0.88, h * 0.78)
      ..lineTo(w * 0.12, h * 0.78)
      ..quadraticBezierTo(w * 0.05, h * 0.70, w * 0.06, h * 0.60)
      ..close();
    canvas.drawPath(hull, Paint()..color = const Color(0xFF66798A));
    canvas.save();
    canvas.clipPath(hull);
    canvas.drawRect(Rect.fromLTWH(0, h * 0.715, w, h * 0.03), Paint()..color = const Color(0xFF8E2A2A));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.745, w, h * 0.06), Paint()..color = Colors.black26);
    // portillas y números de casco
    for (var i = 0; i < 18; i++) {
      canvas.drawCircle(Offset(w * (0.12 + i * 0.045), h * 0.655), 1.6,
          Paint()..color = const Color(0xFF263238));
    }
    canvas.restore();
    canvas.drawPath(hull, line);

    // cubierta de vuelo con rampa de salto
    final deck = Path()
      ..moveTo(w * 0.03, h * 0.58)
      ..lineTo(w * 0.86, h * 0.58)
      ..lineTo(w * 0.975, h * 0.545)
      ..lineTo(w * 0.975, h * 0.60)
      ..lineTo(w * 0.03, h * 0.60)
      ..close();
    canvas.drawPath(deck, Paint()..color = const Color(0xFF8A9BA6));
    canvas.drawPath(deck, line);
    for (var i = 0; i < 12; i++) {
      canvas.drawRect(Rect.fromLTWH(w * (0.07 + i * 0.07), h * 0.588, w * 0.035, h * 0.006),
          Paint()..color = const Color(0xFFFFEE58).withOpacity(0.9));
    }

    // cazas en cubierta
    for (final x in [0.16, 0.27, 0.38]) {
      final cx = w * x;
      canvas.drawOval(Rect.fromCenter(center: Offset(cx, h * 0.562), width: w * 0.075, height: h * 0.026),
          Paint()..color = const Color(0xFF37474F));
      canvas.drawPath(
          Path()
            ..moveTo(cx - w * 0.03, h * 0.562)
            ..lineTo(cx - w * 0.042, h * 0.525)
            ..lineTo(cx - w * 0.018, h * 0.562)
            ..close(),
          Paint()..color = const Color(0xFF263238));
      canvas.drawOval(
          Rect.fromCenter(center: Offset(cx + w * 0.015, h * 0.556), width: w * 0.02, height: h * 0.014),
          Paint()..color = const Color(0xFF81D4FA));
    }

    // isla de mando
    final isl = Rect.fromLTRB(w * 0.55, h * 0.37, w * 0.66, h * 0.58);
    canvas.drawRect(isl, Paint()..color = const Color(0xFF56707F));
    canvas.drawRect(isl, line);
    final bridge = Rect.fromLTRB(w * 0.535, h * 0.335, w * 0.675, h * 0.385);
    canvas.drawRect(bridge, Paint()..color = const Color(0xFF455A64));
    canvas.drawRect(bridge, line);
    for (var i = 0; i < 6; i++) {
      canvas.drawRect(Rect.fromLTWH(w * (0.543 + i * 0.021), h * 0.349, w * 0.014, h * 0.014),
          Paint()..color = const Color(0xFFFFE082));
    }
    // mástil y radar giratorio
    final mx = w * 0.60;
    canvas.drawLine(Offset(mx, h * 0.335), Offset(mx, h * 0.17), Paint()..strokeWidth = 2 ..color = const Color(0xFF263238));
    final sweep = cos(u * 2 * pi * 5) * w * 0.045;
    canvas.drawLine(Offset(mx - sweep, h * 0.17), Offset(mx + sweep, h * 0.17),
        Paint()..strokeWidth = 3 ..strokeCap = StrokeCap.round ..color = const Color(0xFF90A4AE));
    canvas.drawLine(Offset(mx, h * 0.24), Offset(mx + w * 0.05, h * 0.24), Paint()..strokeWidth = 1.5 ..color = const Color(0xFF263238));
    canvas.drawLine(Offset(mx, h * 0.28), Offset(mx - w * 0.05, h * 0.28), Paint()..strokeWidth = 1.5 ..color = const Color(0xFF263238));
    canvas.drawCircle(Offset(mx, h * 0.165), 2.5,
        Paint()..color = Colors.redAccent.withOpacity(0.5 + 0.5 * sin(u * 2 * pi * 8)));

    // lanzamisiles en la proa
    canvas.drawRect(Rect.fromLTRB(w * 0.745, h * 0.545, w * 0.835, h * 0.58),
        Paint()..color = const Color(0xFF37474F));
    canvas.save();
    canvas.translate(w * 0.79, h * 0.55);
    canvas.rotate(-0.9);
    final tube = RRect.fromRectAndRadius(
        Rect.fromLTWH(-w * 0.015, -h * 0.022, w * 0.12, h * 0.044), const Radius.circular(3));
    canvas.drawRRect(tube, Paint()..color = const Color(0xFF455A64));
    canvas.drawRRect(tube, line);
    if (u < 0.25 || u > 0.85) {
      // misil cargado asomando
      canvas.drawRect(Rect.fromLTWH(w * 0.02, -h * 0.012, w * 0.09, h * 0.024),
          Paint()..color = const Color(0xFFECEFF1));
      canvas.drawPath(
          Path()
            ..moveTo(w * 0.11, -h * 0.012)
            ..lineTo(w * 0.135, 0)
            ..lineTo(w * 0.11, h * 0.012)
            ..close(),
          Paint()..color = const Color(0xFFD32F2F));
    }
    canvas.restore();
    // cañón antiaéreo (CIWS) en popa
    canvas.drawCircle(Offset(w * 0.1, h * 0.565), w * 0.018, Paint()..color = const Color(0xFF546E7A));
    canvas.drawLine(Offset(w * 0.1, h * 0.565), Offset(w * 0.1 + w * 0.035, h * 0.545),
        Paint()..strokeWidth = 2.5 ..color = const Color(0xFF263238));
  }

  void _missile(Canvas canvas, double w, double h, double u) {
    const a = 0.25, dur = 0.55;
    if (u < a || u > a + dur) return;
    final f = (u - a) / dur;
    final ang = -0.9;
    final o = Offset(w * 0.79 + cos(ang) * w * 0.105, h * 0.55 + h * 0.006 + sin(ang) * w * 0.105);
    final c = Offset(o.dx + w * 0.06, o.dy - h * 0.38);
    final e = Offset(w * 1.02, -h * 0.25);
    final p = Curves.easeIn.transform(f);

    // humo y destello del lanzamiento
    if (f < 0.5) {
      for (var k = 0; k < 8; k++) {
        final ph = f / 0.5;
        final dx = sin(k * 2.1) * w * 0.05 * ph - w * 0.02 * ph;
        final dy = -h * 0.05 * ph * (0.5 + k / 8) - cos(k * 1.3) * h * 0.02;
        canvas.drawCircle(Offset(o.dx + dx, o.dy + dy), h * (0.03 + 0.05 * ph),
            Paint()..color = Colors.white.withOpacity((1 - ph) * 0.45));
      }
    }
    if (f < 0.12) {
      canvas.drawCircle(
          o,
          h * 0.09 * (1 - f / 0.12),
          Paint()
            ..color = const Color(0xFFFFF59D).withOpacity(0.9)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }

    // estela de humo y fuego
    for (var k = 18; k >= 1; k--) {
      final pk = max(0.0, p - k * 0.028);
      final pos = _bez(o, c, e, pk);
      final fade = 1 - k / 18;
      canvas.drawCircle(pos, h * (0.012 + 0.022 * (1 - fade)),
          Paint()..color = Color.lerp(const Color(0xFFFFB74D), const Color(0xFFCFD8DC), 1 - fade)!.withOpacity(fade * 0.7));
    }
    final head = _bez(o, c, e, p);
    final prev = _bez(o, c, e, max(0.0, p - 0.03));
    final dir = (head - prev);
    final d = dir.distance == 0 ? const Offset(1, 0) : dir / dir.distance;
    canvas.drawCircle(
        head - d * 6,
        h * 0.03,
        Paint()
          ..color = const Color(0xFFFF9800).withOpacity(0.8)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawLine(head - d * 12, head,
        Paint()..strokeWidth = 4.5 ..strokeCap = StrokeCap.round ..color = const Color(0xFFECEFF1));
    canvas.drawCircle(head, 3.2, Paint()..color = const Color(0xFFD32F2F));
  }

  @override
  bool shouldRepaint(covariant WarshipPainter old) => false;
}
