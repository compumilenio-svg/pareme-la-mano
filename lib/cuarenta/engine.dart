import 'dart:math';

// ---------------------------------------------------------------
// Reglas configurables: si tu versión del 40 difiere, cambia aquí.
// ---------------------------------------------------------------
const int winScore = 40; // puntos para ganar una chica
const int pointsRonda = 2; // trío de entrada en el reparto
const int pointsFourOfAKind = 10; // cuatro iguales en el reparto
const int pointsCaida = 2;
const int pointsLimpia = 2;
const int pointsCaidaLimpia = 2; // caída + limpia en la misma jugada
const int cartonMinCards = 20; // cartas para cobrar cartón
const int cartonBasePoints = 6; // puntos con 20 cartas (+1 por carta extra)
const int noCartonFrom = 30; // con 30 puntos o más ya no se cobra cartón
// Sumas: una carta tuya levanta DOS cartas de la mesa que sumen su valor.
// (El código genera solo combinaciones de 2 cartas.)

const List<String> suitSymbols = ['♠', '♥', '♦', '♣'];

/// Carta del 40. rank: 1..7 = A..7, 8 = J, 9 = Q, 10 = K.
/// Orden de la escalera: A,2,3,4,5,6,7,J,Q,K.
class PCard {
  final int rank;
  final int suit; // 0 ♠, 1 ♥, 2 ♦, 3 ♣
  const PCard(this.rank, this.suit);

  int get id => suit * 10 + rank;
  static PCard fromId(int id) {
    final suit = (id - 1) ~/ 10;
    return PCard(id - suit * 10, suit);
  }
  bool get summable => rank <= 7; // J, Q, K no se suman
  bool get isRed => suit == 1 || suit == 2;

  String get rankLabel {
    switch (rank) {
      case 1:
        return 'A';
      case 8:
        return 'J';
      case 9:
        return 'Q';
      case 10:
        return 'K';
      default:
        return '$rank';
    }
  }

  String get label => '$rankLabel${suitSymbols[suit]}';

  @override
  bool operator ==(Object other) => other is PCard && other.id == id;

  @override
  int get hashCode => id;
}

class Move {
  final PCard card;
  final List<PCard> captured; // vacío = dejar la carta en la mesa
  final bool isPareo;
  const Move(this.card, this.captured, {this.isPareo = false});

  bool get isCapture => captured.isNotEmpty;
}

int pointsForCards(int n) {
  var p = cartonBasePoints + (n - cartonMinCards);
  if (p.isOdd) p++; // impar sube al par superior
  return p;
}

class CuarentaGame {
  final int n; // 2 jugadores, o 4 en parejas (asientos 0 y 2 contra 1 y 3)
  final List<String> seatNames;
  final List<String> teamNames;
  final Random rng;

  List<int> scores = [0, 0];
  int dealer = 0;
  int current = 0;
  List<List<PCard>> hands = [];
  List<PCard> table = [];
  List<List<PCard>> won = [[], []];
  List<PCard> deck = [];
  PCard? lastPlaced; // última carta dejada en la mesa (para la caída)
  bool firstOfDeal = true;
  int? winnerTeam;
  final List<String> events = [];

  CuarentaGame(this.n, this.seatNames, this.teamNames, {Random? random})
      : rng = random ?? Random() {
    dealer = rng.nextInt(n);
    _newHand();
  }

  CuarentaGame._raw(this.n, this.seatNames, this.teamNames) : rng = Random();

  /// Reconstruye una partida desde el estado publicado por el anfitrión.
  factory CuarentaGame.fromJson(int n, List<String> seatNames,
      List<String> teamNames, Map<String, dynamic> j) {
    List<PCard> cards(dynamic l) =>
        [for (final i in (l as List)) PCard.fromId(i as int)];
    final g = CuarentaGame._raw(n, seatNames, teamNames);
    g.scores = List<int>.from(j['scores']);
    g.dealer = j['dealer'] as int;
    g.current = j['current'] as int;
    g.hands = [for (final h in (j['hands'] as List)) cards(h)];
    g.table = cards(j['table']);
    g.won = [for (final w in (j['won'] as List)) cards(w)];
    g.deck = cards(j['deck']);
    g.lastPlaced = j['last'] == null ? null : PCard.fromId(j['last'] as int);
    g.firstOfDeal = j['first'] as bool;
    g.winnerTeam = j['winner'] as int?;
    return g;
  }

  Map<String, dynamic> toJson() => {
        'scores': scores,
        'dealer': dealer,
        'current': current,
        'hands': [
          for (final h in hands) [for (final c in h) c.id]
        ],
        'table': [for (final c in table) c.id],
        'won': [
          for (final w in won) [for (final c in w) c.id]
        ],
        'deck': [for (final c in deck) c.id],
        'last': lastPlaced?.id,
        'first': firstOfDeal,
        'winner': winnerTeam,
      };

  int teamOf(int seat) => n == 4 ? seat % 2 : seat;

  void resetChica() {
    scores = [0, 0];
    winnerTeam = null;
    dealer = (dealer + 1) % n;
    events.clear();
    _newHand();
  }

  void _newHand() {
    deck = [
      for (var s = 0; s < 4; s++)
        for (var r = 1; r <= 10; r++) PCard(r, s)
    ]..shuffle(rng);
    table = [];
    won = [[], []];
    lastPlaced = null;
    hands = List.generate(n, (_) => <PCard>[]);
    _deal();
  }

  void _deal() {
    for (var i = 0; i < n; i++) {
      final seat = (dealer + 1 + i) % n; // se reparte desde la izquierda
      hands[seat] = deck.sublist(0, 5);
      deck.removeRange(0, 5);
    }
    current = (dealer + 1) % n; // juega el de la derecha del repartidor
    firstOfDeal = true;
    _checkRondas();
  }

  void _checkRondas() {
    for (var seat = 0; seat < n; seat++) {
      if (winnerTeam != null) return;
      final counts = <int, int>{};
      for (final c in hands[seat]) {
        counts[c.rank] = (counts[c.rank] ?? 0) + 1;
      }
      final team = teamOf(seat);
      if (counts.values.any((v) => v == 4)) {
        _addPoints(team, pointsFourOfAKind,
            'por 4 cartas iguales de ${seatNames[seat]}');
      } else if (counts.values.any((v) => v == 3)) {
        _addPoints(team, pointsRonda, 'por trío de entrada de ${seatNames[seat]}');
      }
    }
  }

  void _addPoints(int team, int pts, String why) {
    scores[team] += pts;
    events.add('${teamNames[team]} +$pts $why');
    if (scores[team] >= winScore && winnerTeam == null) {
      winnerTeam = team;
    }
  }

  // ---------------- Jugadas posibles ----------------

  List<PCard> _withStair(int rank, List<PCard> base) {
    final result = [...base];
    var next = rank + 1;
    while (next <= 10) {
      final nx =
          table.where((c) => c.rank == next && !result.contains(c)).toList();
      if (nx.isEmpty) break;
      result.addAll(nx);
      next++;
    }
    return result;
  }

  List<Move> _captureOptions(PCard card) {
    final res = <Move>[];
    final same = table.where((c) => c.rank == card.rank).toList();
    if (same.isNotEmpty) {
      res.add(Move(card, _withStair(card.rank, same), isPareo: true));
    }
    if (card.summable) {
      final cand =
          table.where((c) => c.summable && c.rank < card.rank).toList();
      final seen = <String>{};
      for (var i = 0; i < cand.length; i++) {
        for (var j = i + 1; j < cand.length; j++) {
          if (cand[i].rank + cand[j].rank == card.rank) {
            final ranks = [cand[i].rank, cand[j].rank]..sort();
            if (seen.add(ranks.join('-'))) {
              res.add(Move(card, _withStair(card.rank, [cand[i], cand[j]])));
            }
          }
        }
      }
    }
    return res;
  }

  /// Primero va "dejar la carta en la mesa", luego las formas de levantar.
  List<Move> movesForCard(PCard card) =>
      [Move(card, const []), ..._captureOptions(card)];

  List<Move> legalMoves() =>
      [for (final c in hands[current]) ...movesForCard(c)];

  bool isCaida(Move m) =>
      m.isPareo &&
      !firstOfDeal &&
      lastPlaced != null &&
      lastPlaced!.rank == m.card.rank &&
      m.captured.contains(lastPlaced);

  int unseenCopies(int rank, int seat) {
    var seen = hands[seat].where((c) => c.rank == rank).length;
    seen += table.where((c) => c.rank == rank).length;
    for (final w in won) {
      seen += w.where((c) => c.rank == rank).length;
    }
    return max(0, 4 - seen);
  }

  // ---------------- Jugar ----------------

  /// Aplica la jugada del jugador actual y devuelve los eventos de puntos.
  List<String> play(Move m) {
    events.clear();
    if (winnerTeam != null) return events;
    final seat = current;
    final team = teamOf(seat);
    hands[seat].remove(m.card);

    if (!m.isCapture) {
      table.add(m.card);
      lastPlaced = m.card;
    } else {
      final caida = isCaida(m);
      for (final c in m.captured) {
        table.remove(c);
      }
      won[team]
        ..addAll(m.captured)
        ..add(m.card);
      lastPlaced = null;
      final limpia = table.isEmpty;
      if (caida && limpia) {
        _addPoints(team, pointsCaidaLimpia, 'por caída y limpia');
      } else if (caida) {
        _addPoints(team, pointsCaida, 'por caída');
      } else if (limpia) {
        _addPoints(team, pointsLimpia, 'por limpia');
      }
    }
    if (winnerTeam != null) return events;

    current = (seat + 1) % n;
    firstOfDeal = false;
    if (hands.every((h) => h.isEmpty)) {
      if (deck.isNotEmpty) {
        _deal();
      } else {
        _endHand();
      }
    }
    return events;
  }

  void _endHand() {
    final c0 = won[0].length;
    final c1 = won[1].length;
    events.add('Fin de la mano: ${teamNames[0]} $c0 cartas, ${teamNames[1]} $c1 cartas.');
    int? cartonTeam;
    var pts = 0;
    if (c0 >= cartonMinCards && c1 >= cartonMinCards) {
      cartonTeam = 1 - teamOf(dealer); // empate en 20: cobra quien no reparte
      pts = cartonBasePoints;
    } else if (c0 >= cartonMinCards) {
      cartonTeam = 0;
      pts = pointsForCards(c0);
    } else if (c1 >= cartonMinCards) {
      cartonTeam = 1;
      pts = pointsForCards(c1);
    }
    if (cartonTeam != null) {
      if (scores[cartonTeam] >= noCartonFrom) {
        events.add(
            '${teamNames[cartonTeam]} ya tiene $noCartonFrom o más: no cobra cartón.');
      } else {
        _addPoints(cartonTeam, pts, 'por cartón');
      }
    }
    if (winnerTeam == null) {
      dealer = (dealer + 1) % n;
      _newHand();
      events.add('Nueva mano.');
    }
  }
}
