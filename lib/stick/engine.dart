// Motor puro (sin Flutter) del juego "Monigote de combate".
// Mundo de 480 x 270 unidades; el suelo está en y = kGround.
import 'dart:math';

const double kW = 480.0;
const double kH = 270.0;
const double kGround = 222.0;

enum EKind { grunt, runner, thrower, brute, boss }

enum Phase { between, playing, over }

enum Ev { swing, jump, hit, bigHit, hurt, kill, coin, rock, parry, wave, boss, over }

class StickEvent {
  final Ev type;
  final double x;
  final double y;
  final int v;
  StickEvent(this.type, this.x, this.y, [this.v = 0]);
}

class WeaponDef {
  final String id;
  final String name;
  final String desc;
  final int price;
  final double dmg;
  final double reach;
  final double swing;
  const WeaponDef(this.id, this.name, this.desc, this.price, this.dmg, this.reach, this.swing);
}

const List<WeaponDef> kWeapons = [
  WeaponDef('palo', 'Palo', 'Equilibrado y rápido', 0, 10.0, 40.0, 0.28),
  WeaponDef('nunchaku', 'Nunchaku', 'Muy veloz, poco alcance', 200, 7.0, 30.0, 0.17),
  WeaponDef('bate', 'Bate', 'Lento pero pega fuerte', 350, 18.0, 44.0, 0.38),
  WeaponDef('katana', 'Katana de bambú', 'Largo alcance y rápida', 700, 13.0, 56.0, 0.24),
];

WeaponDef weaponById(String id) {
  for (final w in kWeapons) {
    if (w.id == id) return w;
  }
  return kWeapons[0];
}

/// Mejoras permanentes que se compran con monedas.
class StickStats {
  final double maxHp;
  final double dmgMul;
  final double speedMul;
  final WeaponDef weapon;
  StickStats({this.maxHp = 100.0, this.dmgMul = 1.0, this.speedMul = 1.0, WeaponDef? weapon})
      : weapon = weapon ?? kWeapons[0];
}

class StickInput {
  bool left = false;
  bool right = false;
  bool crouch = false;
  bool jump = false; // se activa con un toque; clearEdges() lo apaga
  bool attack = false;
  void clearEdges() {
    jump = false;
    attack = false;
  }
}

class Player {
  double x = kW / 2;
  double z = 0.0;
  double vz = 0.0;
  double kx = 0.0;
  int face = 1;
  double hp;
  final double maxHp;
  bool crouching = false;
  bool moving = false;
  double atkT = 0.0;
  double atkDur = 0.3;
  int atkKind = 0; // 0 de pie, 1 en el aire, 2 agachado (barrido)
  bool hitDone = true;
  int combo = 0;
  double comboT = 0.0;
  double hurtT = 0.0;
  double inv = 0.0;
  Player(this.maxHp) : hp = maxHp;
}

class Enemy {
  final int id;
  final EKind kind;
  double x;
  int face = -1;
  double hp;
  final double maxHp;
  final double speed;
  final double reach;
  final double dmg;
  final double windup;
  final double cooldown;
  final double radius;
  double kx = 0.0;
  double hurtT = 0.0;
  double stun = 0.0;
  double cd = 0.6;
  double cd2 = 3.0;
  int state = 0; // 0 avanza, 1 prepara golpe, 2 recupera, 3 aviso carga, 4 cansado, 5 carga
  double t = 0.0;
  bool high = true; // lanzador: la piedra va alta (agacharse) o baja (saltar)
  int chargeDir = 1;
  bool chargeHit = false;
  bool dead = false;
  double deadT = 0.0;
  Enemy(this.id, this.kind, this.x, this.hp, this.speed, this.reach, this.dmg, this.windup,
      this.cooldown, this.radius)
      : maxHp = hp;
}

class Rock {
  double x;
  final double z;
  final double vx;
  final bool high;
  final double dmg;
  Rock(this.x, this.z, this.vx, this.high, this.dmg);
}

class StickWorld {
  final StickStats stats;
  final Random rng;
  final Player p;
  final List<Enemy> enemies = [];
  final List<Rock> rocks = [];
  final List<StickEvent> events = [];
  final List<EKind> queue = [];
  Phase phase = Phase.between;
  int wave = 0;
  double betweenT = 1.2;
  double spawnT = 0.0;
  int kills = 0;
  int coins = 0;
  double time = 0.0;
  int _nextId = 1;
  bool revived = false;

  StickWorld(this.stats, {int seed = 1})
      : rng = Random(seed),
        p = Player(stats.maxHp);

  int get aliveCount {
    var n = 0;
    for (final e in enemies) {
      if (!e.dead) n++;
    }
    return n;
  }

  void step(double dtRaw, StickInput inp) {
    final dt = dtRaw.clamp(0.0, 0.05).toDouble();
    time += dt;
    if (phase == Phase.over) {
      _updateEnemiesDeadOnly(dt);
      return;
    }
    _updatePlayer(dt, inp);
    _updateEnemies(dt);
    _updateRocks(dt);
    _waveLogic(dt);
    if (p.hp <= 0) {
      p.hp = 0.0;
      phase = Phase.over;
      events.add(StickEvent(Ev.over, p.x, kGround - 20));
    }
  }

  /// Segunda oportunidad: vuelve con 60 % de vida y unos segundos de invulnerabilidad.
  void revive() {
    if (phase != Phase.over) return;
    revived = true;
    p.hp = p.maxHp * 0.6;
    p.inv = 2.5;
    p.hurtT = 0.0;
    rocks.clear();
    phase = Phase.playing;
  }

  // ---------------------------------------------------------------- jugador
  void _updatePlayer(double dt, StickInput inp) {
    final pl = p;
    pl.hurtT = max(0.0, pl.hurtT - dt);
    pl.inv = max(0.0, pl.inv - dt);
    pl.comboT = max(0.0, pl.comboT - dt);
    final onGround = pl.z <= 0.0;
    pl.crouching = inp.crouch && onGround;
    final dirIn = (inp.right ? 1.0 : 0.0) - (inp.left ? 1.0 : 0.0);
    var speed = 118.0 * stats.speedMul;
    if (pl.crouching) speed = 0.0;
    if (pl.atkT > 0) speed *= 0.45;
    if (pl.hurtT > 0.15) speed *= 0.3;
    pl.x += dirIn * speed * dt;
    pl.moving = dirIn != 0.0 && !pl.crouching;
    if (dirIn != 0.0 && pl.atkT <= 0) pl.face = dirIn > 0 ? 1 : -1;
    pl.x += pl.kx * dt;
    pl.kx *= pow(0.002, dt).toDouble();
    pl.x = pl.x.clamp(12.0, kW - 12.0).toDouble();

    if (inp.jump && onGround && !pl.crouching && pl.hurtT < 0.15) {
      pl.vz = 330.0;
      pl.z = 0.01;
      events.add(StickEvent(Ev.jump, pl.x, kGround));
    }
    if (pl.z > 0.0 || pl.vz > 0.0) {
      pl.vz -= 950.0 * dt;
      pl.z += pl.vz * dt;
      if (pl.z <= 0.0) {
        pl.z = 0.0;
        pl.vz = 0.0;
      }
    }

    if (inp.attack && pl.atkT <= 0 && pl.hurtT < 0.1) _startAttack();
    if (pl.atkT > 0) {
      final prog = 1.0 - pl.atkT / pl.atkDur;
      if (!pl.hitDone && prog >= 0.4) {
        pl.hitDone = true;
        _applyPlayerHit();
      }
      pl.atkT -= dt;
      if (pl.atkT <= 0) {
        pl.atkT = 0.0;
        pl.comboT = 0.45;
      }
    }
  }

  void _startAttack() {
    final pl = p;
    pl.combo = (pl.comboT > 0 && pl.combo < 3) ? pl.combo + 1 : 1;
    pl.atkDur = stats.weapon.swing;
    pl.atkT = pl.atkDur;
    pl.hitDone = false;
    pl.atkKind = pl.crouching ? 2 : (pl.z > 4.0 ? 1 : 0);
    events.add(StickEvent(Ev.swing, pl.x + pl.face * 20, kGround - pl.z - 24, pl.combo));
  }

  void _applyPlayerHit() {
    final pl = p;
    final w = stats.weapon;
    final f = pl.face;
    if (pl.z > 38.0) return; // en lo más alto del salto el golpe pasa por encima
    final big = pl.combo == 3;
    final sweep = pl.atkKind == 2;
    final air = pl.atkKind == 1;
    for (final e in enemies) {
      if (e.dead) continue;
      final dx = (e.x - pl.x) * f;
      if (dx < -8.0 || dx > w.reach + e.radius) continue;
      var dmg = w.dmg * stats.dmgMul;
      if (big) dmg *= 1.7;
      if (air) dmg *= 1.25;
      if (sweep) dmg *= 0.9;
      if (rng.nextDouble() < 0.1) dmg *= 1.5;
      if (e.state == 4) dmg *= 1.5; // jefe cansado
      e.hp -= dmg;
      e.hurtT = 0.2;
      e.kx += f * (big ? 260.0 : 90.0);
      if (e.kind != EKind.boss && (sweep || big)) e.stun = 0.6;
      if (e.state == 1 && e.kind != EKind.boss && (e.kind != EKind.brute || big)) {
        e.state = 0;
        e.t = 0.0;
        e.cd = max(e.cd, 0.5);
      }
      events.add(StickEvent(big ? Ev.bigHit : Ev.hit, e.x, kGround - 22, dmg.round()));
      if (e.hp <= 0) _kill(e);
    }
    for (final r in rocks) {
      final dx = (r.x - pl.x) * f;
      if (dx > -4.0 && dx < w.reach + 12.0 && r.z < pl.z + 50.0 && r.z + 8.0 > pl.z) {
        r.x = -999.0; // se elimina en _updateRocks
        coins += 1;
        events.add(StickEvent(Ev.parry, pl.x + f * 24, kGround - pl.z - 28));
      }
    }
  }

  void _hurtPlayer(double dmg, int fromFace, {bool melee = true}) {
    final pl = p;
    if (pl.inv > 0) return;
    var d = dmg;
    if (pl.crouching && melee) d *= 0.45;
    pl.hp -= d;
    pl.hurtT = 0.3;
    pl.inv = 0.55;
    pl.kx += fromFace * 180.0;
    pl.atkT = 0.0;
    events.add(StickEvent(Ev.hurt, pl.x, kGround - pl.z - 24, d.round()));
  }

  // --------------------------------------------------------------- enemigos
  int _coinsFor(EKind k) {
    switch (k) {
      case EKind.grunt:
        return 2;
      case EKind.runner:
        return 2;
      case EKind.thrower:
        return 4;
      case EKind.brute:
        return 8;
      case EKind.boss:
        return 50;
    }
  }

  void _kill(Enemy e) {
    e.dead = true;
    e.deadT = 0.0;
    e.hp = 0.0;
    kills++;
    final c = _coinsFor(e.kind);
    coins += c;
    events.add(StickEvent(Ev.kill, e.x, kGround - 20, e.kind.index));
    events.add(StickEvent(Ev.coin, e.x, kGround - 36, c));
  }

  void _updateEnemiesDeadOnly(double dt) {
    for (final e in enemies) {
      if (e.dead) e.deadT += dt;
    }
    enemies.removeWhere((e) => e.dead && e.deadT > 1.0);
  }

  void _updateEnemies(double dt) {
    final pl = p;
    for (final e in enemies) {
      if (e.dead) {
        e.deadT += dt;
        continue;
      }
      e.hurtT = max(0.0, e.hurtT - dt);
      e.x += e.kx * dt;
      e.kx *= pow(0.002, dt).toDouble();
      if (e.stun > 0) {
        e.stun -= dt;
        continue;
      }
      e.cd = max(0.0, e.cd - dt);
      e.cd2 = max(0.0, e.cd2 - dt);
      final dist = pl.x - e.x;
      final dir = dist >= 0 ? 1 : -1;
      final ad = dist.abs();
      switch (e.kind) {
        case EKind.thrower:
          _throwerAI(e, dt, dir, ad);
          break;
        case EKind.boss:
          _bossAI(e, dt, dir, ad);
          break;
        default:
          _meleeAI(e, dt, dir, ad);
      }
    }
    // separación entre enemigos
    for (var i = 0; i < enemies.length; i++) {
      for (var j = i + 1; j < enemies.length; j++) {
        final a = enemies[i], b = enemies[j];
        if (a.dead || b.dead || a.state == 5 || b.state == 5) continue;
        final d = b.x - a.x;
        final min0 = (a.radius + b.radius) * 0.7;
        if (d.abs() < min0) {
          final push = (min0 - d.abs()) * 0.5;
          final s = d >= 0 ? 1.0 : -1.0;
          a.x -= s * push;
          b.x += s * push;
        }
      }
    }
    for (final e in enemies) {
      e.x = e.x.clamp(-30.0, kW + 30.0).toDouble();
    }
    enemies.removeWhere((e) => e.dead && e.deadT > 1.0);
  }

  void _meleeAI(Enemy e, double dt, int dir, double ad) {
    if (e.state == 0) {
      e.face = dir;
      if (ad > e.reach * 0.85) {
        e.x += dir * e.speed * dt;
      } else if (e.cd <= 0) {
        e.state = 1;
        e.t = e.windup;
      }
    } else if (e.state == 1) {
      e.t -= dt;
      if (e.t <= 0) {
        final pl = p;
        if (ad <= e.reach + 8.0 && pl.z < 16.0 && (pl.x - e.x) * e.face >= -4.0) {
          _hurtPlayer(e.dmg, e.face);
        }
        e.state = 2;
        e.t = 0.35;
        e.cd = e.cooldown;
      }
    } else if (e.state == 2) {
      e.t -= dt;
      if (e.t <= 0) e.state = 0;
    }
  }

  void _throwerAI(Enemy e, double dt, int dir, double ad) {
    e.face = dir;
    if (e.state == 0) {
      if (ad < 120.0) {
        e.x -= dir * e.speed * dt;
      } else if (ad > 200.0) {
        e.x += dir * e.speed * dt;
      }
      if (e.cd <= 0 && ad > 60.0) {
        e.state = 1;
        e.t = 0.55;
        e.high = rng.nextBool();
      }
    } else if (e.state == 1) {
      e.t -= dt;
      if (e.t <= 0) {
        rocks.add(Rock(e.x + dir * 12.0, e.high ? 30.0 : 4.0, dir * (150.0 + wave * 3.0), e.high, e.dmg));
        events.add(StickEvent(Ev.rock, e.x, kGround - 30));
        e.state = 2;
        e.t = 0.3;
        e.cd = 1.6 + rng.nextDouble() * 1.2;
      }
    } else {
      e.t -= dt;
      if (e.t <= 0) e.state = 0;
    }
  }

  void _bossAI(Enemy e, double dt, int dir, double ad) {
    final pl = p;
    if (e.state == 3) {
      e.t -= dt;
      if (e.t <= 0) {
        e.state = 5;
        e.t = 0.55;
        e.chargeHit = false;
      }
    } else if (e.state == 5) {
      e.x += e.chargeDir * 300.0 * dt;
      if (!e.chargeHit && (pl.x - e.x).abs() < 24.0 && pl.z < 18.0) {
        e.chargeHit = true;
        _hurtPlayer(e.dmg * 1.2, e.chargeDir, melee: false);
      }
      e.t -= dt;
      if (e.t <= 0 || e.x < 8.0 || e.x > kW - 8.0) {
        e.state = 4;
        e.t = 1.3;
        e.cd2 = 5.0;
      }
    } else if (e.state == 4) {
      e.t -= dt;
      if (e.t <= 0) e.state = 0;
    } else if (e.state == 0 && e.cd2 <= 0 && ad > 110.0) {
      e.state = 3;
      e.t = 0.7;
      e.face = dir;
      e.chargeDir = dir;
    } else {
      _meleeAI(e, dt, dir, ad);
    }
  }

  void _updateRocks(double dt) {
    final pl = p;
    for (final r in rocks) {
      r.x += r.vx * dt;
      final top = pl.z + (pl.crouching ? 22.0 : 44.0);
      if ((r.x - pl.x).abs() < 9.0 && r.z + 6.0 > pl.z && r.z - 6.0 < top) {
        _hurtPlayer(r.dmg, r.vx >= 0 ? 1 : -1, melee: false);
        if (pl.inv > 0.5) r.x = -999.0;
      }
    }
    rocks.removeWhere((r) => r.x < -40.0 || r.x > kW + 40.0);
  }

  // ----------------------------------------------------------------- oleadas
  int get _maxAlive => min(6, 4 + wave ~/ 6);

  void _waveLogic(double dt) {
    if (phase == Phase.between) {
      betweenT -= dt;
      if (betweenT <= 0) {
        _startWave();
        phase = Phase.playing;
      }
      return;
    }
    spawnT -= dt;
    if (queue.isNotEmpty && spawnT <= 0 && aliveCount < _maxAlive) {
      _spawn(queue.removeAt(0));
      spawnT = max(0.6, 2.0 - wave * 0.07);
    }
    if (queue.isEmpty && aliveCount == 0) {
      final bonus = 10 + wave * 5;
      coins += bonus;
      p.hp = min(p.maxHp, p.hp + p.maxHp * 0.25);
      phase = Phase.between;
      betweenT = 2.4;
      rocks.clear();
      events.add(StickEvent(Ev.coin, p.x, kGround - 50, bonus));
    }
  }

  List<EKind> plan(int w) {
    final list = <EKind>[];
    final n = min(16, 3 + (w * 1.7).floor());
    for (var i = 0; i < n; i++) {
      final r = rng.nextDouble();
      if (w >= 4 && r < 0.14) {
        list.add(EKind.brute);
      } else if (w >= 3 && r < 0.34) {
        list.add(EKind.thrower);
      } else if (w >= 2 && r < 0.60) {
        list.add(EKind.runner);
      } else {
        list.add(EKind.grunt);
      }
    }
    if (w % 5 == 0) {
      if (list.length > 6) list.removeRange(6, list.length);
      list.add(EKind.boss);
    }
    return list;
  }

  void _startWave() {
    wave++;
    queue
      ..clear()
      ..addAll(plan(wave));
    spawnT = 0.8;
    events.add(StickEvent(Ev.wave, kW / 2, 60, wave));
    if (wave % 5 == 0) events.add(StickEvent(Ev.boss, kW / 2, 60, wave));
  }

  void _spawn(EKind k) {
    final x = rng.nextBool() ? -16.0 : kW + 16.0;
    final hs = 1.0 + 0.09 * (wave - 1);
    final ds = 1.0 + 0.05 * (wave - 1);
    final id = _nextId++;
    Enemy e;
    switch (k) {
      case EKind.grunt:
        e = Enemy(id, k, x, 24.0 * hs, 52.0, 24.0, 8.0 * ds, 0.5, 0.9, 9.0);
        break;
      case EKind.runner:
        e = Enemy(id, k, x, 14.0 * hs, 98.0, 22.0, 6.0 * ds, 0.28, 0.7, 8.0);
        break;
      case EKind.thrower:
        e = Enemy(id, k, x, 18.0 * hs, 42.0, 0.0, 9.0 * ds, 0.55, 1.6, 9.0);
        break;
      case EKind.brute:
        e = Enemy(id, k, x, 70.0 * hs, 34.0, 30.0, 18.0 * ds, 0.75, 1.4, 13.0);
        break;
      case EKind.boss:
        e = Enemy(id, k, x, 260.0 + wave * 25.0, 46.0, 36.0, 20.0 * ds, 0.6, 1.1, 17.0);
        break;
    }
    e.face = x < p.x ? 1 : -1;
    enemies.add(e);
  }
}
