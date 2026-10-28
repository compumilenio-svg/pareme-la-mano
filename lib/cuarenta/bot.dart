import 'engine.dart';

/// Bot sencillo: prioriza puntos (caída, limpia), luego levantar más cartas,
/// y al dejar una carta evita las que el rival aún puede "caer".
Move chooseBotMove(CuarentaGame g) {
  final seat = g.current;
  final moves = g.legalMoves();
  Move best = moves.first;
  var bestScore = -1e9;
  for (final m in moves) {
    var s = 0.0;
    if (m.isCapture) {
      s += 5 + m.captured.length * 3;
      if (g.table.length - m.captured.length == 0) s += 20; // limpia
      if (g.isCaida(m)) s += 20; // caída
    } else {
      s -= g.unseenCopies(m.card.rank, seat) * 4; // riesgo de caída
      if (m.card.rank >= 8) s += 1; // soltar figuras es más seguro
    }
    s += g.rng.nextDouble(); // desempate aleatorio
    if (s > bestScore) {
      bestScore = s;
      best = m;
    }
  }
  return best;
}
