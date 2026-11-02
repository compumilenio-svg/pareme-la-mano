import 'dart:math';
import '../lib/pares/engine.dart';

void check(bool c, String m) {
  if (!c) throw 'FALLÓ: $m';
}

void main() {
  for (var t = 0; t < kPairThemes.length; t++) {
    check(poolFor(t).length >= 30, 'tema ${kPairThemes[t].name} necesita 30 imágenes distintas');
  }
  check(poolFor(kMixedTheme).length >= 100, 'mezcla');
  for (final pairs in kLevelPairs) {
    for (final theme in [-1, 0, 1, 2, 3, 4, 5, 6]) {
      final g = PairsGame.create(pairs, theme, 3, rng: Random(pairs + theme));
      check(g.faces.length == pairs * 2, 'cantidad de cartas');
      final counts = <String, int>{};
      for (final f in g.faces) {
        counts[f] = (counts[f] ?? 0) + 1;
      }
      check(counts.values.every((c) => c == 2), 'cada imagen exactamente dos veces');
    }
  }
  // Partidas completas con bots de 2 a 4 jugadores
  for (final players in [1, 2, 3, 4]) {
    for (final pairs in kLevelPairs) {
      final g = PairsGame.create(pairs, -1, players, rng: Random(players * 7 + pairs));
      final bot = PairsBot(rng: Random(5));
      var guard = 0;
      while (!g.finished) {
        check(guard++ < 20000, 'partida infinita');
        final a = bot.pickFirst(g);
        check(g.canFlip(a), 'primera carta inválida');
        g.flip(a);
        bot.observe(g);
        final b = bot.pickSecond(g, a);
        check(b != a && g.canFlip(b), 'segunda carta inválida');
        g.flip(b);
        bot.observe(g);
        check(g.needsResolve, 'debe resolverse');
        g.resolve();
      }
      check(g.scores.reduce((x, y) => x + y) == pairs, 'suma de pares');
      check(g.winners.isNotEmpty, 'ganador');
      // ida y vuelta por Firestore
      final g2 = PairsGame.fromMap(g.toMap());
      check(g2.finished && g2.scores.join() == g.scores.join(), 'serialización');
    }
  }
  // La PC con memoria debe ganar en menos intentos que el azar puro.
  var botMoves = 0;
  for (var i = 0; i < 20; i++) {
    final g = PairsGame.create(20, -1, 1, rng: Random(i));
    final bot = PairsBot(rng: Random(i), skill: 0.9);
    while (!g.finished) {
      final a = bot.pickFirst(g);
      g.flip(a);
      bot.observe(g);
      final b = bot.pickSecond(g, a);
      g.flip(b);
      bot.observe(g);
      g.resolve();
    }
    botMoves += g.moves;
  }
  check(botMoves / 20 < 60, 'la PC debe usar la memoria (promedio ${botMoves / 20})');
  print('Pares: todas las pruebas OK');
}
