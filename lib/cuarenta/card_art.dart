import 'dart:math';
import 'package:flutter/material.dart';
import 'engine.dart';

const Color _red = Color(0xFFC62828);
const Color _ink = Color(0xFF1B1B1B);

/// Reverso clásico: borde blanco, marco ornamental, malla de rombos y medallón.
class CardBack extends StatelessWidget {
  final double width, height;
  final Color color;
  const CardBack(
      {super.key,
      required this.width,
      required this.height,
      this.color = const Color(0xFF1B3F94)});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(min(width, height) * 0.14),
          border: Border.all(color: Colors.black26, width: 0.8),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(1, 2)),
          ],
        ),
        child: CustomPaint(painter: _BackPainter(color)),
      );
}

class _BackPainter extends CustomPainter {
  final Color c;
  _BackPainter(this.c);

  @override
  void paint(Canvas canvas, Size s) {
    final m = min(s.width, s.height) * 0.09;
    final r = Rect.fromLTWH(m, m, s.width - 2 * m, s.height - 2 * m);
    final rr = RRect.fromRectAndRadius(r, Radius.circular(m * 0.8));
    canvas.drawRRect(rr, Paint()..color = c);
    canvas.save();
    canvas.clipRRect(rr);
    // malla de rombos
    final line = Paint()
      ..color = Colors.white.withOpacity(0.55)
      ..strokeWidth = max(0.6, s.width * 0.012);
    final step = s.width * 0.16;
    for (var d = -s.height; d < s.width + s.height; d += step) {
      canvas.drawLine(Offset(d, 0), Offset(d + s.height, s.height), line);
      canvas.drawLine(Offset(d, s.height), Offset(d + s.height, 0), line);
    }
    canvas.restore();
    // marco ornamental con guirnalda de puntos
    final inner = r.deflate(m * 1.1);
    canvas.drawRRect(
        RRect.fromRectAndRadius(inner, Radius.circular(m * 0.6)),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.8, m * 0.35));
    final dot = Paint()..color = Colors.white;
    final dr = max(0.7, m * 0.22);
    final per = (inner.width * 2 + inner.height * 2);
    final cnt = (per / (m * 1.6)).round();
    for (var i = 0; i < cnt; i++) {
      var p = per * i / cnt;
      Offset o;
      if (p < inner.width) {
        o = Offset(inner.left + p, inner.top - m * 0.55);
      } else if ((p -= inner.width) < inner.height) {
        o = Offset(inner.right + m * 0.55, inner.top + p);
      } else if ((p -= inner.height) < inner.width) {
        o = Offset(inner.right - p, inner.bottom + m * 0.55);
      } else {
        p -= inner.width;
        o = Offset(inner.left - m * 0.55, inner.bottom - p);
      }
      canvas.drawCircle(o, dr, dot);
    }
    // medallón central con laurel
    final ctr = s.center(Offset.zero);
    final rad = min(s.width, s.height) * 0.27;
    canvas.drawCircle(ctr, rad, Paint()..color = c);
    canvas.drawCircle(
        ctr,
        rad,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = max(0.9, rad * 0.12));
    canvas.drawCircle(ctr, rad * 0.62, Paint()..color = Colors.white);
    canvas.drawCircle(ctr, rad * 0.48, Paint()..color = c);
    // pétalos
    final leaf = Paint()..color = Colors.white;
    for (var i = 0; i < 8; i++) {
      final a = i * pi / 4;
      canvas.save();
      canvas.translate(ctr.dx, ctr.dy);
      canvas.rotate(a);
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(0, -rad * 0.3),
              width: rad * 0.16,
              height: rad * 0.34),
          leaf);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _BackPainter old) => old.c != c;
}

/// Cara clásica de baraja: fondo blanco, índices en esquinas, pintas y figuras.
class PlayingCardFace extends StatelessWidget {
  final PCard card;
  final double width, height;
  const PlayingCardFace(
      {super.key, required this.card, required this.width, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFEFA),
          borderRadius: BorderRadius.circular(min(width, height) * 0.12),
          border: Border.all(color: Colors.black38, width: 0.8),
          boxShadow: const [
            BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(2, 3)),
          ],
        ),
        child: CustomPaint(painter: _FacePainter(card)),
      );
}

class _FacePainter extends CustomPainter {
  final PCard c;
  _FacePainter(this.c);

  Color get col => c.isRed ? _red : _ink;

  void _text(Canvas cv, String t, Offset center, double fs,
      {bool flip = false, FontWeight w = FontWeight.bold}) {
    final tp = TextPainter(
      text: TextSpan(
          text: t,
          style: TextStyle(
              color: col, fontSize: fs, fontWeight: w, height: 1.0)),
      textDirection: TextDirection.ltr,
    )..layout();
    cv.save();
    cv.translate(center.dx, center.dy);
    if (flip) cv.rotate(pi);
    tp.paint(cv, Offset(-tp.width / 2, -tp.height / 2));
    cv.restore();
  }

  @override
  void paint(Canvas cv, Size s) {
    final w = s.width, h = s.height;
    final suit = suitSymbols[c.suit];
    final rank = c.rankLabel;
    final ifs = w * 0.27;
    // índices en esquinas
    _text(cv, rank, Offset(w * 0.15, h * 0.11), ifs);
    _text(cv, suit, Offset(w * 0.15, h * 0.11 + ifs * 0.95), ifs * 0.95);
    _text(cv, rank, Offset(w * 0.85, h * 0.89), ifs, flip: true);
    _text(cv, suit, Offset(w * 0.85, h * 0.89 - ifs * 0.95), ifs * 0.95,
        flip: true);

    final pip = w * 0.26;
    if (c.rank >= 8) {
      _face(cv, s);
      return;
    }
    final xl = w * 0.36, xc = w * 0.5, xr = w * 0.64;
    final yt = h * 0.21, ym = h * 0.5, yb = h * 0.79;
    final pts = <List<double>>[];
    switch (c.rank) {
      case 1:
        _text(cv, suit, Offset(xc, ym), w * 0.6);
        return;
      case 2:
        pts.addAll([[xc, yt], [xc, yb]]);
        break;
      case 3:
        pts.addAll([[xc, yt], [xc, ym], [xc, yb]]);
        break;
      case 4:
        pts.addAll([[xl, yt], [xr, yt], [xl, yb], [xr, yb]]);
        break;
      case 5:
        pts.addAll([[xl, yt], [xr, yt], [xc, ym], [xl, yb], [xr, yb]]);
        break;
      case 6:
        pts.addAll([[xl, yt], [xr, yt], [xl, ym], [xr, ym], [xl, yb], [xr, yb]]);
        break;
      case 7:
        pts.addAll([
          [xl, yt], [xr, yt], [xc, h * 0.355], [xl, ym], [xr, ym],
          [xl, yb], [xr, yb]
        ]);
        break;
    }
    for (final p in pts) {
      _text(cv, suit, Offset(p[0], p[1]), pip, flip: p[1] > h * 0.5);
    }
  }

  void _face(Canvas cv, Size s) {
    final w = s.width, h = s.height;
    final fr = Rect.fromLTRB(w * 0.30, h * 0.13, w * 0.74, h * 0.87);
    final frameC = c.isRed ? _red : _ink;
    // fondo de la figura en dos tonos
    cv.save();
    cv.clipRect(fr);
    cv.drawRect(fr, Paint()..color = const Color(0xFFFFF1B8));
    final tri = Path()
      ..moveTo(fr.left, fr.top)
      ..lineTo(fr.right, fr.top)
      ..lineTo(fr.left, fr.bottom)
      ..close();
    cv.drawPath(tri, Paint()..color = const Color(0xFF2C5AA0).withOpacity(0.35));
    final tri2 = Path()
      ..moveTo(fr.right, fr.bottom)
      ..lineTo(fr.right, fr.top)
      ..lineTo(fr.left, fr.bottom)
      ..close();
    cv.drawPath(tri2, Paint()..color = _red.withOpacity(0.30));
    cv.restore();
    cv.drawRect(
        fr,
        Paint()
          ..color = frameC
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1);
    cv.drawLine(fr.topLeft, fr.bottomRight, Paint()..color = frameC.withOpacity(0.35)..strokeWidth = 0.8);
    // corona o gorro
    final cx = fr.center.dx;
    final top = fr.top + fr.height * 0.18;
    final cw = fr.width * 0.46;
    final crown = Path();
    if (c.rank == 10 || c.rank == 9) {
      final base = top + fr.height * 0.12;
      crown.moveTo(cx - cw / 2, base);
      crown.lineTo(cx - cw / 2, top + fr.height * 0.02);
      crown.lineTo(cx - cw / 4, top + fr.height * 0.07);
      crown.lineTo(cx, top - (c.rank == 10 ? fr.height * 0.03 : fr.height * 0.0));
      crown.lineTo(cx + cw / 4, top + fr.height * 0.07);
      crown.lineTo(cx + cw / 2, top + fr.height * 0.02);
      crown.lineTo(cx + cw / 2, base);
      crown.close();
    } else {
      // J: gorro con pluma
      final base = top + fr.height * 0.12;
      crown.moveTo(cx - cw / 2, base);
      crown.quadraticBezierTo(cx - cw / 2, top, cx + cw * 0.1, top + fr.height * 0.02);
      crown.lineTo(cx + cw * 0.5, top - fr.height * 0.04);
      crown.lineTo(cx + cw * 0.35, base);
      crown.close();
    }
    cv.drawPath(crown, Paint()..color = const Color(0xFFE8B923));
    cv.drawPath(
        crown,
        Paint()
          ..color = frameC
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8);
    // letra grande y pinta
    _text(cv, c.rankLabel, Offset(cx, fr.center.dy + fr.height * 0.02), w * 0.34);
    _text(cv, suitSymbols[c.suit], Offset(cx, fr.top + fr.height * 0.80), w * 0.2);
  }

  @override
  bool shouldRepaint(covariant _FacePainter old) => old.c != c;
}

/// Cartón levantado por una pareja (para presionar a la contraria).
class CartonChip extends StatelessWidget {
  final int cards;
  final int score;
  final bool mine;
  const CartonChip(
      {super.key, required this.cards, required this.score, this.mine = false});

  @override
  Widget build(BuildContext context) {
    final dead = score >= noCartonFrom;
    final ok = cards >= cartonMinCards && !dead;
    final pts = ok ? pointsForCards(cards) : 0;
    final color = dead
        ? Colors.grey
        : ok
            ? Colors.green.shade700
            : (mine ? Colors.blue.shade700 : Colors.deepOrange.shade700);
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.style, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          dead
              ? 'Cartón $cards ✗'
              : ok
                  ? 'Cartón $cards  →  +$pts'
                  : 'Cartón $cards / $cartonMinCards',
          style: TextStyle(
              color: color, fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ]),
    );
  }
}
