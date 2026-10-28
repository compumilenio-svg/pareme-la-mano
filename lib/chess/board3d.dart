import 'dart:math';
import 'package:flutter/material.dart';
import 'countries.dart';
import 'engine.dart';

class FightInfo {
  final int from, to, defSq;
  final int attacker, defender; // piezas con signo
  const FightInfo(this.from, this.to, this.defSq, this.attacker, this.defender);
}

/// Proyección en perspectiva del tablero (tablero inclinado hacia atrás).
class Proj {
  static const double D = 11.0;
  static const double th = 0.95;
  late final double sinT = sin(th);
  late final double cosT = cos(th);
  late final double F;
  late final double cx;
  late final double cy;

  Proj(double w, double h) {
    final zNear = D - 4.4 * sinT;
    final f1 = (w / 2 * 0.97) * zNear / 4.4;
    final zf = D + 3.5 * sinT;
    final zFrame = D + 4.4 * sinT;
    final top1 = min(-4.4 * cosT / zFrame, -3.5 * cosT / zf - 1.8 / zf);
    final bottom1 = 4.4 * cosT / zNear + 0.5 / zNear;
    final total1 = bottom1 - top1;
    F = min(f1, h / total1);
    cx = w / 2;
    cy = (h - F * total1) / 2 - F * top1;
  }

  double scaleAt(double y) => F / (D - (y - 4) * sinT);

  Offset project(double x, double y) {
    final z = D - (y - 4) * sinT;
    return Offset(cx + (x - 4) * F / z, cy + (y - 4) * cosT * F / z);
  }
}

const double _cellsPerPx = 1.2 / 300;

class Board3D extends StatelessWidget {
  final ChessState state;
  final bool flipped;
  final ChessCountry whiteCountry;
  final ChessCountry blackCountry;
  final int? selected;
  final Set<int> targets;
  final ChessMove? lastMove;
  final FightInfo? fight;
  final double fightT;
  final void Function(int sq) onTap;

  const Board3D({
    super.key,
    required this.state,
    required this.flipped,
    required this.whiteCountry,
    required this.blackCountry,
    required this.onTap,
    this.selected,
    this.targets = const {},
    this.lastMove,
    this.fight,
    this.fightT = 0,
  });

  // Coordenadas de pantalla (fila/columna mostradas) de una casilla.
  int _dr(int sq) => flipped ? 7 - sq ~/ 8 : sq ~/ 8;
  int _dc(int sq) => flipped ? 7 - sq % 8 : sq % 8;

  Offset _center(int sq) => Offset(_dc(sq) + 0.5, _dr(sq) + 0.5);

  ChessCountry _country(int piece) => piece > 0 ? whiteCountry : blackCountry;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final proj = Proj(c.maxWidth, c.maxHeight);
      final hidden = <int>{};
      if (fight != null) {
        hidden.add(fight!.from);
        hidden.add(fight!.defSq);
      }
      final rings = <_Ring>[];
      final pieceWidgets = <MapEntry<double, Widget>>[];

      // Piezas normales
      for (var sq = 0; sq < 64; sq++) {
        final v = state.b[sq];
        if (v == 0 || hidden.contains(sq)) continue;
        final cc = _center(sq);
        rings.add(_ring(proj, cc, v > 0));
        pieceWidgets.add(MapEntry(cc.dy, _pieceWidget(proj, v, cc, 1, 1, 0)));
      }

      // Pelea
      Widget? fx;
      if (fight != null) {
        final f = fight!;
        final t = fightT.clamp(0.0, 1.0);
        final a0 = _center(f.from);
        final tt = _center(f.to);
        final dd = _center(f.defSq);
        final near = Offset(a0.dx + (tt.dx - a0.dx) * 0.72, a0.dy + (tt.dy - a0.dy) * 0.72);
        Offset aPos;
        if (t < 0.2) {
          final u = Curves.easeOut.transform(t / 0.2);
          aPos = Offset(a0.dx + (near.dx - a0.dx) * u, a0.dy + (near.dy - a0.dy) * u);
        } else if (t < 0.8) {
          aPos = near;
        } else {
          final u = (t - 0.8) / 0.2;
          aPos = Offset(near.dx + (tt.dx - near.dx) * u, near.dy + (tt.dy - near.dy) * u);
        }
        final shake = (t > 0.2 && t < 0.7) ? sin(t * 90) * 0.05 : 0.0;
        final aDraw = Offset(aPos.dx + shake, aPos.dy);
        var dDraw = dd;
        double dOpacity = 1, dScale = 1, dLift = 0;
        if (t > 0.2 && t < 0.65) dDraw = Offset(dd.dx - shake, dd.dy);
        if (t >= 0.65) {
          final u = (t - 0.65) / 0.35;
          dOpacity = 1 - u;
          dScale = 1 + 0.25 * u;
          dLift = u * 1.2;
        }
        rings.add(_ring(proj, aPos, f.attacker > 0));
        if (t < 0.65) rings.add(_ring(proj, dd, f.defender > 0));
        pieceWidgets.add(MapEntry(
            dd.dy, _pieceWidget(proj, f.defender, dDraw, dOpacity, dScale, dLift)));
        pieceWidgets.add(MapEntry(
            aDraw.dy + 0.001, _pieceWidget(proj, f.attacker, aDraw, 1, 1, 0)));

        // Efectos: choque y humo
        final children = <Widget>[];
        if (t > 0.18 && t < 0.7) {
          final mid = Offset((aPos.dx + dd.dx) / 2, (aPos.dy + dd.dy) / 2);
          final p = proj.project(mid.dx, mid.dy);
          final s = proj.scaleAt(mid.dy);
          final pulse = 0.8 + 0.4 * sin(t * 60).abs();
          final size = s * 0.9 * pulse;
          children.add(Positioned(
            left: p.dx - size / 2,
            top: p.dy - s * 0.9 - size / 2,
            child: Text('💥', style: TextStyle(fontSize: size)),
          ));
        }
        if (t >= 0.65) {
          final u = (t - 0.65) / 0.35;
          final p = proj.project(dd.dx, dd.dy);
          final s = proj.scaleAt(dd.dy);
          for (var i = 0; i < 7; i++) {
            final ang = i * 0.9;
            final dx = cos(ang) * s * 0.35 * (0.4 + u);
            final dy = -u * s * (0.8 + 0.15 * i) - 0.2 * s;
            final r = s * (0.12 + 0.1 * u + 0.02 * i);
            children.add(Positioned(
              left: p.dx + dx - r,
              top: p.dy + dy - r,
              child: Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity((1 - u) * 0.55),
                ),
              ),
            ));
          }
        }
        fx = Stack(children: children);
      }

      pieceWidgets.sort((a, b) => a.key.compareTo(b.key));

      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (d) {
          final sq = _hit(proj, d.localPosition);
          if (sq != null) onTap(sq);
        },
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: _BoardPainter(
                  proj: proj,
                  state: state,
                  flipped: flipped,
                  selected: selected,
                  targets: targets,
                  lastMove: lastMove,
                  rings: rings,
                ),
              ),
            ),
            for (final e in pieceWidgets) e.value,
            if (fx != null) Positioned.fill(child: IgnorePointer(child: fx)),
          ],
        ),
      );
    });
  }

  _Ring _ring(Proj proj, Offset boardPos, bool white) {
    final p = proj.project(boardPos.dx, boardPos.dy);
    final s = proj.scaleAt(boardPos.dy);
    return _Ring(p, s * 0.40, s * 0.40 * proj.cosT * 0.9, white);
  }

  Widget _pieceWidget(Proj proj, int piece, Offset boardPos, double opacity,
      double scale, double lift) {
    final country = _country(piece);
    final type = piece.abs();
    final size = country.size(type);
    final p = proj.project(boardPos.dx, boardPos.dy);
    final s = proj.scaleAt(boardPos.dy);
    final h = size[1] * _cellsPerPx * s;
    final w = size[0] * _cellsPerPx * s;
    final bottom = p.dy + 0.10 * s - lift * s;
    return Positioned(
      left: p.dx - w / 2,
      top: bottom - h,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Image.asset(country.asset(type),
                fit: BoxFit.fill, gaplessPlayback: true),
          ),
        ),
      ),
    );
  }

  int? _hit(Proj proj, Offset pos) {
    // Primero busca por la casilla cuyo cuadrilátero contiene el toque.
    for (var dr = 0; dr < 8; dr++) {
      for (var dc = 0; dc < 8; dc++) {
        final path = _quad(proj, dc.toDouble(), dr.toDouble(), 1);
        if (path.contains(pos)) {
          final r = flipped ? 7 - dr : dr;
          final f = flipped ? 7 - dc : dc;
          return r * 8 + f;
        }
      }
    }
    return null;
  }
}

Path _quad(Proj proj, double x, double y, double size) {
  final a = proj.project(x, y);
  final b = proj.project(x + size, y);
  final c = proj.project(x + size, y + size);
  final d = proj.project(x, y + size);
  return Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();
}

class _Ring {
  final Offset c;
  final double rx, ry;
  final bool white;
  _Ring(this.c, this.rx, this.ry, this.white);
}

class _BoardPainter extends CustomPainter {
  final Proj proj;
  final ChessState state;
  final bool flipped;
  final int? selected;
  final Set<int> targets;
  final ChessMove? lastMove;
  final List<_Ring> rings;

  _BoardPainter({
    required this.proj,
    required this.state,
    required this.flipped,
    required this.selected,
    required this.targets,
    required this.lastMove,
    required this.rings,
  });

  int _dr(int sq) => flipped ? 7 - sq ~/ 8 : sq ~/ 8;
  int _dc(int sq) => flipped ? 7 - sq % 8 : sq % 8;

  @override
  void paint(Canvas canvas, Size size) {
    // Marco con grosor
    final frame = _quad(proj, -0.45, -0.45, 8.9);
    final thick = proj.scaleAt(8.45) * 0.45;
    canvas.drawPath(frame.shift(Offset(0, thick)),
        Paint()..color = const Color(0xFF3B2412));
    canvas.drawPath(frame, Paint()..color = const Color(0xFF6B4423));

    final light = Paint()..color = const Color(0xFFEBD9B4);
    final dark = Paint()..color = const Color(0xFFA9763F);
    for (var r = 0; r < 8; r++) {
      for (var c = 0; c < 8; c++) {
        canvas.drawPath(
            _quad(proj, c.toDouble(), r.toDouble(), 1), (r + c) % 2 == 0 ? light : dark);
      }
    }

    void overlay(int sq, Color color) {
      canvas.drawPath(
          _quad(proj, _dc(sq).toDouble(), _dr(sq).toDouble(), 1), Paint()..color = color);
    }

    if (lastMove != null) {
      overlay(lastMove!.from, const Color(0x55FFE000));
      overlay(lastMove!.to, const Color(0x66FFE000));
    }
    // Rey en jaque
    for (final white in const [true, false]) {
      if (state.inCheck(white)) {
        final k = state.kingSquare(white);
        if (k >= 0) overlay(k, const Color(0x99FF0000));
      }
    }
    if (selected != null) overlay(selected!, const Color(0x8800BFFF));

    // Anillos de las piezas (distinguen a cada bando)
    for (final r in rings) {
      final rect = Rect.fromCenter(center: r.c, width: r.rx * 2, height: r.ry * 2);
      canvas.drawOval(
          rect, Paint()..color = r.white ? const Color(0xF2FFFFFF) : const Color(0xF2151515));
      canvas.drawOval(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = r.white ? const Color(0xFFFFC107) : const Color(0xFFB0BEC5));
    }

    // Destinos posibles
    for (final sq in targets) {
      final cc = Offset(_dc(sq) + 0.5, _dr(sq) + 0.5);
      final p = proj.project(cc.dx, cc.dy);
      final s = proj.scaleAt(cc.dy);
      final capture = state.b[sq] != 0 ||
          (state.ep == sq && selected != null && state.b[selected!].abs() == pPawn);
      final rect =
          Rect.fromCenter(center: p, width: s * 0.5, height: s * 0.5 * proj.cosT);
      if (capture) {
        canvas.drawOval(
            Rect.fromCenter(center: p, width: s * 0.9, height: s * 0.9 * proj.cosT),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4
              ..color = const Color(0xCCE53935));
      } else {
        canvas.drawOval(rect, Paint()..color = const Color(0x9943A047));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
