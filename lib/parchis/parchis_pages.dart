import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../game_service.dart';
import '../sfx.dart';
import 'board.dart';
import 'engine.dart';

// ======================================================================
// Asientos y servicio en línea
// ======================================================================

class Seat {
  final String uid;
  final String name;
  final int color;
  final int theme;
  final bool bot;
  const Seat(this.uid, this.name, this.color, this.theme, this.bot);

  Map<String, dynamic> toMap() =>
      {'uid': uid, 'name': name, 'color': color, 'theme': theme, 'bot': bot};

  factory Seat.fromMap(Map<String, dynamic> m) => Seat(
      m['uid'] as String,
      m['name'] as String,
      (m['color'] as num).toInt(),
      (m['theme'] as num).toInt(),
      m['bot'] == true);

  Seat withTheme(int t) => Seat(uid, name, color, t, bot);
}

List<Seat> _seatsOf(Map<String, dynamic> d) => [
      for (final s in (d['seats'] as List? ?? const []))
        Seat.fromMap(Map<String, dynamic>.from(s as Map))
    ];

class ParchisOnline {
  static const _colorOrder = [0, 2, 1, 3];

  static Future<String> create(String playerName, int theme) async {
    svc.name = playerName;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'parchis',
      'hostId': svc.uid,
      'status': 'lobby',
      'seats': [Seat(svc.uid, playerName, 0, theme, false).toMap()],
      'state': null,
      'createdAt': nowMs(),
    });
    return code;
  }

  static int _freeColor(List<Seat> seats) {
    for (final c in _colorOrder) {
      if (!seats.any((s) => s.color == c)) return c;
    }
    return -1;
  }

  /// null si todo bien, o un mensaje de error.
  static Future<String?> join(String code, String playerName, int theme) async {
    svc.name = playerName;
    code = code.trim().toUpperCase();
    final ref = svc.roomRef(code);
    String? err;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()!['game'] != 'parchis') {
        err = 'No existe una sala de Parchís con ese código.';
        return;
      }
      final d = snap.data()!;
      final seats = _seatsOf(d);
      if (seats.any((s) => s.uid == svc.uid)) return; // reingreso
      if (d['status'] != 'lobby') {
        err = 'La partida ya comenzó.';
        return;
      }
      final c = _freeColor(seats);
      if (c < 0) {
        err = 'La sala está llena (máx. 4).';
        return;
      }
      tx.update(ref, {
        'seats': [...seats, Seat(svc.uid, playerName, c, theme, false)].map((s) => s.toMap()).toList(),
      });
    });
    return err;
  }

  static Future<void> setTheme(String code, int theme) async {
    final ref = svc.roomRef(code);
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final seats = _seatsOf(snap.data()!);
      tx.update(ref, {
        'seats': [for (final s in seats) (s.uid == svc.uid ? s.withTheme(theme) : s).toMap()],
      });
    });
  }

  static Future<void> addBot(String code) async {
    final ref = svc.roomRef(code);
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final seats = _seatsOf(snap.data()!);
      final c = _freeColor(seats);
      if (c < 0) return;
      final usedThemes = seats.map((s) => s.theme).toSet();
      final free = [for (var i = 0; i < kThemes.length; i++) if (!usedThemes.contains(i)) i];
      final th = free.isEmpty ? Random().nextInt(kThemes.length) : free[Random().nextInt(free.length)];
      final n = seats.where((s) => s.bot).length + 1;
      tx.update(ref, {
        'seats': [...seats, Seat('bot$n', 'PC $n', c, th, true)].map((s) => s.toMap()).toList(),
      });
    });
  }

  static Future<void> start(String code) async {
    final ref = svc.roomRef(code);
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final seats = _seatsOf(snap.data()!);
      if (seats.length < 2) return;
      final g = ParchisGame([for (final s in seats) s.color]);
      tx.update(ref, {'status': 'playing', 'state': g.toMap()});
    });
  }

  /// Aplica una acción sobre el estado del servidor. false si ya cambió.
  static Future<bool> act(String code, String kind, int expectedSeq,
      {int die = 1, int piece = 0}) async {
    final ref = svc.roomRef(code);
    var ok = false;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null || d['state'] == null) return;
      final g = ParchisGame.fromMap(Map<String, dynamic>.from(d['state'] as Map));
      if (g.seq != expectedSeq) return;
      if (kind == 'roll') {
        if (g.phase != 'roll') return;
        g.roll(die);
      } else {
        if (g.phase != 'move' || g.destination(piece, g.die) == null) return;
        g.move(piece);
      }
      tx.update(ref, {
        'state': g.toMap(),
        'status': g.winner >= 0 ? 'finished' : 'playing',
      });
      ok = true;
    });
    return ok;
  }
}

// ======================================================================
// Menú
// ======================================================================

class ParchisMenuPage extends StatefulWidget {
  const ParchisMenuPage({super.key});

  @override
  State<ParchisMenuPage> createState() => _ParchisMenuPageState();
}

class _ParchisMenuPageState extends State<ParchisMenuPage> {
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  int theme = 0;
  int myColor = 0;
  int bots = 1;
  String? error;
  bool loading = false;

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _create() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final code = await ParchisOnline.create(name, theme);
      _open(ParchisMatchPage.online(code));
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
      final err = await ParchisOnline.join(code, name, theme);
      if (err != null) {
        setState(() => error = err);
      } else {
        _open(ParchisMatchPage.online(code));
      }
    } catch (e) {
      setState(() => error = 'No se pudo entrar: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _playLocal() {
    final name = nameCtrl.text.trim().isEmpty ? 'Tú' : nameCtrl.text.trim();
    // Rivales: primero el color opuesto, luego los demás.
    final others = [(myColor + 2) % 4, (myColor + 1) % 4, (myColor + 3) % 4];
    final rnd = Random();
    final themes = [for (var i = 0; i < kThemes.length; i++) if (i != theme) i]..shuffle(rnd);
    final seats = <Seat>[Seat('me', name, myColor, theme, false)];
    for (var i = 0; i < bots; i++) {
      seats.add(Seat('bot${i + 1}', 'PC ${i + 1}', others[i], themes[i], true));
    }
    _open(ParchisMatchPage.local(seats));
  }

  Widget _themePicker() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < kThemes.length; i++)
          ChoiceChip(
            selected: theme == i,
            onSelected: (_) => setState(() => theme = i),
            label: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(kThemes[i].pieces.join(' '), style: const TextStyle(fontSize: 18)),
                Text(kThemes[i].name, style: const TextStyle(fontSize: 11)),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Parchís')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Tu nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            Text('Elige tu temática (4 fichas)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _themePicker(),
            const SizedBox(height: 18),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Contra la PC',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    const Text('Tu color'),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var c = 0; c < 4; c++)
                          Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: GestureDetector(
                              onTap: () => setState(() => myColor = c),
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: kPlayerColors[c],
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: myColor == c ? Colors.black : Colors.white,
                                      width: 3),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 1, label: Text('1 rival')),
                        ButtonSegment(value: 2, label: Text('2 rivales')),
                        ButtonSegment(value: 3, label: Text('3 rivales')),
                      ],
                      selected: {bots},
                      onSelectionChanged: (s) => setState(() => bots = s.first),
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: _playLocal,
                      icon: const Icon(Icons.smart_toy),
                      label: const Text('Jugar contra la PC'),
                    ),
                  ],
                ),
              ),
            ),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('En línea (2 a 4 jugadores)',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: loading ? null : _create,
                      icon: const Icon(Icons.add),
                      label: const Text('Crear sala'),
                    ),
                    const Divider(height: 28),
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
                      label: const Text('Unirme'),
                    ),
                  ],
                ),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(error!, style: const TextStyle(color: Colors.red)),
              ),
            const SizedBox(height: 8),
            const Text(
              'Reglas: se sale de casa con un 5 · un 6 da otra tirada (tres 6 seguidos mandan la última ficha a casa) · '
              'al comer una ficha rival ganas 20 casillas y al llegar a la meta 10 · en las casillas con estrella no se come · '
              'hay que sacar el número exacto para entrar a la meta.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Partida (sin conexión contra la PC, o en línea)
// ======================================================================

class ParchisMatchPage extends StatefulWidget {
  final List<Seat>? localSeats;
  final String? roomCode;
  const ParchisMatchPage.local(List<Seat> seats, {super.key})
      : localSeats = seats,
        roomCode = null;
  const ParchisMatchPage.online(String code, {super.key})
      : localSeats = null,
        roomCode = code;

  @override
  State<ParchisMatchPage> createState() => _ParchisMatchPageState();
}

class _ParchisMatchPageState extends State<ParchisMatchPage>
    with TickerProviderStateMixin {
  bool get online => widget.roomCode != null;
  String get code => widget.roomCode!;

  final rnd = Random();
  List<Seat> seats = [];
  Map<String, dynamic>? room;
  ParchisGame? g;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;

  // Animación
  final List<double> disp = List<double>.filled(16, 0);
  final List<double> hop = List<double>.filled(16, 0);
  final List<double> pop = List<double>.filled(16, 1);
  final Set<int> hidden = {};
  final List<List<Map<String, dynamic>>> queue = [];
  bool playing = false;
  int diceFace = 0;
  double diceAngle = 0;
  String banner = '';
  // Pelea
  double fightT = -1;
  Offset fightCenter = Offset.zero;
  int fightAtt = 0, fightVic = 0;
  late final AnimationController _pulse;
  Timer? _driveTimer;
  bool endShown = false;
  bool sending = false;

  bool get busy => playing || queue.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    if (online) {
      sub = svc.roomStream(code).listen(_onRoom);
    } else {
      seats = widget.localSeats!;
      g = ParchisGame([for (final s in seats) s.color]);
      _syncDisp();
      WidgetsBinding.instance.addPostFrameCallback((_) => _drive());
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    _driveTimer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Estado
  // ------------------------------------------------------------------

  Seat? _seatOf(int color) {
    for (final s in seats) {
      if (s.color == color) return s;
    }
    return null;
  }

  bool _isMine(Seat s) => online ? s.uid == svc.uid : !s.bot;
  bool get _isHost => !online || room?['hostId'] == svc.uid;

  void _syncDisp() {
    final game = g;
    if (game == null) return;
    for (var i = 0; i < 16; i++) {
      disp[i] = game.pos[i].toDouble();
      hop[i] = 0;
      pop[i] = 1;
    }
    hidden.clear();
  }

  void _onRoom(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || !mounted) return;
    final d = snap.data()!;
    setState(() {
      room = d;
      seats = _seatsOf(d);
    });
    final st = d['status'] as String;
    if (st == 'lobby' || d['state'] == null) return;
    final ng = ParchisGame.fromMap(Map<String, dynamic>.from(d['state'] as Map));
    final cur = g;
    if (cur == null) {
      g = ng;
      _syncDisp();
      setState(() {});
      _drive();
      return;
    }
    if (ng.seq <= cur.seq) return;
    final events = ng.events;
    final consecutive = ng.seq == cur.seq + 1;
    g = ng;
    if (consecutive) {
      queue.add(events);
      _pump();
    } else {
      queue.clear();
      _syncDisp();
      setState(() {});
      _drive();
    }
  }

  // ------------------------------------------------------------------
  // Acciones
  // ------------------------------------------------------------------

  void _drive() {
    _driveTimer?.cancel();
    final game = g;
    if (!mounted || game == null || busy || game.phase == 'over') return;
    final seat = _seatOf(game.turn);
    if (seat == null) return;
    final seqNow = game.seq;
    final botDriver = seat.bot && _isHost;
    if (game.phase == 'roll') {
      if (botDriver) {
        _driveTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted && g!.seq == seqNow && !busy) _doRoll();
        });
      }
    } else if (game.phase == 'move') {
      final legal = game.legalMoves();
      if (legal.isEmpty) return;
      if (botDriver) {
        _driveTimer = Timer(const Duration(milliseconds: 900), () {
          if (mounted && g!.seq == seqNow && !busy) _doMove(g!.botPick(rnd));
        });
      } else if (_isMine(seat) && legal.length == 1) {
        _driveTimer = Timer(const Duration(milliseconds: 700), () {
          if (mounted && g!.seq == seqNow && !busy) _doMove(legal.first);
        });
      }
    }
  }

  Future<void> _doRoll() async {
    final game = g;
    if (game == null || game.phase != 'roll' || busy || sending) return;
    final d = rnd.nextInt(6) + 1;
    if (online) {
      sending = true;
      try {
        await ParchisOnline.act(code, 'roll', game.seq, die: d);
      } catch (_) {}
      sending = false;
    } else {
      game.roll(d);
      queue.add(game.events);
      _pump();
    }
  }

  Future<void> _doMove(int p) async {
    final game = g;
    if (game == null || game.phase != 'move' || busy || sending) return;
    if (game.destination(p, game.die) == null) return;
    if (online) {
      sending = true;
      try {
        await ParchisOnline.act(code, 'move', game.seq, piece: p);
      } catch (_) {}
      sending = false;
    } else {
      game.move(p);
      queue.add(game.events);
      _pump();
    }
  }

  // ------------------------------------------------------------------
  // Animaciones
  // ------------------------------------------------------------------

  Future<void> _anim(int ms, void Function(double t) f) async {
    final c = AnimationController(vsync: this, duration: Duration(milliseconds: ms));
    c.addListener(() {
      f(c.value);
      if (mounted) setState(() {});
    });
    try {
      await c.forward();
    } catch (_) {}
    c.dispose();
  }

  Future<void> _pump() async {
    if (playing) return;
    playing = true;
    if (mounted) setState(() {});
    while (queue.isNotEmpty && mounted) {
      final evs = queue.removeAt(0);
      for (final e in evs) {
        if (!mounted) return;
        await _play(e);
      }
    }
    playing = false;
    if (!mounted) return;
    _syncDisp();
    setState(() {});
    _checkEnd();
    _drive();
  }

  Future<void> _showBanner(String text, int ms) async {
    banner = text;
    if (mounted) setState(() {});
    await Future<void>.delayed(Duration(milliseconds: ms));
    banner = '';
    if (mounted) setState(() {});
  }

  Offset _boardCenterOf(int gi, double r, double u) => tokenPos(gi, r) * u;

  Future<void> _play(Map<String, dynamic> e) async {
    switch (e['t'] as String) {
      case 'roll':
        {
        final d = (e['d'] as num).toInt();
        Sfx.play('dice');
        final t0 = DateTime.now().millisecondsSinceEpoch;
        await _anim(750, (t) {
          final k = ((DateTime.now().millisecondsSinceEpoch - t0) / 70).floor();
          diceFace = (k * 5 % 6) + 1;
          diceAngle = sin(t * 30) * 0.5 * (1 - t);
        });
        diceFace = d;
        diceAngle = 0;
        if (mounted) setState(() {});
        await Future<void>.delayed(const Duration(milliseconds: 350));
        break;
        }
      case 'move':
        {
        final gi = (e['p'] as num).toInt();
        final from = (e['from'] as num).toInt();
        final to = (e['to'] as num).toInt();
        if (from == 0) {
          Sfx.play('card_place');
          await _anim(450, (t) {
            disp[gi] = t;
            hop[gi] = sin(t * pi) * 0.5;
          });
        } else {
          final stepMs = (to - from) > 8 ? 70 : 140;
          for (var s = from + 1; s <= to; s++) {
            if (!mounted) return;
            Sfx.play('tick');
            final a = (s - 1).toDouble();
            await _anim(stepMs, (t) {
              disp[gi] = a + t;
              hop[gi] = sin(t * pi) * 0.35;
            });
          }
        }
        disp[gi] = to.toDouble();
        hop[gi] = 0;
        break;
        }
      case 'capture':
        await _fight(e);
        break;
      case 'goal':
        Sfx.play('bonus');
        await _showBanner('¡Llegó a la meta! +10 casillas', 900);
        break;
      case 'sixes':
        await _showBanner('Tres 6 seguidos...', 800);
        break;
      case 'nest':
        {
        final gi = (e['p'] as num).toInt();
        final from = (e['from'] as num).toDouble();
        Sfx.play('lose');
        await _anim(600, (t) => disp[gi] = from * (1 - t));
        disp[gi] = 0;
        break;
        }
      case 'nomove':
        await _showBanner('Sin jugada posible', 700);
        break;
      case 'win':
        break;
    }
  }

  Future<void> _fight(Map<String, dynamic> e) async {
    final a = (e['a'] as num).toInt();
    final v = (e['v'] as num).toInt();
    final to = (e['to'] as num).toInt();
    fightAtt = a;
    fightVic = v;
    hidden
      ..add(a)
      ..add(v);
    final boardW = _boardW;
    final u = boardW / 19;
    fightCenter = routeCenter(a ~/ 4, to) * u;
    const total = 2400;
    Sfx.play('sword_clash', delayMs: (total * 0.30).round());
    Sfx.play('chess_clash', delayMs: (total * 0.54).round());
    Sfx.play('chess_evaporate', delayMs: (total * 0.68).round());
    Sfx.play('capture', delayMs: (total * 0.30).round());
    await _anim(total, (t) => fightT = t);
    fightT = -1;
    hidden.clear();
    disp[v] = 0;
    pop[v] = 0;
    if (mounted) setState(() {});
    Sfx.play('card_play');
    await _anim(500, (t) => pop[v] = Curves.easeOutBack.transform(t));
    pop[v] = 1;
    await _showBanner('¡Pelea ganada! +20 casillas', 800);
  }

  double _boardW = 300;

  void _checkEnd() {
    final game = g;
    if (game == null || game.winner < 0 || endShown) return;
    endShown = true;
    final seat = _seatOf(game.winner);
    final mine = seat != null && _isMine(seat);
    Sfx.play(mine ? 'win' : 'score');
    if (mine) Sfx.play('applause', delayMs: 700);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('¡Tenemos ganador! 🏆'),
        content: Text(mine ? '¡Ganaste tú!' : 'Ganó ${seat?.name ?? ''}'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop();
            },
            child: const Text('Salir'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------
  // Interfaz
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final game = g;
    final started = !online || (room != null && room!['status'] != 'lobby' && game != null);
    return Scaffold(
      appBar: AppBar(
        title: Text(online ? 'Parchís · Sala $code' : 'Parchís'),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: Sfx.enabled,
            builder: (context, on, _) => IconButton(
              icon: Icon(on ? Icons.volume_up : Icons.volume_off),
              onPressed: () => Sfx.enabled.value = !on,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: !started || game == null ? _lobby() : _game(game),
      ),
    );
  }

  Widget _lobby() {
    if (room == null) return const Center(child: CircularProgressIndicator());
    final mySeat = seats.where((s) => s.uid == svc.uid).toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Comparte este código:', textAlign: TextAlign.center),
        Text(code,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 46, fontWeight: FontWeight.bold, letterSpacing: 6)),
        const SizedBox(height: 12),
        for (final s in seats)
          ListTile(
            leading: CircleAvatar(
                backgroundColor: kPlayerColors[s.color],
                child: Text(kThemes[s.theme].pieces[0])),
            title: Text(s.name + (s.bot ? ' (PC)' : '')),
            subtitle: Text('${kColorNames[s.color]} · ${kThemes[s.theme].name}'),
            trailing: s.uid == room!['hostId'] ? const Chip(label: Text('Anfitrión')) : null,
          ),
        if (mySeat.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('Tu temática:'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (var i = 0; i < kThemes.length; i++)
                ChoiceChip(
                  selected: mySeat.first.theme == i,
                  onSelected: (_) => ParchisOnline.setTheme(code, i),
                  label: Text('${kThemes[i].pieces[0]} ${kThemes[i].name}'),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (_isHost) ...[
          OutlinedButton.icon(
            onPressed: seats.length < 4 ? () => ParchisOnline.addBot(code) : null,
            icon: const Icon(Icons.smart_toy),
            label: const Text('Agregar un jugador de la PC'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: seats.length >= 2 ? () => ParchisOnline.start(code) : null,
            child: Text(seats.length >= 2 ? 'Iniciar partida' : 'Se necesitan al menos 2 jugadores'),
          ),
        ] else
          const Text('Esperando que el anfitrión inicie...', textAlign: TextAlign.center),
      ],
    );
  }

  String _message(ParchisGame game) {
    final seat = _seatOf(game.turn);
    if (seat == null) return '';
    final mine = _isMine(seat);
    if (game.phase == 'over') return 'Fin de la partida';
    if (busy) return banner.isEmpty ? '' : banner;
    if (banner.isNotEmpty) return banner;
    if (game.phase == 'roll') {
      return mine ? 'Tu turno: tira el dado' : 'Turno de ${seat.name}';
    }
    final legal = game.legalMoves();
    final bonus = game.bonus > 0 ? ' (¡${game.bonus} casillas extra!)' : '';
    if (mine && legal.length > 1) return 'Elige una ficha para mover ${game.die}$bonus';
    return mine ? 'Moviendo ${game.die}...' : '${seat.name} mueve ${game.die}';
  }

  Widget _playersBar(ParchisGame game) {
    final sorted = [...seats]..sort((a, b) => a.color.compareTo(b.color));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(
        children: [
          for (final s in sorted)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: kPlayerColors[s.color].withOpacity(0.25),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: game.turn == s.color && game.phase != 'over'
                      ? Colors.black
                      : kPlayerColors[s.color],
                  width: game.turn == s.color ? 3 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Text(kThemes[s.theme].pieces[0], style: const TextStyle(fontSize: 20)),
                  const SizedBox(width: 6),
                  Text(_isMine(s) ? '${s.name} (tú)' : s.name,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('🏁 ${[for (var k = 0; k < 4; k++) game.pos[s.color * 4 + k]].where((r) => r == kGoal).length}/4',
                      style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _game(ParchisGame game) {
    final seat = _seatOf(game.turn);
    final myTurn = seat != null && _isMine(seat) && !busy && game.phase != 'over';
    final canRoll = myTurn && game.phase == 'roll' && !sending;
    final legal = myTurn && game.phase == 'move' ? game.legalMoves() : <int>[];
    return Column(
      children: [
        _playersBar(game),
        Expanded(
          child: Center(
            child: LayoutBuilder(builder: (context, box) {
              final side = min(box.maxWidth, box.maxHeight) - 8;
              _boardW = side;
              return SizedBox(
                width: side,
                height: side,
                child: _board(game, side, legal),
              );
            }),
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(
            children: [
              DiceFace(value: diceFace, size: 64, angle: diceAngle),
              const SizedBox(width: 14),
              Expanded(
                child: Text(_message(game),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              FilledButton.icon(
                onPressed: canRoll ? _doRoll : null,
                icon: const Icon(Icons.casino),
                label: const Text('Tirar'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _board(ParchisGame game, double side, List<int> legal) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => _boardInner(game, side, legal),
    );
  }

  Widget _boardInner(ParchisGame game, double side, List<int> legal) {
    final u = side / 19;
    final tokens = <Widget>[];
    // Agrupar para que las fichas apiladas se vean todas
    final groups = <String, List<int>>{};
    for (var gi = 0; gi < 16; gi++) {
      if (!game.active.contains(gi ~/ 4)) continue;
      if (hidden.contains(gi)) continue;
      final p = tokenPos(gi, disp[gi]);
      final key = '${(p.dx * 4).round()}_${(p.dy * 4).round()}';
      groups.putIfAbsent(key, () => []).add(gi);
    }
    const offs = [Offset(-0.2, -0.2), Offset(0.2, 0.2), Offset(-0.2, 0.2), Offset(0.2, -0.2)];
    final entries = <MapEntry<int, Offset>>[];
    for (final list in groups.values) {
      for (var i = 0; i < list.length; i++) {
        final gi = list[i];
        final base = tokenPos(gi, disp[gi]);
        final o = list.length > 1 ? offs[i % 4] * 1.0 : Offset.zero;
        entries.add(MapEntry(gi, base + o + Offset(0, -hop[gi])));
      }
    }
    // Las fichas más abajo se dibujan después (encima)
    entries.sort((a, b) => a.value.dy.compareTo(b.value.dy));
    for (final en in entries) {
      final gi = en.key;
      final c = gi ~/ 4, p = gi % 4;
      final seat = _seatOf(c);
      final emoji = kThemes[seat?.theme ?? 0].pieces[p];
      final isLegal = legal.contains(p) && c == game.turn;
      final scale = (disp[gi] >= kGoal ? 0.7 : 1.0) * pop[gi];
      final size = u * 1.05 * scale;
      final pos = en.value * u;
      tokens.add(Positioned(
        left: pos.dx - size / 2,
        top: pos.dy - size / 2,
        width: size,
        height: size,
        child: GestureDetector(
          onTap: isLegal ? () => _doMove(p) : null,
          child: ParchisToken(
            color: c,
            emoji: emoji,
            size: size,
            highlight: isLegal,
            pulse: _pulse.value,
          ),
        ),
      ));
    }
    return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: CustomPaint(painter: ParchisBoardPainter(game.active)),
          ),
          ...tokens,
          if (banner.isNotEmpty && fightT < 0)
            Positioned(
              left: 0,
              right: 0,
              top: side * 0.44,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(14)),
                  child: Text(banner,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.none)),
                ),
              ),
            ),
          if (fightT >= 0)
            Positioned.fill(
              child: FightOverlay(
                t: fightT,
                center: fightCenter,
                u: u,
                boardSize: Size(side, side),
                attColor: fightAtt ~/ 4,
                vicColor: fightVic ~/ 4,
                attEmoji: kThemes[_seatOf(fightAtt ~/ 4)?.theme ?? 0].pieces[fightAtt % 4],
                vicEmoji: kThemes[_seatOf(fightVic ~/ 4)?.theme ?? 0].pieces[fightVic % 4],
              ),
            ),
        ],
    );
  }
}
