import 'dart:math';
import 'package:flutter/material.dart';
import 'engine.dart';
import '../sfx.dart';

const double fxCardW = 54;
const double fxCardH = 78;

/// Cara de una carta (la misma que se ve en la mesa y en la mano).
Widget playingCardFace(PCard c) => Container(
      width: fxCardW,
      height: fxCardH,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black54),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(2, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        c.label,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.bold,
          color: c.isRed ? Colors.red : Colors.black,
        ),
      ),
    );

class FxGhost {
  final PCard card;
  final Rect rect;
  FxGhost(this.card, this.rect);
}

class FxFlight {
  final int id;
  final PCard card;
  final Rect from;
  final Rect to; // donde cae la carta jugada
  final List<FxGhost> ghosts; // cartas levantadas (ya no están en la mesa)
  final Rect? pile; // hacia dónde se retiran (null si solo se deja la carta)
  final Set<int> hide;
  FxFlight({
    required this.id,
    required this.card,
    required this.from,
    required this.to,
    required this.ghosts,
    required this.pile,
    required this.hide,
  });

  static const int flyMs = 520;
  static const int holdMs = 320;
  static const int gatherMs = 520;
  int get totalMs => pile == null ? flyMs : flyMs + holdMs + gatherMs;
}

class FxOverlay extends StatelessWidget {
  final List<FxFlight> flights;
  final void Function(FxFlight) onDone;
  const FxOverlay({super.key, required this.flights, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final f in flights)
            _FlightView(key: ValueKey(f.id), flight: f, onDone: onDone),
        ],
      ),
    );
  }
}

class _FlightView extends StatelessWidget {
  final FxFlight flight;
  final void Function(FxFlight) onDone;
  const _FlightView({super.key, required this.flight, required this.onDone});

  Offset _lerp(Offset a, Offset b, double u) =>
      Offset(a.dx + (b.dx - a.dx) * u, a.dy + (b.dy - a.dy) * u);

  Widget _piece(PCard c, Offset center, double scale, double opacity, double angle) {
    return Positioned(
      left: center.dx - fxCardW / 2,
      top: center.dy - fxCardH / 2,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: scale, child: playingCardFace(c)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final f = flight;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: f.totalMs),
      onEnd: () => onDone(f),
      builder: (context, t, _) {
        final ms = t * f.totalMs;
        final landing = f.pile == null
            ? f.to.center
            : f.to.center + const Offset(6, 6); // cae encima de la carta
        final u1 = Curves.easeOutCubic.transform((ms / FxFlight.flyMs).clamp(0.0, 1.0));
        var center = _lerp(f.from.center, landing, u1);
        var scale = 1.0 + 0.18 * sin(pi * u1); // se "levanta" al volar
        var opacity = 1.0;
        var angle = 0.2 * sin(pi * u1);
        double g = 0; // avance del retiro 0..1
        if (f.pile != null) {
          final start = FxFlight.flyMs + FxFlight.holdMs;
          if (ms > start) {
            g = Curves.easeInCubic.transform(((ms - start) / FxFlight.gatherMs).clamp(0.0, 1.0));
            center = _lerp(landing, f.pile!.center, g);
            scale = 1 - 0.45 * g;
            opacity = 1 - 0.7 * g;
            angle = 0.0;
          }
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (f.pile != null)
              for (final gh in f.ghosts)
                _piece(
                  gh.card,
                  _lerp(gh.rect.center, f.pile!.center, g),
                  1 - 0.45 * g,
                  1 - 0.7 * g,
                  0,
                ),
            _piece(f.card, center, scale, opacity, angle),
          ],
        );
      },
    );
  }
}

/// Animaciones de cartas: de la mano (o del rival) a la mesa, caídas encima de
/// la carta, y el retiro de lo levantado hacia el que lo levantó.
mixin CardFx<T extends StatefulWidget> on State<T> {
  final GlobalKey fxStackKey = GlobalKey();
  final GlobalKey fxHandKey = GlobalKey();
  final Map<int, GlobalKey> _cardKeys = {};
  final Map<int, GlobalKey> _seatKeys = {};
  final Map<int, Rect> _rects = {};
  final Set<int> _hidden = {};
  final List<FxFlight> _flights = [];
  int? _seenSeq;
  int _flightCounter = 0;

  GlobalKey fxCardKey(int id) => _cardKeys.putIfAbsent(id, () => GlobalKey());
  GlobalKey fxSeatKey(int seat) => _seatKeys.putIfAbsent(seat, () => GlobalKey());
  bool fxHidden(int id) => _hidden.contains(id);

  Rect? _rectOf(GlobalKey k) {
    final ctx = k.currentContext;
    final stack = fxStackKey.currentContext;
    if (ctx == null || stack == null) return null;
    final rb = ctx.findRenderObject();
    final sb = stack.findRenderObject();
    if (rb is! RenderBox || sb is! RenderBox) return null;
    if (!rb.attached || !rb.hasSize || !sb.attached) return null;
    final off = sb.globalToLocal(rb.localToGlobal(Offset.zero));
    return off & rb.size;
  }

  void _measure() {
    for (final e in _cardKeys.entries) {
      final r = _rectOf(e.value);
      if (r == null) {
        _rects.remove(e.key);
      } else {
        _rects[e.key] = r;
      }
    }
  }

  Rect _asCard(Rect r) => Rect.fromCenter(
      center: r.center, width: fxCardW, height: fxCardH);

  /// Llamar al inicio de cada build con la partida que se va a dibujar.
  void fxSync(CuarentaGame g, int mySeat) {
    final seq = g.moveSeq;
    final old = Map<int, Rect>.of(_rects);
    if (_seenSeq == null || seq < _seenSeq!) {
      _seenSeq = seq;
    } else if (seq != _seenSeq) {
      _seenSeq = seq;
      _startFlight(g, mySeat, old);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _measure();
    });
  }

  void _startFlight(CuarentaGame g, int mySeat, Map<int, Rect> old) {
    if (g.lastCard <= 0) return;
    final card = PCard.fromId(g.lastCard);
    final cap = [for (final i in g.lastCap) PCard.fromId(i)];
    final seat = g.lastSeat;
    final hide = <int>{};
    if (cap.isEmpty) {
      hide.add(card.id);
      _hidden.addAll(hide);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Rect? start;
      if (seat == mySeat) start = old[card.id];
      if (start == null) {
        final src = seat == mySeat
            ? _rectOf(fxHandKey)
            : _rectOf(fxSeatKey(seat));
        if (src != null) start = _asCard(src);
      }
      Rect? to;
      Rect? pile;
      final ghosts = <FxGhost>[];
      if (cap.isEmpty) {
        to = _rectOf(fxCardKey(card.id));
      } else {
        for (final c in cap) {
          final r = old[c.id];
          if (r != null) ghosts.add(FxGhost(c, r));
        }
        to = ghosts.isEmpty ? null : ghosts.first.rect;
        final p = seat == mySeat
            ? _rectOf(fxHandKey)
            : _rectOf(fxSeatKey(seat));
        if (p != null) pile = _asCard(p);
      }
      if (start == null || to == null || (cap.isNotEmpty && pile == null)) {
        setState(() => _hidden.removeAll(hide));
        return;
      }
      Sfx.play('card_play');
      Sfx.play(cap.isEmpty ? 'card_place' : (g.lastBonus ? 'bonus' : 'card_place'),
          delayMs: FxFlight.flyMs - 60);
      if (cap.isNotEmpty) {
        Sfx.play('capture', delayMs: FxFlight.flyMs + FxFlight.holdMs);
      }
      setState(() {
        _flights.add(FxFlight(
          id: _flightCounter++,
          card: card,
          from: start!,
          to: to!,
          ghosts: ghosts,
          pile: pile,
          hide: hide,
        ));
      });
    });
  }

  Widget fxOverlay() => FxOverlay(
        flights: _flights,
        onDone: (f) {
          if (!mounted) return;
          setState(() {
            _flights.remove(f);
            _hidden.removeAll(f.hide);
          });
        },
      );
}
