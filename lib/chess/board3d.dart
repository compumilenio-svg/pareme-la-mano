import 'dart:math';
import 'package:flutter/material.dart';
import 'countries.dart';
import 'engine.dart';

class FightInfo {
  final int from, to, defSq;
  final int attacker, defender; // piezas con signo
  const FightInfo(this.from, this.to, this.defSq, this.attacker, this.defender);
}

/// Proyección en perspectiva del tablero (inclinado, con zoom, giro y desplazamiento).
class Proj {
  static const double D = 11.0;
  static const double th = 0.95;
  late final double sinT = sin(th);
  late final double cosT = cos(th);
  late final double F;
  late final double cx;
  late final double cy;
  late final double sinY;
  late final double cosY;

  Proj(double w, double h,
      {double zoom = 1, double yaw = 0, Offset pan = Offset.zero}) {
    final zNear = D - 4.4 * sinT;
    final f1 = (w / 2 * 0.97) * zNear / 4.4;
    final zf = D + 3.5 * sinT;
    final zFrame = D + 4.4 * sinT;
    final top1 = min(-4.4 * cosT / zFrame, -3.5 * cosT / zf - 1.8 / zf);
    final bottom1 = 4.4 * cosT / zNear + 0.5 / zNear;
    final total1 = bottom1 - top1;
    F = min(f1, h / total1) * zoom;
    cx = w / 2 + pan.dx;
    cy = (h - min(f1, h / total1) * total1) / 2 -
        min(f1, h / total1) * top1 +
        pan.dy;
    sinY = sin(yaw);
    cosY = cos(yaw);
  }

  // Profundidad (hacia el jugador = mayor) tras girar la vista.
  double depth(double x, double y) =>
      (x - 4) * sinY + (y - 4) * cosY;

  double scaleAt(double x, double y) => F / (D - depth(x, y) * sinT);

  Offset project(double x, double y) {
    final u = x - 4, v = y - 4;
    final ru = u * cosY - v * sinY;
    final rv = u * sinY + v * cosY;
    final z = D - rv * sinT;
    return Offset(cx + ru * F / z, cy + rv * cosT * F / z);
  }
}

const double _cellsPerPx = 1.2 / 300;

class _BoardView extends StatelessWidget {
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
  final double zoom, yaw;
  final Offset pan;

  const _BoardView({
    super.key,
    required this.state,
    required this.flipped,
    required this.whiteCountry,
    required this.blackCountry,
    required this.onTap,
    required this.zoom,
    required this.yaw,
    required this.pan,
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
      final proj = Proj(c.maxWidth, c.maxHeight, zoom: zoom, yaw: yaw, pan: pan);
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
        pieceWidgets.add(MapEntry(proj.depth(cc.dx, cc.dy), _pieceWidget(proj, v, cc, 1, 1, 0)));
      }

      // Pelea: cada uno saca su espada, dos choques y cae el comido.
      // La torre, en cambio, salta y le cae encima.
      Widget? fx;
      if (fight != null) {
        final f = fight!;
        final t = fightT.clamp(0.0, 1.0);
        final isRook = f.attacker.abs() == pRook;
        final rookDef = f.defender.abs() == pRook;
        // La torre no usa espada: si participa, no hay choques de espadas.
        final hasClash = !isRook && !rookDef;
        final go = isRook ? 0.25 : (hasClash ? 0.62 : 0.38);
        final jEnd = go + 0.16;
        final a0 = _center(f.from);
        final tt = _center(f.to);
        final dd = _center(f.defSq);
        Offset lerp(Offset a, Offset b, double u) =>
            Offset(a.dx + (b.dx - a.dx) * u, a.dy + (b.dy - a.dy) * u);
        final near = lerp(a0, tt, 0.70);

        // Fase de choques de espadas (t entre 0.28 y 0.62)
        final inClash = hasClash && t >= 0.28 && t < 0.62;
        final k = inClash ? (t - 0.28) / 0.34 : 0.0;
        final swing = inClash ? sin(k * 2 * pi).abs() : 0.0;
        final sparkI = inClash ? max(0.0, (swing - 0.8) / 0.2) : 0.0;
        final shake = sparkI * 0.05 * sin(t * 140);

        // Posición y salto del atacante
        Offset aPos;
        double aLift = 0;
        if (t < 0.15) {
          aPos = lerp(a0, near, Curves.easeOut.transform(t / 0.15));
        } else if (t < go) {
          aPos = near;
        } else if (isRook) {
          if (t < jEnd) {
            final u = (t - go) / 0.16;
            aPos = lerp(near, tt, Curves.easeIn.transform(u));
            aLift = sin(u * pi) * 1.7;
          } else {
            aPos = tt;
          }
        } else {
          final u = ((t - go) / (1 - go)).clamp(0.0, 1.0);
          aPos = lerp(near, tt, Curves.easeOut.transform(u));
        }
        final aDraw = Offset(aPos.dx + shake, aPos.dy);

        // Caída del defensor
        final deathStart = isRook ? jEnd - 0.02 : go + 0.06;
        var dDraw = dd;
        double dOpacity = 1, dScale = 1, dLift = 0, dSquash = 1;
        if (inClash) dDraw = Offset(dd.dx - shake, dd.dy);
        if (t >= deathStart) {
          final u = ((t - deathStart) / (1 - deathStart)).clamp(0.0, 1.0);
          if (isRook) {
            dSquash = 1 - 0.8 * min(1.0, u * 3);
            dScale = 1 + 0.15 * min(1.0, u * 3);
            dOpacity = 1 - max(0.0, (u - 0.3) / 0.7);
          } else {
            dOpacity = 1 - u;
            dScale = 1 + 0.25 * u;
            dLift = u * 1.2;
          }
        }
        rings.add(_ring(proj, aPos, f.attacker > 0));
        if (t < deathStart) rings.add(_ring(proj, dd, f.defender > 0));
        pieceWidgets.add(MapEntry(
            proj.depth(dd.dx, dd.dy),
            _pieceWidget(proj, f.defender, dDraw, dOpacity, dScale, dLift,
                squash: dSquash)));
        pieceWidgets.add(MapEntry(proj.depth(aDraw.dx, aDraw.dy) + 0.001,
            _pieceWidget(proj, f.attacker, aDraw, 1, 1, aLift)));

        final children = <Widget>[];

        // Espadas
        final pa = proj.project(aDraw.dx, aDraw.dy);
        final pd = proj.project(dDraw.dx, dDraw.dy);
        final sA = proj.scaleAt(aDraw.dx, aDraw.dy);
        final sD = proj.scaleAt(dDraw.dx, dDraw.dy);
        final sideA = pd.dx >= pa.dx ? 1.0 : -1.0;
        final draw = ((t - 0.15) / 0.13).clamp(0.0, 1.0);
        if (t > 0.15) {
          double theta(bool attacker) {
            if (inClash) return -0.3 + 1.2 * swing;
            if (attacker && !isRook && t >= go && t < go + 0.1) return 1.4;
            return -0.6;
          }

          double aAlpha = draw, dAlpha = draw;
          if (isRook) {
            aAlpha = 0;
          } else if (t > 0.85) {
            aAlpha = draw * (1 - (t - 0.85) / 0.1).clamp(0.0, 1.0);
          }
          if (rookDef) dAlpha = 0;
          if (t >= deathStart) {
            dAlpha = draw * (1 - (t - deathStart) / 0.08).clamp(0.0, 1.0);
          }
          final swords = <_SwordSpec>[
            _SwordSpec(Offset(pa.dx + sideA * 0.22 * sA, pa.dy - 0.55 * sA - aLift * sA),
                sideA, theta(true), sA * 0.95 * (0.4 + 0.6 * draw), aAlpha, true),
            _SwordSpec(Offset(pd.dx - sideA * 0.22 * sD, pd.dy - 0.55 * sD),
                -sideA, theta(false), sD * 0.95 * (0.4 + 0.6 * draw), dAlpha, false),
          ];
          // Chispas del choque o del golpe final
          Offset? spark;
          double sparkPower = 0;
          if (sparkI > 0) {
            spark = Offset((pa.dx + pd.dx) / 2, (pa.dy + pd.dy) / 2 - 0.75 * sA);
            sparkPower = sparkI;
          } else if (!isRook && t >= go && t < go + 0.1) {
            spark = Offset(pd.dx, pd.dy - 0.6 * sD);
            sparkPower = (1 - (t - (go + 0.04)).abs() / 0.04).clamp(0.0, 1.0);
          }
          children.add(Positioned.fill(
            child: CustomPaint(
              painter: _SwordFxPainter(swords, spark, sparkPower, sA),
            ),
          ));
        }

        // Polvo / humo del que cae
        if (t >= deathStart) {
          final u = (t - deathStart) / (1 - deathStart);
          final p = proj.project(dd.dx, dd.dy);
          final s = proj.scaleAt(dd.dx, dd.dy);
          for (var i = 0; i < 7; i++) {
            final ang = i * 0.9;
            final dx = cos(ang) * s * (isRook ? 0.6 : 0.35) * (0.4 + u);
            final dy = isRook
                ? -u * s * 0.25 * (1 + 0.2 * i) - 0.05 * s
                : -u * s * (0.8 + 0.15 * i) - 0.2 * s;
            final r = s * (0.12 + 0.1 * u + 0.02 * i);
            children.add(Positioned(
              left: p.dx + dx - r,
              top: p.dy + dy - r,
              child: Container(
                width: r * 2,
                height: r * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (isRook ? const Color(0xFFBCAAA4) : Colors.white)
                      .withOpacity((1 - u) * 0.55),
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
        onTapUp: (d) {
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
    final s = proj.scaleAt(boardPos.dx, boardPos.dy);
    return _Ring(p, s * 0.40, s * 0.40 * proj.cosT * 0.9, white);
  }

  Widget _pieceWidget(Proj proj, int piece, Offset boardPos, double opacity,
      double scale, double lift,
      {double squash = 1}) {
    final country = _country(piece);
    final type = piece.abs();
    final size = country.size(type);
    final p = proj.project(boardPos.dx, boardPos.dy);
    final s = proj.scaleAt(boardPos.dx, boardPos.dy);
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
            scaleX: scale,
            scaleY: scale * squash,
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
    var thick = 0.0;
    for (final p in const [Offset(-0.45, -0.45), Offset(8.45, -0.45), Offset(8.45, 8.45), Offset(-0.45, 8.45)]) {
      thick = max(thick, proj.scaleAt(p.dx, p.dy) * 0.45);
    }
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
      final s = proj.scaleAt(cc.dx, cc.dy);
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


/// Tablero 3D con zoom (pellizco o botones), giro de la vista (dos dedos o
/// botones) y desplazamiento (arrastrar).
class Board3D extends StatefulWidget {
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

  @override
  State<Board3D> createState() => _Board3DState();
}

class _Board3DState extends State<Board3D> {
  double zoom = 1.25;
  double yaw = 0;
  Offset pan = Offset.zero;
  double _z0 = 1, _y0 = 0;
  Offset _p0 = Offset.zero, _f0 = Offset.zero;

  void _reset() => setState(() {
        zoom = 1.25;
        yaw = 0;
        pan = Offset.zero;
      });

  Widget _btn(IconData icon, String tip, VoidCallback f) => IconButton(
        icon: Icon(icon, color: Colors.white),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: f,
      );

  @override
  Widget build(BuildContext context) {
    final w = widget;
    return ClipRect(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onScaleStart: (d) {
                _z0 = zoom;
                _y0 = yaw;
                _p0 = pan;
                _f0 = d.focalPoint;
              },
              onScaleUpdate: (d) {
                setState(() {
                  zoom = (_z0 * d.scale).clamp(0.6, 3.5);
                  yaw = _y0 + d.rotation;
                  final np = _p0 + (d.focalPoint - _f0);
                  pan = Offset(np.dx.clamp(-700.0, 700.0), np.dy.clamp(-900.0, 900.0));
                });
              },
              child: _BoardView(
                state: w.state,
                flipped: w.flipped,
                whiteCountry: w.whiteCountry,
                blackCountry: w.blackCountry,
                selected: w.selected,
                targets: w.targets,
                lastMove: w.lastMove,
                fight: w.fight,
                fightT: w.fightT,
                onTap: w.onTap,
                zoom: zoom,
                yaw: yaw,
                pan: pan,
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 4,
            child: Center(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _btn(Icons.zoom_out, 'Alejar',
                        () => setState(() => zoom = (zoom / 1.2).clamp(0.6, 3.5))),
                    _btn(Icons.zoom_in, 'Acercar',
                        () => setState(() => zoom = (zoom * 1.2).clamp(0.6, 3.5))),
                    _btn(Icons.rotate_left, 'Girar a la izquierda',
                        () => setState(() => yaw -= pi / 8)),
                    _btn(Icons.rotate_right, 'Girar a la derecha',
                        () => setState(() => yaw += pi / 8)),
                    _btn(Icons.center_focus_strong, 'Restablecer vista', _reset),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SwordSpec {
  final Offset pivot;
  final double side; // +1 apunta a la derecha, -1 a la izquierda
  final double theta; // 0 = vertical, + inclina hacia el rival
  final double len;
  final double alpha;
  final bool attacker;
  const _SwordSpec(
      this.pivot, this.side, this.theta, this.len, this.alpha, this.attacker);
}

class _SwordFxPainter extends CustomPainter {
  final List<_SwordSpec> swords;
  final Offset? spark;
  final double sparkPower;
  final double s;
  _SwordFxPainter(this.swords, this.spark, this.sparkPower, this.s);

  @override
  void paint(Canvas canvas, Size size) {
    for (final w in swords) {
      if (w.alpha <= 0.01) continue;
      final dir = Offset(w.side * sin(w.theta), -cos(w.theta));
      final perp = Offset(-dir.dy, dir.dx);
      final l = w.len;
      final hilt = w.pivot;
      final guard = hilt + dir * (l * 0.14);
      final tip = hilt + dir * l;
      final a = w.alpha.clamp(0.0, 1.0);
      final grip = Paint()
        ..color = const Color(0xFF5D4037).withOpacity(a)
        ..strokeWidth = l * 0.09
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(hilt, guard, grip);
      canvas.drawLine(
          guard - perp * (l * 0.12),
          guard + perp * (l * 0.12),
          Paint()
            ..color = const Color(0xFFFFC107).withOpacity(a)
            ..strokeWidth = l * 0.07
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          guard,
          tip,
          Paint()
            ..color = const Color(0xFFCFD8DC).withOpacity(a)
            ..strokeWidth = l * 0.075
            ..strokeCap = StrokeCap.round);
      canvas.drawLine(
          guard + perp * (l * 0.01),
          tip,
          Paint()
            ..color = Colors.white.withOpacity(a * 0.9)
            ..strokeWidth = l * 0.025
            ..strokeCap = StrokeCap.round);
    }
    if (spark != null && sparkPower > 0.01) {
      final c = spark!;
      final r = s * (0.25 + 0.55 * sparkPower);
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              Colors.white.withOpacity(0.95 * sparkPower),
              const Color(0xFFFFEB3B).withOpacity(0.6 * sparkPower),
              const Color(0x00FF9800),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
      final ray = Paint()
        ..color = Colors.white.withOpacity(sparkPower)
        ..strokeWidth = max(1.5, s * 0.03)
        ..strokeCap = StrokeCap.round;
      for (var i = 0; i < 12; i++) {
        final ang = i * pi / 6 + 0.3;
        final d = Offset(cos(ang), sin(ang));
        canvas.drawLine(c + d * (r * 0.5), c + d * (r * (1.1 + 0.5 * (i % 3) / 2)), ray);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SwordFxPainter old) => true;
}
