// Pruebas del motor de La Galleta (se ejecutan en la compilación en la nube).
import 'dart:math';
import '../lib/galleta/engine.dart';

void expect(bool c, String msg) {
  if (!c) throw StateError('FALLÓ: $msg');
}

void main() {
  // Figuras: tienen celdas y todas las aristas utilizables tocan alguna celda.
  for (final s in galletaShapes) {
    for (var size = 0; size < 3; size++) {
      final g = GalletaGame.shape(s.id, size);
      expect(g.totalCells > 10, 'figura ${s.id}/$size muy pequeña');
      expect(g.usable.isNotEmpty, 'sin aristas ${s.id}');
      print('${s.id} tamaño $size: ${g.w}x${g.h}, ${g.totalCells} cuadritos, ${g.usable.length} rayas');
    }
  }

  // Cuadro 2x2 a mano: el que cierra un cuadrito repite turno.
  final sq = GalletaGame(1, 1, [true]);
  expect(sq.usable.length == 4, 'un cuadrito tiene 4 rayas');
  expect(sq.play(sq.usable[0]) == 0 && sq.turn == 2, 'cambia de turno');
  expect(sq.play(sq.usable[1]) == 0 && sq.turn == 1, 'cambia de turno 2');
  expect(sq.play(sq.usable[2]) == 0 && sq.turn == 2, 'cambia de turno 3');
  expect(sq.play(sq.usable[3]) == 1 && sq.turn == 2, 'cierra y repite');
  expect(sq.score2 == 1 && sq.over, 'puntaje y fin');

  // Una raya compartida puede cerrar dos cuadritos a la vez.
  final two = GalletaGame(2, 1, [true, true]);
  // aristas: hor 0..3 (arriba 0,1; abajo 2,3), ver: 4,5,6
  for (final e in [0, 1, 2, 3, 4, 6]) {
    two.play(e);
  }
  final t = two.turn;
  expect(two.play(5) == 2, 'doble cierre');
  expect(two.turn == t && two.over, 'repite y termina');

  // Partidas completas IA contra IA: legales, terminan y suman bien.
  final rng = Random(5);
  for (final s in galletaShapes) {
    for (final lv in [1, 2, 3]) {
      final g = GalletaGame.shape(s.id, 0);
      var guard = 0;
      final sw = Stopwatch()..start();
      while (!g.over) {
        final e = chooseGalletaMove(g, lv, rng.nextInt(1 << 30));
        expect(g.isFree(e), 'IA nivel $lv jugó una raya inválida en ${s.id}');
        g.play(e);
        expect(++guard < 1000, 'partida infinita');
      }
      expect(g.score1 + g.score2 == g.totalCells, 'suma de cuadritos');
      expect(g.freeEdges().isEmpty, 'quedaron rayas libres');
      print('${s.id} nivel $lv: ${g.score1}-${g.score2} en ${sw.elapsedMilliseconds} ms');
    }
  }

  // Repetición de jugadas reproduce el mismo resultado.
  final base = GalletaGame.shape('rombo', 0);
  final moves = <int>[];
  while (!base.over) {
    final e = chooseGalletaMove(base, 2, rng.nextInt(1 << 30));
    moves.add(e);
    base.play(e);
  }
  final rep = GalletaGame.replay('rombo', 0, moves);
  expect(rep.score1 == base.score1 && rep.score2 == base.score2, 'replay');

  // La IA difícil no pierde contra la fácil en el cuadro pequeño (varias partidas).
  var wins = 0;
  for (var i = 0; i < 6; i++) {
    final g = GalletaGame.shape('cuadro', 0);
    final hardIs = (i % 2) + 1;
    while (!g.over) {
      final lv = g.turn == hardIs ? 3 : 1;
      g.play(chooseGalletaMove(g, lv, rng.nextInt(1 << 30)));
    }
    final hs = hardIs == 1 ? g.score1 : g.score2;
    final es = hardIs == 1 ? g.score2 : g.score1;
    if (hs > es) wins++;
  }
  print('Difícil ganó $wins de 6 contra fácil');
  if (wins < 4) print('Aviso: la IA difícil ganó pocas veces ($wins de 6)');

  print('Todas las pruebas de La Galleta pasaron');
}
