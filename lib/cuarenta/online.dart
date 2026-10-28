import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../game_service.dart';
import 'bot.dart';
import 'cuarenta_page.dart' show rulesText;
import 'engine.dart';
import 'card_fx.dart';
import 'table_ui.dart';
import '../sfx.dart';
import '../music.dart';

// Orden de asientos al repartir humanos: en 4 jugadores el segundo humano
// queda de compañero (asiento 2) del anfitrión (asiento 0).
const _seatOrder4 = [0, 2, 1, 3];
const _seatOrder2 = [0, 1];

class CuarentaOnline {
  static Future<String> create(
      String playerName, int numPlayers, bool grande) async {
    svc.name = playerName;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'cuarenta',
      'hostId': svc.uid,
      'status': 'lobby',
      'numPlayers': numPlayers,
      'grande': grande,
      'state': '',
      'log': <String>[],
      'wins': [0, 0],
      'matchOver': false,
      'seats': <String, String>{},
      'seatNames': <String>[],
      'teamNames': <String>[],
      'createdAt': nowMs(),
    });
    await svc.playersRef(code).doc(svc.uid).set(_player(playerName));
    return code;
  }

  static Map<String, dynamic> _player(String name) => {
        'name': name,
        'joinedAt': nowMs(),
        'move': {'n': 0, 'card': 0, 'cap': <int>[]},
      };

  /// null si todo bien, o un mensaje de error.
  static Future<String?> join(String code, String playerName) async {
    svc.name = playerName;
    code = code.trim().toUpperCase();
    final snap = await svc.roomRef(code).get();
    if (!snap.exists || snap.data()!['game'] != 'cuarenta') {
      return 'No existe una sala de Cuarenta con ese código.';
    }
    final existing = await svc.playersRef(code).doc(svc.uid).get();
    if (existing.exists) return null;
    if (snap.data()!['status'] != 'lobby') return 'La partida ya comenzó.';
    final count = (await svc.playersRef(code).get()).size;
    if (count >= (snap.data()!['numPlayers'] as int)) {
      return 'La sala está llena.';
    }
    await svc.playersRef(code).doc(svc.uid).set(_player(playerName));
    return null;
  }
}

class CuarentaRoomPage extends StatefulWidget {
  final String code;
  const CuarentaRoomPage({super.key, required this.code});

  @override
  State<CuarentaRoomPage> createState() => _CuarentaRoomPageState();
}

class _CuarentaRoomPageState extends State<CuarentaRoomPage>
    with CardFx<CuarentaRoomPage> {
  String get code => widget.code;

  // Solo el anfitrión usa esto (partida autoritativa).
  CuarentaGame? hostGame;
  final Map<String, int> applied = {}; // uid -> último movimiento aplicado
  final List<String> log = [];
  int wins0 = 0;
  int wins1 = 0;
  Timer? botTimer;
  bool _endSounded = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? playersSub;
  Map<String, dynamic>? room;

  bool get isHost => room?['hostId'] == svc.uid;

  @override
  void initState() {
    super.initState();
    playersSub = svc.playersStream(code).listen(_onPlayers);
    Ambient.start('cuarenta_ambiente');
  }

  @override
  void dispose() {
    botTimer?.cancel();
    playersSub?.cancel();
    Ambient.stop();
    super.dispose();
  }

  // ------------------ Anfitrión ------------------

  Map<String, String> _seats() =>
      Map<String, String>.from(room?['seats'] ?? {}); // asiento -> uid

  bool _isHuman(int seat) => _seats().containsKey('$seat');

  Future<void> _start(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> players) async {
    final n = room!['numPlayers'] as int;
    final order = n == 4 ? _seatOrder4 : _seatOrder2;
    final sorted = [...players]..sort((a, b) =>
        (a['joinedAt'] as int).compareTo(b['joinedAt'] as int));
    final seats = <String, String>{};
    final names = List<String>.filled(n, '');
    for (var i = 0; i < sorted.length && i < n; i++) {
      seats['${order[i]}'] = sorted[i].id;
      names[order[i]] = sorted[i]['name'] as String;
    }
    var botN = 1;
    for (var s = 0; s < n; s++) {
      if (names[s].isEmpty) names[s] = 'Bot ${botN++}';
    }
    final teamNames = n == 4
        ? ['${names[0]} y ${names[2]}', '${names[1]} y ${names[3]}']
        : [names[0], names[1]];
    // Marca como ya vistos los movimientos anteriores.
    for (final p in players) {
      applied[p.id] = (p['move']?['n'] as int?) ?? 0;
    }
    room = {...room!, 'seats': seats};
    final g = CuarentaGame(n, names, teamNames);
    hostGame = g;
    log
      ..clear()
      ..addAll(g.events);
    wins0 = 0;
    wins1 = 0;
    await svc.roomRef(code).update({
      'seats': seats,
      'seatNames': names,
      'teamNames': teamNames,
      'wins': [0, 0],
      'matchOver': false,
    });
    await _publish();
    _scheduleBot();
  }

  Future<void> _publish() {
    final g = hostGame!;
    final matchOver = g.winnerTeam != null &&
        (!(room!['grande'] as bool) || wins0 >= 2 || wins1 >= 2);
    return svc.roomRef(code).update({
      'state': jsonEncode(g.toJson()),
      'log': log.length > 6 ? log.sublist(log.length - 6) : log,
      'status': g.winnerTeam != null ? 'chica_end' : 'playing',
      'wins': [wins0, wins1],
      'matchOver': matchOver,
    });
  }

  void _applyHostMove(Move m) {
    final g = hostGame!;
    final seat = g.current;
    final names = g.seatNames;
    final desc = m.isCapture
        ? '${names[seat]} jugó ${m.card.label} y levantó ${m.captured.map((c) => c.label).join(' + ')}'
        : '${names[seat]} dejó ${m.card.label}';
    final ev = g.play(m);
    log.add(desc);
    log.addAll(ev);
    if (g.winnerTeam != null) {
      if (g.winnerTeam == 0) {
        wins0++;
      } else {
        wins1++;
      }
    }
    _publish();
    _scheduleBot();
  }

  void _scheduleBot() {
    final g = hostGame;
    botTimer?.cancel();
    if (g == null || g.winnerTeam != null || _isHuman(g.current)) return;
    botTimer = Timer(const Duration(milliseconds: 1800), () {
      final g2 = hostGame;
      if (!mounted || g2 == null || g2.winnerTeam != null) return;
      if (_isHuman(g2.current)) return;
      _applyHostMove(chooseBotMove(g2));
    });
  }

  Move? _match(CuarentaGame g, int cardId, List<int> cap) {
    for (final m in g.legalMoves()) {
      if (m.card.id == cardId &&
          m.captured.length == cap.length &&
          m.captured.every((c) => cap.contains(c.id))) {
        return m;
      }
    }
    return null;
  }

  void _onPlayers(QuerySnapshot<Map<String, dynamic>> q) {
    final g = hostGame;
    if (!isHost || g == null || g.winnerTeam != null) return;
    final seats = _seats();
    for (final d in q.docs) {
      final mv = d.data()['move'];
      if (mv == null) continue;
      final n = (mv['n'] as int?) ?? 0;
      if (n <= (applied[d.id] ?? 0)) continue;
      final seatKey = seats.entries
          .where((e) => e.value == d.id)
          .map((e) => e.key)
          .toList();
      if (seatKey.isEmpty) continue;
      if (int.parse(seatKey.first) != g.current) continue;
      applied[d.id] = n;
      final m = _match(g, mv['card'] as int,
          List<int>.from((mv['cap'] as List?) ?? const []));
      if (m != null) {
        _applyHostMove(m);
        return;
      }
    }
  }

  Future<void> _nextChica() async {
    final g = hostGame!;
    g.resetChica();
    log
      ..clear()
      ..addAll(g.events);
    await _publish();
    _scheduleBot();
  }

  // ------------------ Jugador ------------------

  int _mySeat() {
    for (final e in _seats().entries) {
      if (e.value == svc.uid) return int.parse(e.key);
    }
    return -1;
  }

  CuarentaGame? _viewGame() {
    final r = room!;
    final st = r['state'] as String? ?? '';
    if (st.isEmpty) return null;
    return CuarentaGame.fromJson(
      r['numPlayers'] as int,
      List<String>.from(r['seatNames']),
      List<String>.from(r['teamNames']),
      jsonDecode(st) as Map<String, dynamic>,
    );
  }

  Future<void> _onTapCard(CuarentaGame g, int seat, PCard c) async {
    if (g.winnerTeam != null || g.current != seat) return;
    final moves = g.movesForCard(c);
    Move? chosen;
    if (moves.length == 1) {
      chosen = moves.first;
    } else {
      chosen = await showModalBottomSheet<Move>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in moves)
                ListTile(
                  title: Text(m.isCapture
                      ? 'Levantar: ${m.captured.map((x) => x.label).join(' + ')}${g.isCaida(m) ? '  ¡caída!' : ''}'
                      : 'Dejar ${c.label} en la mesa'),
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
          ),
        ),
      );
    }
    if (chosen == null) return;
    await svc.playersRef(code).doc(svc.uid).update({
      'move': {
        'n': nowMs(),
        'card': chosen.card.id,
        'cap': [for (final x in chosen.captured) x.id],
      }
    });
  }

  Widget _cardView(PCard c, {VoidCallback? onTap}) {
    return Opacity(
      opacity: fxHidden(c.id) ? 0 : 1,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        key: fxCardKey(c.id),
        width: 54,
        height: 78,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black54),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          c.label,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: c.isRed ? Colors.red : Colors.black,
          ),
        ),
      ),
    ),
    );
  }

  // ------------------ Pantallas ------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Cuarenta · Sala $code'),
        actions: [
          const MusicButton(),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Reglas'),
                content: const SingleChildScrollView(child: Text(rulesText)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cerrar'))
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: svc.roomStream(code),
          builder: (context, snap) {
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: CircularProgressIndicator());
            }
            room = snap.data!.data()!;
            if (room!['status'] == 'lobby') return _lobby();
            return _game();
          },
        ),
      ),
    );
  }

  Widget _lobby() {
    final n = room!['numPlayers'] as int;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.playersStream(code),
      builder: (context, snap) {
        final players = snap.data?.docs ?? [];
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Text('Comparte este código:'),
              Text(code,
                  style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 6)),
              const SizedBox(height: 8),
              Text(
                  '${n == 4 ? 'En parejas (4)' : '2 jugadores'} · ${(room!['grande'] as bool) ? 'Grande (mejor de 3)' : 'Chica (a 40)'}'),
              if (n == 4)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                      'El segundo en entrar es el compañero del anfitrión. Los asientos libres los juegan bots.',
                      textAlign: TextAlign.center),
                )
              else
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text('Si nadie más entra, juegas contra un bot.'),
                ),
              const SizedBox(height: 16),
              Text('Jugadores (${players.length}/$n)',
                  style: Theme.of(context).textTheme.titleMedium),
              Expanded(
                child: ListView(
                  children: [
                    for (final p in players)
                      ListTile(
                        leading: const Icon(Icons.person),
                        title: Text(p.data()['name'] ?? ''),
                        trailing: p.id == room!['hostId']
                            ? const Chip(label: Text('Anfitrión'))
                            : null,
                      ),
                  ],
                ),
              ),
              if (isHost)
                FilledButton(
                  onPressed: players.isNotEmpty ? () => _start(players) : null,
                  child: const Text('Iniciar partida'),
                )
              else
                const Text('Esperando que el anfitrión inicie...'),
            ],
          ),
        );
      },
    );
  }

  Widget _game() {
    final g = _viewGame();
    if (g == null) return const Center(child: CircularProgressIndicator());
    final mySeat = _mySeat();
    if (mySeat < 0) {
      return const Center(child: Text('No estás en esta partida.'));
    }
    fxSync(g, mySeat);
    if (room!['status'] == 'chica_end') {
      if (!_endSounded) {
        _endSounded = true;
        Sfx.play(g.winnerTeam == g.teamOf(mySeat) ? 'win' : 'lose', delayMs: 900);
      }
    } else {
      _endSounded = false;
    }
    final names = g.seatNames;
    final myTeam = g.teamOf(mySeat);
    final status = room!['status'];
    final wins = List<int>.from(room!['wins']);
    final grande = room!['grande'] as bool;
    final myTurn = g.current == mySeat && status == 'playing';
    final log = List<String>.from(room!['log'] ?? []);
    final others = [
      for (var i = 1; i < g.n; i++) (mySeat + i) % g.n,
    ];

    return Stack(
      key: fxStackKey,
      children: [
        Positioned.fill(
          child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('Nosotros: ${g.scores[myTeam]}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              if (grande) Text('Chicas ${wins[myTeam]} - ${wins[1 - myTeam]}'),
              Text('Ellos: ${g.scores[1 - myTeam]}',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        Expanded(
          child: WoodTable(
            others: [
              for (final s in others)
                SeatSpec(
                    fxSeatKey(s),
                    '${names[s]}${g.teamOf(s) == myTeam ? ' (compañero)' : ''}',
                    g.hands[s].length,
                    g.current == s),
            ],
            center: status == 'chica_end'
                ? _chicaEnd(g, myTeam, wins)
                : g.table.isEmpty
                    ? const Text('Mesa vacía')
                    : Wrap(
                        alignment: WrapAlignment.center,
                        children: [for (final c in g.table) _cardView(c)],
                      ),
          ),
        ),
        Container(
          width: double.infinity,
          color: Colors.black12,
          padding: const EdgeInsets.all(8),
          child: Text(
            log.length <= 4
                ? log.join('\n')
                : log.sublist(log.length - 4).join('\n'),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(myTurn ? 'Tu turno' : 'Turno de ${names[g.current]}...'),
        ),
        Wrap(
          key: fxHandKey,
          alignment: WrapAlignment.center,
          children: [
            for (final c in g.hands[mySeat])
              _cardView(c,
                  onTap: myTurn ? () => _onTapCard(g, mySeat, c) : null),
          ],
        ),
        const SizedBox(height: 12),
      ],
    ),
        ),
        Positioned.fill(child: fxOverlay()),
      ],
    );
  }

  Widget _chicaEnd(CuarentaGame g, int myTeam, List<int> wins) {
    final w = g.winnerTeam!;
    final matchOver = room!['matchOver'] as bool;
    final grande = room!['grande'] as bool;
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(16),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.black87),
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(w == myTeam ? '¡Ganaron ustedes!' : 'Ganaron los rivales',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(grande
              ? 'Chicas: Nosotros ${wins[myTeam]} - Ellos ${wins[1 - myTeam]}'
              : 'Marcador final: ${g.scores[myTeam]} - ${g.scores[1 - myTeam]}'),
          const SizedBox(height: 16),
          if (matchOver)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Salir'),
            )
          else if (isHost)
            FilledButton(
              onPressed: _nextChica,
              child: const Text('Siguiente chica'),
            )
          else
            const Text('Esperando al anfitrión...'),
        ],
      ),
      ),
    );
  }
}
