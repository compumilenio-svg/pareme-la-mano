import 'dart:math';

/// Temática de imágenes (emojis grandes, sin marcas ni personajes con derechos).
class PairTheme {
  final String name;
  final String icon;
  final List<String> faces;
  const PairTheme(this.name, this.icon, this.faces);
}

const List<PairTheme> kPairThemes = [
  PairTheme('Animales', '🐶', [
    '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮',
    '🐷', '🐸', '🐵', '🐔', '🐧', '🐦', '🦆', '🦉', '🦄', '🐴', '🐝', '🦋',
    '🐢', '🐍', '🐙', '🦀', '🐠', '🐬', '🐳', '🦈', '🐘', '🦒', '🦓', '🐊',
  ]),
  PairTheme('Frutas y verduras', '🍎', [
    '🍎', '🍐', '🍊', '🍋', '🍌', '🍉', '🍇', '🍓', '🍒', '🍑', '🍍', '🥥',
    '🥝', '🍅', '🍆', '🥑', '🥦', '🥕', '🌽', '🥒', '🥬', '🥔', '🍄', '🍈',
    '🍏', '🥭', '🍠', '🌰', '🥜', '🧅',
  ]),
  PairTheme('Comida', '🍕', [
    '🍕', '🍔', '🍟', '🌭', '🍿', '🥓', '🥚', '🍳', '🥞', '🍞', '🥐', '🥖',
    '🧀', '🍗', '🍖', '🥩', '🌮', '🌯', '🍣', '🍤', '🍙', '🍚', '🍜', '🍝',
    '🍩', '🍪', '🎂', '🍰', '🍫', '🍬', '🍭', '🍦',
  ]),
  PairTheme('Deportes y juegos', '⚽', [
    '⚽', '🏀', '🏈', '⚾', '🎾', '🏐', '🏉', '🎱', '🏓', '🏸', '🥊', '🥋',
    '⛳', '🏹', '🎣', '🎿', '🏆', '🥇', '🎯', '🎳', '🎮', '🎲', '🧩', '🎸',
    '🎺', '🥁', '🎻', '🎤', '🎧', '🎨',
  ]),
  PairTheme('Transportes', '🚗', [
    '🚗', '🚕', '🚙', '🚌', '🚎', '🚓', '🚑', '🚒', '🚚', '🚜', '🛵', '🚲',
    '🚁', '🚀', '🛸', '🚤', '🚢', '🚂', '🚆', '🚇', '🚠', '🚡', '🛶', '🚛',
    '🚐', '🚔', '🚖', '🚘', '🚃', '🚞',
  ]),
  PairTheme('Naturaleza', '🌻', [
    '🌞', '🌙', '⭐', '🌈', '🔥', '💧', '🌊', '🌋', '🌵', '🌴', '🌲', '🌳',
    '🌻', '🌹', '🌷', '🌺', '🌼', '🍀', '🍁', '🍂', '🌾', '🌍', '🌎', '🌏',
    '🌟', '⚡', '🌸', '💐', '🌿', '🌱', '🍃',
  ]),
  PairTheme('Caras y fantasía', '🤩', [
    '😀', '😂', '😍', '😎', '🤩', '😴', '🤔', '😱', '🥳', '😡', '🤠', '🤖',
    '👻', '👽', '💀', '🎃', '😈', '👶', '🧙', '🧛', '🧟', '🧜', '🧚', '🤡',
    '👸', '🤴', '🎅', '🦸', '🦹', '🐲',
  ]),
];

/// Índice [mixed] = mezcla de todas las temáticas.
const int kMixedTheme = -1;

List<String> poolFor(int theme) {
  if (theme >= 0 && theme < kPairThemes.length) {
    return kPairThemes[theme].faces.toSet().toList();
  }
  return [for (final t in kPairThemes) ...t.faces].toSet().toList();
}

/// Niveles: pares por nivel y mínimo de jugadores permitido.
const List<int> kLevelPairs = [10, 20, 30];
const List<String> kLevelNames = ['Básico', 'Medio', 'Alto'];

class PairsGame {
  final int players;
  final List<String> faces; // una por carta
  final List<int> owner; // -1 sin descubrir, o el asiento que la ganó
  List<int> open; // cartas volteadas ahora (0..2)
  int turn;
  final List<int> scores;
  int seq;
  int moves; // intentos (cada dos cartas volteadas)

  PairsGame._(this.players, this.faces, this.owner, this.open, this.turn,
      this.scores, this.seq, this.moves);

  factory PairsGame.create(int pairs, int theme, int players, {Random? rng}) {
    final r = rng ?? Random();
    final pool = poolFor(theme)..shuffle(r);
    final chosen = pool.take(pairs).toList();
    final cards = [...chosen, ...chosen]..shuffle(r);
    return PairsGame._(players, cards, List.filled(cards.length, -1), [], 0,
        List.filled(players, 0), 0, 0);
  }

  factory PairsGame.fromMap(Map<String, dynamic> m) => PairsGame._(
        (m['players'] as num).toInt(),
        List<String>.from(m['faces'] as List),
        [for (final x in (m['owner'] as List)) (x as num).toInt()],
        [for (final x in ((m['open'] as List?) ?? const [])) (x as num).toInt()],
        (m['turn'] as num).toInt(),
        [for (final x in (m['scores'] as List)) (x as num).toInt()],
        (m['seq'] as num).toInt(),
        (m['moves'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'players': players,
        'faces': faces,
        'owner': owner,
        'open': open,
        'turn': turn,
        'scores': scores,
        'seq': seq,
        'moves': moves,
      };

  int get pairs => faces.length ~/ 2;
  bool get finished => owner.every((o) => o >= 0);
  bool get needsResolve => open.length == 2;

  bool isUp(int i) => open.contains(i) || owner[i] >= 0;

  bool canFlip(int i) =>
      !finished && open.length < 2 && owner[i] < 0 && !open.contains(i);

  void flip(int i) {
    if (!canFlip(i)) return;
    open = [...open, i];
    seq++;
  }

  /// Cierra el intento. true si hubo pareja (el mismo jugador sigue).
  bool resolve() {
    if (open.length != 2) return false;
    final a = open[0], b = open[1];
    final match = faces[a] == faces[b];
    if (match) {
      owner[a] = turn;
      owner[b] = turn;
      scores[turn]++;
    } else {
      turn = (turn + 1) % players;
    }
    open = [];
    seq++;
    moves++;
    return match;
  }

  /// Asientos ganadores (puede haber empate).
  List<int> get winners {
    final best = scores.reduce(max);
    return [for (var i = 0; i < players; i++) if (scores[i] == best) i];
  }
}

/// PC con memoria imperfecta: recuerda cada carta vista con probabilidad [skill].
class PairsBot {
  final Random rng;
  final double skill;
  final Map<int, String> known = {};
  final Set<int> _seen = {};
  PairsBot({Random? rng, this.skill = 0.8}) : rng = rng ?? Random();

  void reset() {
    known.clear();
    _seen.clear();
  }

  void observe(PairsGame g) {
    for (final i in g.open) {
      if (_seen.add(i) && rng.nextDouble() < skill) known[i] = g.faces[i];
    }
    known.removeWhere((i, _) => g.owner[i] >= 0);
  }

  int pickFirst(PairsGame g) {
    final byFace = <String, List<int>>{};
    known.forEach((i, f) {
      if (g.owner[i] < 0) byFace.putIfAbsent(f, () => []).add(i);
    });
    for (final l in byFace.values) {
      if (l.length >= 2) return l.first;
    }
    final free = [for (var i = 0; i < g.faces.length; i++) if (g.owner[i] < 0) i];
    final unknown = free.where((i) => !known.containsKey(i)).toList();
    final list = unknown.isNotEmpty ? unknown : free;
    return list[rng.nextInt(list.length)];
  }

  int pickSecond(PairsGame g, int first) {
    final face = g.faces[first];
    for (final e in known.entries) {
      if (e.key != first && g.owner[e.key] < 0 && e.value == face) return e.key;
    }
    final free = [
      for (var i = 0; i < g.faces.length; i++) if (g.owner[i] < 0 && i != first) i
    ];
    final unknown = free.where((i) => !known.containsKey(i)).toList();
    final list = unknown.isNotEmpty ? unknown : free;
    return list[rng.nextInt(list.length)];
  }
}
