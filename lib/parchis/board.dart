import 'dart:math';
import 'package:flutter/material.dart';
import 'engine.dart';

const List<Color> kPlayerColors = [
  Color(0xFFFBC02D), // amarillo
  Color(0xFF1E88E5), // azul
  Color(0xFFE53935), // rojo
  Color(0xFF43A047), // verde
];

/// Temáticas (personajes originales hechos con emojis: sin marcas registradas).
class ParchisTheme {
  final String name;
  final List<String> pieces;
  const ParchisTheme(this.name, this.pieces);
}

const List<ParchisTheme> kThemes = [
  ParchisTheme('Magia', ['🧙‍♂️', '🦉', '🐉', '🔮']),
  ParchisTheme('Monstruitos', ['🦊', '🐢', '🐲', '🐥']),
  ParchisTheme('Guerreros', ['🥷', '🥋', '🔥', '🐒']),
  ParchisTheme('Fútbol', ['⚽', '🏆', '🧤', '👟']),
  ParchisTheme('Familia', ['👨', '👩', '👦', '👧']),
  ParchisTheme('Superhéroes', ['🦸‍♂️', '🦸‍♀️', '🛡️', '⚡']),
  ParchisTheme('Liga heroica', ['🦇', '🦅', '🔱', '🏹']),
  ParchisTheme('Bosque amigo', ['🐻', '🐯', '🐰', '🐷']),
];

// ----------------------------------------------------------------------
// Geometría (cuadrícula de 19 x 19; Offset(x = columna, y = fila) de centros)
// ----------------------------------------------------------------------

Offset _rot(Offset p, int k) {
  var q = p;
  for (var i = 0; i < k; i++) {
    q = Offset(19 - q.dy, q.dx);
  }
  return q;
}

final List<Offset> kCircuitCenters = _buildCircuit();

List<Offset> _buildCircuit() {
  final arm = <Offset>[];
  for (var r = 11; r <= 18; r++) {
    arm.add(Offset(10.5, r + 0.5));
  }
  arm.add(const Offset(9.5, 18.5));
  for (var r = 18; r >= 11; r--) {
    arm.add(Offset(8.5, r + 0.5));
  }
  final out = <Offset>[];
  for (var k = 0; k < 4; k++) {
    for (final o in arm) {
      out.add(_rot(o, k));
    }
  }
  return out;
}

Offset routeCenter(int color, int r) {
  if (r <= 64) return kCircuitCenters[circuitIndexOf(color, r)];
  if (r < kGoal) return _rot(Offset(9.5, 17.5 - (r - 65)), color);
  return _rot(const Offset(9.5, 10.5), color);
}

Offset nestSlot(int color, int p) {
  const base = [Offset(2.3, 13.3), Offset(5.7, 13.3), Offset(2.3, 16.7), Offset(5.7, 16.7)];
  return _rot(base[p], color);
}

/// Posición (en casillas) de una ficha cuyo paso es [r] (puede ser fraccionario).
Offset tokenPos(int gi, double r) {
  final c = gi ~/ 4, p = gi % 4;
  if (r <= 0) return nestSlot(c, p);
  if (r <= 1) return Offset.lerp(nestSlot(c, p), routeCenter(c, 1), r)!;
  final a = r.floor();
  final b = min(a + 1, kGoal);
  return Offset.lerp(routeCenter(c, a), routeCenter(c, b), r - a)!;
}

// ----------------------------------------------------------------------
// Tablero
// ----------------------------------------------------------------------

class ParchisBoardPainter extends CustomPainter {
  final List<int> active;
  ParchisBoardPainter(this.active);

  void _cell(Canvas canvas, double u, Offset c, Color fill, {bool star = false}) {
    final rect = Rect.fromCenter(center: c * u, width: u * 0.94, height: u * 0.94);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(u * 0.18));
    canvas.drawRRect(rr, Paint()..color = fill);
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.05
          ..color = const Color(0xFF5D4037));
    if (star) {
      final path = Path();
      for (var i = 0; i < 10; i++) {
        final a = -pi / 2 + i * pi / 5;
        final rad = i.isEven ? u * 0.3 : u * 0.13;
        final p = c * u + Offset(cos(a), sin(a)) * rad;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      canvas.drawPath(path, Paint()..color = const Color(0xFF8D6E63));
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 19;
    final bg = RRect.fromRectAndRadius(
        Offset.zero & size, Radius.circular(u * 0.7));
    canvas.drawRRect(bg, Paint()..color = const Color(0xFFFFF3D6));
    canvas.drawRRect(
        bg,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = u * 0.25
          ..color = const Color(0xFF6D4C41));

    for (var c = 0; c < 4; c++) {
      final col = kPlayerColors[c];
      final on = active.contains(c);
      canvas.save();
      canvas.translate(size.width / 2, size.height / 2);
      canvas.rotate(c * pi / 2);
      canvas.translate(-size.width / 2, -size.height / 2);

      // Casa (nido)
      final nest = RRect.fromRectAndRadius(
          Rect.fromLTRB(0.5 * u, 11.5 * u, 7.5 * u, 18.5 * u), Radius.circular(u * 1.2));
      canvas.drawRRect(nest, Paint()..color = col.withOpacity(on ? 0.9 : 0.35));
      canvas.drawCircle(Offset(4 * u, 15 * u), u * 3.2,
          Paint()..color = Colors.white.withOpacity(0.55));
      for (final s in const [
        Offset(2.3, 13.3),
        Offset(5.7, 13.3),
        Offset(2.3, 16.7),
        Offset(5.7, 16.7)
      ]) {
        canvas.drawCircle(s * u, u * 1.05,
            Paint()..color = Color.lerp(col, Colors.black, 0.25)!.withOpacity(0.8));
      }

      // Casillas del circuito de este brazo
      for (var r = 11; r <= 18; r++) {
        final j = r - 11; // lado derecho
        _cell(canvas, u, Offset(10.5, r + 0.5), Colors.white, star: j == 4);
      }
      _cell(canvas, u, const Offset(9.5, 18.5), Colors.white, star: true);
      for (var r = 18; r >= 11; r--) {
        final isStart = r == 14;
        _cell(canvas, u, Offset(8.5, r + 0.5),
            isStart ? col.withOpacity(0.75) : Colors.white,
            star: isStart);
      }
      // Pasillo final
      for (var r = 17; r >= 11; r--) {
        _cell(canvas, u, Offset(9.5, r + 0.5), col.withOpacity(0.55));
      }
      // Triángulo del centro
      final tri = Path()
        ..moveTo(8 * u, 11 * u)
        ..lineTo(11 * u, 11 * u)
        ..lineTo(9.5 * u, 9.5 * u)
        ..close();
      canvas.drawPath(tri, Paint()..color = col);
      canvas.drawPath(
          tri,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = u * 0.06
            ..color = const Color(0xFF5D4037));
      canvas.restore();
    }
    canvas.drawCircle(Offset(9.5 * u, 9.5 * u), u * 0.35, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant ParchisBoardPainter old) => false;
}

// ----------------------------------------------------------------------
// Ficha
// ----------------------------------------------------------------------

class ParchisToken extends StatelessWidget {
  final int color;
  final String emoji;
  final double size;
  final bool highlight;
  final double pulse; // 0..1
  const ParchisToken({
    super.key,
    required this.color,
    required this.emoji,
    required this.size,
    this.highlight = false,
    this.pulse = 0,
  });

  @override
  Widget build(BuildContext context) {
    final col = kPlayerColors[color];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (highlight)
            Container(
              width: size * (1.0 + 0.18 * pulse),
              height: size * (1.0 + 0.18 * pulse),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: size * 0.08),
                boxShadow: [
                  BoxShadow(color: col.withOpacity(0.9), blurRadius: size * 0.4)
                ],
              ),
            ),
          Container(
            width: size * 0.9,
            height: size * 0.9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.4, -0.5),
                colors: [Color.lerp(col, Colors.white, 0.6)!, col, Color.lerp(col, Colors.black, 0.35)!],
                stops: const [0.0, 0.55, 1.0],
              ),
              border: Border.all(color: Colors.white, width: size * 0.06),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 2))],
            ),
            alignment: Alignment.center,
            child: Text(emoji,
                style: TextStyle(fontSize: size * 0.5, height: 1.0, decoration: TextDecoration.none)),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Dado
// ----------------------------------------------------------------------

class DiceFace extends StatelessWidget {
  final int value; // 0 = vacío
  final double size;
  final double angle;
  const DiceFace({super.key, required this.value, required this.size, this.angle = 0});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: CustomPaint(size: Size(size, size), painter: _DicePainter(value)),
    );
  }
}

class _DicePainter extends CustomPainter {
  final int v;
  _DicePainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final rr = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(s * 0.2));
    canvas.drawRRect(rr.shift(Offset(0, s * 0.04)), Paint()..color = Colors.black26);
    canvas.drawRRect(rr, Paint()..color = Colors.white);
    canvas.drawRRect(
        rr,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.04
          ..color = const Color(0xFF5D4037));
    const spots = {
      1: [Offset(.5, .5)],
      2: [Offset(.28, .28), Offset(.72, .72)],
      3: [Offset(.28, .28), Offset(.5, .5), Offset(.72, .72)],
      4: [Offset(.28, .28), Offset(.72, .28), Offset(.28, .72), Offset(.72, .72)],
      5: [Offset(.28, .28), Offset(.72, .28), Offset(.5, .5), Offset(.28, .72), Offset(.72, .72)],
      6: [Offset(.28, .25), Offset(.72, .25), Offset(.28, .5), Offset(.72, .5), Offset(.28, .75), Offset(.72, .75)],
    };
    for (final o in spots[v] ?? const <Offset>[]) {
      canvas.drawCircle(Offset(o.dx * s, o.dy * s), s * 0.08,
          Paint()..color = v == 6 || v == 1 ? Colors.red.shade700 : const Color(0xFF212121));
    }
  }

  @override
  bool shouldRepaint(covariant _DicePainter old) => old.v != v;
}

// ----------------------------------------------------------------------
// Pelea (cuando una ficha se come a otra)
// ----------------------------------------------------------------------

double _kf(double t, List<List<double>> k) {
  if (t <= k.first[0]) return k.first[1];
  for (var i = 0; i + 1 < k.length; i++) {
    if (t <= k[i + 1][0]) {
      final a = k[i], b = k[i + 1];
      final f = (t - a[0]) / (b[0] - a[0]);
      return a[1] + (b[1] - a[1]) * f;
    }
  }
  return k.last[1];
}

class FightOverlay extends StatelessWidget {
  final double t; // 0..1
  final Offset center; // en píxeles, dentro del tablero
  final double u;
  final Size boardSize;
  final int attColor, vicColor;
  final String attEmoji, vicEmoji;
  const FightOverlay({
    super.key,
    required this.t,
    required this.center,
    required this.u,
    required this.boardSize,
    required this.attColor,
    required this.vicColor,
    required this.attEmoji,
    required this.vicEmoji,
  });

  @override
  Widget build(BuildContext context) {
    final dim = _kf(t, [
      [0, 0],
      [0.1, 1],
      [0.88, 1],
      [1, 0]
    ]);
    final sep = u * 2.2;
    // Distancia al centro de cada contendiente
    final dist = _kf(t, [
      [0.0, 1.2],
      [0.14, 1.0],
      [0.28, 0.1],
      [0.34, 0.1],
      [0.42, 1.0],
      [0.52, 0.1],
      [0.58, 0.1],
      [0.62, 0.4],
    ]);
    final scale = _kf(t, [
      [0.0, 0.5],
      [0.14, 2.3],
      [0.8, 2.3],
      [1.0, 1.0]
    ]);
    // Perdedor: sale despedido y se esfuma
    final knock = _kf(t, [
      [0.58, 0.0],
      [0.7, 1.0],
      [1.0, 1.0]
    ]);
    final vicOpacity = _kf(t, [
      [0.0, 1.0],
      [0.66, 1.0],
      [0.82, 0.0],
      [1.0, 0.0]
    ]);
    final vicScale = scale * _kf(t, [
      [0.0, 1.0],
      [0.62, 1.0],
      [0.82, 0.2],
      [1.0, 0.0]
    ]);
    final vicSpin = _kf(t, [
      [0.58, 0.0],
      [0.82, 9.0],
      [1.0, 9.0]
    ]);
    final attX = center.dx - sep * dist + (t > 0.58 ? u * 0.3 * sin((t - 0.58) * 20) : 0);
    final vicX = center.dx + sep * dist + knock * u * 3.0;
    final vicY = center.dy - knock * u * 1.5;
    final tokenSize = u * 1.0;

    Widget tok(int c, String e, double sc) =>
        ParchisToken(color: c, emoji: e, size: tokenSize * sc);

    final shake = (t > 0.28 && t < 0.34) || (t > 0.52 && t < 0.58)
        ? sin(t * 400) * u * 0.12
        : 0.0;

    return IgnorePointer(
      child: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(color: Colors.black.withOpacity(0.55 * dim)),
          ),
          Positioned.fill(
            child: CustomPaint(painter: _FightFxPainter(t, center, u)),
          ),
          if (t > 0.02 && t < 0.85)
            Positioned(
              left: 0,
              right: 0,
              top: max(0.0, center.dy - u * 4.2),
              child: Opacity(
                opacity: dim,
                child: const Text('¡PELEA!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        letterSpacing: 4,
                        decoration: TextDecoration.none,
                        shadows: [Shadow(color: Colors.red, blurRadius: 12), Shadow(color: Colors.black, offset: Offset(2, 3))])),
              ),
            ),
          Positioned(
            left: attX - tokenSize * scale / 2 + shake,
            top: center.dy - tokenSize * scale / 2,
            child: tok(attColor, attEmoji, scale),
          ),
          Positioned(
            left: vicX - tokenSize * vicScale / 2 - shake,
            top: vicY - tokenSize * vicScale / 2,
            child: Opacity(
              opacity: vicOpacity.clamp(0.0, 1.0),
              child: Transform.rotate(
                angle: vicSpin,
                child: tok(vicColor, vicEmoji, vicScale.clamp(0.01, 5.0)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FightFxPainter extends CustomPainter {
  final double t;
  final Offset c;
  final double u;
  _FightFxPainter(this.t, this.c, this.u);

  void _burst(Canvas canvas, double k) {
    // k: 0..1 desde el choque
    final p = Paint()
      ..color = Colors.yellow.withOpacity((1 - k).clamp(0.0, 1.0))
      ..strokeWidth = u * 0.14
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 14; i++) {
      final a = i * 2 * pi / 14 + 0.3;
      final r0 = u * (0.5 + k * 1.2);
      final r1 = u * (1.1 + k * 2.4);
      canvas.drawLine(c + Offset(cos(a), sin(a)) * r0, c + Offset(cos(a), sin(a)) * r1, p);
    }
    canvas.drawCircle(c, u * (0.6 + k * 1.5),
        Paint()..color = Colors.white.withOpacity((0.8 * (1 - k)).clamp(0.0, 1.0)));
  }

  @override
  void paint(Canvas canvas, Size size) {
    for (final hit in const [0.30, 0.54]) {
      if (t >= hit && t < hit + 0.1) _burst(canvas, (t - hit) / 0.1);
    }
    // Nube cuando el perdedor se esfuma
    if (t > 0.66 && t < 0.92) {
      final k = (t - 0.66) / 0.26;
      final cc = c + Offset(u * 3.0, -u * 1.5);
      for (var i = 0; i < 10; i++) {
        final a = i * 2 * pi / 10;
        final r = u * (0.4 + k * 2.2);
        canvas.drawCircle(
            cc + Offset(cos(a), sin(a)) * r * 0.7,
            u * (0.5 + 0.4 * sin(i * 1.7)) * (1 - k * 0.5),
            Paint()..color = Colors.white.withOpacity(0.7 * (1 - k)));
      }
      // Estrellitas
      for (var i = 0; i < 6; i++) {
        final a = i * pi / 3 + k * 3;
        canvas.drawCircle(cc + Offset(cos(a), sin(a)) * u * (1 + k * 3), u * 0.12,
            Paint()..color = Colors.amber.withOpacity(1 - k));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _FightFxPainter old) => true;
}
