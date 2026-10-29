import 'dart:math';

/// Parchís de 4 colores (reglas simplificadas del parchís español):
/// - Se sale de la casa con un 5.
/// - Un 6 da otra tirada; tres 6 seguidos mandan la última ficha a casa.
/// - Comer una ficha rival da 20 casillas extra; llegar a la meta da 10.
/// - En los seguros no se come. Dos fichas rivales juntas en una casilla
///   normal forman un bloqueo y no se puede caer ahí.
/// - Hay que sacar el número exacto para entrar a la meta.
const int kPieces = 4;
const int kGoal = 72; // 64 casillas del circuito + 7 del pasillo + meta
const int kCircuit = 68;
const List<String> kColorNames = ['Amarillo', 'Azul', 'Rojo', 'Verde'];

/// Casilla del circuito (0..67) donde sale cada color.
int startIndex(int color) => 17 * color + 13;

/// Casilla del circuito por la que pasa una ficha del [color] en el paso [r] (1..64).
int circuitIndexOf(int color, int r) => (startIndex(color) + r - 1) % kCircuit;

bool isSafeIndex(int i) {
  final j = i % 17;
  return j == 4 || j == 8 || j == 13;
}

int _i(Object? v) => (v as num).toInt();

class ParchisGame {
  List<int> active; // colores en juego, ordenados
  List<int> pos = List<int>.filled(16, 0); // paso de cada ficha: 0 = en casa
  int turn;
  String phase = 'roll'; // roll | move | over
  int die = 0;
  int sixes = 0;
  bool extra = false;
  int bonus = 0;
  int lastMoved = -1;
  int seq = 0;
  int winner = -1;
  List<Map<String, dynamic>> events = [];

  ParchisGame(List<int> activeColors)
      : active = ([...activeColors]..sort()),
        turn = ([...activeColors]..sort()).first;

  Map<String, dynamic> toMap() => {
        'active': active,
        'pos': pos,
        'turn': turn,
        'phase': phase,
        'die': die,
        'sixes': sixes,
        'extra': extra,
        'bonus': bonus,
        'last': lastMoved,
        'seq': seq,
        'winner': winner,
        'ev': events,
      };

  factory ParchisGame.fromMap(Map<String, dynamic> m) {
    final g = ParchisGame([for (final c in (m['active'] as List)) _i(c)]);
    g.pos = [for (final p in (m['pos'] as List)) _i(p)];
    g.turn = _i(m['turn']);
    g.phase = m['phase'] as String;
    g.die = _i(m['die']);
    g.sixes = _i(m['sixes']);
    g.extra = m['extra'] == true;
    g.bonus = _i(m['bonus']);
    g.lastMoved = _i(m['last']);
    g.seq = _i(m['seq']);
    g.winner = _i(m['winner']);
    g.events = [
      for (final e in (m['ev'] as List? ?? const []))
        Map<String, dynamic>.from(e as Map)
    ];
    return g;
  }

  /// Fichas (índice global 0..15) en una casilla del circuito.
  List<int> tokensAt(int circuitIdx, {int? exceptColor}) {
    final res = <int>[];
    for (var gi = 0; gi < 16; gi++) {
      final c = gi ~/ 4;
      if (!active.contains(c)) continue;
      if (exceptColor != null && c == exceptColor) continue;
      final r = pos[gi];
      if (r >= 1 && r <= 64 && circuitIndexOf(c, r) == circuitIdx) res.add(gi);
    }
    return res;
  }

  /// Paso final si la ficha [p] (0..3) del jugador de turno avanza [steps]; null si no puede.
  int? destination(int p, int steps) {
    final gi = turn * 4 + p;
    final r = pos[gi];
    if (r == 0) return steps == 5 ? 1 : null;
    if (r >= kGoal) return null;
    final t = r + steps;
    if (t > kGoal) return null;
    if (t <= 64) {
      final idx = circuitIndexOf(turn, t);
      final others = tokensAt(idx, exceptColor: turn);
      if (others.length >= 2 && !isSafeIndex(idx)) return null;
    }
    return t;
  }

  List<int> legalMoves() {
    if (phase != 'move') return const [];
    return [
      for (var p = 0; p < kPieces; p++)
        if (destination(p, die) != null) p
    ];
  }

  void _pass() {
    final i = active.indexOf(turn);
    turn = active[(i + 1) % active.length];
    phase = 'roll';
    die = 0;
    sixes = 0;
    extra = false;
    bonus = 0;
  }

  void _afterMove() {
    if (winner >= 0) {
      phase = 'over';
      return;
    }
    if (extra) {
      phase = 'roll';
      die = 0;
      bonus = 0;
      return;
    }
    _pass();
  }

  void roll(int d) {
    if (phase != 'roll') return;
    events = [];
    seq++;
    die = d;
    bonus = 0;
    events.add({'t': 'roll', 'd': d, 'c': turn});
    if (d == 6) {
      sixes++;
    } else {
      sixes = 0;
    }
    if (sixes >= 3) {
      events.add({'t': 'sixes'});
      if (lastMoved >= 0 && lastMoved ~/ 4 == turn) {
        final r = pos[lastMoved];
        if (r >= 1 && r < kGoal) {
          events.add({'t': 'nest', 'p': lastMoved, 'from': r});
          pos[lastMoved] = 0;
        }
      }
      _pass();
      return;
    }
    extra = d == 6;
    phase = 'move';
    if (legalMoves().isEmpty) {
      events.add({'t': 'nomove'});
      _afterMove();
    }
  }

  void move(int p) {
    if (phase != 'move') return;
    final to = destination(p, die);
    if (to == null) return;
    events = [];
    seq++;
    final gi = turn * 4 + p;
    final from = pos[gi];
    pos[gi] = to;
    lastMoved = gi;
    events.add({'t': 'move', 'p': gi, 'from': from, 'to': to});
    var newBonus = 0;
    if (to >= 1 && to <= 64) {
      final idx = circuitIndexOf(turn, to);
      final others = tokensAt(idx, exceptColor: turn);
      if (others.isNotEmpty && (!isSafeIndex(idx) || from == 0)) {
        final v = others.first;
        events.add({'t': 'capture', 'a': gi, 'v': v, 'to': to, 'vf': pos[v]});
        pos[v] = 0;
        newBonus = 20;
      }
    }
    if (to == kGoal) {
      events.add({'t': 'goal', 'p': gi});
      newBonus = 10;
    }
    var all = true;
    for (var k = 0; k < kPieces; k++) {
      if (pos[turn * 4 + k] != kGoal) all = false;
    }
    if (all) {
      winner = turn;
      events.add({'t': 'win', 'c': turn});
      phase = 'over';
      return;
    }
    if (newBonus > 0) {
      die = newBonus;
      bonus = newBonus;
      phase = 'move';
      if (legalMoves().isEmpty) {
        events.add({'t': 'nomove'});
        bonus = 0;
        _afterMove();
      }
      return;
    }
    bonus = 0;
    _afterMove();
  }

  /// Elección sencilla del bot: comer > meta > salir > seguro > avanzar.
  int botPick(Random rnd) {
    final legal = legalMoves();
    var best = legal.first;
    var bestScore = -1e9;
    for (final p in legal) {
      final gi = turn * 4 + p;
      final r = pos[gi];
      final to = destination(p, die)!;
      var s = rnd.nextDouble() * 5;
      if (to == kGoal) s += 80;
      if (r == 0) s += 55;
      if (to >= 1 && to <= 64) {
        final idx = circuitIndexOf(turn, to);
        final others = tokensAt(idx, exceptColor: turn);
        if (others.isNotEmpty && (!isSafeIndex(idx) || r == 0)) s += 100;
        if (isSafeIndex(idx)) s += 25;
        if (!isSafeIndex(idx)) {
          for (var back = 1; back <= 6; back++) {
            if (tokensAt((idx - back) % kCircuit, exceptColor: turn).isNotEmpty) {
              s -= 12;
              break;
            }
          }
        }
      }
      if (to > 64) s += 30;
      if (r >= 1 && r <= 64) {
        final cur = circuitIndexOf(turn, r);
        if (!isSafeIndex(cur)) {
          for (var back = 1; back <= 6; back++) {
            if (tokensAt((cur - back) % kCircuit, exceptColor: turn).isNotEmpty) {
              s += 15;
              break;
            }
          }
        }
      }
      s += to * 0.3;
      if (s > bestScore) {
        bestScore = s;
        best = p;
      }
    }
    return best;
  }
}
