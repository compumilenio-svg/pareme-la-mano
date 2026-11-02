import 'dart:math';
import 'package:flutter/material.dart';
import 'teams.dart';

// ======================================================================
// Camisetas y jugadores dibujados por código (sin escudos ni patrocinadores)
// ======================================================================

class Kit {
  final Color primary, secondary, sleeve, shorts, socks;
  final int pattern;
  const Kit(this.primary, this.secondary, this.sleeve, this.shorts, this.socks,
      this.pattern);

  factory Kit.of(TeamInfo t) => Kit(Color(t.primary), Color(t.secondary),
      Color(t.sleeve), Color(t.shorts), Color(t.socks), t.pattern);

  factory Kit.keeper(int team) {
    final c = Color(gkColorFor(team));
    return Kit(c, const Color(0xFF222222), c, const Color(0xFF1B1B1B),
        const Color(0xFF1B1B1B), kPatSolid);
  }
}

const Color _skin = Color(0xFFE0AC7B);
const Color _skinDark = Color(0xFF9C6B45);

double _ease(double t) => 1 - pow(1 - t.clamp(0.0, 1.0), 2).toDouble();

/// Dibuja un jugador con los pies en [feet] y altura [h].
/// [swing] -1..1 mueve piernas y brazos; [armsUp] 0..1 levanta los brazos.
void drawPlayer(Canvas c, Offset feet, double h, Kit kit,
    {double swing = 0,
    double armsUp = 0,
    bool back = false,
    double lean = 0,
    bool dark = false,
    String? label,
    double labelSize = 0}) {
  final u = h;
  final skin = dark ? _skinDark : _skin;
  c.save();
  c.translate(feet.dx, feet.dy);
  c.rotate(lean);

  // sombra
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: u * 0.38, height: u * 0.07),
      Paint()..color = Colors.black.withOpacity(0.28));

  final legW = u * 0.075;
  void leg(double dx, double ang) {
    c.save();
    c.translate(dx, -u * 0.36);
    c.rotate(ang);
    // muslo/short
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-legW / 2 - u * 0.01, 0, legW + u * 0.02, u * 0.15),
            Radius.circular(u * 0.02)),
        Paint()..color = kit.shorts);
    // pierna
    c.drawRect(Rect.fromLTWH(-legW / 2, u * 0.14, legW, u * 0.10), Paint()..color = skin);
    // media
    c.drawRect(Rect.fromLTWH(-legW / 2, u * 0.22, legW, u * 0.10),
        Paint()..color = kit.socks);
    // botín
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(-legW / 2 - u * 0.005, u * 0.31, legW + u * 0.04, u * 0.05),
            Radius.circular(u * 0.02)),
        Paint()..color = const Color(0xFF151515));
    c.restore();
  }

  leg(-u * 0.05, swing * 0.7);
  leg(u * 0.05, -swing * 0.7);

  // brazos
  void arm(double side) {
    c.save();
    c.translate(side * u * 0.145, -u * 0.80);
    final ang = side * (0.25 + armsUp * 2.4) + swing * side * -0.5;
    c.rotate(ang);
    c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-u * 0.035, 0, u * 0.07, u * 0.12),
            Radius.circular(u * 0.03)),
        Paint()..color = kit.sleeve);
    c.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(-u * 0.03, u * 0.10, u * 0.06, u * 0.13),
            Radius.circular(u * 0.03)),
        Paint()..color = skin);
    c.restore();
  }

  arm(-1);
  arm(1);

  // camiseta
  final shirt = RRect.fromRectAndRadius(
      Rect.fromLTWH(-u * 0.14, -u * 0.83, u * 0.28, u * 0.36), Radius.circular(u * 0.05));
  c.save();
  c.clipRRect(shirt);
  c.drawRect(shirt.outerRect, Paint()..color = kit.primary);
  final sp = Paint()..color = kit.secondary;
  final r = shirt.outerRect;
  switch (kit.pattern) {
    case kPatStripes:
      for (var i = 1; i < 6; i += 2) {
        c.drawRect(Rect.fromLTWH(r.left + r.width * i / 6, r.top, r.width / 6, r.height), sp);
      }
      break;
    case kPatHoops:
      for (var i = 1; i < 5; i += 2) {
        c.drawRect(Rect.fromLTWH(r.left, r.top + r.height * i / 5, r.width, r.height / 5), sp);
      }
      break;
    case kPatHalves:
      c.drawRect(Rect.fromLTWH(r.center.dx, r.top, r.width / 2, r.height), sp);
      break;
    case kPatSash:
      final p = Path()
        ..moveTo(r.left, r.top)
        ..lineTo(r.left + r.width * 0.34, r.top)
        ..lineTo(r.right, r.bottom)
        ..lineTo(r.right - r.width * 0.34, r.bottom)
        ..close();
      c.drawPath(p, sp);
      break;
    case kPatChest:
      c.drawRect(Rect.fromLTWH(r.left, r.top + r.height * 0.30, r.width, r.height * 0.26), sp);
      break;
    case kPatCenter:
      c.drawRect(Rect.fromLTWH(r.center.dx - r.width * 0.14, r.top, r.width * 0.28, r.height), sp);
      break;
    case kPatTri:
      c.drawRect(Rect.fromLTWH(r.left + r.width / 3, r.top, r.width / 3, r.height),
          Paint()..color = Colors.white);
      c.drawRect(Rect.fromLTWH(r.left + r.width * 2 / 3, r.top, r.width / 3, r.height), sp);
      break;
    default:
      break;
  }
  c.restore();

  // cuello y cabeza
  c.drawRect(Rect.fromLTWH(-u * 0.03, -u * 0.87, u * 0.06, u * 0.05), Paint()..color = skin);
  final head = Offset(0, -u * 0.93);
  c.drawCircle(head, u * 0.062, Paint()..color = skin);
  final hair = Paint()..color = const Color(0xFF1E1410);
  if (back) {
    c.drawCircle(head, u * 0.062, hair);
  } else {
    c.drawArc(Rect.fromCircle(center: head, radius: u * 0.064), pi, pi, true, hair);
    final eye = Paint()..color = const Color(0xFF1E1410);
    c.drawCircle(head + Offset(-u * 0.022, u * 0.005), u * 0.006, eye);
    c.drawCircle(head + Offset(u * 0.022, u * 0.005), u * 0.006, eye);
  }

  if (label != null && labelSize > 0) {
    final tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: kit.secondary.computeLuminance() > 0.6 &&
                      kit.primary.computeLuminance() > 0.6
                  ? Colors.black87
                  : (kit.primary.computeLuminance() > 0.55 ? Colors.black87 : Colors.white),
              fontSize: labelSize,
              fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: u * 0.34);
    tp.paint(c, Offset(-tp.width / 2, -u * 0.78));
  }
  c.restore();
}

void drawBall(Canvas c, Offset p, double r, {double spin = 0}) {
  c.drawCircle(p + Offset(r * 0.25, r * 0.95), r * 0.9,
      Paint()..color = Colors.black.withOpacity(0.25));
  c.drawCircle(p, r, Paint()..color = Colors.white);
  c.save();
  c.translate(p.dx, p.dy);
  c.rotate(spin);
  final dark = Paint()..color = const Color(0xFF222222);
  Path pent(double cx, double cy, double rr) {
    final path = Path();
    for (var i = 0; i < 5; i++) {
      final a = -pi / 2 + i * 2 * pi / 5;
      final x = cx + rr * cos(a), y = cy + rr * sin(a);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  c.drawPath(pent(0, 0, r * 0.38), dark);
  for (var i = 0; i < 5; i++) {
    final a = -pi / 2 + i * 2 * pi / 5;
    c.drawCircle(Offset(cos(a) * r * 0.82, sin(a) * r * 0.82), r * 0.2, dark);
  }
  c.restore();
  c.drawCircle(p, r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.07
        ..color = Colors.black26);
}

// ======================================================================
// Estadio
// ======================================================================

/// Geometría del arco en fracciones de la pantalla.
class GoalGeom {
  static const double l = 0.20, r = 0.80, t = 0.26, b = 0.50;
  static Rect rect(Size s) =>
      Rect.fromLTRB(s.width * l, s.height * t, s.width * r, s.height * b);
  static Offset zoneCenter(Size s, int z) {
    final g = rect(s);
    final col = z % 3, row = z ~/ 3;
    return Offset(g.left + g.width * (col + 0.5) / 3, g.top + g.height * (row + 0.5) / 2);
  }

  /// Zona tocada en [p] (o -1 si cae fuera del arco).
  static int zoneAt(Size s, Offset p) {
    final g = rect(s).inflate(s.width * 0.02);
    if (!g.contains(p)) return -1;
    final rr = rect(s);
    final col = ((p.dx - rr.left) / rr.width * 3).floor().clamp(0, 2).toInt();
    final row = ((p.dy - rr.top) / rr.height * 2).floor().clamp(0, 1).toInt();
    return row * 3 + col;
  }

  static Offset spot(Size s) => Offset(s.width * 0.5, s.height * 0.80);
}

void _drawStadium(Canvas c, Size s, Color home, Color away, double clock,
    double cheer, {bool showGoal = true}) {
  final w = s.width, h = s.height;
  // cielo nocturno
  c.drawRect(
      Rect.fromLTWH(0, 0, w, h * 0.45),
      Paint()
        ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF050B1F), Color(0xFF14264F)])
            .createShader(Rect.fromLTWH(0, 0, w, h * 0.45)));
  // reflectores
  for (final x in [0.08, 0.30, 0.70, 0.92]) {
    c.drawCircle(Offset(w * x, h * 0.035), w * 0.05,
        Paint()
          ..shader = RadialGradient(colors: [
            Colors.white.withOpacity(0.95),
            Colors.white.withOpacity(0.0)
          ]).createShader(Rect.fromCircle(center: Offset(w * x, h * 0.035), radius: w * 0.09)));
  }
  // tribunas: hinchada con los colores de los clubes
  final rnd = Random(11);
  c.drawRect(Rect.fromLTWH(0, h * 0.06, w, h * 0.20), Paint()..color = const Color(0xFF1B2238));
  final palette = [home, away, Colors.white, const Color(0xFF2B3354), home, away];
  for (var row = 0; row < 7; row++) {
    final y = h * (0.075 + row * 0.026);
    final count = 70;
    for (var i = 0; i < count; i++) {
      final x = (i + 0.5 + (row.isOdd ? 0.5 : 0)) * w / count;
      final jump = cheer > 0
          ? sin(clock * 9 + i * 1.7 + row) * h * 0.007 * cheer
          : 0.0;
      c.drawCircle(Offset(x, y + jump), w * 0.0065,
          Paint()..color = palette[rnd.nextInt(palette.length)].withOpacity(0.92));
    }
  }
  // banderas / trapos
  for (var i = 0; i < 6; i++) {
    final x = w * (0.08 + i * 0.17);
    final sway = sin(clock * 3 + i) * w * 0.004;
    final col = i.isEven ? home : away;
    c.drawRect(Rect.fromLTWH(x + sway, h * 0.085, w * 0.07, h * 0.03),
        Paint()..color = col.withOpacity(0.95));
  }
  // vallas
  c.drawRect(Rect.fromLTWH(0, h * 0.245, w, h * 0.028), Paint()..color = const Color(0xFF0F3B73));
  final tp = TextPainter(
      text: TextSpan(
          text: 'NOCHE DE JUEGOS   ⚽   COPA DE PENALES   ⚽   NOCHE DE JUEGOS   ⚽   COPA DE PENALES',
          style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: h * 0.016,
              fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr)
    ..layout();
  tp.paint(c, Offset(-(clock * 20) % (w * 0.5) - w * 0.1, h * 0.2475));

  // césped con franjas en perspectiva
  final horizon = h * 0.273;
  c.drawRect(
      Rect.fromLTWH(0, horizon, w, h - horizon),
      Paint()
        ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1C6B2B), Color(0xFF2E9A3E)])
            .createShader(Rect.fromLTWH(0, horizon, w, h - horizon)));
  for (var i = 0; i < 9; i++) {
    final y0 = horizon + (h - horizon) * pow(i / 9, 1.7);
    final y1 = horizon + (h - horizon) * pow((i + 1) / 9, 1.7);
    if (i.isEven) {
      c.drawRect(Rect.fromLTRB(0, y0.toDouble(), w, y1.toDouble()),
          Paint()..color = Colors.black.withOpacity(0.07));
    }
  }
  // líneas: área grande y chica, punto penal
  final line = Paint()
    ..color = Colors.white.withOpacity(0.85)
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * 0.004;
  c.drawLine(Offset(0, h * 0.50), Offset(w, h * 0.50), line); // línea de meta
  final area = Path()
    ..moveTo(w * 0.04, h * 0.50)
    ..lineTo(w * -0.02, h * 0.74)
    ..lineTo(w * 1.02, h * 0.74)
    ..lineTo(w * 0.96, h * 0.50);
  c.drawPath(area, line);
  final small = Path()
    ..moveTo(w * 0.22, h * 0.50)
    ..lineTo(w * 0.15, h * 0.60)
    ..lineTo(w * 0.85, h * 0.60)
    ..lineTo(w * 0.78, h * 0.50);
  c.drawPath(small, line);
  final sp = GoalGeom.spot(s);
  c.drawOval(Rect.fromCenter(center: sp, width: w * 0.03, height: h * 0.012),
      Paint()..color = Colors.white);
  c.drawArc(Rect.fromCenter(center: Offset(w * 0.5, h * 0.74), width: w * 0.30, height: h * 0.16),
      0.15, pi - 0.3, false, line);
}

/// Estado de la animación de un tiro (0..1) y lo necesario para dibujarlo.
class ShotAnim {
  final double t; // -1 = en reposo
  final int kz, gz; // zona del pateador y del arquero (-1 = ninguna)
  final bool goal;
  const ShotAnim(this.t, this.kz, this.gz, this.goal);
  static const ShotAnim idle = ShotAnim(-1, -1, -1, false);
}

class PenaltyScenePainter extends CustomPainter {
  final Kit kicker, keeper;
  final Color home, away;
  final ShotAnim shot;
  final int hover; // zona marcada por quien elige (-1 ninguna)
  final bool showZones;
  final String kickerName;
  final double clock;
  final double cheer;
  PenaltyScenePainter({
    required this.kicker,
    required this.keeper,
    required this.home,
    required this.away,
    required this.shot,
    required this.hover,
    required this.showZones,
    required this.kickerName,
    required this.clock,
    required this.cheer,
  });

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    _drawStadium(c, s, home, away, clock, cheer);
    final g = GoalGeom.rect(s);

    // fondo de la red
    final netBack = Paint()
      ..color = Colors.white.withOpacity(0.18)
      ..strokeWidth = 1;
    c.drawRect(g, Paint()..color = Colors.black.withOpacity(0.35));
    final depth = h * 0.035;
    final back = Rect.fromLTRB(g.left + w * 0.02, g.top + depth * 0.6, g.right - w * 0.02, g.bottom - depth * 0.2);
    for (var i = 0; i <= 24; i++) {
      final x = back.left + back.width * i / 24;
      c.drawLine(Offset(x, back.top), Offset(x, back.bottom), netBack);
    }
    for (var j = 0; j <= 10; j++) {
      final y = back.top + back.height * j / 10;
      c.drawLine(Offset(back.left, y), Offset(back.right, y), netBack);
    }

    // zonas
    if (showZones) {
      final zp = Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5;
      for (var i = 1; i < 3; i++) {
        final x = g.left + g.width * i / 3;
        c.drawLine(Offset(x, g.top), Offset(x, g.bottom), zp);
      }
      c.drawLine(Offset(g.left, g.center.dy), Offset(g.right, g.center.dy), zp);
      for (var z = 0; z < kZonesCount; z++) {
        final col = z % 3, row = z ~/ 3;
        final zr = Rect.fromLTWH(g.left + g.width * col / 3, g.top + g.height * row / 2,
            g.width / 3, g.height / 2);
        c.drawRect(zr, Paint()..color = Colors.white.withOpacity(0.04));
        if (z == hover) {
          c.drawRect(zr.deflate(2), Paint()..color = const Color(0xFFFFD600).withOpacity(0.38));
          c.drawRect(
              zr.deflate(2),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 3
                ..color = const Color(0xFFFFD600));
        }
        final tp = TextPainter(
            text: TextSpan(
                text: '${z + 1}',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.55),
                    fontSize: h * 0.03,
                    fontWeight: FontWeight.w900)),
            textDirection: TextDirection.ltr)
          ..layout();
        tp.paint(c, zr.center - Offset(tp.width / 2, tp.height / 2));
      }
    }

    final t = shot.t;
    final spot = GoalGeom.spot(s);
    final ballR = h * 0.026;

    // arquero
    final keeperRest = Offset(w * 0.5, g.bottom - h * 0.115);
    final kh = h * 0.215;
    var kCenter = keeperRest;
    var kAng = 0.0;
    var kArms = 0.35;
    if (t >= 0 && shot.gz >= 0) {
      final q = _ease(((t - 0.20) / 0.26));
      final target = GoalGeom.zoneCenter(s, shot.gz);
      kCenter = Offset.lerp(keeperRest, target + Offset(0, h * 0.02), q)!;
      final col = shot.gz % 3;
      final dir = col == 0 ? -1.0 : (col == 2 ? 1.0 : 0.0);
      kAng = dir * 1.25 * q;
      if (col == 1) kCenter = kCenter - Offset(0, q * h * 0.03);
      kArms = 0.35 + q * 0.65;
    } else {
      // pequeño balanceo mientras espera
      kCenter = keeperRest + Offset(sin(clock * 2.2) * w * 0.012, 0);
      kArms = 0.35 + 0.15 * sin(clock * 4);
    }
    c.save();
    c.translate(kCenter.dx, kCenter.dy);
    c.rotate(kAng);
    drawPlayer(c, Offset(0, kh * 0.5), kh, keeper, armsUp: kArms, swing: 0.1);
    c.restore();

    // balón
    var ball = spot;
    var br = ballR;
    var spin = 0.0;
    if (t >= 0.22 && shot.kz >= 0) {
      final p = ((t - 0.22) / 0.28).clamp(0.0, 1.0).toDouble();
      final e = _ease(p);
      final target = GoalGeom.zoneCenter(s, shot.kz);
      ball = Offset.lerp(spot, target, e)! - Offset(0, sin(pi * p) * h * 0.05);
      br = ballR * (1 - 0.45 * e);
      spin = p * 14;
    }
    // red: se sacude cuando entra el gol
    if (t >= 0.5 && shot.goal && shot.kz >= 0) {
      final k = ((t - 0.5) / 0.5).clamp(0.0, 1.0).toDouble();
      final amp = (1 - k) * h * 0.02;
      final tgt = GoalGeom.zoneCenter(s, shot.kz);
      final netP = Paint()
        ..color = Colors.white.withOpacity(0.55)
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke;
      for (var i = 0; i <= 14; i++) {
        final x = g.left + g.width * i / 14;
        final d = ((x - tgt.dx).abs() / (g.width * 0.35)).clamp(0.0, 1.0).toDouble();
        final off = amp * (1 - d) * sin(k * 30);
        c.drawLine(Offset(x, g.top), Offset(x + off, g.bottom + off * 0.5), netP);
      }
    }
    drawBall(c, ball, br, spin: spin);

    // palos y travesaño
    final post = Paint()
      ..color = Colors.white
      ..strokeWidth = w * 0.011
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(g.left, g.bottom), Offset(g.left, g.top), post);
    c.drawLine(Offset(g.right, g.bottom), Offset(g.right, g.top), post);
    c.drawLine(Offset(g.left, g.top), Offset(g.right, g.top), post);

    // pateador (de espaldas, con su apellido)
    var run = 0.0;
    var swing = 0.0;
    if (t >= 0) {
      run = _ease((t / 0.22));
      swing = t < 0.30 ? sin(t / 0.30 * pi * 1.4) * 1.0 : 0.0;
    }
    final kickerH = h * 0.40;
    final kickerFeet = Offset(w * 0.40 + run * w * 0.06, h * 0.995 - (1 - run) * -h * 0.0 - run * h * 0.07);
    drawPlayer(c, kickerFeet, kickerH, kicker,
        back: true, swing: swing, label: kickerName.toUpperCase(), labelSize: h * 0.021);
  }

  @override
  bool shouldRepaint(covariant PenaltyScenePainter old) => true;
}

const int kZonesCount = 6;

// ======================================================================
// Celebración: los jugadores corren a abrazarse
// ======================================================================

class CelebrationPainter extends CustomPainter {
  final Kit kit, keeper;
  final Color away;
  final double t; // segundos desde que empezó
  final double clock;
  final bool trophy;
  CelebrationPainter(
      {required this.kit,
      required this.keeper,
      required this.away,
      required this.t,
      required this.clock,
      required this.trophy});

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    _drawStadium(c, s, kit.primary == Colors.white ? kit.secondary : kit.primary, away,
        clock, 1.0);
    // 10 jugadores de campo + arquero corren desde los costados al centro
    final center = Offset(w * 0.5, h * 0.80);
    for (var i = 0; i < 11; i++) {
      final fromLeft = i.isEven;
      final start = Offset(fromLeft ? -w * 0.10 : w * 1.10, h * (0.68 + (i % 4) * 0.07));
      final ang = i * 2 * pi / 11;
      final target = center + Offset(cos(ang) * w * 0.15, sin(ang) * h * 0.075);
      final p = _ease(((t - 0.15 - i * 0.07) / 1.4));
      final pos = Offset.lerp(start, target, p)!;
      final arrived = p >= 1.0;
      final hgt = h * (0.22 + 0.16 * (pos.dy / h));
      final bounce = arrived ? (sin(clock * 7 + i * 1.3)).abs() * h * 0.035 : 0.0;
      drawPlayer(c, pos - Offset(0, bounce), hgt, i == 10 ? keeper : kit,
          swing: arrived ? 0.0 : sin(clock * 16 + i) * 1.0,
          armsUp: arrived ? 0.85 : 0.1,
          dark: i % 3 == 0);
    }
    if (trophy) _drawTrophy(c, Offset(w * 0.5, h * 0.50), h * 0.20, clock);
    // confeti
    final rnd = Random(9);
    for (var i = 0; i < 90; i++) {
      final x = rnd.nextDouble() * w;
      final speed = 0.18 + rnd.nextDouble() * 0.35;
      final y = ((t * speed + rnd.nextDouble()) % 1.15) * h * 1.1 - h * 0.1;
      final col = HSVColor.fromAHSV(1, rnd.nextDouble() * 360, 0.85, 1).toColor();
      c.save();
      c.translate(x + sin(clock * 2 + i) * 8, y);
      c.rotate(clock * 3 + i);
      c.drawRect(Rect.fromCenter(center: Offset.zero, width: w * 0.012, height: w * 0.02),
          Paint()..color = col);
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CelebrationPainter old) => true;
}

void _drawTrophy(Canvas c, Offset p, double size, double clock) {
  final gold = Paint()
    ..shader = const LinearGradient(colors: [Color(0xFFFFE066), Color(0xFFC79200)])
        .createShader(Rect.fromCenter(center: p, width: size, height: size));
  c.save();
  c.translate(p.dx, p.dy + sin(clock * 3) * size * 0.04);
  final cup = Path()
    ..moveTo(-size * 0.28, -size * 0.5)
    ..lineTo(size * 0.28, -size * 0.5)
    ..quadraticBezierTo(size * 0.26, size * 0.05, 0, size * 0.1)
    ..quadraticBezierTo(-size * 0.26, size * 0.05, -size * 0.28, -size * 0.5)
    ..close();
  c.drawPath(cup, gold);
  c.drawRect(Rect.fromLTWH(-size * 0.04, size * 0.08, size * 0.08, size * 0.18), gold);
  c.drawRRect(
      RRect.fromRectAndRadius(
          Rect.fromLTWH(-size * 0.2, size * 0.24, size * 0.4, size * 0.09),
          Radius.circular(size * 0.03)),
      gold);
  final handle = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = size * 0.05
    ..color = const Color(0xFFD9A400);
  c.drawArc(Rect.fromCenter(center: Offset(-size * 0.3, -size * 0.32), width: size * 0.22, height: size * 0.3),
      pi / 2, pi, false, handle);
  c.drawArc(Rect.fromCenter(center: Offset(size * 0.3, -size * 0.32), width: size * 0.22, height: size * 0.3),
      -pi / 2, pi, false, handle);
  c.restore();
}

/// Miniatura de un jugador con la camiseta del equipo (para elegir equipo).
class KitIcon extends StatelessWidget {
  final TeamInfo team;
  final double size;
  const KitIcon({super.key, required this.team, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _KitIconPainter(Kit.of(team))),
    );
  }
}

class _KitIconPainter extends CustomPainter {
  final Kit kit;
  _KitIconPainter(this.kit);
  @override
  void paint(Canvas c, Size s) {
    drawPlayer(c, Offset(s.width / 2, s.height * 0.98), s.height * 0.98, kit);
  }

  @override
  bool shouldRepaint(covariant _KitIconPainter old) => old.kit != kit;
}
