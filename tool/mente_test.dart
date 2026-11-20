import 'dart:math';
import '../lib/mente/engine.dart';

void check(bool c, String m) {
  if (!c) throw 'FALLÓ: $m';
}

void main() {
  // ---- ¿Quién es el culpable?: solución única y frases coherentes
  for (var level = 0; level < 3; level++) {
    for (var seed = 0; seed < 300; seed++) {
      final rng = Random(level * 1000 + seed);
      final c = CulpritCase.generate(level, rng);
      check(c.count == 4 + level, 'cantidad de sospechosos');
      check(c.names.toSet().length == c.count, 'nombres distintos');
      check(c.statements.length == c.count, 'una frase por sospechoso');
      final cons = c.consistentCulprits();
      check(cons.length == 1 && cons.first == c.culprit,
          'solución única (nivel $level, semilla $seed): $cons vs ${c.culprit}');
      for (var i = 0; i < c.count; i++) {
        check(c.say(i).isNotEmpty, 'frase vacía');
        check(c.statements[i].truthAt(c.culprit) == (i != c.culprit),
            'el culpable miente y los demás dicen la verdad');
      }
      check(c.explain().length == c.count + 1, 'explicación completa');
    }
  }

  // ---- Patrones numéricos
  for (var level = 0; level < 3; level++) {
    for (var seed = 0; seed < 600; seed++) {
      final q = makePattern(level, Random(level * 5000 + seed));
      check(q.shown.length == (level == 0 ? 5 : 6), 'números mostrados');
      check(q.options.length == 4, '4 opciones');
      check(q.options.toSet().length == 4, 'opciones distintas');
      check(q.options.contains(q.answer), 'la respuesta está entre las opciones');
      check(q.rule.isNotEmpty, 'regla explicada');
    }
  }

  // ---- Nim: jugando perfecto el jugador siempre gana desde la posición inicial
  for (var level = 0; level < 3; level++) {
    for (var seed = 0; seed < 300; seed++) {
      final rng = Random(level * 777 + seed);
      final g = NimGame.generate(level, rng);
      check(g.moverWins, 'el jugador parte de una posición ganadora (nivel $level)');
      var playerTurn = true;
      var guard = 0;
      var playerWon = false;
      while (!g.over && guard++ < 200) {
        final m = g.bestMove(rng);
        check(g.canTake(m.heap, m.take), 'jugada válida');
        if (playerTurn) {
          check(g.moverWins, 'el jugador sigue en posición ganadora');
        }
        g.applyMove(m.heap, m.take);
        if (g.over) {
          final moverWins = !g.misere;
          playerWon = playerTurn ? moverWins : !moverWins;
          break;
        }
        playerTurn = !playerTurn;
      }
      check(g.over, 'la partida termina');
      check(playerWon, 'quien juega perfecto desde la posición ganadora gana (nivel $level)');
    }
  }
  // La PC (perfecta) gana si el jugador comete un error
  final bad = NimGame([5], 3, false); // 5 % 4 = 1: ganadora tomando 1
  bad.applyMove(0, 2); // error: deja 3
  check(bad.moverWins, 'tras el error, la PC mueve en posición ganadora');

  // ---- Pensamiento lateral
  for (final p in kLateral) {
    check(p.options.length == 4, '${p.title}: 4 opciones');
    check(p.correct >= 0 && p.correct < 4, '${p.title}: respuesta válida');
    check(p.questions.length >= 5, '${p.title}: al menos 5 preguntas');
    check(p.questions.every((q) => q.answer >= 0 && q.answer < 3), '${p.title}: respuestas Sí/No');
    check(p.explanation.isNotEmpty, '${p.title}: explicación');
    check(p.options.toSet().length == 4, '${p.title}: opciones distintas');
  }

  // ---- Acertijos
  for (final r in kRiddles) {
    check(r.options.length == 4, 'acertijo: 4 opciones');
    check(r.options.toSet().length == 4, 'acertijo: opciones distintas');
    check(r.correct >= 0 && r.correct < 4, 'acertijo: respuesta válida');
    check(r.hint.isNotEmpty && r.explanation.isNotEmpty, 'acertijo: pista y explicación');
  }

  print('Mente brillante: todas las pruebas pasaron.');
}
