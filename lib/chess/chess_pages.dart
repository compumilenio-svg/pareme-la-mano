import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../game_service.dart';
import 'board3d.dart';
import '../sfx.dart';
import 'countries.dart';
import 'engine.dart';

// ======================================================================
// Servicio en línea (Firestore)
// ======================================================================

class ChessOnline {
  static Future<String> create(String playerName, String country) async {
    svc.name = playerName;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'chess',
      'hostId': svc.uid,
      'hostName': playerName,
      'hostCountry': country,
      'guestId': '',
      'guestName': '',
      'guestCountry': country == 'peru' ? 'inglaterra' : 'peru',
      'status': 'lobby',
      'fen': ChessState.startFen,
      'moveN': 0,
      'last': {'from': -1, 'to': -1, 'promo': 0},
      'result': '',
      'reason': '',
      'createdAt': nowMs(),
    });
    return code;
  }

  /// null si todo bien, o un mensaje de error.
  static Future<String?> join(
      String code, String playerName, String country) async {
    svc.name = playerName;
    code = code.trim().toUpperCase();
    final ref = svc.roomRef(code);
    String? err;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()!['game'] != 'chess') {
        err = 'No existe una sala de ajedrez con ese código.';
        return;
      }
      final d = snap.data()!;
      if (d['hostId'] == svc.uid || d['guestId'] == svc.uid) return; // reingreso
      if ((d['guestId'] as String).isNotEmpty) {
        err = 'La sala ya tiene dos jugadores.';
        return;
      }
      tx.update(ref, {
        'guestId': svc.uid,
        'guestName': playerName,
        'guestCountry': country,
        'status': 'playing',
      });
    });
    return err;
  }

  static Future<bool> sendMove(String code, ChessMove m, String fen,
      int expectedN, String result) async {
    final ref = svc.roomRef(code);
    var ok = false;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (snap.data()?['moveN'] != expectedN) return;
      tx.update(ref, {
        'fen': fen,
        'moveN': expectedN + 1,
        'last': {'from': m.from, 'to': m.to, 'promo': m.promo},
        'result': result,
        'reason': result.isEmpty ? '' : 'end',
        'status': result.isEmpty ? 'playing' : 'finished',
      });
      ok = true;
    });
    return ok;
  }

  static Future<void> resign(String code, bool iAmWhite) =>
      svc.roomRef(code).update({
        'result': iAmWhite ? 'b' : 'w',
        'reason': 'resign',
        'status': 'finished',
      });
}

// ======================================================================
// Menú del ajedrez
// ======================================================================

class ChessMenuPage extends StatefulWidget {
  const ChessMenuPage({super.key});

  @override
  State<ChessMenuPage> createState() => _ChessMenuPageState();
}

class _ChessMenuPageState extends State<ChessMenuPage> {
  ChessCountry mine = chessCountries[0];
  ChessCountry rival = chessCountries[5];
  int level = 2;
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String? error;
  bool loading = false;

  Future<void> _create() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final code = await ChessOnline.create(name, mine.id);
      _openRoom(code);
    } catch (e) {
      setState(() => error = 'No se pudo crear la sala: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _join() async {
    final name = nameCtrl.text.trim();
    final code = codeCtrl.text.trim().toUpperCase();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    if (code.length != 5) {
      return setState(() => error = 'El código tiene 5 caracteres.');
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final err = await ChessOnline.join(code, name, mine.id);
      if (err != null) {
        setState(() => error = err);
      } else {
        _openRoom(code);
      }
    } catch (e) {
      setState(() => error = 'No se pudo entrar: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _openRoom(String code) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChessMatchPage(roomCode: code)));
  }

  Widget _picker(ChessCountry selected, ValueChanged<ChessCountry> onChanged) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in chessCountries)
          InkWell(
            onTap: () => onChanged(c),
            child: Container(
              width: 92,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    width: selected.id == c.id ? 3 : 1,
                    color: selected.id == c.id
                        ? Colors.deepOrange
                        : Colors.black26),
                color: selected.id == c.id
                    ? Colors.deepOrange.withOpacity(0.08)
                    : null,
              ),
              child: Column(
                children: [
                  SizedBox(
                    height: 70,
                    child: Image.asset(c.asset(pKing), fit: BoxFit.contain),
                  ),
                  const SizedBox(height: 4),
                  Text(c.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajedrez de naciones')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Tu nación', style: t.titleMedium),
            const SizedBox(height: 8),
            _picker(mine, (c) => setState(() => mine = c)),
            const Divider(height: 36),
            Text('Contra la computadora', style: t.titleLarge),
            const SizedBox(height: 8),
            Text('Nación del rival', style: t.titleMedium),
            const SizedBox(height: 8),
            _picker(rival, (c) => setState(() => rival = c)),
            const SizedBox(height: 12),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Fácil')),
                ButtonSegment(value: 2, label: Text('Medio')),
                ButtonSegment(value: 3, label: Text('Difícil')),
              ],
              selected: {level},
              onSelectionChanged: (s) => setState(() => level = s.first),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ChessMatchPage(
                      myCountry: mine, rivalCountry: rival, aiLevel: level))),
              child: const Text('Jugar contra la computadora'),
            ),
            const Divider(height: 36),
            Text('En línea con otra persona', style: t.titleLarge),
            const SizedBox(height: 4),
            const Text(
                'Quien crea la sala juega con las blancas. Cada jugador usa la nación elegida arriba.'),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Tu nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: loading ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('Crear sala'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              maxLength: 5,
              decoration: const InputDecoration(
                  labelText: 'Código de sala', border: OutlineInputBorder()),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : _join,
              icon: const Icon(Icons.login),
              label: const Text('Unirme a una sala'),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            if (loading)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Partida (contra la computadora o en línea)
// ======================================================================

class ChessMatchPage extends StatefulWidget {
  final String? roomCode; // en línea
  final ChessCountry? myCountry; // contra la computadora
  final ChessCountry? rivalCountry;
  final int aiLevel;
  const ChessMatchPage({
    super.key,
    this.roomCode,
    this.myCountry,
    this.rivalCountry,
    this.aiLevel = 2,
  });

  @override
  State<ChessMatchPage> createState() => _ChessMatchPageState();
}

class _ChessMatchPageState extends State<ChessMatchPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  ChessState cur = ChessState.start();
  ChessMove? last;
  int? selected;
  Set<int> targets = {};
  FightInfo? fight;
  bool busy = false;
  bool thinking = false;
  String? resultMsg;
  bool resultShown = false;
  bool myWhite = true;
  ChessCountry whiteC = chessCountries[0];
  ChessCountry blackC = chessCountries[5];
  Map<String, dynamic>? room;
  int appliedN = 0;
  final List<Map<String, dynamic>> queue = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
  bool precached = false;

  bool get online => widget.roomCode != null;
  String get code => widget.roomCode!;
  bool get playing => !online || (room != null && room!['status'] != 'lobby');

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2000))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    if (online) {
      sub = svc.roomStream(code).listen(_onRoom);
    } else {
      myWhite = true;
      whiteC = widget.myCountry!;
      blackC = widget.rivalCountry!;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!precached && !online) _precache();
  }

  void _precache() {
    precached = true;
    for (final c in {whiteC, blackC}) {
      for (var t = 1; t <= 6; t++) {
        precacheImage(AssetImage(c.asset(t)), context);
      }
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    _anim.dispose();
    super.dispose();
  }

  // ---------------- Sincronización en línea ----------------

  void _onRoom(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || !mounted) return;
    final data = snap.data()!;
    setState(() {
      room = data;
      myWhite = data['hostId'] == svc.uid;
      if (data['status'] != 'lobby') {
        whiteC = countryById(data['hostCountry'] as String);
        blackC = countryById(data['guestCountry'] as String);
        if (!precached && mounted) _precache();
      }
    });
    final n = data['moveN'] as int;
    if (n > appliedN) queue.add(data);
    final res = data['result'] as String? ?? '';
    if (res.isNotEmpty && data['reason'] == 'resign' && resultMsg == null) {
      _finish(res, 'resign');
    }
    _drain();
  }

  Future<void> _drain() async {
    if (busy || queue.isEmpty || !mounted) return;
    final data = queue.removeAt(0);
    final n = data['moveN'] as int;
    if (n <= appliedN) return _drain();
    final lm = Map<String, dynamic>.from(data['last'] as Map);
    if (n == appliedN + 1 && (lm['from'] as int) >= 0) {
      final m = cur.find(lm['from'] as int, lm['to'] as int, lm['promo'] as int);
      if (m != null) {
        appliedN = n;
        await _play(m, broadcast: false);
        return;
      }
    }
    // Se perdió una jugada: sincroniza con la posición publicada.
    setState(() {
      cur = ChessState.fromFen(data['fen'] as String);
      appliedN = n;
      last = null;
      selected = null;
      targets = {};
    });
    _checkEnd(cur);
    _drain();
  }

  // ---------------- Jugar ----------------

  bool get _myTurn =>
      playing &&
      !busy &&
      resultMsg == null &&
      cur.whiteToMove == myWhite &&
      (!online || room!['status'] == 'playing');

  void _onTap(int sq) {
    if (!_myTurn) return;
    final v = cur.b[sq];
    final mine = v != 0 && (v > 0) == myWhite;
    if (selected != null && targets.contains(sq)) {
      _tryMove(selected!, sq);
      return;
    }
    if (mine) {
      final ts = <int>{};
      for (final m in cur.legalMoves()) {
        if (m.from == sq) ts.add(m.to);
      }
      setState(() {
        selected = sq;
        targets = ts;
      });
    } else {
      setState(() {
        selected = null;
        targets = {};
      });
    }
  }

  Future<void> _tryMove(int from, int to) async {
    final options =
        cur.legalMoves().where((m) => m.from == from && m.to == to).toList();
    if (options.isEmpty) return;
    ChessMove m = options.first;
    if (m.promo != 0) {
      final p = await showDialog<int>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => SimpleDialog(
          title: const Text('Corona tu peón'),
          children: [
            for (final e in const {
              'Dama': pQueen,
              'Torre': pRook,
              'Alfil': pBishop,
              'Caballo': pKnight
            }.entries)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, e.value),
                child: Text(e.key, style: const TextStyle(fontSize: 18)),
              ),
          ],
        ),
      );
      m = options.firstWhere((o) => o.promo == (p ?? pQueen));
    }
    await _play(m, broadcast: online);
  }

  String _resultFor(ChessState after) {
    switch (after.status()) {
      case 'checkmate':
        return after.whiteToMove ? 'b' : 'w';
      case 'stalemate':
      case 'fifty':
      case 'material':
        return 'd';
      default:
        return '';
    }
  }

  Future<void> _play(ChessMove m, {required bool broadcast}) async {
    busy = true;
    if (mounted) {
      setState(() {
        selected = null;
        targets = {};
      });
    }
    final before = cur;
    final after = before.apply(m);
    if (broadcast) {
      final expected = appliedN;
      appliedN = expected + 1;
      ChessOnline.sendMove(code, m, after.toFen(), expected, _resultFor(after))
          .catchError((_) => false);
    }
    final capture = before.b[m.to] != 0 || m.ep;
    if (capture) {
      final rookAttack = before.b[m.from].abs() == pRook;
      Sfx.play('sword_draw', delayMs: 300);
      Sfx.play('sword_clash', delayMs: 700);
      Sfx.play('sword_clash', delayMs: 1040);
      if (rookAttack) {
        Sfx.play('rook_jump', delayMs: 1240);
      } else {
        Sfx.play('sword_hit', delayMs: 1230);
        Sfx.play('chess_evaporate', delayMs: 1420);
      }
    } else {
      Sfx.play('chess_move');
    }
    if (capture) {
      final defSq = m.ep ? (m.from ~/ 8) * 8 + m.to % 8 : m.to;
      setState(() {
        fight = FightInfo(
            m.from, m.to, defSq, before.b[m.from], before.b[defSq]);
      });
      await _anim.forward(from: 0);
      if (!mounted) return;
    }
    setState(() {
      fight = null;
      cur = after;
      last = m;
    });
    if (cur.inCheck(cur.whiteToMove)) Sfx.play('chess_check', delayMs: 150);
    _checkEnd(cur);
    busy = false;
    if (!mounted) return;
    setState(() {});
    if (resultMsg == null && !online && cur.whiteToMove != myWhite) {
      _aiTurn();
    }
    _drain();
  }

  void _checkEnd(ChessState s) {
    final r = _resultFor(s);
    if (r.isNotEmpty && resultMsg == null) _finish(r, s.status());
  }

  void _finish(String res, String reason) {
    final why = {
      'checkmate': 'Jaque mate',
      'stalemate': 'Tablas: rey ahogado',
      'fifty': 'Tablas: regla de los 50 movimientos',
      'material': 'Tablas: material insuficiente',
      'resign': 'Abandono',
      'end': '',
    }[reason];
    String who;
    if (res == 'd') {
      who = 'Empate';
    } else {
      final c = res == 'w' ? whiteC : blackC;
      final iWon = (res == 'w') == myWhite;
      who = iWon ? '¡Ganaste con ${c.name}!' : 'Ganó ${c.name}';
      Sfx.play(iWon ? 'win' : 'lose', delayMs: 400);
    }
    setState(() => resultMsg = (why == null || why.isEmpty) ? who : '$who\n$why');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || resultShown) return;
      resultShown = true;
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Fin de la partida'),
          content: Text(resultMsg ?? ''),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Ver tablero')),
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).pop();
                },
                child: const Text('Salir')),
          ],
        ),
      );
    });
  }

  Future<void> _aiTurn() async {
    busy = true;
    if (mounted) setState(() => thinking = true);
    final sw = Stopwatch()..start();
    final r = await compute(aiMoveIsolate,
        <Object>[cur.toFen(), widget.aiLevel, Random().nextInt(1 << 30)]);
    final wait = 700 - sw.elapsedMilliseconds;
    if (wait > 0) await Future<void>.delayed(Duration(milliseconds: wait));
    if (!mounted) return;
    setState(() => thinking = false);
    if (r.isEmpty) {
      busy = false;
      return;
    }
    final m = cur.find(r[0], r[1], r[2]);
    if (m == null) {
      busy = false;
      return;
    }
    await _play(m, broadcast: false);
  }

  Future<void> _resign() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Abandonar la partida?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Abandonar')),
        ],
      ),
    );
    if (ok != true) return;
    if (online && playing && resultMsg == null) {
      await ChessOnline.resign(code, myWhite);
    }
    if (mounted) Navigator.of(context).pop();
  }

  // ---------------- Pantalla ----------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(online ? 'Ajedrez · Sala $code' : 'Ajedrez de naciones'),
        actions: [
          IconButton(
            tooltip: 'Abandonar',
            icon: const Icon(Icons.flag_outlined),
            onPressed: _resign,
          ),
        ],
      ),
      backgroundColor: const Color(0xFF1B2A38),
      body: SafeArea(
        child: !playing ? _lobby() : _game(),
      ),
    );
  }

  Widget _lobby() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Comparte este código:',
              style: TextStyle(color: Colors.white70)),
          Text(online ? code : '',
              style: const TextStyle(
                  fontSize: 48,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6)),
          const SizedBox(height: 16),
          const Text('Esperando al rival...',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          const CircularProgressIndicator(),
        ],
      ),
    );
  }

  Widget _sideTag(ChessCountry c, bool white, bool active, String? who) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active ? Colors.orange.shade700 : Colors.black26,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        '${white ? '⚪' : '⚫'} ${c.name}${who == null ? '' : ' ($who)'}',
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _game() {
    String? hostName, guestName;
    if (online && room != null) {
      hostName = room!['hostName'] as String?;
      guestName = room!['guestName'] as String?;
    }
    final whiteWho = online ? hostName : (myWhite ? 'tú' : 'PC');
    final blackWho = online ? guestName : (myWhite ? 'PC' : 'tú');
    String status;
    if (resultMsg != null) {
      status = resultMsg!.replaceAll('\n', ' · ');
    } else if (thinking) {
      status = 'La computadora está pensando...';
    } else if (fight != null) {
      status = '¡Pelea!';
    } else {
      final check = cur.inCheck(cur.whiteToMove) ? ' ¡Jaque!' : '';
      final mine = cur.whiteToMove == myWhite;
      status = (mine ? 'Tu turno' : 'Turno del rival') + check;
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _sideTag(whiteC, true, cur.whiteToMove && resultMsg == null, whiteWho),
              _sideTag(blackC, false, !cur.whiteToMove && resultMsg == null, blackWho),
            ],
          ),
        ),
        Expanded(
          child: Board3D(
            state: cur,
            flipped: !myWhite,
            whiteCountry: whiteC,
            blackCountry: blackC,
            selected: selected,
            targets: targets,
            lastMove: last,
            fight: fight,
            fightT: _anim.value,
            onTap: _onTap,
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(status,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 17)),
        ),
      ],
    );
  }
}
