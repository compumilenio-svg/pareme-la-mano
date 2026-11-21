import 'dart:math';

// ======================================================================
// Batalla naval (Asalto Radar): motor puro de reglas, sin Flutter.
// Tablero 10×10, flota clásica (5, 4, 3, 3, 2), 3 señuelos y 2 escudos.
// ======================================================================

const int kN = 10;
const int kCells = 100;

// Resultado de un disparo
const int kMiss = 1;
const int kHit = 2;
const int kShield = 3; // el escudo bloqueó el disparo (y se destruyó)
const int kDecoy = 4; // señuelo: el atacante lo ve como un impacto

const int kDecoyCount = 3;
const int kShieldCount = 2;

class ShipKind {
  final String name;
  final int len;
  const ShipKind(this.name, this.len);
}

const List<ShipKind> kShips = [
  ShipKind('Portaaviones', 5),
  ShipKind('Acorazado', 4),
  ShipKind('Crucero', 3),
  ShipKind('Submarino', 3),
  ShipKind('Destructor', 2),
];

String cellName(int c) => '${'ABCDEFGHIJ'[c % kN]}${c ~/ kN + 1}';

List<int> neighbors4(int c) {
  final r = c ~/ kN, k = c % kN;
  return [
    if (r > 0) c - kN,
    if (r < kN - 1) c + kN,
    if (k > 0) c - 1,
    if (k < kN - 1) c + 1,
  ];
}

/// Resultado de un disparo (viaja por Firestore entre los dos jugadores).
class Outcome {
  final int cell;
  final int res;
  final int sunk; // índice del barco hundido (-1 si ninguno)
  final List<int> sunkCells;
  final bool defeated;
  const Outcome(this.cell, this.res, this.sunk, this.sunkCells, this.defeated);

  Map<String, dynamic> toMap() => {
        'c': cell,
        'r': res,
        's': sunk,
        'sc': sunkCells,
        'df': defeated ? 1 : 0,
      };

  factory Outcome.fromMap(Map m) => Outcome(
        (m['c'] as num).toInt(),
        (m['r'] as num).toInt(),
        (m['s'] as num? ?? -1).toInt(),
        [for (final x in (m['sc'] as List? ?? const [])) (x as num).toInt()],
        ((m['df'] as num? ?? 0).toInt()) == 1,
      );
}

// ----------------------------------------------------------------------
// Flota propia (secreta)
// ----------------------------------------------------------------------

class Fleet {
  final List<int> cellShip = List.filled(kCells, -1);
  final List<bool> shot = List.filled(kCells, false);
  final List<List<int>> shipCells = [];
  final List<bool> shield = [];
  final Set<int> decoys = {};

  Fleet();

  static Fleet random(Random rng) {
    for (var attempt = 0; attempt < 500; attempt++) {
      final f = Fleet();
      var ok = true;
      for (var s = 0; s < kShips.length && ok; s++) {
        final len = kShips[s].len;
        var placed = false;
        for (var t = 0; t < 200 && !placed; t++) {
          final horiz = rng.nextBool();
          final r = rng.nextInt(horiz ? kN : kN - len + 1);
          final c = rng.nextInt(horiz ? kN - len + 1 : kN);
          final cells = [
            for (var i = 0; i < len; i++) horiz ? r * kN + c + i : (r + i) * kN + c,
          ];
          if (cells.every((x) => f.cellShip[x] < 0)) {
            f.shipCells.add(cells);
            f.shield.add(false);
            for (final x in cells) {
              f.cellShip[x] = s;
            }
            placed = true;
          }
        }
        if (!placed) ok = false;
      }
      if (!ok) continue;
      final free = [
        for (var c = 0; c < kCells; c++)
          if (f.cellShip[c] < 0) c,
      ]..shuffle(rng);
      f.decoys.addAll(free.take(kDecoyCount));
      final idx = [for (var i = 0; i < kShips.length; i++) i]..shuffle(rng);
      for (final i in idx.take(kShieldCount)) {
        f.shield[i] = true;
      }
      return f;
    }
    throw StateError('No se pudo colocar la flota');
  }

  Fleet copy() {
    final f = Fleet();
    for (var c = 0; c < kCells; c++) {
      f.cellShip[c] = cellShip[c];
      f.shot[c] = shot[c];
    }
    for (final cs in shipCells) {
      f.shipCells.add(List<int>.from(cs));
    }
    f.shield.addAll(shield);
    f.decoys.addAll(decoys);
    return f;
  }

  // --- edición (antes de empezar) -------------------------------------

  bool isHoriz(int s) => shipCells[s][1] - shipCells[s][0] == 1;

  /// Esquina (fila, columna) del barco [s].
  (int, int) originOf(int s) => (shipCells[s].first ~/ kN, shipCells[s].first % kN);

  int get shieldCount => shield.where((x) => x).length;
  int get decoyCount => decoys.length;

  bool _put(int s, bool horiz, int r0, int c0) {
    final len = kShips[s].len;
    final r = r0 < 0 ? 0 : (r0 > (horiz ? kN - 1 : kN - len) ? (horiz ? kN - 1 : kN - len) : r0);
    final c = c0 < 0 ? 0 : (c0 > (horiz ? kN - len : kN - 1) ? (horiz ? kN - len : kN - 1) : c0);
    final cells = [
      for (var i = 0; i < len; i++) horiz ? r * kN + c + i : (r + i) * kN + c,
    ];
    for (final x in cells) {
      if (cellShip[x] >= 0 && cellShip[x] != s) return false;
      if (decoys.contains(x)) return false;
    }
    for (final old in shipCells[s]) {
      cellShip[old] = -1;
    }
    shipCells[s] = cells;
    for (final x in cells) {
      cellShip[x] = s;
    }
    return true;
  }

  /// Mueve el barco para que su esquina quede en (r0, c0). false si choca.
  bool moveShip(int s, int r0, int c0) => _put(s, isHoriz(s), r0, c0);

  /// Gira el barco 90° sobre su esquina. false si no cabe.
  bool rotateShip(int s) {
    final o = originOf(s);
    return _put(s, !isHoriz(s), o.$1, o.$2);
  }

  /// Pone o quita un señuelo. Devuelve un mensaje de error o null.
  String? toggleDecoy(int c) {
    if (decoys.contains(c)) {
      decoys.remove(c);
      return null;
    }
    if (cellShip[c] >= 0) return 'Los señuelos van en el agua, no sobre un barco.';
    if (decoys.length >= kDecoyCount) {
      return 'Ya pusiste los $kDecoyCount señuelos. Toca uno para quitarlo.';
    }
    decoys.add(c);
    return null;
  }

  /// Pone o quita el escudo del barco que ocupa [c]. Devuelve error o null.
  String? toggleShield(int c) {
    final s = cellShip[c];
    if (s < 0) return 'Los escudos se ponen sobre un barco.';
    if (shield[s]) {
      shield[s] = false;
      return null;
    }
    if (shieldCount >= kShieldCount) {
      return 'Ya pusiste los $kShieldCount escudos. Toca uno para quitarlo.';
    }
    shield[s] = true;
    return null;
  }

  bool get ready => decoyCount == kDecoyCount && shieldCount == kShieldCount;

  // --- combate -----------------------------------------------------------

  bool shipSunk(int s) => shipCells[s].every((x) => shot[x]);

  int get shipsAlive {
    var n = 0;
    for (var s = 0; s < shipCells.length; s++) {
      if (!shipSunk(s)) n++;
    }
    return n;
  }

  bool get defeated => shipsAlive == 0;

  /// Recibe un disparo en [c] (la casilla no debe haber sido disparada antes).
  Outcome fire(int c) {
    final s = cellShip[c];
    if (s >= 0) {
      if (shield[s]) {
        // El escudo aguanta este turno y se destruye.
        shield[s] = false;
        return Outcome(c, kShield, -1, const [], false);
      }
      shot[c] = true;
      if (shipSunk(s)) {
        return Outcome(c, kHit, s, List<int>.from(shipCells[s]), defeated);
      }
      return Outcome(c, kHit, -1, const [], false);
    }
    shot[c] = true;
    if (decoys.contains(c)) return Outcome(c, kDecoy, -1, const [], false);
    return Outcome(c, kMiss, -1, const [], false);
  }
}

// ----------------------------------------------------------------------
// Lo que yo sé del tablero rival
// ----------------------------------------------------------------------

class EnemyView {
  /// 0 desconocido · 1 agua · 2 impacto · 3 escudo bloqueó · 4 barco hundido
  final List<int> st = List.filled(kCells, 0);
  final Set<int> sunkShips = {};
  final Map<int, List<int>> sunkCells = {};

  bool canFire(int c) => st[c] == 0 || st[c] == 3;

  void apply(int c, Outcome o) {
    switch (o.res) {
      case kMiss:
        st[c] = 1;
        break;
      case kHit:
      case kDecoy:
        st[c] = 2;
        break;
      case kShield:
        st[c] = 3;
        break;
    }
    if (o.sunk >= 0) {
      sunkShips.add(o.sunk);
      sunkCells[o.sunk] = List<int>.from(o.sunkCells);
      for (final x in o.sunkCells) {
        st[x] = 4;
      }
    }
  }
}

// ----------------------------------------------------------------------
// La PC
// ----------------------------------------------------------------------

class BotBrain {
  final Random rng;
  final int level; // 0 fácil (al azar) · 1 normal (caza y remata)
  final List<int> queue = [];
  BotBrain(this.rng, {this.level = 1});

  int think(EnemyView v) {
    if (level >= 1) {
      while (queue.isNotEmpty) {
        final c = queue.removeLast();
        if (v.canFire(c)) return c;
      }
    }
    final all = [
      for (var c = 0; c < kCells; c++)
        if (v.canFire(c)) c,
    ];
    if (level >= 1) {
      final par = [
        for (final c in all)
          if (((c ~/ kN) + (c % kN)) % 2 == 0 && v.st[c] == 0) c,
      ];
      if (par.isNotEmpty) return par[rng.nextInt(par.length)];
    }
    return all[rng.nextInt(all.length)];
  }

  void observe(int c, Outcome o, EnemyView v) {
    if (level < 1) return;
    if (o.res == kShield) {
      queue.add(c); // ahora sí se puede
      return;
    }
    if (o.res == kHit || o.res == kDecoy) {
      if (o.sunk >= 0) {
        queue.clear();
        for (var x = 0; x < kCells; x++) {
          if (v.st[x] == 2) {
            for (final n in neighbors4(x)) {
              if (v.canFire(n)) queue.add(n);
            }
          }
        }
        queue.shuffle(rng);
      } else {
        final ns = [
          for (final n in neighbors4(c))
            if (v.canFire(n)) n,
        ]..shuffle(rng);
        queue.addAll(ns);
      }
    }
  }
}
