// Pruebas del juego de penales (se ejecutan en la compilación en la nube).
import 'dart:math';
import '../lib/penales/engine.dart';
import '../lib/penales/teams.dart';

void check(bool c, String m) {
  if (!c) throw 'FALLÓ: $m';
}

void main() {
  // ---- Datos de equipos
  check(kTeams.length == 16, '16 equipos');
  final names = <String>{};
  for (final t in kTeams) {
    check(names.add(t.key), 'clave repetida ${t.key}');
    check(t.takers.length == 11, '${t.name}: 11 pateadores');
    check(t.takers.toSet().length == 11, '${t.name}: pateadores repetidos');
    check(t.gk.isNotEmpty, '${t.name}: arquero');
    check(t.strength >= 0 && t.strength <= 1, 'fuerza');
  }
  check(kTeams.map((t) => t.rank).toSet().length == 16, 'rankings distintos');
  check(kTeams.firstWhere((t) => t.key == 'pal').strength >
      kTeams.firstWhere((t) => t.key == 'bsc').strength, 'más ranking = más difícil');

  // ---- Torneos completos solo con PC
  for (var s = 0; s < 300; s++) {
    final rng = Random(s);
    final g = Penales.create(
        fillTeams([], rng), List<String>.filled(8, 'bot'), List<String>.filled(8, 'PC'),
        rng: rng);
    check(g.finished, 'torneo de PC debe terminar solo');
    check(g.champion >= 0 && g.champion < 8, 'campeón');
    check(g.results.length == 7, '7 partidos (4+2+1), hubo ${g.results.length}');
    for (final r in g.results) {
      final p = r.split(',').map(int.parse).toList();
      check(p[3] != p[4], 'no hay empate en penales');
      check((p[3] > p[4] ? p[1] : p[2]) == p[5], 'ganador coincide con el marcador');
      check(p[3] <= 40 && p[4] <= 40, 'marcador razonable');
    }
    final fin = g.results.last.split(',').map(int.parse).toList();
    check(fin[5] == g.champion, 'campeón = ganador de la final');
  }

  // ---- Partido con una persona: reglas, moneda, serialización
  var firstCounts = [0, 0];
  for (var s = 0; s < 200; s++) {
    final rng = Random(1000 + s);
    final ctrl = ['u1', 'bot', 'bot', 'bot', 'bot', 'bot', 'bot', 'bot'];
    final g = Penales.create(
        fillTeams([4], rng), ctrl, ['Yo', ...List<String>.filled(7, 'PC')], rng: rng);
    // la persona juega en algún momento
    check(!g.finished, 'debe esperar a la persona');
    check(g.stage == 'lineup', 'primero el orden de tiro');
    check(g.setLineup(g.slotOf('u1'), [for (var i = 10; i >= 0; i--) i]), 'orden válido');
    check(g.lineupOf(g.slotOf('u1')).first == 10, 'orden guardado');
    check(g.freeTakers(g.a == g.slotOf('u1') ? 0 : 1).first == 10, 'patea el primero del orden');
    g.confirmLineup(g.slotOf('u1'));
    check(g.stage == 'toss', 'luego la moneda');
    firstCounts[g.first]++;
    var guard = 0;
    while (!g.finished && guard++ < 5000) {
      if (g.stage == 'pick') {
        final me = g.slotOf('u1');
        final ks = g.kickerSlot;
        if (ks == me) {
          g.humanKick(rng.nextInt(6), g.defaultShooter(g.kickerSide));
        }
        g.autoPick();
        if (g.pickKeep < 0) g.humanKeep(rng.nextInt(6));
        check(g.ready, 'ambos eligieron');
        // idempotencia por serialización
        final g2 = Penales.fromMap(g.toMap());
        check(g2.seq == g.seq && g2.stage == g.stage && g2.pickKick == g.pickKick, 'ida y vuelta');
        check(g.resolve(), 'resolver');
        check(g.stage == 'show', 'muestra el resultado');
        check(g.lastGoal == (g.lastKZ != g.lastGZ), 'gol solo si no coinciden');
      } else {
        g.advance();
      }
      // reglas del partido en curso
      if (g.stage == 'pick') {
        final ta = g.taken[0], tb = g.taken[1];
        check((ta - tb).abs() <= 1, 'tiros alternados');
        check(g.matchWinner == -1, 'sin ganador mientras se patea');
      }
    }
    check(g.finished && g.champion >= 0, 'terminó con campeón');
  }
  check(firstCounts[0] > 60 && firstCounts[1] > 60, 'la moneda reparte parejo: $firstCounts');

  // ---- Reglas de corte anticipado y muerte súbita (casos armados)
  Penales armado(List<int> res0, List<int> res1) {
    final rng = Random(1);
    final g = Penales.create(fillTeams([0], rng),
        ['u1', 'bot', 'bot', 'bot', 'bot', 'bot', 'bot', 'bot'], List<String>.filled(8, 'x'),
        rng: rng);
    g.advance(); // orden -> moneda
    g.advance(); // moneda -> pick
    final n = max(res0.length, res1.length);
    for (var i = 0; i < n * 2; i++) {
      if (g.matchWinner >= 0) break;
      final side = g.kickerSide;
      final list = side == 0 ? res0 : res1;
      final idx = g.taken[side];
      if (idx >= list.length) break;
      g.pickKick = 0;
      g.pickKeep = list[idx] == 1 ? 1 : 0; // 1 = gol (zonas distintas)
      g.pickShooter = g.defaultShooter(side);
      g.resolve();
      if (g.stage == 'show' && g.matchWinner < 0) g.advance();
    }
    return g;
  }

  // 3-0 tras 3 tiros cada uno: al otro le quedan 2 tiros, aún puede alcanzar (3-0 vs max 2).
  var pg = armado([1, 1, 1], [0, 0, 0]);
  check(pg.matchWinner >= 0, 'con 3-0 tras 3 tiros ya no se alcanza');
  // empate 4-4 tras 5 -> sigue
  pg = armado([1, 1, 1, 1, 0], [1, 1, 1, 1, 0]);
  check(pg.matchWinner < 0, 'empate tras 5 tiros: muerte súbita');
  check(pg.taken[0] == 5 && pg.taken[1] == 5, '5 tiros cada uno');
  // muerte súbita: uno anota y el otro falla
  pg = armado([1, 1, 1, 1, 0, 1], [1, 1, 1, 1, 0, 0]);
  check(pg.matchWinner >= 0, 'muerte súbita se decide');
  // en muerte súbita ambos anotan -> sigue
  pg = armado([1, 1, 1, 1, 0, 1], [1, 1, 1, 1, 0, 1]);
  check(pg.matchWinner < 0, 'ambos anotan en muerte súbita: sigue');

  // ---- Dificultad: un arquero de más ranking ataja más contra un pateador repetitivo
  double saveRate(String key) {
    final tIdx = teamIndexByKey(key);
    var saves = 0, shots = 0;
    for (var s = 0; s < 400; s++) {
      final rng = Random(5000 + s);
      final g = Penales.create(
          fillTeams([tIdx, teamIndexByKey('bsc')], rng),
          ['bot', 'u1', 'bot', 'bot', 'bot', 'bot', 'bot', 'bot'],
          List<String>.filled(8, 'x'),
          rng: rng);
      // ubica un partido entre el equipo evaluado y el pateador repetitivo
      for (var r = 0; r < 25; r++) {
        g.a = g.teams.indexOf(tIdx);
        g.b = g.teams.indexOf(teamIndexByKey('bsc'));
        g.taken = [0, 0];
        g.kzHist = [<int>[], <int>[]];
        g.first = 1; // patea el humano (lado 1)
        g.stage = 'pick';
        g.pickKick = 4; // siempre al medio abajo: muy repetitivo
        g.pickShooter = 0;
        g.pickKeep = g.botKeepZone(g.a, 1);
        // dos tiros previos para que haya historia
        g.kzHist[1] = [4, 4, 4, 4, 4, 4];
        g.pickKeep = g.botKeepZone(g.a, 1);
        shots++;
        if (g.pickKeep == g.pickKick) saves++;
      }
    }
    return saves / shots;
  }

  final fuerte = saveRate('pal');
  final debil = saveRate('uch');
  check(fuerte > debil + 0.05, 'dificultad por ranking: $fuerte vs $debil');
  check(debil > 0.10 && debil < 0.35, 'tasa base razonable: $debil');

  print('penales: todo correcto (arquero fuerte ${(fuerte * 100).toStringAsFixed(1)} %, '
      'débil ${(debil * 100).toStringAsFixed(1)} %)');
}
