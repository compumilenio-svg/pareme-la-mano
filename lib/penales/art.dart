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
  Color(0xFF17100D),
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

Color _shade(Color c, double k) => Color.lerp(c, Colors.black, k)!;

/// Color de ribetes (cuello, puños): el secundario si contrasta, si no uno más oscuro.
Color _trimOf(Kit kit) {
  final d = (kit.secondary.computeLuminance() - kit.primary.computeLuminance()).abs();
  return d > 0.12 ? kit.secondary : _shade(kit.primary, 0.45);
}

/// Bosquejo genérico de escudo (no es el escudo oficial): usa los colores del club.
void _drawCrestSketch(Canvas c, Offset p, double s, Kit kit) {
  final path = Path()
    ..moveTo(p.dx - s * 0.5, p.dy - s * 0.55)
    ..lineTo(p.dx + s * 0.5, p.dy - s * 0.55)
    ..lineTo(p.dx + s * 0.5, p.dy + s * 0.05)
    ..quadraticBezierTo(p.dx + s * 0.45, p.dy + s * 0.45, p.dx, p.dy + s * 0.65)
    ..quadraticBezierTo(p.dx - s * 0.45, p.dy + s * 0.45, p.dx - s * 0.5, p.dy + s * 0.05)
    ..close();
  final lum = kit.primary.computeLuminance();
  final base = lum > 0.7 ? kit.secondary : Colors.white;
  final fill = lum > 0.7 ? Colors.white : kit.secondary;
  c.save();
  c.clipPath(path);
  c.drawRect(path.getBounds(), Paint()..color = base);
  c.drawRect(
      Rect.fromLTWH(p.dx - s * 0.5, p.dy - s * 0.05, s, s * 0.7), Paint()..color = fill);
  c.drawRect(Rect.fromLTWH(p.dx - s * 0.5, p.dy - s * 0.12, s, s * 0.14),
      Paint()..color = kit.primary);
  c.restore();
  c.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.10
        ..color = _shade(kit.primary, 0.55));
  c.drawCircle(p + Offset(0, -s * 0.30), s * 0.11, Paint()..color = _shade(kit.primary, 0.55));
}

const List<Color> _bootTones = [
  Color(0xFF1B1B1F),
  Color(0xFFF2F2F2),
  Color(0xFF35A7E0),
  Color(0xFFFF8A00),
];

/// Dibuja un jugador en estilo vectorial plano y sencillo (cabeza grande sin
/// rasgos, camiseta con manga corta y ribete, brazos rectos), con los pies en
/// [feet] y altura [h]. Piel, peinado, cabello y botines salen de [look].
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
    String? number,
    bool crest = false,
    double? liftL,
    double? liftR,
    double spreadL = 0,
    double spreadR = 0,
    Color? glove}) {
  final u = h;
  final skin = _skinTones[const [1, 1, 2, 2, 2, 3, 3, 0, 4, 5][(look >> 3) % 10]];
  final hairC = _hairTones[const [0, 0, 0, 1, 1, 2, 2, 3, 4, 5][(look >> 7) % 10]];
  final style = const [0, 0, 1, 1, 2, 3, 4, 0, 1, 2][(look >> 11) % 10];
  final bootC = _bootTones[(look >> 5) % 4];
  final skinSh = _shade(skin, 0.20);
  final trim = _trimOf(kit);
  final lL = liftL ?? (swing > 0 ? swing : 0.0);
  final lR = liftR ?? (swing < 0 ? -swing : 0.0);
  c.save();
  c.translate(feet.dx, feet.dy);
  c.rotate(lean);

  Paint fillP(Color col) => Paint()..color = col;
  void oval(double cx, double cy, double w, double hh, Color col) =>
      c.drawOval(Rect.fromCenter(center: Offset(cx, cy), width: w, height: hh), fillP(col));
  void poly(List<Offset> pts, Color col) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      p.lineTo(pts[i].dx, pts[i].dy);
    }
    p.close();
    c.drawPath(p, fillP(col));
  }

  oval(0, 0, u * 0.40, u * 0.05, Colors.black.withOpacity(0.20));

  void quad(Offset a, Offset b, double wa, double wb, double off, Color col,
      [bool caps = false]) {
    final d = b - a;
    final len = d.distance;
    if (len < 0.0001) return;
    final n = Offset(-d.dy / len, d.dx / len);
    poly([
      a + n * (off + wa / 2),
      b + n * (off + wb / 2),
      b + n * (off - wb / 2),
      a + n * (off - wa / 2),
    ], col);
    if (caps) {
      c.drawCircle(a + n * off, wa / 2, fillP(col));
      c.drawCircle(b + n * off, wb / 2, fillP(col));
    }
  }

  void leg(double side, double lift, double spread) {
    final hip = Offset(side * u * 0.052, -u * 0.44);
    final ta = side * (0.03 + spread);
    final knee = hip + _dir(ta) * (u * 0.23 * (1 - 0.55 * lift));
    final sa = ta - side * 0.10 * lift;
    final ank = knee + _dir(sa) * (u * 0.165 * (1 - 0.70 * lift));
    quad(hip, knee, u * 0.088, u * 0.078, 0, skin, true);
    quad(hip, knee, u * 0.030, u * 0.026, side * u * 0.030, skinSh);
    quad(knee, ank, u * 0.086, u * 0.074, 0, kit.socks);
    quad(knee, Offset.lerp(knee, ank, 0.14)!, u * 0.088, u * 0.086, 0,
        _trimOf(Kit(kit.socks, kit.secondary, kit.socks, kit.shorts, kit.socks, 0)));
    final boot = ank + Offset(side * u * 0.014, u * 0.020);
    final bp = Path()
      ..moveTo(boot.dx - u * 0.050, boot.dy + u * 0.022)
      ..lineTo(boot.dx - u * 0.045, boot.dy - u * 0.012)
      ..quadraticBezierTo(boot.dx, boot.dy - u * 0.030, boot.dx + u * 0.062, boot.dy + u * 0.004)
      ..lineTo(boot.dx + u * 0.066, boot.dy + u * 0.022)
      ..close();
    c.drawPath(bp, fillP(bootC));
    c.drawRect(Rect.fromLTWH(boot.dx - u * 0.052, boot.dy + u * 0.016, u * 0.120, u * 0.008),
        fillP(Colors.black.withOpacity(0.35)));
    quad(hip, Offset.lerp(hip, knee, 0.66)!, u * 0.112, u * 0.116, 0, kit.shorts);
  }

  leg(-1, lL, spreadL);
  leg(1, lR, spreadR);
  poly([
    Offset(-u * 0.108, -u * 0.47),
    Offset(u * 0.108, -u * 0.47),
    Offset(u * 0.112, -u * 0.36),
    Offset(-u * 0.112, -u * 0.36),
  ], kit.shorts);
  c.drawRect(Rect.fromLTWH(u * 0.084, -u * 0.47, u * 0.028, u * 0.11),
      fillP(Colors.black.withOpacity(0.12)));

  // brazos rectos hacia abajo
  void arm(double side) {
    final sho = Offset(side * u * 0.128, -u * 0.755);
    final a1 = side * (0.05 + armsUp * 2.65) + swing * side * -0.5;
    final elb = sho + _dir(a1) * (u * 0.150);
    final a2 = a1 + side * (0.04 - armsUp * 0.25);
    final hand = elb + _dir(a2) * (u * 0.140);
    quad(sho, elb, u * 0.058, u * 0.050, 0, skin, true);
    quad(elb, hand, u * 0.050, u * 0.042, 0, skin, true);
    quad(sho, elb, u * 0.020, u * 0.018, side * u * 0.020, skinSh);
    c.drawCircle(hand, glove != null ? u * 0.040 : u * 0.027, fillP(glove ?? skin));
  }

  arm(-1);
  arm(1);

  // camiseta
  const bt = 0.775, bb = 0.46;
  final body = Path()
    ..moveTo(-u * 0.042, -u * (bt + 0.010))
    ..lineTo(u * 0.042, -u * (bt + 0.010))
    ..lineTo(u * 0.118, -u * (bt - 0.012))
    ..lineTo(u * 0.122, -u * (bt - 0.060))
    ..lineTo(u * 0.114, -u * bb)
    ..lineTo(-u * 0.114, -u * bb)
    ..lineTo(-u * 0.122, -u * (bt - 0.060))
    ..lineTo(-u * 0.118, -u * (bt - 0.012))
    ..close();
  final rx0 = -u * 0.124, rw = u * 0.248, ry0 = -u * (bt + 0.010), rh = u * (bt + 0.010 - bb);
  c.save();
  c.clipPath(body);
  c.drawRect(Rect.fromLTWH(rx0, ry0, rw, rh), fillP(kit.primary));
  final sp = fillP(kit.secondary);
  switch (kit.pattern) {
    case kPatStripes:
      for (var i = 1; i < 8; i += 2) {
        c.drawRect(Rect.fromLTWH(rx0 + rw * i / 8, ry0, rw / 8, rh), sp);
      }
      break;
    case kPatHoops:
      for (var i = 1; i < 7; i += 2) {
        c.drawRect(Rect.fromLTWH(rx0, ry0 + rh * i / 7, rw, rh / 7), sp);
      }
      break;
    case kPatHalves:
      c.drawRect(Rect.fromLTWH(rx0 + rw / 2, ry0, rw / 2, rh), sp);
      break;
    case kPatSash:
      c.drawPath(
          Path()
            ..moveTo(rx0, ry0)
            ..lineTo(rx0 + rw * 0.34, ry0)
            ..lineTo(rx0 + rw, ry0 + rh)
            ..lineTo(rx0 + rw * 0.66, ry0 + rh)
            ..close(),
          sp);
      break;
    case kPatChest:
      c.drawRect(Rect.fromLTWH(rx0, ry0 + rh * 0.28, rw, rh * 0.22), sp);
      break;
    case kPatCenter:
      c.drawRect(Rect.fromLTWH(rx0 + rw * 0.35, ry0, rw * 0.30, rh), sp);
      break;
    case kPatTri:
      c.drawRect(Rect.fromLTWH(rx0 + rw / 3, ry0, rw / 3, rh), fillP(Colors.white));
      c.drawRect(Rect.fromLTWH(rx0 + rw * 2 / 3, ry0, rw / 3, rh), sp);
      break;
    default:
      break;
  }
  c.drawRect(Rect.fromLTWH(rx0, ry0, rw * 0.20, rh), fillP(Colors.black.withOpacity(0.14)));
  c.restore();

  // mangas cortas con ribete
  for (final side in [-1.0, 1.0]) {
    final s0 = Offset(side * u * 0.128, -u * (bt - 0.002));
    final s1 = Offset(side * u * 0.140, -u * (bt - 0.082));
    quad(s0, s1, u * 0.096, u * 0.094, 0, kit.sleeve);
    quad(Offset.lerp(s0, s1, 0.80)!, s1, u * 0.094, u * 0.094, 0, trim);
  }

  // cuello
  final trimP = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = u * 0.015
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..color = trim;
  if (back) {
    c.drawPath(
        Path()
          ..moveTo(-u * 0.042, -u * (bt + 0.010))
          ..quadraticBezierTo(0, -u * (bt - 0.020), u * 0.042, -u * (bt + 0.010)),
        trimP);
  } else {
    poly([
      Offset(-u * 0.046, -u * (bt + 0.010)),
      Offset(0, -u * (bt - 0.052)),
      Offset(u * 0.046, -u * (bt + 0.010)),
    ], skinSh);
    c.drawPath(
        Path()
          ..moveTo(-u * 0.046, -u * (bt + 0.010))
          ..lineTo(0, -u * (bt - 0.052))
          ..lineTo(u * 0.046, -u * (bt + 0.010)),
        trimP);
    if (crest) _drawCrestSketch(c, Offset(u * 0.062, -u * (bt - 0.105)), u * 0.050, kit);
  }
  if (number != null) {
    final lum = kit.primary.computeLuminance();
    final tpn = TextPainter(
      text: TextSpan(
          text: number,
          style: TextStyle(
              color: lum > 0.5 ? _shade(trim, 0.2) : Colors.white.withOpacity(0.95),
              fontSize: u * 0.085,
              fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tpn.paint(c, Offset(-tpn.width / 2, -u * (back ? 0.69 : 0.64)));
  }

  // ---- cabeza grande, sin rasgos
  quad(Offset(0, -u * 0.76), Offset(0, -u * 0.84), u * 0.050, u * 0.048, 0, skinSh);
  final rx = u * 0.058, ry = u * 0.070;
  final hc = Offset(0, -u * 0.905);
  Path headPath() => Path()
    ..moveTo(hc.dx, hc.dy - ry)
    ..cubicTo(hc.dx + rx * 1.1, hc.dy - ry, hc.dx + rx * 1.05, hc.dy + ry * 0.2,
        hc.dx + rx * 0.6, hc.dy + ry * 0.78)
    ..quadraticBezierTo(hc.dx + rx * 0.3, hc.dy + ry * 1.02, hc.dx, hc.dy + ry * 1.03)
    ..quadraticBezierTo(hc.dx - rx * 0.3, hc.dy + ry * 1.02, hc.dx - rx * 0.6, hc.dy + ry * 0.78)
    ..cubicTo(hc.dx - rx * 1.05, hc.dy + ry * 0.2, hc.dx - rx * 1.1, hc.dy - ry, hc.dx,
        hc.dy - ry)
    ..close();

  if (style == 4) {
    for (final sd in [-1.0, 1.0]) {
      quad(Offset(hc.dx + sd * rx * 0.85, hc.dy - ry * 0.2),
          Offset(hc.dx + sd * rx * 1.05, hc.dy + ry * 1.8), rx * 0.7, rx * 0.55, 0, hairC, true);
    }
  } else if (style == 3) {
    oval(hc.dx, hc.dy - ry * 0.2, rx * 2.4, ry * 2.2, hairC);
  }
  for (final sd in [-1.0, 1.0]) {
    oval(hc.dx + sd * rx * 1.0, hc.dy + ry * 0.12, rx * 0.30, ry * 0.38, skin);
  }
  c.drawPath(headPath(), fillP(skin));
  c.save();
  c.clipPath(headPath());
  c.drawRect(Rect.fromLTRB(hc.dx + rx * 0.35, hc.dy - ry, hc.dx + rx * 1.4, hc.dy + ry * 1.2),
      fillP(Colors.black.withOpacity(0.13)));
  c.restore();

  void hairArc(double a0, double a1, [double alpha = 1.0]) {
    final p = Path()
      ..moveTo(hc.dx, hc.dy)
      ..arcTo(Rect.fromCenter(center: hc, width: rx * 2.08, height: ry * 2.08), a0, a1 - a0, false)
      ..close();
    c.drawPath(p, fillP(hairC.withOpacity(alpha)));
  }

  if (back) {
    oval(hc.dx, hc.dy - ry * 0.10, rx * 2.14, ry * 1.84, hairC);
    c.drawRect(Rect.fromLTRB(hc.dx - rx * 0.8, hc.dy + ry * 0.64, hc.dx + rx * 0.8, hc.dy + ry * 0.94),
        fillP(skin));
  } else {
    switch (style) {
      case 0: // copete
        hairArc(pi, pi * 2);
        poly([
          Offset(hc.dx - rx * 0.9, hc.dy - ry * 0.55),
          Offset(hc.dx - rx * 0.5, hc.dy - ry * 1.35),
          Offset(hc.dx + rx * 0.4, hc.dy - ry * 1.40),
          Offset(hc.dx + rx * 0.95, hc.dy - ry * 0.70),
          Offset(hc.dx + rx * 0.95, hc.dy - ry * 0.30),
          Offset(hc.dx, hc.dy - ry * 0.62),
        ], hairC);
        break;
      case 1: // corto con flequillo
        hairArc(pi, pi * 2);
        poly([
          Offset(hc.dx - rx, hc.dy - ry * 0.30),
          Offset(hc.dx, hc.dy - ry * 0.72),
          Offset(hc.dx + rx, hc.dy - ry * 0.30),
          Offset(hc.dx + rx, hc.dy - ry),
          Offset(hc.dx - rx, hc.dy - ry),
        ], hairC);
        break;
      case 2: // rapado
        hairArc(pi * 1.04, pi * 1.96, 0.75);
        break;
      case 3: // rizado
        for (var i = 0; i < 5; i++) {
          c.drawCircle(Offset(hc.dx + (i - 2) * rx * 0.46, hc.dy - ry * 0.86 + (i % 2) * ry * 0.06),
              rx * 0.34, fillP(hairC));
        }
        break;
      default: // largo con raya
        hairArc(pi, pi * 2);
        oval(hc.dx + rx * 0.4, hc.dy - ry * 0.78, rx * 1.5, ry * 0.55, hairC);
        break;
    }
  }

  if (label != null && labelSize > 0) {
    final lum = kit.primary.computeLuminance();
    TextPainter mk(double size) => TextPainter(
          text: TextSpan(
              text: label,
              style: TextStyle(
                  color: lum > 0.5 ? _shade(trim, 0.2) : Colors.white.withOpacity(0.95),
                  fontSize: size,
                  fontWeight: FontWeight.w900)),
          textDirection: TextDirection.ltr,
        )..layout();
    var fs = labelSize;
    var tp = mk(fs);
    final maxW = u * 0.23;
    if (tp.width > maxW) {
      fs = fs * maxW / tp.width;
      tp = mk(fs);
    }
    tp.paint(c, Offset(-tp.width / 2, -u * 0.745));
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
    final kh = h * 0.23;
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
        crest: true,
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
    final endFeet = Offset(spot.dx - endH * 0.10, spot.dy + endH * 0.17);
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
        number: '${(lookOf(kickerName) % 11) + 1}',
        label: kickerName.toUpperCase(),
        labelSize: kh2 * 0.040);
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
          look: lookOf('jugador$i'),
          crest: true,
          number: '${i + 1}');
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
    c.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * 0.14)),
        Paint()..color = const Color(0xFFDCE3EE));
    drawPlayer(c, Offset(s.width / 2, s.height * 0.96), s.height * 0.92, kit,
        crest: true, look: 4256);
  }

  @override
  bool shouldRepaint(covariant _KitIconPainter old) => old.kit != kit;
}
