import 'dart:math';
import '../lib/radar/engine.dart';

void check(bool c, String m) {
  if (!c) throw 'FALLÓ: $m';
}

void main() {
  // Colocación válida: sin solapes, formas y cantidades correctas
  for (var s = 0; s < 500; s++) {
    final f = Fleet.random(Random(s));
    check(f.modKind.length == 6, 'seis módulos');
    var real = 0;
    final seen = <int>{};
    for (var m = 0; m < f.modKind.length; m++) {
      final cells = f.modCells[m];
      check(cells.length == kKinds[f.modKind[m]].shape.length, 'tamaño del módulo');
      for (final c in cells) {
        check(c >= 0 && c < kCells, 'dentro del tablero');
        check(seen.add(c), 'sin solapes');
      }
      if (kKinds[f.modKind[m]].real) real += cells.length;
    }
    check(real == 16, 'casillas reales = 16 (hay $real)');
    check(!f.defeated, 'flota nueva no está derrotada');
    check(f.realAlive == 4, 'cuatro objetivos');
  }

  // Blindado: dos impactos por casilla
  final f = Fleet.random(Random(3));
  final mb = f.modKind.indexOf(3);
  final c0 = f.modCells[mb].first;
  check(f.fire(c0).result == kShield, 'primer impacto abre el escudo');
  check(f.fire(c0).result == kHit, 'segundo impacto destruye la casilla');
  check(f.fire(c0).result == kAgain, 'casilla repetida');

  // Módulo destruido por completo
  final g = Fleet.random(Random(4));
  final mt = g.modKind.indexOf(1);
  ShotOut? last;
  for (final c in g.modCells[mt]) {
    last = g.fire(c);
  }
  check(last!.modDown && last.modKind == 1 && last.modCells.length == 4, 'Torre destruida');

  // Mina y baliza
  final h = Fleet.random(Random(5));
  final mine = h.modCells[h.modKind.indexOf(kKindMine)].first;
  final o1 = h.apply(RAction(kFire, mine), Random(1));
  check(o1.hitMine, 'mina detectada');
  var (t, s) = nextTurn(0, o1, 0);
  check(t == 1 && s == 1, 'mina: el rival juega dos veces');
  (t, s) = nextTurn(t, o1.hitMine ? const Outcome([], 0, -1, false) : o1, s);
  check(t == 1 && s == 0, 'segundo turno seguido del rival');
  (t, s) = nextTurn(t, const Outcome([], 0, -1, false), s);
  check(t == 0 && s == 0, 'vuelve el turno');
  final bea = h.modCells[h.modKind.indexOf(kKindBeacon)].first;
  final o2 = h.apply(RAction(kFire, bea), Random(1));
  check(o2.hitBeacon && o2.reveal >= 0, 'baliza revela una casilla');
  check(h.cellMod[o2.reveal] >= 0 && kKinds[h.modKind[h.cellMod[o2.reveal]]].real, 'revela casilla real');
  (t, s) = nextTurn(1, o2, 0);
  check(t == 1, 'baliza: turno extra');

  // Escaneo y onda cuentan solo casillas reales vivas
  final k = Fleet.random(Random(6));
  var total = 0;
  for (var r = 0; r < kN; r++) {
    total += k.apply(RAction(kWave, r, 0), Random(1)).count;
  }
  check(total == 16, 'suma de filas = 16');
  total = 0;
  for (var c = 0; c < kN; c++) {
    total += k.apply(RAction(kWave, c, 1), Random(1)).count;
  }
  check(total == 16, 'suma de columnas = 16');

  // Serialización ida y vuelta
  final oo = k.apply(RAction(kMissile, 27), Random(2));
  final back = Outcome.fromMap(oo.toMap());
  check(back.shots.length == oo.shots.length && back.defeated == oo.defeated, 'serialización');
  final ab = RAction.fromMap(const RAction(kWave, 3, 1).toMap());
  check(ab.kind == kWave && ab.a == 3 && ab.b == 1, 'serialización de acción');

  // Partidas completas PC contra PC: terminan y son rápidas
  for (final level in [0, 1]) {
    var totalTurns = 0;
    const games = 150;
    for (var i = 0; i < games; i++) {
      final rng = Random(i * 31 + level);
      final fl = [Fleet.random(rng), Fleet.random(rng)];
      final views = [EnemyView(), EnemyView()];
      final brains = [BotBrain(rng, level: level), BotBrain(rng, level: level)];
      final ammo = [Ammo(), Ammo()];
      var turn = 0, streak = 0, n = 0, winner = -1;
      while (winner < 0) {
        check(n++ < 400, 'partida infinita');
        final a = brains[turn].think(views[turn], ammo[turn]);
        if (a.kind != kFire) {
          check(ammo[turn].left(a.kind) > 0, 'habilidad sin munición');
        }
        if (a.kind == kFire) check(views[turn].canFire(a.a), 'disparo inválido ${a.a}');
        final o = fl[1 - turn].apply(a, rng);
        ammo[turn].use(a.kind);
        views[turn].apply(a, o);
        brains[turn].observe(a, o, views[turn]);
        if (o.defeated) {
          winner = turn;
          break;
        }
        (turn, streak) = nextTurn(turn, o, streak);
      }
      check(fl[1 - winner].defeated, 'el perdedor debe estar derrotado');
      totalTurns += n;
    }
    final avg = totalTurns / games;
    print('Nivel $level: ${avg.toStringAsFixed(1)} turnos por partida (ambos jugadores)');
    check(avg < 140, 'partidas demasiado largas');
  }
  print('Pruebas de Asalto Radar: OK');
}
