import 'dart:math';

// ---------------------------------------------------------------
// La Galleta (Timbiriche / Cuadraditos / Dots and Boxes).
// Dos jugadores trazan por turnos una raya entre dos puntos vecinos.
// Quien cierra un cuadrito se lo queda (lo marca con su X o su O) y
// juega otra vez. Gana quien se quede con más cuadritos.
// ---------------------------------------------------------------

class ShapeDef {
  final String id;
  final String name;
  final bool hasSize; // si admite tamaños
  const ShapeDef(this.id, this.name, this.hasSize);
}

const List<ShapeDef> galletaShapes = [
  ShapeDef('galleta', 'Galleta', true),
  ShapeDef('rombo', 'Galleta (rombo)', true),
  ShapeDef('cuadro', 'Cuadro', true),
  ShapeDef('circulo', 'Círculo', true),
  ShapeDef('cruz', 'Cruz', true),
  ShapeDef('corazon', 'Corazón', false),
];

const List<String> _heart = [
  '.###.###.',
  '#########',
  '#########',
  '#########',
  '.#######.',
  '..#####..',
  '...###...',
  '....#....',
];

class ShapeMask {
  final int w, h;
  final List<bool> cells; // h * w
  ShapeMask(this.w, this.h, this.cells);
}

/// size: 0 pequeña, 1 mediana, 2 grande.
ShapeMask buildShape(String id, int size) {
  size = size.clamp(0, 2);
  switch (id) {
    case 'galleta':
      {
        // Galleta: redonda con puntas arriba, abajo y a los lados (como en el cuaderno).
        final n = 11 + 2 * size;
        final cells = <bool>[];
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n; x++) {
            final dx = (x + 0.5 - n / 2) / (n / 2);
            final dy = (y + 0.5 - n / 2) / (n / 2);
            cells.add(pow(dx.abs(), 1.2) + pow(dy.abs(), 1.2) <= 1.0);
          }
        }
        return ShapeMask(n, n, cells);
      }
    case 'cuadro':
      {
        final n = 5 + 2 * size;
        return ShapeMask(n, n, List.filled(n * n, true));
      }
    case 'circulo':
      {
        final n = 7 + 2 * size;
        final r = n / 2.0;
        final cells = <bool>[];
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n; x++) {
            final dx = x + 0.5 - r, dy = y + 0.5 - r;
            cells.add(dx * dx + dy * dy <= r * r * 0.92);
          }
        }
        return ShapeMask(n, n, cells);
      }
    case 'cruz':
      {
        final n = 7 + 2 * size;
        final m = (n - 1) / 2;
        final cells = <bool>[];
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n; x++) {
            cells.add((y - m).abs() <= 1 || (x - m).abs() <= 1);
          }
        }
        return ShapeMask(n, n, cells);
      }
    case 'corazon':
      {
        final h = _heart.length, w = _heart[0].length;
        return ShapeMask(w, h, [
          for (final row in _heart)
            for (var i = 0; i < w; i++) row[i] == '#'
        ]);
      }
    case 'rombo':
    default:
      {
        final r = 3 + size;
        final n = 2 * r + 1;
        final cells = <bool>[];
        for (var y = 0; y < n; y++) {
          for (var x = 0; x < n; x++) {
            cells.add((y - r).abs() + (x - r).abs() <= r);
          }
        }
        return ShapeMask(n, n, cells);
      }
  }
}

class GalletaGame {
  final int w, h;
  final List<bool> mask; // h * w
  final List<int> hor; // (h + 1) * w : 0 libre, 1 o 2 = quién la trazó
  final List<int> ver; // h * (w + 1)
  final List<int> owner; // h * w : 0 nadie, 1 o 2
  int turn = 1;
  int score1 = 0;
  int score2 = 0;
  int lastEdge = -1;
  int moveCount = 0;
  late final List<int> usable; // aristas que tocan alguna celda de la figura
  late final int totalCells;

  GalletaGame(this.w, this.h, List<bool> m)
      : mask = List<bool>.of(m),
        hor = List<int>.filled((h + 1) * w, 0),
        ver = List<int>.filled(h * (w + 1), 0),
        owner = List<int>.filled(h * w, 0) {
    _init();
  }

  factory GalletaGame.shape(String id, int size) {
    final s = buildShape(id, size);
    return GalletaGame(s.w, s.h, s.cells);
  }

  /// Reconstruye una partida repitiendo las jugadas (para el modo en línea).
  factory GalletaGame.replay(String id, int size, List<int> moves) {
    final g = GalletaGame.shape(id, size);
    for (final e in moves) {
      if (g.isFree(e)) g.play(e);
    }
    return g;
  }

  void _init() {
    final u = <int>[];
    for (var e = 0; e < edgeCount; e++) {
      if (cellsOfEdge(e).isNotEmpty) u.add(e);
    }
    usable = u;
    totalCells = mask.where((x) => x).length;
  }

  int get edgeCount => (h + 1) * w + h * (w + 1);
  int get horCount => (h + 1) * w;

  bool isHor(int e) => e < horCount;

  int _val(int e) => e < horCount ? hor[e] : ver[e - horCount];

  bool isFree(int e) => e >= 0 && e < edgeCount && _val(e) == 0 && _isUsable(e);

  bool _isUsable(int e) => cellsOfEdge(e).isNotEmpty;

  int edgeOwner(int e) => _val(e);

  /// Celdas de la figura que tocan la arista.
  List<int> cellsOfEdge(int e) {
    final out = <int>[];
    if (e < horCount) {
      final r = e ~/ w, c = e % w;
      if (r - 1 >= 0 && mask[(r - 1) * w + c]) out.add((r - 1) * w + c);
      if (r < h && mask[r * w + c]) out.add(r * w + c);
    } else {
      final k = e - horCount;
      final r = k ~/ (w + 1), c = k % (w + 1);
      if (c - 1 >= 0 && mask[r * w + c - 1]) out.add(r * w + c - 1);
      if (c < w && mask[r * w + c]) out.add(r * w + c);
    }
    return out;
  }

  /// Las cuatro aristas de una celda: arriba, abajo, izquierda, derecha.
  List<int> edgesOfCell(int cell) {
    final r = cell ~/ w, c = cell % w;
    return [
      r * w + c,
      (r + 1) * w + c,
      horCount + r * (w + 1) + c,
      horCount + r * (w + 1) + c + 1,
    ];
  }

  int sides(int cell) {
    var n = 0;
    for (final e in edgesOfCell(cell)) {
      if (_val(e) != 0) n++;
    }
    return n;
  }

  bool get over => score1 + score2 == totalCells;

  List<int> freeEdges() => [
        for (final e in usable)
          if (_val(e) == 0) e
      ];

  /// Traza la raya. Devuelve cuántos cuadritos cerró (0, 1 o 2).
  int play(int e) {
    final p = turn;
    if (e < horCount) {
      hor[e] = p;
    } else {
      ver[e - horCount] = p;
    }
    var done = 0;
    for (final c in cellsOfEdge(e)) {
      if (owner[c] == 0 && sides(c) == 4) {
        owner[c] = p;
        done++;
      }
    }
    if (p == 1) {
      score1 += done;
    } else {
      score2 += done;
    }
    lastEdge = e;
    moveCount++;
    if (done == 0) turn = 3 - p;
    return done;
  }

  /// Deshace la última jugada (solo para la búsqueda de la IA, en orden inverso).
  void undo(int e, int done, int prevTurn) {
    if (done > 0) {
      for (final c in cellsOfEdge(e)) {
        if (owner[c] != 0) {
          owner[c] = 0;
        }
      }
      if (prevTurn == 1) {
        score1 -= done;
      } else {
        score2 -= done;
      }
    }
    if (e < horCount) {
      hor[e] = 0;
    } else {
      ver[e - horCount] = 0;
    }
    turn = prevTurn;
    moveCount--;
  }

  GalletaGame copy() {
    final g = GalletaGame(w, h, mask);
    for (var i = 0; i < hor.length; i++) {
      g.hor[i] = hor[i];
    }
    for (var i = 0; i < ver.length; i++) {
      g.ver[i] = ver[i];
    }
    for (var i = 0; i < owner.length; i++) {
      g.owner[i] = owner[i];
    }
    g.turn = turn;
    g.score1 = score1;
    g.score2 = score2;
    g.lastEdge = lastEdge;
    g.moveCount = moveCount;
    return g;
  }
}

// ---------------------------------------------------------------
// Inteligencia artificial
// ---------------------------------------------------------------

/// Aristas que cierran al menos un cuadrito ahora mismo.
List<int> _capturing(GalletaGame g) {
  final out = <int>[];
  for (final e in g.freeEdges()) {
    for (final c in g.cellsOfEdge(e)) {
      if (g.owner[c] == 0 && g.sides(c) == 3) {
        out.add(e);
        break;
      }
    }
  }
  return out;
}

int _gain(GalletaGame g, int e) {
  var n = 0;
  for (final c in g.cellsOfEdge(e)) {
    if (g.owner[c] == 0 && g.sides(c) == 3) n++;
  }
  return n;
}

bool _isSafe(GalletaGame g, int e) {
  for (final c in g.cellsOfEdge(e)) {
    if (g.owner[c] == 0 && g.sides(c) == 2) return false;
  }
  return true;
}

/// Cuántos cuadritos se llevaría el rival, tomando todo lo que pueda, tras trazar [e].
int _giveAway(GalletaGame g, int e) {
  final stack = <List<int>>[]; // [arista, cerrados, turno previo]
  final prevT = g.turn;
  stack.add([e, g.play(e), prevT]);
  var taken = 0;
  while (true) {
    final caps = _capturing(g);
    if (caps.isEmpty || g.over) break;
    final c = caps.first;
    final t = g.turn;
    final d = g.play(c);
    stack.add([c, d, t]);
    taken += d;
  }
  while (stack.isNotEmpty) {
    final s = stack.removeLast();
    g.undo(s[0], s[1], s[2]);
  }
  return taken;
}

class _Solver {
  final GalletaGame g;
  final List<int> free;
  final Map<int, int> memo = {};
  final Map<int, int> bitOf = {};
  _Solver(this.g) : free = g.freeEdges() {
    for (var i = 0; i < free.length; i++) {
      bitOf[free[i]] = i;
    }
  }

  // Mejor diferencia de cuadritos (para quien mueve) desde esta posición.
  int solve(int mask) {
    if (g.over) return 0;
    final key = mask * 2 + (g.turn - 1);
    final m = memo[key];
    if (m != null) return m;
    var best = -1000;
    for (final e in free) {
      final bit = 1 << bitOf[e]!;
      if (mask & bit != 0) continue;
      final t = g.turn;
      final d = g.play(e);
      final v = d > 0 ? d + solve(mask | bit) : -solve(mask | bit);
      g.undo(e, d, t);
      if (v > best) best = v;
    }
    memo[key] = best;
    return best;
  }

  int bestEdge() {
    var best = -1000;
    var bestE = free.first;
    for (final e in free) {
      final bit = 1 << bitOf[e]!;
      final t = g.turn;
      final d = g.play(e);
      final v = d > 0 ? d + solve(bit) : -solve(bit);
      g.undo(e, d, t);
      if (v > best) {
        best = v;
        bestE = e;
      }
    }
    return bestE;
  }
}

/// level 1 fácil, 2 medio, 3 difícil.
int chooseGalletaMove(GalletaGame g, int level, int seed) {
  final rng = Random(seed);
  final free = g.freeEdges();
  if (free.isEmpty) return -1;
  final caps = _capturing(g);

  if (level <= 1) {
    if (caps.isNotEmpty && rng.nextDouble() < 0.65) {
      return caps[rng.nextInt(caps.length)];
    }
    return free[rng.nextInt(free.length)];
  }

  // Difícil: en el final de la partida se calcula la jugada exacta.
  if (level >= 3 && free.length <= 14) {
    return _Solver(g.copy()).bestEdge();
  }

  if (caps.isNotEmpty) {
    caps.sort((a, b) => _gain(g, b).compareTo(_gain(g, a)));
    return caps.first;
  }
  final safe = [
    for (final e in free)
      if (_isSafe(g, e)) e
  ];
  if (safe.isNotEmpty) return safe[rng.nextInt(safe.length)];

  // Todas las jugadas regalan cuadritos: regala lo menos posible.
  var bestE = free.first;
  var bestN = 1 << 30;
  final shuffled = [...free]..shuffle(rng);
  for (final e in shuffled) {
    final n = _giveAway(g, e);
    if (n < bestN) {
      bestN = n;
      bestE = e;
    }
  }
  return bestE;
}

/// Para usar con compute(): args = [w, h, mask(0/1), hor, ver, owner, turn, level, seed].
int galletaAiIsolate(List<Object> a) {
  final w = a[0] as int, h = a[1] as int;
  final mask = [for (final x in (a[2] as List)) (x as int) == 1];
  final g = GalletaGame(w, h, mask);
  final hor = a[3] as List, ver = a[4] as List, own = a[5] as List;
  for (var i = 0; i < g.hor.length; i++) {
    g.hor[i] = hor[i] as int;
  }
  for (var i = 0; i < g.ver.length; i++) {
    g.ver[i] = ver[i] as int;
  }
  var s1 = 0, s2 = 0;
  for (var i = 0; i < g.owner.length; i++) {
    g.owner[i] = own[i] as int;
    if (g.owner[i] == 1) s1++;
    if (g.owner[i] == 2) s2++;
  }
  g.score1 = s1;
  g.score2 = s2;
  g.turn = a[6] as int;
  return chooseGalletaMove(g, a[7] as int, a[8] as int);
}
