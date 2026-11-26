import 'dart:math';
import '../lib/stick/engine.dart';

void check(bool c, String m) {
  if (!c) throw 'FALLÓ: $m';
}

void sane(StickWorld w) {
  check(!w.p.x.isNaN && !w.p.z.isNaN && !w.p.hp.isNaN, 'jugador sin NaN');
  check(w.p.x >= 11.9 && w.p.x <= kW - 11.9, 'jugador dentro del escenario');
  check(w.p.z >= 0.0 && w.p.z < 80.0, 'altura razonable');
  check(w.p.hp >= 0.0 && w.p.hp <= w.p.maxHp + 0.001, 'vida en rango');
  for (final e in w.enemies) {
    check(!e.x.isNaN, 'enemigo sin NaN');
    check(e.x >= -31.0 && e.x <= kW + 31.0, 'enemigo acotado');
  }
}

/// Bot simple: va hacia el enemigo más cercano, golpea, salta piedras bajas
/// y se agacha ante las altas.
StickInput bot(StickWorld w) {
  final i = StickInput();
  Enemy? best;
  var bd = 1e9;
  for (final e in w.enemies) {
    if (e.dead) continue;
    final d = (e.x - w.p.x).abs();
    if (d < bd) {
      bd = d;
      best = e;
    }
  }
  for (final r in w.rocks) {
    final d = r.x - w.p.x;
    final coming = (d > 0 && r.vx < 0) || (d < 0 && r.vx > 0);
    if (coming && d.abs() < 70.0) {
      if (r.high) {
        i.crouch = true;
      } else {
        i.jump = true;
      }
    }
  }
  if (best != null && !i.crouch) {
    final d = best.x - w.p.x;
    if (d.abs() > 34.0) {
      if (d > 0) {
        i.right = true;
      } else {
        i.left = true;
      }
    } else {
      w.p.face = d >= 0 ? 1 : -1;
      i.attack = true;
    }
  }
  return i;
}

void main() {
  // 1) El palo mata a un soldado en 3 golpes aproximadamente y da monedas.
  {
    final w = StickWorld(StickStats(), seed: 3);
    w.step(0.05, StickInput());
    final e = Enemy(99, EKind.grunt, w.p.x + 30, 24.0, 52.0, 24.0, 8.0, 0.5, 0.9, 9.0);
    e.cd = 99.0;
    w.enemies.add(e);
    w.p.face = 1;
    var swings = 0;
    for (var t = 0; t < 400 && !e.dead; t++) {
      final inp = StickInput();
      if (w.p.atkT <= 0) {
        inp.attack = true;
        swings++;
      }
      w.step(1 / 60, inp);
      e.x = w.p.x + 30; // se queda al alcance
      e.stun = 0;
      sane(w);
    }
    check(e.dead, 'el soldado muere');
    check(swings >= 2 && swings <= 6, 'golpes razonables: $swings');
    check(w.coins >= 2, 'recompensa por la baja');
  }

  // 2) Agacharse esquiva la piedra alta; saltar esquiva la baja.
  {
    final high = StickWorld(StickStats(), seed: 4);
    high.step(0.05, StickInput());
    high.phase = Phase.playing;
    high.queue.clear();
    high.rocks.add(Rock(high.p.x + 60, 30.0, -150.0, true, 9.0));
    final hp0 = high.p.hp;
    final crouch = StickInput()..crouch = true;
    for (var t = 0; t < 90; t++) {
      high.step(1 / 60, crouch);
    }
    check(high.p.hp == hp0, 'agachado esquiva la piedra alta');

    final high2 = StickWorld(StickStats(), seed: 4);
    high2.step(0.05, StickInput());
    high2.phase = Phase.playing;
    high2.rocks.add(Rock(high2.p.x + 60, 30.0, -150.0, true, 9.0));
    for (var t = 0; t < 90; t++) {
      high2.step(1 / 60, StickInput());
    }
    check(high2.p.hp < high2.p.maxHp, 'de pie recibe la piedra alta');

    final low = StickWorld(StickStats(), seed: 5);
    low.step(0.05, StickInput());
    low.phase = Phase.playing;
    low.rocks.add(Rock(low.p.x + 60, 4.0, -150.0, false, 9.0));
    var jumped = false;
    for (var t = 0; t < 90; t++) {
      final inp = StickInput();
      if (!jumped && t == 12) {
        inp.jump = true;
        jumped = true;
      }
      low.step(1 / 60, inp);
    }
    check(low.p.hp == low.p.maxHp, 'saltar esquiva la piedra baja');
  }

  // 3) El combo de 3 golpes pega más que uno suelto.
  {
    final w = StickWorld(StickStats(), seed: 6);
    w.step(0.05, StickInput());
    final e = Enemy(1, EKind.brute, w.p.x + 30, 1000.0, 34.0, 30.0, 18.0, 0.75, 1.4, 13.0);
    e.cd = 999.0;
    w.enemies.add(e);
    final dmgs = <double>[];
    var last = e.hp;
    for (var t = 0; t < 400 && dmgs.length < 3; t++) {
      final inp = StickInput();
      if (w.p.atkT <= 0) inp.attack = true;
      w.step(1 / 60, inp);
      e.x = w.p.x + 30;
      e.stun = 0;
      if (e.hp < last) {
        dmgs.add(last - e.hp);
        last = e.hp;
      }
    }
    check(dmgs.length == 3, 'tres golpes');
    check(dmgs[2] > dmgs[0], 'el tercer golpe del combo es más fuerte');
  }

  // 4) Partida completa con el bot: no se rompe nada y se avanza de oleada.
  {
    final w = StickWorld(StickStats(maxHp: 400.0, dmgMul: 2.5), seed: 7);
    var maxWave = 0;
    for (var t = 0; t < 60 * 240; t++) {
      final inp = bot(w);
      w.step(1 / 60, inp);
      inp.clearEdges();
      sane(w);
      maxWave = max(maxWave, w.wave);
      w.events.clear();
      if (w.phase == Phase.over) break;
    }
    check(maxWave >= 3, 'el bot supera varias oleadas: $maxWave');
    check(w.kills > 5, 'hay bajas: ${w.kills}');
  }

  // 5) Los jefes aparecen cada 5 oleadas y la vida del jugador puede llegar a 0.
  {
    final w = StickWorld(StickStats(), seed: 8);
    check(w.plan(5).contains(EKind.boss), 'jefe en la oleada 5');
    check(!w.plan(4).contains(EKind.boss), 'sin jefe en la 4');
    w.step(0.05, StickInput());
    w.phase = Phase.playing;
    w.p.hp = 1.0;
    w.p.inv = 0.0;
    final e = Enemy(2, EKind.brute, w.p.x + 20, 70.0, 34.0, 30.0, 18.0, 0.1, 1.4, 13.0);
    e.face = -1;
    w.enemies.add(e);
    for (var t = 0; t < 120 && w.phase != Phase.over; t++) {
      w.step(1 / 60, StickInput());
    }
    check(w.phase == Phase.over, 'fin de la partida con 0 de vida');
    w.revive();
    check(w.phase == Phase.playing && w.p.hp > 0, 'revivir funciona');
  }

  // 6) Todas las armas existen y la búsqueda por id es segura.
  check(kWeapons.length >= 4, 'armas');
  check(weaponById('no_existe').id == 'palo', 'arma por defecto');
  print('Pruebas del Monigote de combate: OK');
}
