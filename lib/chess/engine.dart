// Motor de ajedrez en Dart puro (sin Flutter) para poder probarlo con perft.
// Tablero: 64 casillas, índice = fila*8 + columna. Fila 0 = fila 8 (arriba, negras),
// columna 0 = a. Piezas blancas positivas, negras negativas.
import 'dart:math';

const int pEmpty = 0, pPawn = 1, pKnight = 2, pBishop = 3, pRook = 4, pQueen = 5, pKing = 6;

class ChessMove {
  final int from, to;
  final int promo; // tipo de pieza (2..5) o 0
  final bool ep; // captura al paso
  final bool castle;
  const ChessMove(this.from, this.to,
      {this.promo = 0, this.ep = false, this.castle = false});

  @override
  bool operator ==(Object o) =>
      o is ChessMove && o.from == from && o.to == to && o.promo == promo;

  @override
  int get hashCode => from * 4096 + to * 8 + promo;

  @override
  String toString() => '${sqName(from)}${sqName(to)}${promo == 0 ? '' : 'nbrq'[promo - 2]}';
}

String sqName(int i) => '${'abcdefgh'[i % 8]}${8 - i ~/ 8}';

class ChessState {
  final List<int> b; // 64
  final bool whiteToMove;
  final int castling; // 1 K blanco, 2 Q blanco, 4 k negro, 8 q negro
  final int ep; // casilla de captura al paso o -1
  final int halfmove;
  final int fullmove;

  ChessState(this.b, this.whiteToMove, this.castling, this.ep, this.halfmove,
      this.fullmove);

  static const startFen =
      'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

  factory ChessState.start() => ChessState.fromFen(startFen);

  factory ChessState.fromFen(String fen) {
    final parts = fen.trim().split(RegExp(r'\s+'));
    final b = List<int>.filled(64, 0);
    var idx = 0;
    for (final ch in parts[0].split('')) {
      if (ch == '/') continue;
      final n = int.tryParse(ch);
      if (n != null) {
        idx += n;
        continue;
      }
      final lower = ch.toLowerCase();
      final t = 'pnbrqk'.indexOf(lower) + 1;
      b[idx++] = ch == lower ? -t : t;
    }
    final white = parts.length < 2 || parts[1] == 'w';
    var c = 0;
    final cs = parts.length > 2 ? parts[2] : '-';
    if (cs.contains('K')) c |= 1;
    if (cs.contains('Q')) c |= 2;
    if (cs.contains('k')) c |= 4;
    if (cs.contains('q')) c |= 8;
    var ep = -1;
    if (parts.length > 3 && parts[3] != '-') {
      final f = 'abcdefgh'.indexOf(parts[3][0]);
      final r = 8 - int.parse(parts[3][1]);
      ep = r * 8 + f;
    }
    final hm = parts.length > 4 ? int.parse(parts[4]) : 0;
    final fm = parts.length > 5 ? int.parse(parts[5]) : 1;
    return ChessState(b, white, c, ep, hm, fm);
  }

  String toFen() {
    final sb = StringBuffer();
    for (var r = 0; r < 8; r++) {
      var empty = 0;
      for (var f = 0; f < 8; f++) {
        final v = b[r * 8 + f];
        if (v == 0) {
          empty++;
        } else {
          if (empty > 0) {
            sb.write(empty);
            empty = 0;
          }
          final ch = 'pnbrqk'[v.abs() - 1];
          sb.write(v > 0 ? ch.toUpperCase() : ch);
        }
      }
      if (empty > 0) sb.write(empty);
      if (r < 7) sb.write('/');
    }
    final cs = StringBuffer();
    if (castling & 1 != 0) cs.write('K');
    if (castling & 2 != 0) cs.write('Q');
    if (castling & 4 != 0) cs.write('k');
    if (castling & 8 != 0) cs.write('q');
    return '$sb ${whiteToMove ? 'w' : 'b'} ${cs.isEmpty ? '-' : cs} '
        '${ep < 0 ? '-' : sqName(ep)} $halfmove $fullmove';
  }

  // ---------------- Ataques ----------------

  static const _knightD = [
    [-2, -1], [-2, 1], [-1, -2], [-1, 2], [1, -2], [1, 2], [2, -1], [2, 1]
  ];
  static const _kingD = [
    [-1, -1], [-1, 0], [-1, 1], [0, -1], [0, 1], [1, -1], [1, 0], [1, 1]
  ];
  static const _diag = [
    [-1, -1], [-1, 1], [1, -1], [1, 1]
  ];
  static const _orth = [
    [-1, 0], [1, 0], [0, -1], [0, 1]
  ];

  bool isAttacked(int sq, bool byWhite) {
    final r = sq ~/ 8, f = sq % 8;
    final s = byWhite ? 1 : -1;
    // peones: un peón blanco ataca hacia arriba (r-1), así que está en r+1
    final pr = byWhite ? r + 1 : r - 1;
    if (pr >= 0 && pr < 8) {
      for (final df in const [-1, 1]) {
        final pf = f + df;
        if (pf >= 0 && pf < 8 && b[pr * 8 + pf] == s * pPawn) return true;
      }
    }
    for (final d in _knightD) {
      final rr = r + d[0], ff = f + d[1];
      if (rr >= 0 && rr < 8 && ff >= 0 && ff < 8 && b[rr * 8 + ff] == s * pKnight) {
        return true;
      }
    }
    for (final d in _kingD) {
      final rr = r + d[0], ff = f + d[1];
      if (rr >= 0 && rr < 8 && ff >= 0 && ff < 8 && b[rr * 8 + ff] == s * pKing) {
        return true;
      }
    }
    for (final d in _diag) {
      var rr = r + d[0], ff = f + d[1];
      while (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
        final v = b[rr * 8 + ff];
        if (v != 0) {
          if (v == s * pBishop || v == s * pQueen) return true;
          break;
        }
        rr += d[0];
        ff += d[1];
      }
    }
    for (final d in _orth) {
      var rr = r + d[0], ff = f + d[1];
      while (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
        final v = b[rr * 8 + ff];
        if (v != 0) {
          if (v == s * pRook || v == s * pQueen) return true;
          break;
        }
        rr += d[0];
        ff += d[1];
      }
    }
    return false;
  }

  int kingSquare(bool white) {
    final k = white ? pKing : -pKing;
    for (var i = 0; i < 64; i++) {
      if (b[i] == k) return i;
    }
    return -1;
  }

  bool inCheck(bool white) {
    final k = kingSquare(white);
    return k >= 0 && isAttacked(k, !white);
  }

  // ---------------- Generación de jugadas ----------------

  List<ChessMove> _pseudo() {
    final out = <ChessMove>[];
    final white = whiteToMove;
    final s = white ? 1 : -1;
    for (var i = 0; i < 64; i++) {
      final v = b[i];
      if (v == 0 || (v > 0) != white) continue;
      final t = v.abs();
      final r = i ~/ 8, f = i % 8;
      switch (t) {
        case pPawn:
          final dir = white ? -1 : 1;
          final startR = white ? 6 : 1;
          final promoR = white ? 0 : 7;
          final r1 = r + dir;
          if (r1 < 0 || r1 > 7) break;
          void add(int to, {bool ep = false}) {
            if (to ~/ 8 == promoR) {
              for (final p in const [pQueen, pRook, pBishop, pKnight]) {
                out.add(ChessMove(i, to, promo: p));
              }
            } else {
              out.add(ChessMove(i, to, ep: ep));
            }
          }
          if (b[r1 * 8 + f] == 0) {
            add(r1 * 8 + f);
            if (r == startR && b[(r + 2 * dir) * 8 + f] == 0) {
              out.add(ChessMove(i, (r + 2 * dir) * 8 + f));
            }
          }
          for (final df in const [-1, 1]) {
            final ff = f + df;
            if (ff < 0 || ff > 7) continue;
            final to = r1 * 8 + ff;
            final tv = b[to];
            if (tv != 0 && (tv > 0) != white) {
              add(to);
            } else if (tv == 0 && to == ep) {
              add(to, ep: true);
            }
          }
          break;
        case pKnight:
          for (final d in _knightD) {
            final rr = r + d[0], ff = f + d[1];
            if (rr < 0 || rr > 7 || ff < 0 || ff > 7) continue;
            final tv = b[rr * 8 + ff];
            if (tv == 0 || (tv > 0) != white) out.add(ChessMove(i, rr * 8 + ff));
          }
          break;
        case pBishop:
        case pRook:
        case pQueen:
          final dirs = <List<int>>[
            if (t != pRook) ..._diag,
            if (t != pBishop) ..._orth,
          ];
          for (final d in dirs) {
            var rr = r + d[0], ff = f + d[1];
            while (rr >= 0 && rr < 8 && ff >= 0 && ff < 8) {
              final tv = b[rr * 8 + ff];
              if (tv == 0) {
                out.add(ChessMove(i, rr * 8 + ff));
              } else {
                if ((tv > 0) != white) out.add(ChessMove(i, rr * 8 + ff));
                break;
              }
              rr += d[0];
              ff += d[1];
            }
          }
          break;
        case pKing:
          for (final d in _kingD) {
            final rr = r + d[0], ff = f + d[1];
            if (rr < 0 || rr > 7 || ff < 0 || ff > 7) continue;
            final tv = b[rr * 8 + ff];
            if (tv == 0 || (tv > 0) != white) out.add(ChessMove(i, rr * 8 + ff));
          }
          // Enroque
          final home = white ? 60 : 4;
          if (i == home && !isAttacked(home, !white)) {
            final kBit = white ? 1 : 4, qBit = white ? 2 : 8;
            if (castling & kBit != 0 &&
                b[home + 1] == 0 &&
                b[home + 2] == 0 &&
                b[home + 3] == s * pRook &&
                !isAttacked(home + 1, !white) &&
                !isAttacked(home + 2, !white)) {
              out.add(ChessMove(home, home + 2, castle: true));
            }
            if (castling & qBit != 0 &&
                b[home - 1] == 0 &&
                b[home - 2] == 0 &&
                b[home - 3] == 0 &&
                b[home - 4] == s * pRook &&
                !isAttacked(home - 1, !white) &&
                !isAttacked(home - 2, !white)) {
              out.add(ChessMove(home, home - 2, castle: true));
            }
          }
          break;
      }
    }
    return out;
  }

  ChessState apply(ChessMove m) {
    final nb = List<int>.from(b);
    final piece = nb[m.from];
    final captured = nb[m.to];
    final white = piece > 0;
    var c = castling;
    var newEp = -1;
    nb[m.from] = 0;
    if (m.ep) {
      nb[(m.from ~/ 8) * 8 + m.to % 8] = 0;
    }
    if (m.castle) {
      if (m.to > m.from) {
        nb[m.from + 3] = 0;
        nb[m.from + 1] = white ? pRook : -pRook;
      } else {
        nb[m.from - 4] = 0;
        nb[m.from - 1] = white ? pRook : -pRook;
      }
    }
    nb[m.to] = m.promo != 0 ? (white ? m.promo : -m.promo) : piece;
    if (piece.abs() == pPawn && (m.to - m.from).abs() == 16) {
      newEp = (m.from + m.to) ~/ 2;
    }
    if (piece == pKing) c &= ~3;
    if (piece == -pKing) c &= ~12;
    if (m.from == 63 || m.to == 63) c &= ~1;
    if (m.from == 56 || m.to == 56) c &= ~2;
    if (m.from == 7 || m.to == 7) c &= ~4;
    if (m.from == 0 || m.to == 0) c &= ~8;
    final reset = piece.abs() == pPawn || captured != 0 || m.ep;
    return ChessState(nb, !whiteToMove, c, newEp, reset ? 0 : halfmove + 1,
        whiteToMove ? fullmove : fullmove + 1);
  }

  List<ChessMove> legalMoves() {
    final res = <ChessMove>[];
    for (final m in _pseudo()) {
      final n = apply(m);
      if (!n.inCheck(whiteToMove)) res.add(m);
    }
    return res;
  }

  /// Devuelve la jugada legal que coincide con from/to/promo, o null.
  ChessMove? find(int from, int to, [int promo = 0]) {
    for (final m in legalMoves()) {
      if (m.from == from && m.to == to && m.promo == promo) return m;
    }
    return null;
  }

  /// 'ongoing', 'checkmate' (pierde quien mueve), 'stalemate', 'fifty', 'material'.
  String status() {
    if (legalMoves().isEmpty) {
      return inCheck(whiteToMove) ? 'checkmate' : 'stalemate';
    }
    if (halfmove >= 100) return 'fifty';
    var minors = 0;
    for (final v in b) {
      final t = v.abs();
      if (t == pPawn || t == pRook || t == pQueen) return 'ongoing';
      if (t == pKnight || t == pBishop) minors++;
    }
    if (minors <= 1) return 'material';
    return 'ongoing';
  }

  int perft(int depth) {
    if (depth == 0) return 1;
    var n = 0;
    for (final m in legalMoves()) {
      n += depth == 1 ? 1 : apply(m).perft(depth - 1);
    }
    return n;
  }
}

// ---------------------------------------------------------------
// Computadora rival
// ---------------------------------------------------------------

const _values = [0, 100, 320, 330, 500, 900, 0];

int _evaluate(ChessState s) {
  // Puntaje desde el punto de vista de las blancas.
  var score = 0;
  for (var i = 0; i < 64; i++) {
    final v = s.b[i];
    if (v == 0) continue;
    final t = v.abs();
    final r = i ~/ 8, f = i % 8;
    var val = _values[t];
    final cr = 3.5 - (r - 3.5).abs(); // cercanía al centro (filas)
    final cf = 3.5 - (f - 3.5).abs();
    final center = ((cr + cf) * 4).round();
    if (t == pPawn) {
      final adv = v > 0 ? (6 - r) : (r - 1); // avance
      val += adv * 6 + center ~/ 2;
    } else if (t == pKnight || t == pBishop) {
      val += center * 2;
    } else if (t == pQueen) {
      val += center;
    } else if (t == pKing) {
      // Rey: mejor en las esquinas/atrás durante el medio juego
      final back = v > 0 ? r : 7 - r;
      val += back * 8 - center * 2;
    }
    score += v > 0 ? val : -val;
  }
  return score;
}

int _orderScore(ChessState s, ChessMove m) {
  var sc = 0;
  final target = s.b[m.to].abs();
  if (target != 0) sc += 10 * _values[target] - _values[s.b[m.from].abs()] ~/ 10;
  if (m.ep) sc += 900;
  if (m.promo != 0) sc += _values[m.promo];
  return sc;
}

int _negamax(ChessState s, int depth, int alpha, int beta, int ply) {
  final moves = s.legalMoves();
  if (moves.isEmpty) {
    return s.inCheck(s.whiteToMove) ? -(100000 - ply) : 0;
  }
  if (depth == 0) {
    final e = _evaluate(s);
    return s.whiteToMove ? e : -e;
  }
  moves.sort((a, b) => _orderScore(s, b).compareTo(_orderScore(s, a)));
  var best = -1000000;
  for (final m in moves) {
    final v = -_negamax(s.apply(m), depth - 1, -beta, -alpha, ply + 1);
    if (v > best) best = v;
    if (best > alpha) alpha = best;
    if (alpha >= beta) break;
  }
  return best;
}

/// Elige una jugada. level: 1 fácil, 2 medio, 3 difícil.
ChessMove? chooseAiMove(ChessState s, int level, [int? seed]) {
  final moves = s.legalMoves();
  if (moves.isEmpty) return null;
  final rng = Random(seed);
  final depth = level <= 1 ? 1 : (level == 2 ? 2 : 3);
  moves.sort((a, b) => _orderScore(s, b).compareTo(_orderScore(s, a)));
  final scored = <MapEntry<ChessMove, int>>[];
  var alpha = -1000000;
  for (final m in moves) {
    // En fácil se evalúa cada jugada con ventana completa para poder elegir "casi mejores".
    final v = -_negamax(s.apply(m), depth - 1, -1000000, level <= 1 ? 1000000 : -alpha, 1);
    scored.add(MapEntry(m, v));
    if (v > alpha) alpha = v;
  }
  scored.sort((a, b) => b.value.compareTo(a.value));
  final best = scored.first.value;
  if (level <= 1) {
    // Fácil: elige entre jugadas razonables con cierto azar (y a veces cualquiera).
    if (rng.nextInt(100) < 25) return moves[rng.nextInt(moves.length)];
    final near = scored.where((e) => e.value >= best - 120).toList();
    return near[rng.nextInt(near.length)].key;
  }
  final top = scored.where((e) => e.value >= best - (level == 2 ? 15 : 0)).toList();
  return top[rng.nextInt(top.length)].key;
}

/// Para usar con `compute`: [fen, level, seed] -> [from, to, promo] o [].
List<int> aiMoveIsolate(List<Object> args) {
  final s = ChessState.fromFen(args[0] as String);
  final m = chooseAiMove(s, args[1] as int, args[2] as int);
  return m == null ? <int>[] : [m.from, m.to, m.promo];
}
