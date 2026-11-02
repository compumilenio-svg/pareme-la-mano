import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../cuarenta/card_art.dart' show CardBack;
import '../game_service.dart';
import '../sfx.dart';
import 'engine.dart';

const List<Color> kPairColors = [
  Color(0xFF1E88E5), // azul
  Color(0xFFE53935), // rojo
  Color(0xFF43A047), // verde
  Color(0xFFFB8C00), // naranja
];

class PSeat {
  final String uid;
  final String name;
  final bool bot;
  const PSeat(this.uid, this.name, this.bot);
  Map<String, dynamic> toMap() => {'uid': uid, 'name': name, 'bot': bot};
  factory PSeat.fromMap(Map<String, dynamic> m) =>
      PSeat(m['uid'] as String, m['name'] as String, m['bot'] == true);
}

List<PSeat> _seatsOf(Map<String, dynamic> d) => [
      for (final s in (d['seats'] as List? ?? const []))
        PSeat.fromMap(Map<String, dynamic>.from(s as Map))
    ];

// ======================================================================
// Servicio en línea
// ======================================================================

class PairsOnline {
  static Future<String> create(String name, int pairs, int theme) async {
    svc.name = name;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'pares',
      'hostId': svc.uid,
      'status': 'lobby',
      'pairs': pairs,
      'theme': theme,
      'seats': [PSeat(svc.uid, name, false).toMap()],
      'state': null,
      'createdAt': nowMs(),
    });
    return code;
  }

  /// null si todo bien, o un mensaje de error.
  static Future<String?> join(String code, String name) async {
    svc.name = name;
    code = code.trim().toUpperCase();
    final ref = svc.roomRef(code);
    String? err;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()!['game'] != 'pares') {
        err = 'No existe una sala de Encuentra los pares con ese código.';
        return;
      }
      final d = snap.data()!;
      final seats = _seatsOf(d);
      if (seats.any((s) => s.uid == svc.uid)) return; // reingreso
      if (d['status'] != 'lobby') {
        err = 'La partida ya comenzó.';
        return;
      }
      if (seats.length >= 4) {
        err = 'La sala está llena (máx. 4).';
        return;
      }
      tx.update(ref, {
        'seats': [...seats, PSeat(svc.uid, name, false)].map((s) => s.toMap()).toList(),
      });
    });
    return err;
  }

  static Future<void> addBot(String code) async {
    final ref = svc.roomRef(code);
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final seats = _seatsOf(snap.data()!);
      if (seats.length >= 4) return;
      final n = seats.where((s) => s.bot).length + 1;
      tx.update(ref, {
        'seats': [...seats, PSeat('bot$n', 'PC $n', true)].map((s) => s.toMap()).toList(),
      });
    });
  }

  static Future<void> start(String code) async {
    final ref = svc.roomRef(code);
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data()!;
      final seats = _seatsOf(d);
      if (seats.length < 2) return;
      final g = PairsGame.create(
          (d['pairs'] as num).toInt(), (d['theme'] as num).toInt(), seats.length);
      tx.update(ref, {'status': 'playing', 'state': g.toMap()});
    });
  }

  /// Aplica 'flip' (carta [idx]) o 'resolve' sobre el servidor. false si ya cambió.
  static Future<bool> act(String code, String kind, int expectedSeq,
      {int idx = 0}) async {
    final ref = svc.roomRef(code);
    var ok = false;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null || d['state'] == null) return;
      final g = PairsGame.fromMap(Map<String, dynamic>.from(d['state'] as Map));
      if (g.seq != expectedSeq) return;
      if (kind == 'flip') {
        if (!g.canFlip(idx)) return;
        g.flip(idx);
      } else {
        if (!g.needsResolve) return;
        g.resolve();
      }
      tx.update(ref, {
        'state': g.toMap(),
        'status': g.finished ? 'finished' : 'playing',
      });
      ok = true;
    });
    return ok;
  }
}

// ======================================================================
// Menú
// ======================================================================

class PairsMenuPage extends StatefulWidget {
  const PairsMenuPage({super.key});

  @override
  State<PairsMenuPage> createState() => _PairsMenuPageState();
}

class _PairsMenuPageState extends State<PairsMenuPage> {
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  int level = 0;
  int theme = kMixedTheme;
  int players = 2;
  String? error;
  bool loading = false;

  int get pairs => kLevelPairs[level];
  bool get multiOk => level >= 1;

  String get _name =>
      nameCtrl.text.trim().isEmpty ? 'Tú' : nameCtrl.text.trim();

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _solo() => _open(PairsMatchPage.local(
      pairs: pairs, theme: theme, seats: [PSeat('me', _name, false)]));

  void _vsPc() => _open(PairsMatchPage.local(pairs: pairs, theme: theme, seats: [
        PSeat('me', _name, false),
        for (var i = 1; i < players; i++) PSeat('bot$i', 'PC $i', true),
      ]));

  void _pass() => _open(PairsMatchPage.local(pairs: pairs, theme: theme, seats: [
        for (var i = 1; i <= players; i++) PSeat('h$i', 'Jugador $i', false),
      ]));

  Future<void> _create() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final code = await PairsOnline.create(name, pairs, theme);
      _open(PairsMatchPage.online(code));
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
      final err = await PairsOnline.join(code, name);
      if (err != null) {
        setState(() => error = err);
      } else {
        _open(PairsMatchPage.online(code));
      }
    } catch (e) {
      setState(() => error = 'No se pudo entrar: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Encuentra los pares')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('Nivel', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < 3; i++)
                  ButtonSegment(
                      value: i, label: Text('${kLevelNames[i]}\n${kLevelPairs[i]} pares', textAlign: TextAlign.center)),
              ],
              selected: {level},
              onSelectionChanged: (s) => setState(() => level = s.first),
            ),
            const SizedBox(height: 6),
            Text(multiOk
                ? 'Desde este nivel puedes jugar con hasta 4 jugadores.'
                : 'El nivel básico es para jugar solo. Para varios jugadores elige Medio o Alto.',
                style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 20),
            const Text('Temática de las imágenes', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  selected: theme == kMixedTheme,
                  onSelected: (_) => setState(() => theme = kMixedTheme),
                  label: const Text('🎉 Todas mezcladas'),
                ),
                for (var i = 0; i < kPairThemes.length; i++)
                  ChoiceChip(
                    selected: theme == i,
                    onSelected: (_) => setState(() => theme = i),
                    label: Text('${kPairThemes[i].icon} ${kPairThemes[i].name}'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Tu nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _solo,
              icon: const Icon(Icons.person),
              label: const Text('Jugar solo'),
            ),
            if (multiOk) ...[
              const SizedBox(height: 16),
              const Text('Jugadores (2 a 4)', style: TextStyle(fontSize: 16)),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('2')),
                  ButtonSegment(value: 3, label: Text('3')),
                  ButtonSegment(value: 4, label: Text('4')),
                ],
                selected: {players},
                onSelectionChanged: (s) => setState(() => players = s.first),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _vsPc,
                icon: const Icon(Icons.smart_toy),
                label: Text('Tú contra ${players - 1} PC'),
              ),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _pass,
                icon: const Icon(Icons.group),
                label: Text('$players personas en este mismo equipo (por turnos)'),
              ),
              const Divider(height: 36),
              const Text('En línea con otras personas', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 4),
              const Text('Usa el nivel y la temática de arriba. Puedes agregar PC en la sala.'),
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
            ],
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
// Carta que voltea
// ======================================================================

class _FlipCard extends StatelessWidget {
  final String face;
  final bool up;
  final int owner; // -1 si no la ganó nadie
  final bool dim;
  final double size;
  final VoidCallback? onTap;
  const _FlipCard({
    required this.face,
    required this.up,
    required this.owner,
    required this.size,
    this.dim = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ownerColor = owner >= 0 ? kPairColors[owner % 4] : null;
    final front = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ownerColor == null ? Colors.white : ownerColor.withOpacity(0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: ownerColor ?? Colors.black26, width: ownerColor == null ? 1 : 4),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(1, 2)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(face, style: TextStyle(fontSize: size * 0.58, height: 1.0)),
    );
    final back = CardBack(
        width: size, height: size, color: const Color(0xFF5E35B1));
    return GestureDetector(
      onTap: onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: up ? 1.0 : 0.0),
        duration: const Duration(milliseconds: 320),
        builder: (context, t, _) {
          final showFront = t >= 0.5;
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.identity()
              ..setEntry(3, 2, 0.001)
              ..rotateY(t * pi),
            child: showFront
                ? Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()..rotateY(pi),
                    child: front)
                : back,
          );
        },
      ),
    );
  }
}

// ======================================================================
// Partida (local y en línea)
// ======================================================================

class PairsMatchPage extends StatefulWidget {
  final bool online;
  final String? code;
  final int pairs;
  final int theme;
  final List<PSeat> seats;
  const PairsMatchPage._(
      this.online, this.code, this.pairs, this.theme, this.seats);

  factory PairsMatchPage.local(
          {required int pairs, required int theme, required List<PSeat> seats}) =>
      PairsMatchPage._(false, null, pairs, theme, seats);

  factory PairsMatchPage.online(String code) =>
      PairsMatchPage._(true, code, 0, 0, const []);

  @override
  State<PairsMatchPage> createState() => _PairsMatchPageState();
}

class _PairsMatchPageState extends State<PairsMatchPage> {
  PairsGame? g;
  List<PSeat> seats = [];
  Map<String, dynamic>? room;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
  Timer? _timer;
  Timer? _clock;
  final PairsBot bot = PairsBot();
  final DateTime started = DateTime.now();
  int _lastSeq = -1;
  int _lastScoreSum = 0;
  bool _endHandled = false;
  bool _busy = false;

  bool get online => widget.online;
  bool get _isHost => !online || room?['hostId'] == svc.uid;
  bool get _solo => seats.length == 1;
  String get _code => widget.code ?? '';

  @override
  void initState() {
    super.initState();
    if (online) {
      sub = svc.roomStream(_code).listen(_onRoom);
    } else {
      seats = widget.seats;
      g = PairsGame.create(widget.pairs, widget.theme, seats.length);
      _drive();
    }
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _solo && g != null && !g!.finished) setState(() {});
    });
  }

  @override
  void dispose() {
    sub?.cancel();
    _timer?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  // ---------- Estado en línea ----------

  void _onRoom(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) return;
    final d = snap.data()!;
    room = d;
    seats = _seatsOf(d);
    final st = d['state'];
    if (st != null && d['status'] != 'lobby') {
      final ng = PairsGame.fromMap(Map<String, dynamic>.from(st as Map));
      if (ng.seq == 0 && ng.moves == 0 && (g == null || g!.finished)) {
        bot.reset();
        _endHandled = false;
        _lastScoreSum = 0;
      }
      g = ng;
    } else {
      g = null;
    }
    if (mounted) setState(() {});
    _afterChange();
  }

  // ---------- Motor de turnos ----------

  void _afterChange() {
    final game = g;
    if (game == null) return;
    // Sonidos al cambiar el estado
    if (game.seq != _lastSeq) {
      final sum = game.scores.fold<int>(0, (a, b) => a + b);
      if (sum > _lastScoreSum) Sfx.play('capture');
      _lastScoreSum = sum;
      _lastSeq = game.seq;
    }
    bot.observe(game);
    if (game.finished && !_endHandled) {
      _endHandled = true;
      final w = game.winners;
      final mine = online
          ? seats.indexWhere((s) => s.uid == svc.uid)
          : seats.indexWhere((s) => !s.bot);
      Sfx.play(w.contains(mine) || _solo ? 'applause' : 'lose', delayMs: 400);
    }
    _drive();
  }

  void _drive() {
    _timer?.cancel();
    final game = g;
    if (game == null || game.finished) return;
    final seq = game.seq;
    if (game.needsResolve) {
      _timer = Timer(Duration(milliseconds: _isHost ? 1200 : 2400),
          () => _doResolve(seq));
      return;
    }
    if (game.turn < seats.length && seats[game.turn].bot && _isHost) {
      _timer = Timer(const Duration(milliseconds: 900), () => _botStep(seq));
    }
  }

  void _doResolve(int seq) {
    final game = g;
    if (!mounted || game == null || game.seq != seq) return;
    if (online) {
      PairsOnline.act(_code, 'resolve', seq);
    } else {
      game.resolve();
      setState(() {});
      _afterChange();
    }
  }

  void _botStep(int seq) {
    final game = g;
    if (!mounted || game == null || game.seq != seq || game.finished) return;
    final idx = game.open.isEmpty
        ? bot.pickFirst(game)
        : bot.pickSecond(game, game.open[0]);
    _flip(idx);
  }

  bool _myTurn() {
    final game = g;
    if (game == null || game.finished || game.turn >= seats.length) return false;
    final s = seats[game.turn];
    if (s.bot) return false;
    return online ? s.uid == svc.uid : true;
  }

  Future<void> _flip(int i) async {
    final game = g;
    if (game == null || !game.canFlip(i)) return;
    Sfx.play('card_play');
    if (online) {
      if (_busy) return;
      _busy = true;
      try {
        await PairsOnline.act(_code, 'flip', game.seq, idx: i);
      } finally {
        _busy = false;
      }
    } else {
      game.flip(i);
      setState(() {});
      _afterChange();
    }
  }

  void _again() {
    if (online) {
      PairsOnline.start(_code);
    } else {
      bot.reset();
      _endHandled = false;
      _lastScoreSum = 0;
      _lastSeq = -1;
      setState(() =>
          g = PairsGame.create(widget.pairs, widget.theme, seats.length));
      _drive();
    }
  }

  // ---------- Pantallas ----------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(online ? 'Pares · Sala $_code' : 'Encuentra los pares'),
      ),
      body: SafeArea(
        child: online && room == null
            ? const Center(child: CircularProgressIndicator())
            : (online && room!['status'] == 'lobby')
                ? _lobby()
                : g == null
                    ? const Center(child: CircularProgressIndicator())
                    : _board(),
      ),
    );
  }

  Widget _lobby() {
    final d = room!;
    final pairs = (d['pairs'] as num).toInt();
    final th = (d['theme'] as num).toInt();
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Text('Comparte este código:'),
          Text(_code,
              style: const TextStyle(
                  fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: 6)),
          Text(
              '$pairs pares · ${th == kMixedTheme ? 'Todas mezcladas' : kPairThemes[th].name}'),
          const SizedBox(height: 16),
          Text('Jugadores (${seats.length}/4)',
              style: Theme.of(context).textTheme.titleMedium),
          Expanded(
            child: ListView(
              children: [
                for (var i = 0; i < seats.length; i++)
                  ListTile(
                    leading: CircleAvatar(
                        backgroundColor: kPairColors[i % 4],
                        child: Icon(seats[i].bot ? Icons.smart_toy : Icons.person,
                            color: Colors.white)),
                    title: Text(seats[i].name),
                    trailing: seats[i].uid == d['hostId']
                        ? const Chip(label: Text('Anfitrión'))
                        : null,
                  ),
              ],
            ),
          ),
          if (_isHost) ...[
            OutlinedButton.icon(
              onPressed:
                  seats.length >= 4 ? null : () => PairsOnline.addBot(_code),
              icon: const Icon(Icons.smart_toy),
              label: const Text('Agregar una PC'),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: seats.length >= 2 ? () => PairsOnline.start(_code) : null,
              child: Text(seats.length >= 2
                  ? 'Iniciar partida'
                  : 'Necesitas al menos 2 jugadores'),
            ),
          ] else
            const Text('Esperando que el anfitrión inicie...'),
        ],
      ),
    );
  }

  String _clockText() {
    final s = DateTime.now().difference(started).inSeconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  Widget _header(PairsGame game) {
    if (_solo) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _stat('Pares', '${game.scores[0]} / ${game.pairs}'),
            _stat('Intentos', '${game.moves}'),
            _stat('Tiempo', _clockText()),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          for (var i = 0; i < seats.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: kPairColors[i % 4].withOpacity(game.turn == i ? 0.25 : 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: kPairColors[i % 4], width: game.turn == i ? 3 : 1),
              ),
              child: Text(
                '${game.turn == i && !game.finished ? '👉 ' : ''}${seats[i].name}: ${game.scores[i]}',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kPairColors[i % 4].withOpacity(1)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) => Column(children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      ]);

  Widget _board() {
    final game = g!;
    final myTurn = _myTurn();
    return Column(
      children: [
        _header(game),
        if (!game.finished)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              _solo
                  ? 'Voltea dos cartas iguales'
                  : myTurn
                      ? (online ? '¡Tu turno!' : 'Turno de ${seats[game.turn].name}')
                      : 'Turno de ${seats[game.turn].name}...',
              style: const TextStyle(fontSize: 15),
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              LayoutBuilder(builder: (context, c) {
                final cols = max(3, (c.maxWidth / 88).floor());
                const gap = 6.0;
                final size = (c.maxWidth - 16 - gap * (cols - 1)) / cols;
                return GridView.builder(
                  padding: const EdgeInsets.all(8),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: 1,
                  ),
                  itemCount: game.faces.length,
                  itemBuilder: (context, i) => _FlipCard(
                    face: game.faces[i],
                    up: game.isUp(i),
                    owner: game.owner[i],
                    size: size,
                    onTap: myTurn && game.canFlip(i) ? () => _flip(i) : null,
                  ),
                );
              }),
              if (game.finished) Center(child: _result(game)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _result(PairsGame game) {
    final w = game.winners;
    final title = _solo
        ? '¡Lo lograste!'
        : w.length > 1
            ? '¡Empate!'
            : '¡Ganó ${seats[w.first].name}!';
    return Card(
      elevation: 8,
      margin: const EdgeInsets.all(24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('🏆 $title',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center),
            const SizedBox(height: 10),
            if (_solo)
              Text('${game.moves} intentos · ${_clockText()}')
            else
              for (var i = 0; i < seats.length; i++)
                Text('${seats[i].name}: ${game.scores[i]} pares',
                    style: TextStyle(
                        color: kPairColors[i % 4],
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
            const SizedBox(height: 14),
            Wrap(spacing: 10, children: [
              if (!online || _isHost)
                FilledButton(onPressed: _again, child: const Text('Jugar otra vez'))
              else
                const Text('Esperando al anfitrión...'),
              OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Salir')),
            ]),
          ],
        ),
      ),
    );
  }
}
