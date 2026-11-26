// Dibujo del monigote, los enemigos, el escenario y los efectos.
import 'dart:math';
import 'package:flutter/material.dart';
import 'engine.dart';

class _Spark {
  double x, y, vx, vy, life;
  final double max;
  final Color color;
  final double r;
  _Spark(this.x, this.y, this.vx, this.vy, this.life, this.color, this.r) : max = life;
}

class _Floater {
  final String text;
  double x, y, life;
  final Color color;
  _Floater(this.text, this.x, this.y, this.life, this.color);
}

/// Chispas, números flotantes, temblor de pantalla y el cartel central.
class StickFx {
  final List<_Spark> _sparks = [];
  final List<_Floater> _floats = [];
  final Random _rng = Random(5);
  double shake = 0.0;
  String banner = '';
  double bannerT = 0.0;

  void burst(double x, double y, Color c, int n, {double speed = 120.0}) {
    for (var i = 0; i < n; i++) {
      final a = _rng.nextDouble() * pi * 2;
      final s = speed * (0.4 + _rng.nextDouble() * 0.8);
      _sparks.add(_Spark(x, y, cos(a) * s, sin(a) * s - 40, 0.35 + _rng.nextDouble() * 0.3, c,
          1.2 + _rng.nextDouble() * 1.6));
    }
  }

  void floater(String text, double x, double y, Color c) {
    _floats.add(_Floater(text, x, y, 0.9, c));
  }

  void showBanner(String t) {
    banner = t;
    bannerT = 1.8;
  }

  void update(double dt) {
    for (final s in _sparks) {
      s.x += s.vx * dt;
      s.y += s.vy * dt;
      s.vy += 380.0 * dt;
      s.life -= dt;
    }
    _sparks.removeWhere((s) => s.life <= 0);
    for (final f in _floats) {
      f.y -= 30.0 * dt;
      f.life -= dt;
    }
    _floats.removeWhere((f) => f.life <= 0);
    shake = max(0.0, shake - dt * 5.0);
    bannerT = max(0.0, bannerT - dt);
  }
}

Color _wcolor(String id) {
  switch (id) {
    case 'nunchaku':
      return const Color(0xFF9E9E9E);
    case 'bate':
      return const Color(0xFFD7A86E);
    case 'katana':
      return const Color(0xFFE8E2C8);
    default:
      return const Color(0xFFB5651D);
  }
}

double _ease(double t) => 1 - (1 - t) * (1 - t);

/// Dibuja un monigote. (x, gy) = pies; [atk] = progreso del golpe 0..1 o -1.
void drawStick(
  Canvas c, {
  required double x,
  required double gy,
  required int face,
  required double t,
  required Color color,
  double scale = 1.0,
  bool crouch = false,
  bool air = false,
  bool moving = false,
  double atk = -1.0,
  double weaponLen = 0.0,
  Color weaponColor = const Color(0xFFB5651D),
  double weaponThick = 3.5,
  double hurt = 0.0,
  double thick = 3.4,
  double opacity = 1.0,
  bool headband = false,
  bool holdRock = false,
  bool lean = false,
}) {
  final col = color.withOpacity(opacity.clamp(0.0, 1.0).toDouble());
  final line = Paint()
    ..color = col
    ..style = PaintingStyle.stroke
    ..strokeWidth = thick * scale
    ..strokeCap = StrokeCap.round;
  final fill = Paint()..color = col;
  final f = face.toDouble();

  // sombra
  c.drawOval(Rect.fromCenter(center: Offset(x, gy + 1), width: 26 * scale, height: 5 * scale),
      Paint()..color = Colors.black.withOpacity(0.25 * opacity));

  final legLen = 20.0 * scale;
  final hipY = air ? gy - 17 * scale : (crouch ? gy - 11 * scale : gy - legLen);
  var hipX = x - f * 5 * hurt;
  if (lean) hipX += f * 4 * scale;
  final torso = (crouch ? 14.0 : 18.0) * scale;
  final neckX = hipX + (lean ? f * 5 * scale : 0.0) - f * 3 * hurt;
  final neckY = hipY - torso;
  final headR = 6.5 * scale;
  final headC = Offset(neckX + (lean ? f * 2 * scale : 0.0) - f * 3 * hurt, neckY - headR - 1.5 * scale);

  // piernas
  if (air) {
    c.drawLine(Offset(hipX, hipY), Offset(hipX + f * 9 * scale, hipY + 8 * scale), line);
    c.drawLine(Offset(hipX, hipY), Offset(hipX - f * 5 * scale, hipY + 10 * scale), line);
  } else if (crouch) {
    c.drawLine(Offset(hipX, hipY), Offset(hipX + f * 11 * scale, gy), line);
    c.drawLine(Offset(hipX, hipY), Offset(hipX - f * 9 * scale, gy), line);
  } else if (moving) {
    final a = sin(t * 13) * 0.75;
    c.drawLine(Offset(hipX, hipY),
        Offset(hipX + sin(a) * legLen, hipY + cos(a) * legLen), line);
    c.drawLine(Offset(hipX, hipY),
        Offset(hipX - sin(a) * legLen, hipY + cos(a) * legLen), line);
  } else {
    c.drawLine(Offset(hipX, hipY), Offset(hipX + 5 * scale, gy), line);
    c.drawLine(Offset(hipX, hipY), Offset(hipX - 5 * scale, gy), line);
  }
  // torso y cabeza
  c.drawLine(Offset(hipX, hipY), Offset(neckX, neckY), line);
  c.drawCircle(headC, headR, fill);
  if (headband) {
    c.drawLine(Offset(headC.dx - headR, headC.dy - 1 * scale),
        Offset(headC.dx + headR, headC.dy - 1 * scale),
        Paint()
          ..color = const Color(0xFFE53935).withOpacity(opacity)
          ..strokeWidth = 2.2 * scale
          ..strokeCap = StrokeCap.round);
    // cinta ondeando
    final w = sin(t * 9) * 2 * scale;
    c.drawLine(Offset(headC.dx - f * headR, headC.dy - 1 * scale),
        Offset(headC.dx - f * (headR + 7 * scale), headC.dy + 2 * scale + w),
        Paint()
          ..color = const Color(0xFFE53935).withOpacity(opacity)
          ..strokeWidth = 1.8 * scale
          ..strokeCap = StrokeCap.round);
  }

  final shoulder = Offset(neckX, neckY + 4 * scale);
  // brazo de atrás
  final swing = moving ? sin(t * 13) * 5 * scale : 0.0;
  c.drawLine(shoulder, Offset(shoulder.dx - f * 7 * scale + swing * 0.5, shoulder.dy + 10 * scale), line);

  // brazo delantero (con arma o puño)
  if (weaponLen > 0) {
    double th;
    if (atk >= 0) {
      th = -2.0 + 3.5 * _ease(atk.clamp(0.0, 1.0).toDouble());
    } else {
      th = 0.55 + (moving ? sin(t * 13) * 0.12 : sin(t * 3) * 0.04);
    }
    final hand = Offset(shoulder.dx + f * 8 * scale, shoulder.dy + 5 * scale);
    c.drawLine(shoulder, hand, line);
    final dir = Offset(f * sin(th), -cos(th));
    final tip = hand + dir * weaponLen;
    if (atk >= 0.15 && atk <= 0.95) {
      for (var k = 1; k <= 4; k++) {
        final tk = th - k * 0.22 * (atk < 0.5 ? 1 : 1);
        final d2 = Offset(f * sin(tk), -cos(tk));
        c.drawLine(hand + d2 * (weaponLen * 0.45), hand + d2 * weaponLen,
            Paint()
              ..color = Colors.white.withOpacity(0.22 - k * 0.04)
              ..strokeWidth = 3.0 * scale
              ..strokeCap = StrokeCap.round);
      }
    }
    c.drawLine(hand, tip,
        Paint()
          ..color = weaponColor
          ..strokeWidth = weaponThick * scale
          ..strokeCap = StrokeCap.round);
  } else {
    var ext = 0.0;
    if (atk >= 0) {
      ext = atk < 0.6 ? -0.4 * (atk / 0.6) : -0.4 + 1.6 * ((atk - 0.6) / 0.4);
    }
    final hand = holdRock
        ? Offset(shoulder.dx + f * 3 * scale, shoulder.dy - 12 * scale)
        : Offset(shoulder.dx + f * (8 + 16 * ext.clamp(-0.4, 1.2).toDouble()) * scale,
            shoulder.dy + (6 - 3 * ext.clamp(0.0, 1.0).toDouble()) * scale);
    c.drawLine(shoulder, hand, line);
    if (holdRock) {
      c.drawCircle(hand + Offset(0, -4 * scale), 4.5 * scale, Paint()..color = const Color(0xFF8D8D8D));
    }
  }
}

class StickPainter extends CustomPainter {
  final StickWorld w;
  final StickFx fx;
  final double t;
  StickPainter(this.w, this.fx, this.t, Listenable repaint) : super(repaint: repaint);

  @override
  bool shouldRepaint(covariant StickPainter old) => true;

  static void _text(Canvas c, String s, Offset o, double size, Color col,
      {TextAlign align = TextAlign.left, bool bold = true}) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: col,
              fontSize: size,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
              shadows: const [Shadow(color: Colors.black87, blurRadius: 3)])),
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = o.dx;
    if (align == TextAlign.center) dx -= tp.width / 2;
    if (align == TextAlign.right) dx -= tp.width;
    tp.paint(c, Offset(dx, o.dy));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final s = min(size.width / kW, size.height / kH);
    final ox = (size.width - kW * s) / 2;
    final oy = (size.height - kH * s) / 2;
    canvas.save();
    canvas.translate(ox, oy);
    canvas.scale(s);
    canvas.clipRect(const Rect.fromLTWH(0, 0, kW, kH));
    if (fx.shake > 0) {
      canvas.translate(sin(w.time * 90) * fx.shake * 4, cos(w.time * 77) * fx.shake * 3);
    }
    paintScene(canvas, w.time);

    // enemigos (ordenados por x para que no parpadeen)
    for (final e in w.enemies) {
      _drawEnemy(canvas, e);
    }
    // piedras
    for (final r in w.rocks) {
      final p = Offset(r.x, kGround - r.z - 2);
      canvas.drawCircle(p, 5.5, Paint()..color = const Color(0xFF8D8D8D));
      canvas.drawCircle(
          p,
          5.5,
          Paint()
            ..color = Colors.black54
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2);
    }
    _drawPlayer(canvas);

    // chispas y números
    for (final sp in fx._sparks) {
      canvas.drawCircle(Offset(sp.x, sp.y), sp.r,
          Paint()..color = sp.color.withOpacity((sp.life / sp.max).clamp(0.0, 1.0).toDouble()));
    }
    for (final f in fx._floats) {
      _text(canvas, f.text, Offset(f.x, f.y), 11, f.color.withOpacity((f.life / 0.9).clamp(0.0, 1.0).toDouble()),
          align: TextAlign.center);
    }
    _hud(canvas);
    canvas.restore();
  }

  static void paintScene(Canvas canvas, double time) {
    final sky = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF181B3A), Color(0xFF5B4570), Color(0xFFE09A72)],
        stops: [0.0, 0.6, 1.0],
      ).createShader(const Rect.fromLTWH(0, 0, kW, kGround));
    canvas.drawRect(const Rect.fromLTWH(0, 0, kW, kGround), sky);
    canvas.drawCircle(const Offset(390, 56), 20, Paint()..color = const Color(0xFFFFF1C9));
    canvas.drawCircle(const Offset(398, 52), 18, Paint()..color = const Color(0x44181B3A));
    // ciudad
    final b = Paint()..color = const Color(0xFF14162A);
    final win = Paint()..color = const Color(0xFFFFD27A);
    for (var i = 0; i < 16; i++) {
      final bw = 26.0 + ((i * 7) % 3) * 7;
      final bh = 46.0 + ((i * 13) % 5) * 15;
      final bx = i * 31.0 - 6;
      canvas.drawRect(Rect.fromLTWH(bx, kGround - bh, bw, bh), b);
      for (var wy = 0; wy < 4; wy++) {
        for (var wx = 0; wx < 3; wx++) {
          if (((i * 5 + wy * 3 + wx * 7) % 4) == 0) {
            canvas.drawRect(Rect.fromLTWH(bx + 5 + wx * 8, kGround - bh + 6 + wy * 11, 3.5, 4.5), win);
          }
        }
      }
    }
    // suelo
    canvas.drawRect(const Rect.fromLTWH(0, kGround, kW, kH - kGround), Paint()..color = const Color(0xFF23232F));
    canvas.drawRect(const Rect.fromLTWH(0, kGround, kW, 3), Paint()..color = const Color(0xFF3E3E52));
    final dash = Paint()..color = const Color(0xFF34344A);
    for (var i = 0; i < 12; i++) {
      canvas.drawRect(Rect.fromLTWH(i * 44.0 + 6, kGround + 24, 24, 3), dash);
    }
  }

  void _drawPlayer(Canvas canvas) {
    final p = w.p;
    final wp = w.stats.weapon;
    final blink = p.inv > 0 && ((w.time * 18).floor() % 2 == 0);
    final prog = p.atkT > 0 ? 1.0 - p.atkT / p.atkDur : -1.0;
    drawStick(canvas,
        x: p.x,
        gy: kGround - p.z,
        face: p.face,
        t: w.time,
        color: const Color(0xFFF4F4F4),
        crouch: p.crouching,
        air: p.z > 2,
        moving: p.moving,
        atk: prog,
        weaponLen: wp.reach * 0.72,
        weaponColor: _wcolor(wp.id),
        weaponThick: wp.id == 'bate' ? 5.5 : (wp.id == 'katana' ? 2.6 : 3.8),
        hurt: p.hurtT > 0 ? 1.0 : 0.0,
        opacity: blink ? 0.35 : (p.hp <= 0 ? 0.6 : 1.0),
        headband: true);
  }

  void _drawEnemy(Canvas canvas, Enemy e) {
    Color col;
    double sc;
    double th = 3.4;
    switch (e.kind) {
      case EKind.grunt:
        col = const Color(0xFFE35D5B);
        sc = 1.0;
        break;
      case EKind.runner:
        col = const Color(0xFFFFB74D);
        sc = 0.9;
        break;
      case EKind.thrower:
        col = const Color(0xFF6EC1E4);
        sc = 0.95;
        break;
      case EKind.brute:
        col = const Color(0xFF9B2C2C);
        sc = 1.3;
        th = 4.6;
        break;
      case EKind.boss:
        col = const Color(0xFF8E44AD);
        sc = 1.7;
        th = 4.8;
        break;
    }
    if (e.hurtT > 0) col = Colors.white;
    if (e.kind == EKind.boss && e.state == 3 && ((w.time * 14).floor() % 2 == 0)) col = Colors.yellowAccent;
    if (e.kind == EKind.boss && e.state == 4) col = const Color(0xFF6C7A89);

    double atk = -1.0;
    if (e.state == 1 && e.windup > 0) atk = (1.0 - e.t / e.windup).clamp(0.0, 1.0).toDouble();
    if (e.state == 2 && e.kind != EKind.thrower) atk = 0.9;

    if (e.dead) {
      final k = min(1.0, e.deadT * 4.0);
      canvas.save();
      canvas.translate(e.x, kGround);
      canvas.rotate(-e.face * pi / 2 * k);
      drawStick(canvas, x: 0, gy: 0, face: e.face, t: 0, color: col, scale: sc, thick: th,
          opacity: (1.0 - e.deadT).clamp(0.0, 1.0).toDouble());
      canvas.restore();
      return;
    }
    drawStick(canvas,
        x: e.x,
        gy: kGround,
        face: e.face,
        t: w.time + e.id,
        color: col,
        scale: sc,
        thick: th,
        moving: e.state == 0 && e.stun <= 0 && e.kind != EKind.boss || e.state == 5,
        atk: e.kind == EKind.thrower ? -1.0 : atk,
        hurt: e.hurtT > 0 ? 1.0 : 0.0,
        holdRock: e.kind == EKind.thrower && e.state == 1,
        lean: e.state == 5 || e.state == 3);
    // aviso del tipo de piedra: alta (agáchate) o baja (salta)
    if (e.kind == EKind.thrower && e.state == 1) {
      _text(canvas, e.high ? '⬇ AGÁCHATE' : '⬆ SALTA', Offset(e.x, kGround - 70), 9,
          e.high ? Colors.lightBlueAccent : Colors.orangeAccent,
          align: TextAlign.center);
    }
    if (e.kind == EKind.boss && e.state == 3) {
      _text(canvas, '¡CARGA!', Offset(e.x, kGround - 112), 11, Colors.yellowAccent, align: TextAlign.center);
    }
    // barra de vida
    final bw = 24.0 * sc;
    final by = kGround - 52 * sc - 6;
    canvas.drawRect(Rect.fromLTWH(e.x - bw / 2, by, bw, 3), Paint()..color = Colors.black54);
    canvas.drawRect(Rect.fromLTWH(e.x - bw / 2, by, bw * (e.hp / e.maxHp).clamp(0.0, 1.0).toDouble(), 3),
        Paint()..color = const Color(0xFFFF5252));
  }

  void _hud(Canvas canvas) {
    final p = w.p;
    final pct = (p.hp / p.maxHp).clamp(0.0, 1.0).toDouble();
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(10, 8, 124, 12), const Radius.circular(6)),
        Paint()..color = Colors.black54);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(12, 10, 120 * pct, 8), const Radius.circular(4)),
        Paint()..color = Color.lerp(const Color(0xFFE53935), const Color(0xFF43A047), pct)!);
    _text(canvas, '${p.hp.ceil()}/${p.maxHp.round()}', const Offset(16, 21), 8, Colors.white);
    _text(canvas, 'Oleada ${w.wave}', const Offset(kW / 2, 6), 13, Colors.white, align: TextAlign.center);
    _text(canvas, '🪙 ${w.coins}   ☠ ${w.kills}', const Offset(kW - 10, 6), 12, Colors.amberAccent,
        align: TextAlign.right);
    if (fx.bannerT > 0) {
      final a = min(1.0, fx.bannerT).toDouble();
      _text(canvas, fx.banner, Offset(kW / 2, 70), 26, Colors.white.withOpacity(a), align: TextAlign.center);
    }
  }
}

/// Vista previa del menú: escenario con el monigote practicando golpes.
class StickPreviewPainter extends CustomPainter {
  final Animation<double> a; // ciclo de 10 s
  final WeaponDef weapon;
  StickPreviewPainter(this.a, this.weapon) : super(repaint: a);

  @override
  bool shouldRepaint(covariant StickPreviewPainter old) => true;

  @override
  void paint(Canvas canvas, Size size) {
    final t = a.value * 10.0;
    final s = max(size.width / kW, size.height / kH);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate((size.width - kW * s) / 2, (size.height - kH * s) / 2);
    canvas.scale(s);
    StickPainter.paintScene(canvas, t);
    final cyc = (t * 1.2) % 2.0;
    final atk = cyc < 0.45 ? cyc / 0.45 : -1.0;
    drawStick(canvas,
        x: 180,
        gy: kGround,
        face: 1,
        t: t,
        color: const Color(0xFFF4F4F4),
        scale: 1.5,
        atk: atk,
        weaponLen: weapon.reach * 1.05,
        weaponColor: _wcolor(weapon.id),
        weaponThick: weapon.id == 'bate' ? 5.5 : 3.8,
        headband: true,
        thick: 3.6);
    drawStick(canvas,
        x: 330,
        gy: kGround,
        face: -1,
        t: t,
        color: const Color(0xFFE35D5B),
        scale: 1.5,
        thick: 3.6,
        atk: cyc > 1.0 && cyc < 1.4 ? (cyc - 1.0) / 0.4 : -1.0);
    canvas.restore();
  }
}
