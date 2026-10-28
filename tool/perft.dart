// Pruebas del motor de ajedrez (se ejecutan en la compilación en la nube).
import '../lib/chess/engine.dart';

void check(String name, String fen, List<int> expected) {
  final s = ChessState.fromFen(fen);
  for (var d = 1; d <= expected.length; d++) {
    final n = s.perft(d);
    final ok = n == expected[d - 1];
    print('$name depth $d: $n ${ok ? 'OK' : 'ERROR (esperado ${expected[d - 1]})'}');
    if (!ok) throw StateError('perft falló en $name profundidad $d');
  }
}

void main() {
  check('inicio', ChessState.startFen, [20, 400, 8902, 197281]);
  check('kiwipete',
      'r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1',
      [48, 2039, 97862]);
  check('posicion3', '8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1',
      [14, 191, 2812, 43238]);
  check('posicion4',
      'r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1',
      [6, 264, 9467]);
  check('posicion5', 'rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8',
      [44, 1486, 62379]);

  // FEN ida y vuelta
  final s0 = ChessState.start();
  if (ChessState.fromFen(s0.toFen()).toFen() != s0.toFen()) {
    throw StateError('FEN no es estable');
  }
  // Mate del loco
  final mate = ChessState.fromFen(
      'rnb1kbnr/pppp1ppp/8/4p3/6Pq/5P2/PPPPP2P/RNBQKBNR w KQkq - 1 3');
  if (mate.status() != 'checkmate') throw StateError('mate no detectado');
  // Ahogado
  final stale = ChessState.fromFen('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1');
  if (stale.status() != 'stalemate') throw StateError('ahogado no detectado');
  // La IA devuelve jugadas legales en las tres dificultades y encuentra mate en 1.
  for (var lvl = 1; lvl <= 3; lvl++) {
    final sw = Stopwatch()..start();
    final m = chooseAiMove(s0, lvl, 1)!;
    print('IA nivel $lvl: $m en ${sw.elapsedMilliseconds} ms');
    if (s0.find(m.from, m.to, m.promo) == null) throw StateError('IA ilegal');
  }
  final mateIn1 = ChessState.fromFen('6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1');
  final mm = chooseAiMove(mateIn1, 3, 1)!;
  if (mateIn1.apply(mm).status() != 'checkmate') {
    throw StateError('IA no encontró mate en 1: $mm');
  }
  print('Todas las pruebas pasaron');
}
