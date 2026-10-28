import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../game_service.dart';
import '../sfx.dart';
import 'engine.dart';
import 'voice.dart';

Color ballColor(int n) {
  switch (bingoLetter(n)) {
    case 'B':
      return const Color(0xFF1E88E5);
    case 'I':
      return const Color(0xFFE53935);
    case 'N':
      return const Color(0xFF8E24AA);
    case 'G':
      return const Color(0xFF43A047);
    default:
      return const Color(0xFFFB8C00);
  }
}

// ======================================================================
// Servicio en línea (Firestore)
// ======================================================================

class BingoOnline {
  static Future<String> create(String name, String prize, int priceCents) async {
    svc.name = name;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'bingo',
      'hostId': svc.uid,
      'hostName': name,
      'status': 'lobby',
      'prize': prize,
      'priceCents': priceCents,
      'balls': <int>[],
      'paused': false,
      'speed': 6,
      'round': 1,
      'winnerId': '',
      'winnerName': '',
      'createdAt': nowMs(),
    });
    await svc.playersRef(code).doc(svc.uid).set(_player(name));
    return code;
  }

  static Map<String, dynamic> _player(String name) => {
        'name': name,
        'joinedAt': nowMs(),
        'cards': <String>[],
        'marks': <String>[],
        'round': 0,
        'bingo': null,
      };

  /// null si todo bien, o un mensaje de error.
  static Future<String?> join(String code, String name) async {
    svc.name = name;
    code = code.trim().toUpperCase();
    final snap = await svc.roomRef(code).get();
    if (!snap.exists || snap.data()!['game'] != 'bingo') {
      return 'No existe una sala de Bingo con ese código.';
    }
    final existing = await svc.playersRef(code).doc(svc.uid).get();
    if (existing.exists) return null; // reingreso
    if (snap.data()!['status'] != 'lobby') {
      return 'El bingo ya empezó. Entra cuando comience la próxima partida.';
    }
    await svc.playersRef(code).doc(svc.uid).set(_player(name));
    return null;
  }
}

// ======================================================================
// Menú
// ======================================================================

class BingoMenuPage extends StatefulWidget {
  const BingoMenuPage({super.key});

  @override
  State<BingoMenuPage> createState() => _BingoMenuPageState();
}

class _BingoMenuPageState extends State<BingoMenuPage> {
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  final prizeCtrl = TextEditingController();
  final priceCtrl = TextEditingController(text: '0.50');
  String? error;
  bool loading = false;

  void _open(String code) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => BingoRoomPage(code: code)));

  Future<void> _create() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    final cents = parseCents(priceCtrl.text);
    if (cents == null) {
      return setState(() => error = 'El precio de la cartilla no es válido.');
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final code = await BingoOnline.create(name, prizeCtrl.text.trim(), cents);
      _open(code);
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
      final err = await BingoOnline.join(code, name);
      if (err != null) {
        setState(() => error = err);
      } else {
        _open(code);
      }
    } catch (e) {
      setState(() => error = 'No se pudo entrar: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Bingo')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Un bot canta las bolas y tú tachas los números de tu cartilla. '
              'Cuando completas la cartilla, el juego grita ¡BINGO! por ti.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Tu nombre', border: OutlineInputBorder()),
            ),
            const Divider(height: 36),
            Text('Crear una sala (tú eres el anfitrión)', style: t.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Costo de cada cartilla (\$)',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: prizeCtrl,
              decoration: const InputDecoration(
                  labelText: 'Premio de este juego',
                  hintText: 'Ej: \$5, una torta, una pizza...',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: loading ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('Crear sala'),
            ),
            const Divider(height: 36),
            Text('Unirme a una sala', style: t.titleLarge),
            const SizedBox(height: 12),
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
// Bolas
// ======================================================================

class BingoBallWidget extends StatelessWidget {
  final int n;
  final double size;
  final bool showLetter;
  const BingoBallWidget(
      {super.key, required this.n, required this.size, this.showLetter = true});

  @override
  Widget build(BuildContext context) {
    final c = ballColor(n);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.35, -0.45),
          radius: 0.95,
          colors: [
            Color.lerp(c, Colors.white, 0.7)!,
            c,
            Color.lerp(c, Colors.black, 0.5)!,
          ],
          stops: const [0.0, 0.55, 1.0],
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black45,
              blurRadius: size * 0.12,
              offset: Offset(size * 0.04, size * 0.08)),
        ],
      ),
      child: Center(
        child: Container(
          width: size * (showLetter ? 0.58 : 0.66),
          height: size * (showLetter ? 0.58 : 0.66),
          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: showLetter
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(bingoLetter(n),
                        style: TextStyle(
                            fontSize: size * 0.17,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            color: c)),
                    Text('$n',
                        style: TextStyle(
                            fontSize: size * 0.28,
                            fontWeight: FontWeight.bold,
                            height: 1.0,
                            color: Colors.black87)),
                  ],
                )
              : Text('$n',
                  style: TextStyle(
                      fontSize: size * 0.36,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
        ),
      ),
    );
  }
}

class _XPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xCCD32F2F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.12
      ..strokeCap = StrokeCap.round;
    final m = size.shortestSide * 0.16;
    canvas.drawLine(Offset(m, m), Offset(size.width - m, size.height - m), p);
    canvas.drawLine(Offset(size.width - m, m), Offset(m, size.height - m), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ======================================================================
// Sala
// ======================================================================

class BingoRoomPage extends StatefulWidget {
  final String code;
  const BingoRoomPage({super.key, required this.code});

  @override
  State<BingoRoomPage> createState() => _BingoRoomPageState();
}

class _BingoRoomPageState extends State<BingoRoomPage>
    with SingleTickerProviderStateMixin {
  String get code => widget.code;

  Map<String, dynamic>? room;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> playerDocs = [];
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? roomSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? playersSub;

  // Mis cartillas
  List<List<int>> myCards = [];
  List<List<bool>> myMarks = [];
  int myRound = -1;
  bool claimed = false;
  // Un número que salió y no se tachó en 20 s se pierde (se quita de la cartilla).
  final Map<int, int> calledAt = {};
  static const int missMs = 20000;

  // Bolas
  int seenBalls = -1;
  late final AnimationController _ballAnim;
  bool voiceOn = true;
  String? lastStatus;
  bool finishedShown = false;

  // Anfitrión
  Timer? drawTimer;
  List<int> hostBalls = [];
  bool finalizing = false;
  final prizeCtrl = TextEditingController();
  final priceCtrl = TextEditingController();
  bool fieldsLoaded = false;
  Timer? debounce;

  bool get isHost => room?['hostId'] == svc.uid;
  String get status => (room?['status'] as String?) ?? 'lobby';
  List<int> get balls => List<int>.from((room?['balls'] as List?) ?? const []);
  /// Bolas ya reveladas: la última no se muestra hasta que sale de la tómbola.
  List<int> get shownBalls {
    final b = balls;
    if (b.isNotEmpty && seenBalls == b.length && _ballAnim.isAnimating &&
        _ballAnim.value < 0.55) {
      return b.sublist(0, b.length - 1);
    }
    return b;
  }

  /// Salió hace más de 20 s (o antes de que entraras) y no está tachado.
  bool _missed(int n) {
    if (n == 0 || !shownBalls.contains(n)) return false;
    final at = calledAt[n];
    return at == null || nowMs() - at >= missMs;
  }

  int get priceCents => (room?['priceCents'] as int?) ?? 50;

  @override
  void initState() {
    super.initState();
    _ballAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2800))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    roomSub = svc.roomStream(code).listen(_onRoom);
    playersSub = svc.playersStream(code).listen(_onPlayers);
  }

  @override
  void dispose() {
    roomSub?.cancel();
    playersSub?.cancel();
    drawTimer?.cancel();
    debounce?.cancel();
    _ballAnim.dispose();
    prizeCtrl.dispose();
    priceCtrl.dispose();
    BingoVoice.stop();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Sala
  // ------------------------------------------------------------------

  void _onRoom(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || !mounted) return;
    final d = snap.data()!;
    final prevStatus = lastStatus;
    setState(() {
      room = d;
      if (!fieldsLoaded) {
        fieldsLoaded = true;
        prizeCtrl.text = (d['prize'] as String?) ?? '';
        priceCtrl.text = ((d['priceCents'] as int?) ?? 50) == 0
            ? '0'
            : (((d['priceCents'] as int?) ?? 50) / 100).toStringAsFixed(2);
      }
    });
    final st = d['status'] as String;
    lastStatus = st;

    // Nueva bola
    final b = List<int>.from((d['balls'] as List?) ?? const []);
    if (seenBalls < 0) {
      seenBalls = b.length; // al entrar no se cantan las bolas anteriores
      if (b.isNotEmpty) _ballAnim.value = 1;
    } else if (b.length > seenBalls) {
      seenBalls = b.length;
      _ballAnim.forward(from: 0);
      Sfx.play('tombola');
      Sfx.play('ball', delayMs: 1500);
      final n = b.last;
      calledAt[n] = nowMs() + 1550;
      Timer(const Duration(milliseconds: 1550 + missMs + 150), () {
        if (mounted) setState(() {});
      });
      Future<void>.delayed(const Duration(milliseconds: 1550), () {
        if (mounted && voiceOn) BingoVoice.say('${bingoLetter(n)}, $n');
      });
    } else if (b.length < seenBalls) {
      seenBalls = b.length;
      calledAt.clear();
      _ballAnim.value = 0;
    }

    // Nueva partida: las cartillas se renuevan
    if (st == 'lobby') {
      finishedShown = false;
      calledAt.clear();
      claimed = false;
      finalizing = false;
      drawTimer?.cancel();
      drawTimer = null;
      _syncMine();
    }

    // Anfitrión: dirige el sorteo
    if (isHost && st == 'playing' && drawTimer == null) {
      hostBalls = b;
      _startDrawing();
    }
    if (st != 'playing') {
      drawTimer?.cancel();
      drawTimer = null;
    }

    // Fin de la partida
    if (st == 'finished' && prevStatus != 'finished' && !finishedShown) {
      finishedShown = true;
      _onFinished(d);
    }
  }

  void _onFinished(Map<String, dynamic> d) {
    final winner = (d['winnerName'] as String?) ?? '';
    final winnerId = (d['winnerId'] as String?) ?? '';
    if (winnerId.isNotEmpty) {
      Sfx.play(winnerId == svc.uid ? 'win' : 'score', delayMs: 300);
      if (voiceOn) BingoVoice.say('¡Bingo! $winner');
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final prize = (d['prize'] as String?) ?? '';
      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(winnerId.isEmpty ? 'Se acabaron las bolas' : '¡BINGO! 🎉'),
          content: Text(winnerId.isEmpty
              ? 'Nadie completó la cartilla.'
              : '${winnerId == svc.uid ? '¡Ganaste tú!' : 'Ganó $winner'}'
                  '${prize.isEmpty ? '' : '\nPremio: $prize'}'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
          ],
        ),
      );
    });
  }

  // ------------------------------------------------------------------
  // Jugadores y cartillas
  // ------------------------------------------------------------------

  void _onPlayers(QuerySnapshot<Map<String, dynamic>> q) {
    if (!mounted) return;
    setState(() => playerDocs = q.docs);
    _syncMine();
    if (isHost && status == 'playing' && !finalizing) _checkClaims();
  }

  Map<String, dynamic>? _myDoc() {
    for (final d in playerDocs) {
      if (d.id == svc.uid) return d.data();
    }
    return null;
  }

  void _syncMine() {
    final r = room;
    final d = _myDoc();
    if (r == null || d == null) return;
    final round = r['round'] as int;
    final cards = List<String>.from((d['cards'] as List?) ?? const []);
    if ((d['round'] as int? ?? 0) != round || cards.isEmpty) {
      if (r['status'] == 'lobby') {
        _regen(max(1, cards.length), round);
      }
      return;
    }
    if (myRound != round || myCards.length != cards.length) {
      final marks = List<String>.from((d['marks'] as List?) ?? const []);
      myCards = [for (final s in cards) cardFromString(s)];
      myMarks = [
        for (var i = 0; i < cards.length; i++)
          i < marks.length ? marksFromString(marks[i]) : freshMarks()
      ];
      myRound = round;
    }
  }

  void _regen(int n, int round) {
    final rng = Random();
    myCards = [for (var i = 0; i < n; i++) generateBingoCard(rng)];
    myMarks = [for (var i = 0; i < n; i++) freshMarks()];
    myRound = round;
    claimed = false;
    _saveCards();
  }

  Future<void> _saveCards() {
    return svc.playersRef(code).doc(svc.uid).update({
      'cards': [for (final c in myCards) cardToString(c)],
      'marks': [for (final m in myMarks) marksToString(m)],
      'round': myRound,
      'bingo': null,
    });
  }

  void _setCount(int n) {
    n = n.clamp(1, 6);
    if (n == myCards.length || status != 'lobby') return;
    final rng = Random();
    setState(() {
      while (myCards.length < n) {
        myCards.add(generateBingoCard(rng));
        myMarks.add(freshMarks());
      }
      while (myCards.length > n) {
        myCards.removeLast();
        myMarks.removeLast();
      }
    });
    _saveCards();
  }

  void _tapCell(int ci, int idx) {
    if (status != 'playing' || claimed) return;
    final n = myCards[ci][idx];
    if (n == 0) return;
    final drawn = shownBalls.toSet();
    if (!drawn.contains(n)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 900),
            content: Text('Ese número todavía no ha salido')));
      return;
    }
    if (!myMarks[ci][idx] && _missed(n)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
            duration: Duration(milliseconds: 1200),
            content: Text('Se te pasó ese número: ya no se puede tachar')));
      return;
    }
    setState(() => myMarks[ci][idx] = !myMarks[ci][idx]);
    Sfx.play('tick');
    svc.playersRef(code).doc(svc.uid).update({
      'marks': [for (final m in myMarks) marksToString(m)],
    });
    if (cardComplete(myMarks[ci])) {
      claimed = true;
      svc.playersRef(code).doc(svc.uid).update({
        'bingo': {'card': ci, 'at': nowMs()},
      });
    }
  }

  // ------------------------------------------------------------------
  // Anfitrión: sorteo y validación
  // ------------------------------------------------------------------

  Future<void> _start() async {
    final cents = parseCents(priceCtrl.text) ?? priceCents;
    await svc.roomRef(code).update({
      'status': 'playing',
      'balls': <int>[],
      'paused': false,
      'prize': prizeCtrl.text.trim(),
      'priceCents': cents,
      'winnerId': '',
      'winnerName': '',
    });
    for (final d in playerDocs) {
      if (d.data()['bingo'] != null) {
        svc.playersRef(code).doc(d.id).update({'bingo': null});
      }
    }
    hostBalls = [];
  }

  void _startDrawing() {
    drawTimer?.cancel();
    final speed = (room?['speed'] as int?) ?? 6;
    drawTimer = Timer.periodic(Duration(seconds: speed), (_) => _drawBall());
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (mounted && drawTimer != null && hostBalls.isEmpty) _drawBall();
    });
  }

  void _drawBall() {
    if (!mounted || !isHost || status != 'playing') return;
    if (room?['paused'] == true) return;
    if (hostBalls.length >= bingoBalls) {
      drawTimer?.cancel();
      drawTimer = null;
      svc.roomRef(code).update({'status': 'finished', 'winnerId': '', 'winnerName': ''});
      return;
    }
    final remaining = [
      for (var i = 1; i <= bingoBalls; i++)
        if (!hostBalls.contains(i)) i
    ];
    final n = remaining[Random().nextInt(remaining.length)];
    hostBalls = [...hostBalls, n];
    svc.roomRef(code).update({'balls': hostBalls});
  }

  void _checkClaims() {
    final drawn = hostBalls.toSet();
    QueryDocumentSnapshot<Map<String, dynamic>>? best;
    var bestAt = 1 << 62;
    for (final d in playerDocs) {
      final b = d.data()['bingo'];
      if (b == null) continue;
      final ci = (b['card'] as int?) ?? 0;
      final cards = List<String>.from((d.data()['cards'] as List?) ?? const []);
      if (ci >= cards.length || !validBingo(cardFromString(cards[ci]), drawn)) {
        svc.playersRef(code).doc(d.id).update({'bingo': null});
        continue;
      }
      final at = (b['at'] as int?) ?? 0;
      if (at < bestAt) {
        bestAt = at;
        best = d;
      }
    }
    if (best != null) {
      finalizing = true;
      drawTimer?.cancel();
      drawTimer = null;
      svc.roomRef(code).update({
        'status': 'finished',
        'winnerId': best.id,
        'winnerName': (best.data()['name'] as String?) ?? '',
      });
    }
  }

  Future<void> _newGame() async {
    await svc.roomRef(code).update({
      'status': 'lobby',
      'balls': <int>[],
      'paused': false,
      'winnerId': '',
      'winnerName': '',
      'round': ((room?['round'] as int?) ?? 1) + 1,
    });
    hostBalls = [];
    seenBalls = 0;
  }

  void _savePrizeSoon() {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 500), () {
      final cents = parseCents(priceCtrl.text);
      svc.roomRef(code).update({
        'prize': prizeCtrl.text.trim(),
        if (cents != null) 'priceCents': cents,
      });
    });
  }

  // ------------------------------------------------------------------
  // Pantalla
  // ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bingo · Sala $code'),
        actions: [
          IconButton(
            tooltip: voiceOn ? 'Silenciar la voz del bot' : 'Activar la voz del bot',
            icon: Icon(voiceOn ? Icons.record_voice_over : Icons.voice_over_off),
            onPressed: () {
              setState(() => voiceOn = !voiceOn);
              if (!voiceOn) BingoVoice.stop();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: room == null
            ? const Center(child: CircularProgressIndicator())
            : (status == 'lobby' ? _lobby() : _game()),
      ),
    );
  }

  // ---------------- Sala de espera ----------------

  Widget _lobby() {
    final players = [...playerDocs]..sort((a, b) =>
        ((a.data()['joinedAt'] as int?) ?? 0)
            .compareTo((b.data()['joinedAt'] as int?) ?? 0));
    var totalCards = 0;
    for (final p in players) {
      totalCards += ((p.data()['cards'] as List?) ?? const []).length;
    }
    final myCount = myCards.length;
    final price = isHost ? (parseCents(priceCtrl.text) ?? priceCents) : priceCents;
    final prize = (room!['prize'] as String?) ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Center(child: Text('Comparte este código:')),
        Center(
          child: Text(code,
              style: const TextStyle(
                  fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: 6)),
        ),
        const SizedBox(height: 8),
        if (isHost) ...[
          TextField(
            controller: prizeCtrl,
            onChanged: (_) => _savePrizeSoon(),
            decoration: const InputDecoration(
                labelText: 'Premio de este juego',
                hintText: 'Ej: \$5, una torta, una pizza...',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              _savePrizeSoon();
              setState(() {});
            },
            decoration: const InputDecoration(
                labelText: 'Costo de cada cartilla (\$)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          const Text('Velocidad del bot cantor'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 4, label: Text('Rápido')),
              ButtonSegment(value: 6, label: Text('Normal')),
              ButtonSegment(value: 9, label: Text('Lento')),
            ],
            selected: {(room!['speed'] as int?) ?? 6},
            onSelectionChanged: (s) =>
                svc.roomRef(code).update({'speed': s.first}),
          ),
        ] else ...[
          Card(
            child: ListTile(
              leading: const Text('🎁', style: TextStyle(fontSize: 28)),
              title: Text(prize.isEmpty ? 'Premio por definir' : prize),
              subtitle: Text('Cada cartilla cuesta ${money(price)}'),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                const Text('Tus cartillas',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton.filled(
                      onPressed: myCount > 1 ? () => _setCount(myCount - 1) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text('$myCount',
                          style: const TextStyle(
                              fontSize: 32, fontWeight: FontWeight.bold)),
                    ),
                    IconButton.filled(
                      onPressed: myCount < 6 ? () => _setCount(myCount + 1) : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                Text('A pagar: ${money(price * myCount)}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Jugadores (${players.length})  ·  Cartillas: $totalCards  ·  Pozo: ${money(price * totalCards)}',
            style: Theme.of(context).textTheme.titleMedium),
        for (final p in players)
          ListTile(
            dense: true,
            leading: const Icon(Icons.person),
            title: Text((p.data()['name'] as String?) ?? ''),
            subtitle: Text(
                '${((p.data()['cards'] as List?) ?? const []).length} cartilla(s) · ${money(price * ((p.data()['cards'] as List?) ?? const []).length)}'),
            trailing: p.id == room!['hostId']
                ? const Chip(label: Text('Anfitrión'))
                : null,
          ),
        const SizedBox(height: 12),
        if (isHost)
          FilledButton.icon(
            onPressed: myCards.isEmpty ? null : _start,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Iniciar bingo'),
          )
        else
          const Center(child: Text('Esperando que el anfitrión inicie...')),
        const SizedBox(height: 8),
        const Text(
          'El costo y el premio son solo un aviso para ustedes. El cobro y la entrega del premio se hacen entre los jugadores, fuera de la app.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }

  // ---------------- Juego ----------------

  Widget _bigBall() {
    final b = balls;
    if (b.isEmpty) {
      return const Center(
        child: Text('🤖 El bot cantor sacará\nla primera bola...',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
      );
    }
    final v = _ballAnim.value.clamp(0.0, 1.0);
    // 0 a 0.55: la tómbola gira con las bolas; 0.55 a 1: sale la bola y crece.
    final q = ((v - 0.55) / 0.45).clamp(0.0, 1.0);
    final t = Curves.easeOutBack.transform(q);
    final m = Matrix4.identity()
      ..setEntry(3, 2, 0.0012)
      ..rotateY((1 - q) * 2 * pi)
      ..scale(0.2 + 0.8 * t, 0.2 + 0.8 * t, 1.0);
    final animating = v < 1.0 && seenBalls == b.length && _ballAnim.isAnimating;
    return LayoutBuilder(builder: (context, c) {
      final size = min(c.maxWidth, c.maxHeight) * 0.86;
      return Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            bottom: 4,
            child: Container(
              width: size * 0.7,
              height: size * 0.12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withOpacity(0.12 * q),
              ),
            ),
          ),
          if (animating)
            Opacity(
              opacity: (1 - q).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 1 - 0.25 * q,
                child: CustomPaint(
                  size: Size(size, size),
                  painter: _TombolaPainter(v * 2.8, Curves.easeIn.transform((v / 0.55).clamp(0.0, 1.0))),
                ),
              ),
            ),
          if (!animating || v >= 0.55)
            Transform(
              alignment: Alignment.center,
              transform: m,
              child: BingoBallWidget(n: b.last, size: size),
            ),
        ],
      );
    });
  }

  Widget _smallBalls() {
    final b = shownBalls.reversed.toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 4, 8, 4),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Salieron: ${b.length} de $bingoBalls',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  for (final n in b)
                    TweenAnimationBuilder<double>(
                      key: ValueKey(n),
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      builder: (context, s, child) =>
                          Transform.scale(scale: s, child: child),
                      child: BingoBallWidget(n: n, size: 32, showLetter: false),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _game() {
    final prize = (room!['prize'] as String?) ?? '';
    final finished = status == 'finished';
    final winner = (room!['winnerName'] as String?) ?? '';
    final winnerId = (room!['winnerId'] as String?) ?? '';
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Text(
            '🎁 ${prize.isEmpty ? 'Premio por definir' : prize}   ·   Cartilla ${money(priceCents)}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 190,
          child: Row(
            children: [
              Expanded(flex: 5, child: _bigBall()),
              Expanded(flex: 4, child: _smallBalls()),
            ],
          ),
        ),
        if (finished)
          Container(
            width: double.infinity,
            color: winnerId.isEmpty ? Colors.grey : Colors.green,
            padding: const EdgeInsets.all(8),
            child: Text(
              winnerId.isEmpty
                  ? 'Se acabaron las bolas'
                  : '¡BINGO de $winner! 🎉',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        if (isHost)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (status == 'playing')
                  OutlinedButton.icon(
                    onPressed: () => svc
                        .roomRef(code)
                        .update({'paused': !(room!['paused'] == true)}),
                    icon: Icon(room!['paused'] == true
                        ? Icons.play_arrow
                        : Icons.pause),
                    label: Text(room!['paused'] == true ? 'Continuar' : 'Pausar'),
                  ),
                if (finished)
                  FilledButton.icon(
                    onPressed: _newGame,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Nueva partida'),
                  ),
              ],
            ),
          ),
        Expanded(child: _cards()),
      ],
    );
  }

  Widget _cards() {
    if (myCards.isEmpty) {
      return const Center(child: Text('No tienes cartillas en esta partida.'));
    }
    final drawn = shownBalls.toSet();
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
      itemCount: myCards.length,
      itemBuilder: (context, ci) {
        return LayoutBuilder(builder: (context, c) {
          final cell = (c.maxWidth - 8) / 5;
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.black26, width: 2),
              boxShadow: const [
                BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3))
              ],
            ),
            child: Column(
              children: [
                if (myCards.length > 1)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text('Cartilla ${ci + 1} de ${myCards.length}',
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54)),
                  ),
                Row(
                  children: [
                    for (var col = 0; col < 5; col++)
                      Expanded(
                        child: Container(
                          height: cell * 0.7,
                          margin: const EdgeInsets.all(2),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: ballColor(col * 15 + 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(bingoLetters[col],
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: cell * 0.42,
                                  fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
                for (var r = 0; r < 5; r++)
                  Row(
                    children: [
                      for (var col = 0; col < 5; col++)
                        Expanded(child: _cell(ci, r * 5 + col, cell, drawn)),
                    ],
                  ),
              ],
            ),
          );
        });
      },
    );
  }

  Widget _cell(int ci, int idx, double cell, Set<int> drawn) {
    final n = myCards[ci][idx];
    final marked = myMarks[ci][idx];
    final free = n == 0;
    final missed = !marked && _missed(n);
    final shown = marked;
    final called = !free && drawn.contains(n);
    return GestureDetector(
      onTap: () => _tapCell(ci, idx),
      child: Container(
        height: cell,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: free
              ? Colors.amber.shade200
              : (missed
                  ? Colors.grey.shade400
                  : (shown ? const Color(0xFFFFF59D) : const Color(0xFFF5F5F5))),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: called && !marked && !missed ? Colors.orange : Colors.black12,
              width: called && !marked && !missed ? 2.5 : 1),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (free)
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star, size: cell * 0.4, color: Colors.orange.shade800),
                  Text('LIBRE',
                      style: TextStyle(
                          fontSize: cell * 0.18, fontWeight: FontWeight.bold)),
                ],
              )
            else if (missed)
              Icon(Icons.block, size: cell * 0.4, color: Colors.black26)
            else
              Text('$n',
                  style: TextStyle(
                      fontSize: cell * 0.46,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87)),
            if (shown && !free)
              Positioned.fill(child: CustomPaint(painter: _XPainter())),
          ],
        ),
      ),
    );
  }
}


/// Tómbola de bingo: jaula que gira con las bolas saltando adentro.
class _TombolaPainter extends CustomPainter {
  final double time; // segundos
  final double calm; // 0 = a toda marcha, 1 = casi quieta
  _TombolaPainter(this.time, this.calm);

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.46);
    final r = size.width * 0.40;
    // Soporte
    final stand = Paint()
      ..color = const Color(0xFF5D4037)
      ..strokeWidth = r * 0.09
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-r * 0.55, r * 0.85), c + Offset(-r * 0.8, r * 1.3), stand);
    canvas.drawLine(c + Offset(r * 0.55, r * 0.85), c + Offset(r * 0.8, r * 1.3), stand);
    canvas.drawLine(c + Offset(-r * 0.9, r * 1.3), c + Offset(r * 0.9, r * 1.3), stand);
    // Fondo de la jaula
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(0.55));
    // Bolas saltando
    for (var i = 0; i < 14; i++) {
      final w = (1.6 + (i % 5) * 0.55) * (1 - 0.6 * calm);
      final a = i * 2.399 + time * w * 3;
      final rr = r * (0.22 + 0.5 * ((i * 0.6180339) % 1));
      final p = Offset(c.dx + cos(a) * rr, c.dy + sin(a * 1.31 + i) * rr * 0.9);
      final br = r * 0.17;
      final col = ballColor(1 + (i * 13 + 5) % 75);
      canvas.drawCircle(
          p,
          br,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.5),
              colors: [Color.lerp(col, Colors.white, 0.7)!, col, Color.lerp(col, Colors.black, 0.45)!],
              stops: const [0.0, 0.55, 1.0],
            ).createShader(Rect.fromCircle(center: p, radius: br)));
      canvas.drawCircle(p, br * 0.45, Paint()..color = Colors.white.withOpacity(0.85));
    }
    // Barrotes que giran
    final ang = time * 4.5 * (1 - 0.7 * calm);
    final bar = Paint()
      ..color = const Color(0xFF90A4AE)
      ..strokeWidth = r * 0.04
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 6; k++) {
      final a = ang + k * pi / 3;
      canvas.drawLine(c, c + Offset(cos(a), sin(a)) * r, bar);
    }
    // Aro y manija
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFF455A64)
          ..strokeWidth = r * 0.07);
    final h = c + Offset(cos(ang), sin(ang)) * r * 1.12;
    canvas.drawCircle(h, r * 0.1, Paint()..color = const Color(0xFFFFB300));
    canvas.drawCircle(c, r * 0.08, Paint()..color = const Color(0xFF455A64));
  }

  @override
  bool shouldRepaint(covariant _TombolaPainter old) => true;
}
