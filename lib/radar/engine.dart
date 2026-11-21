// Asalto Radar: motor puro de Dart (sin Flutter) para poder probarlo en CI.
//
// Cada jugador esconde en una cuadrícula de 8x8 módulos con formas distintas:
//  - Núcleo (cruz de 5), Torre (línea de 4), Antena (L de 3): objetivos reales.
//  - Blindado (2x2): objetivo real con escudo (cada casilla aguanta 2 impactos).
//  - Mina: señuelo; quien la toca pierde su siguiente turno.
//  - Baliza: nodo especial; da turno extra y revela una casilla enemiga.
// Gana quien destruye primero los 4 objetivos reales del rival.
//
// El rival NUNCA recibe la flota: cada dispositivo resuelve los disparos sobre
// su propia flota y solo comparte el resultado (así no se puede espiar).
import 'dart:math';

const int kN = 8;
const int kCells = kN * kN;

// Resultados de un disparo
const int kAgain = 0;
const int kMiss = 1;
const int kHit = 2;
const int kShield = 3;
const int kMine = 4;
const int kBeacon = 5;

// Acciones
const int kFire = 0;
const int kScan = 1;
const int kWave = 2;
const int kMissile = 3;

class ModKind {
  final String name;
  final String icon;
  final bool real;
  final int hp; // impactos que aguanta cada casilla
  final List<List<int>> shape; // pares [fila, columna]
  const ModKind(this.name, this.icon, this.real, this.hp, this.shape);
}

const List<ModKind> kKinds = [
  ModKind('Núcleo', '💠', true, 1, [
    [0, 1], [1, 0], [1, 1], [1, 2], [2, 1],
  ]),
  ModKind('Torre', '🗼', true, 1, [
    [0, 0], [0, 1], [0, 2], [0, 3],
  ]),
  ModKind('Antena', '📡', true, 1, [
    [0, 0], [1, 0], [1, 1],
  ]),
  ModKind('Blindado', '🛡️', true, 2, [
    [0, 0], [0, 1], [1, 0], [1, 1],
  ]),
  ModKind('Mina', '💣', false, 1, [
    [0, 0],
  ]),
  ModKind('Baliza', '🎁', false, 1, [
    [0, 0],
  ]),
];

const int kKindMine = 4;
const int kKindBeacon = 5;
const int kRealKinds = 4;

String cellName(int c) => '${'ABCDEFGH'[c % kN]}${c ~/ kN + 1}';

List<int> plusOf(int c) {
  final r = c ~/ kN, k = c % kN;
  final out = <int>[c];
  if (r > 0) out.add(c - kN);
  if (r < kN - 1) out.add(c + kN);
  if (k > 0) out.add(c - 1);
  if (k < kN - 1) out.add(c + 1);
  return out;
}

List<int> boxOf(int c) {
  final r = c ~/ kN, k = c % kN;
  final out = <int>[];
  for (var dr = -1; dr <= 1; dr++) {
    for (var dc = -1; dc <= 1; dc++) {
      final rr = r + dr, cc = k + dc;
      if (rr >= 0 && rr < kN && cc >= 0 && cc < kN) out.add(rr * kN + cc);
    }
  }
  return out;
}

List<int> lineOf(int idx, int vertical) {
  // vertical 0 = fila idx, 1 = columna idx
  return [
    for (var i = 0; i < kN; i++) vertical == 0 ? idx * kN + i : i * kN + idx,
  ];
}

// ----------------------------------------------------------------------
// Acción y resultado (se serializan para Firestore)
// ----------------------------------------------------------------------

class RAction {
  final int kind;
  final int a; // casilla (disparo, escaneo, misil) o número de línea (onda)
  final int b; // onda: 0 fila, 1 columna
  const RAction(this.kind, this.a, [this.b = 0]);

  Map<String, dynamic> toMap() => {'k': kind, 'a': a, 'b': b};
  factory RAction.fromMap(Map m) => RAction(
      (m['k'] as num).toInt(), (m['a'] as num).toInt(), (m['b'] as num? ?? 0).toInt());
}

class ShotOut {
  final int cell;
  final int result;
  final int modKind; // tipo de módulo golpeado (-1 si agua)
  final bool modDown; // el módulo quedó completamente destruido
  final List<int> modCells; // casillas del módulo caído
  const ShotOut(this.cell, this.result,
      {this.modKind = -1, this.modDown = false, this.modCells = const []});

  Map<String, dynamic> toMap() => {
        'c': cell,
        'r': result,
        'mk': modKind,
        'md': modDown ? 1 : 0,
        'mc': modCells,
      };
  factory ShotOut.fromMap(Map m) => ShotOut(
        (m['c'] as num).toInt(),
        (m['r'] as num).toInt(),
        modKind: (m['mk'] as num? ?? -1).toInt(),
        modDown: ((m['md'] as num? ?? 0).toInt()) == 1,
        modCells: [for (final x in (m['mc'] as List? ?? const [])) (x as num).toInt()],
      );
}

class Outcome {
  final List<ShotOut> shots;
  final int count; // escaneo / onda
  final int reveal; // casilla revelada por una baliza (-1 si no)
  final bool defeated; // el defensor perdió todos sus objetivos reales
  const Outcome(this.shots, this.count, this.reveal, this.defeated);

  bool get hitMine => shots.any((s) => s.result == kMine);
  bool get hitBeacon => shots.any((s) => s.result == kBeacon);

  Map<String, dynamic> toMap() => {
        's': [for (final s in shots) s.toMap()],
        'n': count,
        'rv': reveal,
        'df': defeated ? 1 : 0,
      };
  factory Outcome.fromMap(Map m) => Outcome(
        [for (final s in (m['s'] as List? ?? const [])) ShotOut.fromMap(Map.from(s as Map))],
        (m['n'] as num? ?? 0).toInt(),
        (m['rv'] as num? ?? -1).toInt(),
        ((m['df'] as num? ?? 0).toInt()) == 1,
      );
}

/// Municiones de habilidades (el disparo simple es ilimitado).
class Ammo {
  int scan;
  int wave;
  int missile;
  Ammo({this.scan = 2, this.wave = 2, this.missile = 1});

  int left(int kind) =>
      kind == kScan ? scan : kind == kWave ? wave : kind == kMissile ? missile : 999;

  void use(int kind) {
    if (kind == kScan) scan--;
    if (kind == kWave) wave--;
    if (kind == kMissile) missile--;
  }
}

/// Quién juega después de [cur] (y cuántos turnos extra le quedan).
/// Mina: el atacante pierde su siguiente turno (el rival juega dos seguidos).
/// Baliza: el atacante repite turno.
(int, int) nextTurn(int cur, Outcome o, int streak) {
  final opp = 1 - cur;
  if (o.hitMine) return (opp, 1);
  if (o.hitBeacon) return (cur, 0);
  if (streak > 0) return (cur, streak - 1);
  return (opp, 0);
}

// ----------------------------------------------------------------------
// Flota propia (secreta)
// ----------------------------------------------------------------------

class Fleet {
  final List<int> cellMod = List.filled(kCells, -1);
  final List<int> hp = List.filled(kCells, 0);
  final List<bool> shot = List.filled(kCells, false);
  final List<int> modKind = [];
  final List<List<int>> modCells = [];

  static List<List<int>> _rot(List<List<int>> s, int k) {
    var cur = s;
    for (var i = 0; i < k; i++) {
      cur = [
        for (final p in cur) [p[1], -p[0]],
      ];
    }
    var minR = 1 << 20, minC = 1 << 20;
    for (final p in cur) {
      if (p[0] < minR) minR = p[0];
      if (p[1] < minC) minC = p[1];
    }
    return [
      for (final p in cur) [p[0] - minR, p[1] - minC],
    ];
  }

  static Fleet random(Random rng) {
    for (var attempt = 0; attempt < 200; attempt++) {
      final f = Fleet();
      var ok = true;
      for (var kind = 0; kind < kKinds.length && ok; kind++) {
        var placed = false;
        for (var t = 0; t < 300 && !placed; t++) {
          final shape = _rot(kKinds[kind].shape, rng.nextInt(4));
          var h = 0, w = 0;
          for (final p in shape) {
            if (p[0] + 1 > h) h = p[0] + 1;
            if (p[1] + 1 > w) w = p[1] + 1;
          }
          final r0 = rng.nextInt(kN - h + 1);
          final c0 = rng.nextInt(kN - w + 1);
          final cells = [
            for (final p in shape) (r0 + p[0]) * kN + (c0 + p[1]),
          ];
          if (cells.any((c) => f.cellMod[c] >= 0)) continue;
          final idx = f.modKind.length;
          f.modKind.add(kind);
          f.modCells.add(cells);
          for (final c in cells) {
            f.cellMod[c] = idx;
            f.hp[c] = kKinds[kind].hp;
          }
          placed = true;
        }
        if (!placed) ok = false;
      }
      if (ok) return f;
    }
    throw StateError('No se pudo colocar la flota');
  }

  bool _realAlive(int c) =>
      cellMod[c] >= 0 && kKinds[modKind[cellMod[c]]].real && !shot[c];

  bool get defeated {
    for (var c = 0; c < kCells; c++) {
      if (_realAlive(c)) return false;
    }
    return true;
  }

  /// Objetivos reales que siguen en pie (para el panel).
  int get realAlive {
    var n = 0;
    for (var m = 0; m < modKind.length; m++) {
      if (kKinds[modKind[m]].real && modCells[m].any((c) => !shot[c])) n++;
    }
    return n;
  }

  bool moduleAlive(int kind) {
    for (var m = 0; m < modKind.length; m++) {
      if (modKind[m] == kind) return modCells[m].any((c) => !shot[c]);
    }
    return false;
  }

  ShotOut fire(int c) {
    if (c < 0 || c >= kCells || shot[c]) return ShotOut(c, kAgain);
    final m = cellMod[c];
    if (m < 0) {
      shot[c] = true;
      return ShotOut(c, kMiss);
    }
    final kind = modKind[m];
    hp[c]--;
    if (hp[c] > 0) return ShotOut(c, kShield, modKind: kind);
    shot[c] = true;
    final down = modCells[m].every((x) => shot[x]);
    final res = kind == kKindMine
        ? kMine
        : kind == kKindBeacon
            ? kBeacon
            : kHit;
    return ShotOut(c, res,
        modKind: kind, modDown: down, modCells: down ? modCells[m] : const []);
  }

  int _countIn(List<int> cells) {
    var n = 0;
    for (final c in cells) {
      if (_realAlive(c)) n++;
    }
    return n;
  }

  int _pickReveal(Random rng) {
    final cand = <int>[];
    for (var c = 0; c < kCells; c++) {
      if (_realAlive(c)) cand.add(c);
    }
    if (cand.isEmpty) return -1;
    return cand[rng.nextInt(cand.length)];
  }

  Outcome apply(RAction a, Random rng) {
    final shots = <ShotOut>[];
    var count = 0;
    if (a.kind == kFire) {
      shots.add(fire(a.a));
    } else if (a.kind == kMissile) {
      for (final c in plusOf(a.a)) {
        shots.add(fire(c));
      }
    } else if (a.kind == kScan) {
      count = _countIn(boxOf(a.a));
    } else if (a.kind == kWave) {
      count = _countIn(lineOf(a.a, a.b));
    }
    var reveal = -1;
    if (shots.any((s) => s.result == kBeacon)) reveal = _pickReveal(rng);
    return Outcome(shots, count, reveal, defeated);
  }
}

// ----------------------------------------------------------------------
// Lo que sé del rival
// ----------------------------------------------------------------------

class EnemyView {
  /// 0 oculto, 1 agua, 2 impacto, 3 escudo agrietado, 4 módulo destruido,
  /// 5 trampa, 6 baliza
  final List<int> st = List.filled(kCells, 0);
  final List<int> kindAt = List.filled(kCells, -1);
  final List<int> scanAt = List.filled(kCells, -1); // número en el centro del escaneo
  final Set<int> scanned = {};
  final Set<int> targets = {}; // casillas reveladas por balizas
  final List<int> rowCount = List.filled(kN, -1);
  final List<int> colCount = List.filled(kN, -1);
  final Set<int> downKinds = {};
  int shotsFired = 0;

  void apply(RAction a, Outcome o) {
    for (final s in o.shots) {
      switch (s.result) {
        case kMiss:
          st[s.cell] = 1;
          break;
        case kHit:
          st[s.cell] = 2;
          break;
        case kShield:
          st[s.cell] = 3;
          break;
        case kMine:
          st[s.cell] = 5;
          break;
        case kBeacon:
          st[s.cell] = 6;
          break;
      }
      if (s.result != kAgain) targets.remove(s.cell);
      if (s.modDown && s.modKind >= 0 && s.modKind < kRealKinds) {
        for (final c in s.modCells) {
          st[c] = 4;
          kindAt[c] = s.modKind;
          targets.remove(c);
        }
        downKinds.add(s.modKind);
      }
    }
    if (a.kind == kScan) {
      scanAt[a.a] = o.count;
      scanned.addAll(boxOf(a.a));
    } else if (a.kind == kWave) {
      if (a.b == 0) {
        rowCount[a.a] = o.count;
      } else {
        colCount[a.a] = o.count;
      }
    }
    if (o.reveal >= 0 && st[o.reveal] == 0) targets.add(o.reveal);
    shotsFired++;
  }

  bool canFire(int c) => st[c] == 0 || st[c] == 3;
}

// ----------------------------------------------------------------------
// Cerebro de la PC
// ----------------------------------------------------------------------

class BotBrain {
  final Random rng;
  final int level; // 0 fácil, 1 normal
  final Set<int> hot = {};
  final Set<int> cold = {};
  BotBrain(this.rng, {this.level = 1});

  List<int> _free(EnemyView v) => [
        for (var c = 0; c < kCells; c++)
          if (v.st[c] == 0) c,
      ];

  List<int> _neighbors(int c) {
    final r = c ~/ kN, k = c % kN;
    return [
      if (r > 0) c - kN,
      if (r < kN - 1) c + kN,
      if (k > 0) c - 1,
      if (k < kN - 1) c + 1,
    ];
  }

  RAction think(EnemyView v, Ammo ammo) {
    final free = _free(v);
    // 1) Balizas: casillas reveladas
    for (final t in v.targets) {
      if (v.st[t] == 0) return RAction(kFire, t);
    }
    // 2) Casillas con escudo agrietado: rematar
    final cracked = [
      for (var c = 0; c < kCells; c++)
        if (v.st[c] == 3) c,
    ];
    if (cracked.isNotEmpty && (level > 0 || rng.nextDouble() < 0.6)) {
      return RAction(kFire, cracked[rng.nextInt(cracked.length)]);
    }
    // 3) Seguir un impacto
    if (level > 0 || rng.nextDouble() < 0.6) {
      final chase = <int>{};
      for (var c = 0; c < kCells; c++) {
        if (v.st[c] != 2) continue;
        for (final n in _neighbors(c)) {
          if (v.st[n] == 0) chase.add(n);
        }
      }
      if (chase.isNotEmpty) {
        final list = chase.toList();
        if (level > 0 && ammo.missile > 0 && rng.nextDouble() < 0.25) {
          return RAction(kMissile, list[rng.nextInt(list.length)]);
        }
        return RAction(kFire, list[rng.nextInt(list.length)]);
      }
    }
    // 4) Zonas calientes
    final hotFree = [for (final c in hot) if (v.st[c] == 0) c];
    if (hotFree.isNotEmpty) {
      return RAction(kFire, hotFree[rng.nextInt(hotFree.length)]);
    }
    // 5) Habilidades
    if (free.length > 6) {
      if (ammo.scan > 0 && rng.nextDouble() < (level > 0 ? 0.5 : 0.3)) {
        final cand = [for (final c in free) if (!v.scanned.contains(c)) c];
        final from = cand.isEmpty ? free : cand;
        return RAction(kScan, from[rng.nextInt(from.length)]);
      }
      if (level > 0 && ammo.wave > 0 && rng.nextDouble() < 0.2) {
        final vertical = rng.nextInt(2);
        final idx = rng.nextInt(kN);
        final known = vertical == 0 ? v.rowCount[idx] : v.colCount[idx];
        if (known < 0) return RAction(kWave, idx, vertical);
      }
      if (ammo.missile > 0 && rng.nextDouble() < (level > 0 ? 0.12 : 0.06)) {
        var best = free.first, bestN = -1;
        for (var i = 0; i < 6; i++) {
          final c = free[rng.nextInt(free.length)];
          var n = 0;
          for (final p in plusOf(c)) {
            if (v.st[p] == 0) n++;
          }
          if (n > bestN) {
            bestN = n;
            best = c;
          }
        }
        return RAction(kMissile, best);
      }
    }
    // 6) Búsqueda: evita zonas frías y usa tablero de ajedrez
    var pool = [for (final c in free) if (!cold.contains(c)) c];
    if (pool.isEmpty) pool = free;
    if (level > 0) {
      final par = [for (final c in pool) if (((c ~/ kN) + (c % kN)) % 2 == 0) c];
      if (par.isNotEmpty) pool = par;
    }
    if (pool.isEmpty) {
      // casillas con escudo agrietado son las únicas que quedan
      for (var c = 0; c < kCells; c++) {
        if (v.st[c] == 3) return RAction(kFire, c);
      }
      return const RAction(kFire, 0);
    }
    return RAction(kFire, pool[rng.nextInt(pool.length)]);
  }

  /// Llamar después de aplicar el resultado a la vista.
  void observe(RAction a, Outcome o, EnemyView v) {
    List<int> area = const [];
    if (a.kind == kScan) area = boxOf(a.a);
    if (a.kind == kWave) area = lineOf(a.a, a.b);
    if (area.isEmpty) return;
    if (o.count == 0) {
      cold.addAll(area);
    } else if (o.count >= 2 || a.kind == kScan) {
      hot.addAll([for (final c in area) if (v.st[c] == 0) c]);
    }
  }
}
