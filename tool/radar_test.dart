import 'dart:math';
import '../lib/radar/engine.dart';

void check(bool c, String m) {
  if (!c) throw 'FALLÓ: $m';
}

void checkFleet(Fleet f) {
  check(f.shipCells.length == 5, 'cinco barcos');
  final seen = <int>{};
  for (var s = 0; s < 5; s++) {
    final cells = f.shipCells[s];
    check(cells.length == kShips[s].len, 'largo del barco');
    final horiz = cells[1] - cells[0] == 1;
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      check(c >= 0 && c < kCells, 'dentro del tablero');
      check(seen.add(c), 'sin solapes');
      check(f.cellShip[c] == s, 'índice coherente');
      if (i > 0) {
        check(cells[i] - cells[i - 1] == (horiz ? 1 : kN), 'recto');
        if (horiz) check(cells[i] ~/ kN == cells[0] ~/ kN, 'misma fila');
      }
    }
    check(!f.decoys.any(cells.contains), 'señuelo sobre barco');
  }
  var n = 0;
  for (var c = 0; c < kCells; c++) {
    if (f.cellShip[c] >= 0) n++;
  }
  check(n == 17, 'casillas fantasma');
}

void main() {
  // Colocación válida
  for (var s = 0; s < 500; s++) {
    final f = Fleet.random(Random(s));
    checkFleet(f);
    check(f.decoyCount == 3, 'tres señuelos');
    check(f.shieldCount == 2, 'dos escudos');
    check(f.ready, 'lista');
    check(!f.defeated && f.shipsAlive == 5, 'flota nueva');
  }

  // Escudo: bloquea UN disparo, se destruye y luego el barco puede dañarse
  {
    final f = Fleet.random(Random(3));
    final s = [for (var i = 0; i < 5; i++) if (f.shield[i]) i].first;
    final c = f.shipCells[s].first;
    final o1 = f.fire(c);
    check(o1.res == kShield, 'escudo bloquea');
    check(!f.shot[c], 'la casilla no queda disparada');
    check(!f.shield[s], 'el escudo se destruye');
    final o2 = f.fire(c);
    check(o2.res == kHit, 'ahora sí impacta');
  }

  // Hundir un barco y señuelo
  {
    final f = Fleet.random(Random(9));
    for (var s = 0; s < 5; s++) {
      f.shield[s] = false;
    }
    final cells = List<int>.from(f.shipCells[4]);
    Outcome? last;
    for (final c in cells) {
      last = f.fire(c);
    }
    check(last!.sunk == 4 && last.sunkCells.length == 2, 'hundido');
    final d = f.decoys.first;
    final od = f.fire(d);
    check(od.res == kDecoy, 'señuelo');
    check(f.shipsAlive == 4, 'quedan 4');
    final back = Outcome.fromMap(last.toMap());
    check(back.sunk == 4 && back.sunkCells.length == 2 && back.cell == last.cell, 'serialización');
    final view = EnemyView()..apply(last.cell, last);
    check(view.sunkShips.contains(4) && view.st[cells.first] == 4, 'vista');
    final vd = EnemyView()..apply(d, od);
    check(vd.st[d] == 2, 'el señuelo parece un impacto');
  }

  // Edición: mover, girar, señuelos y escudos
  {
    final rng = Random(77);
    for (var s = 0; s < 200; s++) {
      final f = Fleet.random(rng);
      for (var i = 0; i < 80; i++) {
        final sh = rng.nextInt(5);
        switch (rng.nextInt(4)) {
          case 0:
            f.rotateShip(sh);
            break;
          case 1:
            f.moveShip(sh, rng.nextInt(12) - 1, rng.nextInt(12) - 1);
            break;
          case 2:
            f.toggleDecoy(rng.nextInt(kCells));
            break;
          default:
            f.toggleShield(f.shipCells[sh].first);
        }
        checkFleet(f);
        check(f.decoyCount <= 3 && f.shieldCount <= 2, 'límites');
      }
      check(f.copy().shipsAlive == f.shipsAlive, 'copia');
    }
  }

  // Partidas completas PC contra PC (también con señuelos y escudos)
  for (final level in [0, 1]) {
    var total = 0;
    const games = 300;
    for (var g = 0; g < games; g++) {
      final rng = Random(1000 + g + level * 100000);
      final fleets = [Fleet.random(rng), Fleet.random(rng)];
      final views = [EnemyView(), EnemyView()];
      final brains = [BotBrain(rng, level: level), BotBrain(rng, level: level)];
      var turn = rng.nextInt(2);
      var turns = 0;
      var over = false;
      while (!over) {
        check(turns < 1000, 'la partida no termina');
        final c = brains[turn].think(views[turn]);
        check(views[turn].canFire(c), 'disparo válido');
        final o = fleets[1 - turn].fire(c);
        views[turn].apply(c, o);
        brains[turn].observe(c, o, views[turn]);
        turns++;
        if (o.defeated) {
          over = true;
        } else {
          turn = 1 - turn;
        }
      }
      total += turns;
    }
    final avg = total / games;
    print('Nivel $level: promedio ${avg.toStringAsFixed(1)} disparos por partida');
    check(avg < (level == 0 ? 240 : 150), 'la PC es demasiado lenta (nivel $level)');
  }

  print('Todas las pruebas de Batalla naval pasaron.');
}
