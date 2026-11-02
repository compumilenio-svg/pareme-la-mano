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

Offset _dir(double a) => Offset(sin(a), cos(a));

const List<Color> _skinTones = [
  Color(0xFFF3CFAE),
  Color(0xFFE5B58A),
  Color(0xFFCB8F5F),
  Color(0xFFA8704A),
  Color(0xFF7D4D31),
  Color(0xFF55321F),
];
const List<Color> _hairTones = [
  Color(0xFF1B1210),
  Color(0xFF3A2416),
  Color(0xFF5B3A22),
  Color(0xFF8D5C2C),
  Color(0xFFD8B25A),
  Color(0xFF8E3B1F),
];

/// Número estable a partir de un nombre, para darle a cada jugador su aspecto.
int lookOf(String s) {
  var h = 7;
  for (final r in s.runes) {
    h = (h * 31 + r) & 0x7fffffff;
  }
  return h;
}

/// Dibuja un jugador estilo caricatura (cabeza grande, ojos grandes) con los pies
/// en [feet] y altura [h]. Piel, peinado y color de cabello salen de [look].
/// [liftL]/[liftR] 0..1 levantan cada pierna; [spreadL]/[spreadR] las abren;
/// [armsUp] 0..1 levanta los brazos.
void drawPlayer(Canvas c, Offset feet, double h, Kit kit,
    {double swing = 0,
    double armsUp = 0,
    bool back = false,
    double lean = 0,
    int look = 0,
    String? label,
    double labelSize = 0,
    double? liftL,
    double? liftR,
    double spreadL = 0,
    double spreadR = 0,
    Color? glove}) {
  final u = h;
  final skin = _skinTones[const [1, 1, 2, 2, 2, 3, 3, 0, 4, 5][(look >> 3) % 10]];
  final hairC = _hairTones[const [0, 0, 0, 1, 1, 2, 2, 3, 4, 5][(look >> 7) % 10]];
  final style = const [0, 0, 1, 1, 2, 3, 4, 0, 1, 2][(look >> 11) % 10];
  final skinShade = Color.lerp(skin, Colors.black, 0.18)!;
  final lL = liftL ?? (swing > 0 ? swing : 0.0);
  final lR = liftR ?? (swing < 0 ? -swing : 0.0);
  c.save();
  c.translate(feet.dx, feet.dy);
  c.rotate(lean);

  // sombra
  c.drawOval(Rect.fromCenter(center: Offset.zero, width: u * 0.44, height: u * 0.07),
      Paint()..color = Colors.black.withOpacity(0.30));

  Paint stroke(Color col, double w, [StrokeCap cap = StrokeCap.round]) => Paint()
    ..color = col
    ..strokeWidth = w
    ..strokeCap = cap
    ..style = PaintingStyle.stroke;

  void leg(double side, double lift, double spread) {
    final hip = Offset(side * u * 0.050, -u * 0.34);
    final ta = side * (0.05 + spread);
    final knee = hip + _dir(ta) * (u * 0.15 * (1 - 0.55 * lift));
    final sa = ta - side * 0.10 * lift;
    final foot = knee + _dir(sa) * (u * 0.15 * (1 - 0.70 * lift));
    c.drawLine(hip, knee, stroke(skin, u * 0.082));
    c.drawLine(hip, Offset.lerp(hip, knee, 0.62)!, stroke(kit.shorts, u * 0.105));
    c.drawLine(knee, foot, stroke(skin, u * 0.070));
    // media alta con franja
    final sockTop = Offset.lerp(knee, foot, 0.18)!;
    c.drawLine(sockTop, foot, stroke(kit.socks, u * 0.078));
    final sd = (foot - knee);
    final len = sd.distance;
    if (len > 0.0001) {
      final perp = Offset(-sd.dy / len, sd.dx / len);
      final sp0 = Offset.lerp(knee, foot, 0.34)!;
      c.drawLine(sp0 - perp * (u * 0.04), sp0 + perp * (u * 0.04),
          stroke(Colors.white.withOpacity(0.85), u * 0.014, StrokeCap.butt));
    }
    // botín blanco
    c.drawOval(
        Rect.fromCenter(
            center: foot + Offset(side * u * 0.014, u * 0.012), width: u * 0.115, height: u * 0.062),
        Paint()..color = Colors.white);
    c.drawLine(foot + Offset(-u * 0.04, u * 0.036), foot + Offset(u * 0.05, u * 0.036),
        stroke(const Color(0xFF8A8A8A), u * 0.012));
  }

  leg(-1, lL, spreadL);
  leg(1, lR, spreadR);

  // pantaloneta
  final shorts = Path()
    ..moveTo(-u * 0.108, -u * 0.42)
    ..lineTo(u * 0.108, -u * 0.42)
    ..lineTo(u * 0.128, -u * 0.27)
    ..lineTo(-u * 0.128, -u * 0.27)
    ..close();
  c.drawPath(shorts, Paint()..color = kit.shorts);
  c.drawLine(Offset(0, -u * 0.40), Offset(0, -u * 0.27),
      stroke(Colors.black.withOpacity(0.12), u * 0.01, StrokeCap.butt));

  // camiseta
  final shirt = Path()
    ..moveTo(-u * 0.135, -u * 0.60)
    ..lineTo(u * 0.135, -u * 0.60)
    ..lineTo(u * 0.128, -u * 0.50)
    ..lineTo(u * 0.108, -u * 0.35)
    ..lineTo(-u * 0.108, -u * 0.35)
    ..lineTo(-u * 0.128, -u * 0.50)
    ..close();
  final r = shirt.getBounds();
  c.save();
  c.clipPath(shirt);
  c.drawRect(r, Paint()..color = kit.primary);
  final sp = Paint()..color = kit.secondary;
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
  // volumen
  c.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(colors: [
          Colors.black.withOpacity(0.26),
          Colors.transparent,
          Colors.white.withOpacity(0.08),
          Colors.black.withOpacity(0.26)
        ], stops: const [0, 0.30, 0.55, 1])
            .createShader(r));
  c.restore();
  // cuello en V (de frente)
  if (!back) {
    final v = Path()
      ..moveTo(-u * 0.045, -u * 0.60)
      ..lineTo(0, -u * 0.545)
      ..lineTo(u * 0.045, -u * 0.60)
      ..close();
    c.drawPath(v, Paint()..color = skin);
    c.drawPath(
        v,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.012
          ..color = Color.lerp(kit.primary, Colors.black, 0.45)!);
  }

  // brazos
  void arm(double side) {
    final shoulder = Offset(side * u * 0.135, -u * 0.575);
    final a1 = side * (0.22 + armsUp * 2.55) + swing * side * -0.5;
    final elbow = shoulder + _dir(a1) * (u * 0.115);
    final a2 = a1 + side * (0.20 - armsUp * 0.28);
    final hand = elbow + _dir(a2) * (u * 0.110);
    c.drawLine(shoulder, elbow, stroke(kit.sleeve, u * 0.074));
    c.drawLine(Offset.lerp(shoulder, elbow, 0.62)!, elbow, stroke(skin, u * 0.058));
    c.drawLine(elbow, hand, stroke(skin, u * 0.056));
    c.drawCircle(hand, glove != null ? u * 0.050 : u * 0.036, Paint()..color = glove ?? skin);
  }

  arm(-1);
  arm(1);

  // ---- cabeza
  c.drawLine(Offset(0, -u * 0.60), Offset(0, -u * 0.655), stroke(skinShade, u * 0.055, StrokeCap.butt));
  final R = u * 0.150;
  final head = Offset(0, -u * 0.790);
  final hairP = Paint()..color = hairC;

  // pelo que va detrás de la cara
  if (style == 2) {
    c.drawCircle(head + Offset(0, -R * 0.12), R * 1.28, hairP);
  } else if (style == 3) {
    c.drawOval(Rect.fromCenter(center: head + Offset(0, R * 0.55), width: R * 2.25, height: R * 2.6),
        hairP);
  }
  // orejas
  if (!back) {
    for (final sd in [-1.0, 1.0]) {
      c.drawCircle(head + Offset(sd * R * 0.98, R * 0.06), R * 0.19, Paint()..color = skin);
      c.drawCircle(head + Offset(sd * R * 0.98, R * 0.06), R * 0.09, Paint()..color = skinShade);
    }
  }
  // cara con brillo
  c.drawCircle(
      head,
      R,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          radius: 1.0,
          colors: [Color.lerp(skin, Colors.white, 0.18)!, skin, skinShade],
          stops: const [0, 0.6, 1],
        ).createShader(Rect.fromCircle(center: head, radius: R)));

  if (back) {
    // nuca: todo cubierto de pelo
    final cover = style == 4 ? hairC.withOpacity(0.75) : hairC;
    c.drawCircle(head + Offset(0, -R * 0.02), R * 1.02, Paint()..color = cover);
    if (style == 0) {
      c.drawCircle(head + Offset(0, -R * 0.98), R * 0.30, hairP);
    }
  } else {
    // ojos grandes
    for (final sd in [-1.0, 1.0]) {
      final e = head + Offset(sd * R * 0.36, R * 0.02);
      c.drawOval(Rect.fromCenter(center: e, width: R * 0.40, height: R * 0.46),
          Paint()..color = Colors.white);
      c.drawCircle(e + Offset(0, R * 0.02), R * 0.15, Paint()..color = const Color(0xFF4A2B14));
      c.drawCircle(e + Offset(0, R * 0.02), R * 0.08, Paint()..color = const Color(0xFF120A06));
      c.drawCircle(e + Offset(-R * 0.05, -R * 0.06), R * 0.045, Paint()..color = Colors.white);
      // cejas
      final b = Path()
        ..moveTo(e.dx - R * 0.17, e.dy - R * 0.28)
        ..quadraticBezierTo(e.dx, e.dy - R * 0.38 - sd * 0.0, e.dx + R * 0.17, e.dy - R * 0.27);
      c.drawPath(
          b,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = R * 0.07
            ..strokeCap = StrokeCap.round
            ..color = hairC);
      // mejillas
      c.drawCircle(head + Offset(sd * R * 0.58, R * 0.40), R * 0.13,
          Paint()..color = const Color(0xFFE57A6A).withOpacity(0.22));
    }
    // nariz y sonrisa
    c.drawOval(Rect.fromCenter(center: head + Offset(0, R * 0.30), width: R * 0.16, height: R * 0.11),
        Paint()..color = skinShade);
    final sm = Path()
      ..moveTo(head.dx - R * 0.22, head.dy + R * 0.52)
      ..quadraticBezierTo(head.dx, head.dy + R * 0.72, head.dx + R * 0.22, head.dy + R * 0.52);
    c.drawPath(
        sm,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = R * 0.06
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF7A3B2E));
    // pelo de frente
    switch (style) {
      case 0: // copete
        c.drawArc(Rect.fromCircle(center: head, radius: R * 1.03), pi * 1.02, pi * 0.96, true, hairP);
        c.drawCircle(head + Offset(-R * 0.35, -R * 1.00), R * 0.30, hairP);
        c.drawCircle(head + Offset(0, -R * 1.08), R * 0.34, hairP);
        c.drawCircle(head + Offset(R * 0.38, -R * 0.96), R * 0.28, hairP);
        break;
      case 1: // corto con flequillo
        c.drawArc(Rect.fromCircle(center: head, radius: R * 1.04), pi * 1.0, pi * 1.0, true, hairP);
        c.drawRect(Rect.fromLTRB(head.dx - R * 1.0, head.dy - R * 0.55, head.dx + R * 1.0, head.dy - R * 0.38), hairP);
        break;
      case 2: // rizado: flequillo de bolitas
        for (var i = 0; i < 5; i++) {
          c.drawCircle(head + Offset((i - 2) * R * 0.34, -R * 0.78 + (i % 2) * R * 0.06),
              R * 0.26, hairP);
        }
        break;
      case 3: // largo: raya al costado
        c.drawArc(Rect.fromCircle(center: head, radius: R * 1.03), pi * 1.0, pi * 1.0, true, hairP);
        c.drawOval(Rect.fromCenter(center: head + Offset(R * 0.45, -R * 0.62), width: R * 1.3, height: R * 0.55),
            hairP);
        break;
      default: // rapado
        c.drawArc(Rect.fromCircle(center: head, radius: R * 1.01), pi * 1.0, pi * 1.0, true,
            Paint()..color = hairC.withOpacity(0.72));
        break;
    }
  }

  if (label != null && labelSize > 0) {
    final lum = kit.primary.computeLuminance();
    var fs = labelSize;
    var tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: lum > 0.55 ? Colors.black87 : Colors.white,
              fontSize: fs,
              fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    final maxW = u * 0.22;
    if (tp.width > maxW) {
      fs = fs * maxW / tp.width;
      tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: lum > 0.55 ? Colors.black87 : Colors.white,
                fontSize: fs,
                fontWeight: FontWeight.w900)),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    tp.paint(c, Offset(-tp.width / 2, -u * 0.545));
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
  final String keeperName;
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
    this.keeperName = '',
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
    const tKick = 0.385, tBall = 0.54;

    // ---- arquero: espera con pasitos y se lanza cuando el pateador golpea
    final kh = h * 0.20;
    final keeperRest = Offset(w * 0.5, g.bottom - kh * 0.5 + h * 0.004);
    var kCenter = keeperRest;
    var kAng = 0.0;
    var kArms = 0.5;
    var kSpread = 0.14;
    var kLiftL = 0.0, kLiftR = 0.0;
    if (t > 0.37 && shot.gz >= 0) {
      final q = _ease((t - 0.37) / 0.17);
      final target = GoalGeom.zoneCenter(s, shot.gz);
      final col = shot.gz % 3;
      final dir = col == 0 ? -1.0 : (col == 2 ? 1.0 : 0.0);
      kCenter = Offset.lerp(keeperRest, target, q)! - Offset(0, sin(pi * q) * h * 0.035);
      kAng = dir * 1.30 * q;
      kArms = 0.55 + 0.45 * q;
      kSpread = 0.14 + 0.22 * q;
      if (col == 1) {
        kCenter = kCenter - Offset(0, q * h * 0.04);
        kArms = 1.0;
      }
    } else {
      final sway = sin(clock * 3.0);
      kCenter = keeperRest + Offset(sway * w * 0.025, 0);
      kArms = 0.5 + 0.12 * sin(clock * 5);
      kLiftL = max(0.0, sway) * 0.25;
      kLiftR = max(0.0, -sway) * 0.25;
    }
    c.save();
    c.translate(kCenter.dx, kCenter.dy);
    c.rotate(kAng);
    drawPlayer(c, Offset(0, kh * 0.5), kh, keeper,
        armsUp: kArms,
        liftL: kLiftL,
        liftR: kLiftR,
        spreadL: kSpread,
        spreadR: kSpread,
        look: lookOf(keeperName),
        glove: const Color(0xFFB6FF00));
    c.restore();

    // ---- balón
    var ball = spot;
    var br = ballR;
    var spin = 0.0;
    if (t >= tKick && shot.kz >= 0) {
      final p = ((t - tKick) / (tBall - tKick)).clamp(0.0, 1.0).toDouble();
      final target = GoalGeom.zoneCenter(s, shot.kz);
      ball = Offset.lerp(spot, target, p)! - Offset(0, sin(pi * p) * h * 0.04);
      br = ballR * (1 - 0.42 * p);
      spin = p * 16;
      if (t > tBall) {
        final k = ((t - tBall) / 0.12).clamp(0.0, 1.0).toDouble();
        br = ballR * 0.58;
        spin += k * 8;
        if (shot.goal) {
          ball = Offset(target.dx, min(target.dy + k * h * 0.05, g.bottom - br));
        } else {
          final col = shot.kz % 3;
          final dx = (col == 0 ? -1.0 : (col == 2 ? 1.0 : 0.0)) * k * w * 0.12;
          ball = target + Offset(dx, k * h * 0.10 - sin(pi * k) * h * 0.04);
          br = ballR * (0.58 + 0.4 * k);
        }
      }
    }
    // red: se sacude cuando entra el gol
    if (t >= tBall && shot.goal && shot.kz >= 0) {
      final k = ((t - tBall) / 0.46).clamp(0.0, 1.0).toDouble();
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

    // ---- pateador (de espaldas, con su apellido): carrera, golpe y festejo
    final startH = h * 0.44, endH = h * 0.33;
    final startFeet = Offset(w * 0.20, h * 1.0);
    final endFeet = Offset(spot.dx - endH * 0.10, spot.dy + endH * 0.15);
    var rp = 0.0;
    var lL = 0.0, lR = 0.0, sR = 0.0;
    var arms = 0.12;
    var bob = 0.0;
    var leanK = 0.0;
    if (t < 0) {
      arms = 0.12 + 0.03 * sin(clock * 2);
    } else if (t >= 0.05) {
      final p = ((t - 0.05) / (tKick - 0.05)).clamp(0.0, 1.0).toDouble();
      rp = p * p * (3 - 2 * p);
      if (t < tKick) {
        final phase = p * 2 * pi * 3.5;
        final run = p < 0.78 ? 1.0 : max(0.0, (1 - p) / 0.22);
        lL = max(0.0, sin(phase)) * 0.8 * run;
        lR = max(0.0, -sin(phase)) * 0.8 * run;
        bob = (sin(phase)).abs() * h * 0.012 * run;
        arms = 0.10 + 0.08 * sin(phase);
        if (p >= 0.78) {
          final b = ((p - 0.78) / 0.22).clamp(0.0, 1.0).toDouble();
          lR = 0.8 * (1 - b) * run + 0.95 * b;
          sR = -0.20 * b;
          lL = 0.0;
        }
      } else {
        final k = (t - tKick) / 0.05;
        final f = ((t - tKick - 0.05) / 0.22).clamp(0.0, 1.0).toDouble();
        if (k < 1) {
          lR = 0.95 - 0.15 * k;
          sR = -0.20 + 0.45 * k;
        } else {
          lR = 0.8 * (1 - f) + 0.0 * f;
          sR = 0.25 - 0.35 * f;
        }
        leanK = 0.07 * (1 - f);
        if (t > tBall + 0.02) {
          if (shot.goal) {
            arms = 0.95;
            bob = (sin((t - tBall) * 38)).abs() * h * 0.022;
          } else {
            arms = 0.55;
            leanK = 0.04;
          }
        }
      }
    }
    final kh2 = startH + (endH - startH) * rp;
    final kFeet = Offset.lerp(startFeet, endFeet, rp)! - Offset(0, bob);
    drawPlayer(c, kFeet, kh2, kicker,
        back: true,
        liftL: lL,
        liftR: lR,
        spreadR: sR,
        armsUp: arms,
        lean: leanK,
        look: lookOf(kickerName),
        label: kickerName.toUpperCase(),
        labelSize: kh2 * 0.045);
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
          look: lookOf('jugador$i'));
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
