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

/// Reverso de carta (para el reparto).
Widget playingCardBack() => Container(
      width: fxCardW,
      height: fxCardH,
      decoration: BoxDecoration(
        color: const Color(0xFF1E3A8A),
        border: Border.all(color: Colors.white, width: 3),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [
          BoxShadow(color: Colors.black38, blurRadius: 6, offset: Offset(2, 3)),
        ],
      ),
      alignment: Alignment.center,
      child: const Text('♠♥\n♦♣',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 18, height: 1.0)),
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
  final bool faceDown; // reparto: se ve el reverso
  final bool fadeOut; // se desvanece al llegar (cartas de otros jugadores)
  final int flyDuration;
  FxFlight({
    required this.id,
    required this.card,
    required this.from,
    required this.to,
    required this.ghosts,
    required this.pile,
    required this.hide,
    this.faceDown = false,
    this.fadeOut = false,
    this.flyDuration = flyMs,
  });

  static const int flyMs = 520;
  static const int holdMs = 320;
  static const int gatherMs = 520;
  int get totalMs =>
      pile == null ? flyDuration : flyDuration + holdMs + gatherMs;
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

  Widget _piece(Widget face, Offset center, double scale, double opacity, double angle) {
    return Positioned(
      left: center.dx - fxCardW / 2,
      top: center.dy - fxCardH / 2,
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0),
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(scale: scale, child: face),
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
        final u1 = Curves.easeOutCubic.transform((ms / f.flyDuration).clamp(0.0, 1.0));
        var center = _lerp(f.from.center, landing, u1);
        var scale = 1.0 + 0.18 * sin(pi * u1); // se "levanta" al volar
        var opacity = 1.0;
        var angle = 0.2 * sin(pi * u1);
        double g = 0; // avance del retiro 0..1
        if (f.pile != null) {
          final start = f.flyDuration + FxFlight.holdMs;
          if (ms > start) {
            g = Curves.easeInCubic.transform(((ms - start) / FxFlight.gatherMs).clamp(0.0, 1.0));
            center = _lerp(landing, f.pile!.center, g);
            scale = 1 - 0.45 * g;
            opacity = 1 - 0.7 * g;
            angle = 0.0;
          }
        }
        if (f.fadeOut) {
          final k = ((ms / f.flyDuration - 0.7) / 0.3).clamp(0.0, 1.0);
          opacity = 1 - 0.85 * k;
          scale *= 1 - 0.3 * k;
        }
        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (f.pile != null)
              for (final gh in f.ghosts)
                _piece(
                  playingCardFace(gh.card),
                  _lerp(gh.rect.center, f.pile!.center, g),
                  1 - 0.45 * g,
                  1 - 0.7 * g,
                  0,
                ),
            _piece(f.faceDown ? playingCardBack() : playingCardFace(f.card), center,
                scale, opacity, angle),
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
  int? _prevTotal;
  Set<int> _prevMyIds = {};
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
    var moveDelay = 0;
    if (_seenSeq == null || seq < _seenSeq!) {
      _seenSeq = seq;
    } else if (seq != _seenSeq) {
      _seenSeq = seq;
      _startFlight(g, mySeat, old);
      moveDelay = g.lastCap.isEmpty ? FxFlight.flyMs : 1400;
    }
    // Reparto: aparecen cartas nuevas en mi mano.
    final myIds = {for (final c in g.hands[mySeat]) c.id};
    final newIds = [
      for (final c in g.hands[mySeat])
        if (!_prevMyIds.contains(c.id)) c.id
    ];
    final first = _prevTotal == null;
    final deal = first ? (seq == 0 && newIds.length >= 3) : newIds.length >= 3;
    _prevTotal = g.hands.length;
    _prevMyIds = myIds;
    if (deal) _startDeal(g, mySeat, newIds, moveDelay);
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

  void _startDeal(CuarentaGame g, int mySeat, List<int> myNew, int delayMs) {
    _hidden.addAll(myNew);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final srcRaw = g.dealer == mySeat
          ? _rectOf(fxHandKey)
          : _rectOf(fxSeatKey(g.dealer));
      if (srcRaw == null) {
        setState(() => _hidden.removeAll(myNew));
        return;
      }
      final src = _asCard(srcRaw);
      var idx = 0;
      var mine = 0;
      for (var round = 0; round < 5; round++) {
        for (var k = 0; k < g.n; k++) {
          final seat = (g.dealer + 1 + k) % g.n;
          Rect? dest;
          PCard card;
          var hide = <int>{};
          if (seat == mySeat) {
            if (mine >= myNew.length) continue;
            final id = myNew[mine++];
            card = PCard.fromId(id);
            dest = _rectOf(fxCardKey(id));
            hide = {id};
          } else {
            card = PCard.fromId(1);
            final r = _rectOf(fxSeatKey(seat));
            dest = r == null ? null : _asCard(r);
          }
          final when = delayMs + idx * 95;
          idx++;
          final d = dest;
          if (d == null) {
            if (hide.isNotEmpty) {
              Future<void>.delayed(Duration(milliseconds: when), () {
                if (mounted) setState(() => _hidden.removeAll(hide));
              });
            }
            continue;
          }
          Future<void>.delayed(Duration(milliseconds: when), () {
            if (!mounted) return;
            Sfx.play('card_play');
            setState(() {
              _flights.add(FxFlight(
                id: _flightCounter++,
                card: card,
                from: src,
                to: d,
                ghosts: const [],
                pile: null,
                hide: hide,
                faceDown: true,
                fadeOut: seat != mySeat,
                flyDuration: 380,
              ));
            });
          });
        }
      }
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
