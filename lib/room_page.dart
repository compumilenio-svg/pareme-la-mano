import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'basta_sheet.dart';
import 'game_service.dart';
import 'sfx.dart';

class RoomPage extends StatefulWidget {
  final String code;
  const RoomPage({super.key, required this.code});

  @override
  State<RoomPage> createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> with WidgetsBindingObserver {
  Map<String, dynamic>? room;
  int loadedRound = -1;
  final Map<String, TextEditingController> ctrls = {};
  bool submittedLocal = false;
  bool timeoutTriggered = false;
  bool completeTriggered = false;
  bool scoringStarted = false;
  bool cheatedLocal = false;
  Timer? ticker;
  Timer? debounce;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? playersSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> playerDocs = [];
  final Map<String, bool> myVotes = {};
  bool votedLocal = false;
  bool votingStarted = false;
  String? _lastStatus;
  int _lastSecs = -1;
  bool drawing = false; // la tómbola está girando
  bool letterShown = true;
  final GlobalKey letterKey = GlobalKey();
  final ScrollController hScroll = ScrollController();

  String get code => widget.code;
  bool get isHost => room?['hostId'] == svc.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
    playersSub = svc.playersStream(code).listen((q) => playerDocs = q.docs);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    debounce?.cancel();
    playersSub?.cancel();
    hScroll.dispose();
    for (final c in ctrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Anti-trampa: si la app pasa a segundo plano durante la ronda, vale 0.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final st = room?['status'];
    if (state == AppLifecycleState.paused &&
        (st == 'playing' || st == 'counting') &&
        !submittedLocal) {
      cheatedLocal = true;
      svc.markCheated(code);
    }
  }

  void _statusSound(String st) {
    switch (st) {
      case 'playing':
        Sfx.play('round_start');
      case 'counting':
        Sfx.play('alarm');
      case 'voting':
        Sfx.play('vote_start');
      case 'finished':
        Sfx.play('win');
        Sfx.play('applause', delayMs: 700);
      case 'lobby':
      case 'scoring':
        break;
      default:
        Sfx.play('score');
    }
  }

  void _onRoom(Map<String, dynamic> data) {
    room = data;
    final stNow = data['status'] as String;
    if (stNow != _lastStatus) {
      if (_lastStatus != null) _statusSound(stNow);
      _lastStatus = stNow;
      _lastSecs = -1;
    }
    final round = data['round'] as int;
    if (data['status'] == 'playing' && round != loadedRound) {
      loadedRound = round;
      submittedLocal = false;
      timeoutTriggered = false;
      completeTriggered = false;
      scoringStarted = false;
      votingStarted = false;
      cheatedLocal = false;
      myVotes.clear();
      votedLocal = false;
      // Solo giro la tómbola si la ronda acaba de empezar (no al reentrar).
      final startedAt = (data['roundEndsAt'] as int) - roundSeconds * 1000 - tombolaMs;
      final fresh = nowMs() - startedAt < 7000;
      drawing = fresh;
      letterShown = !fresh;
      if (hScroll.hasClients) hScroll.jumpTo(0);
      for (final c in ctrls.values) {
        c.dispose();
      }
      ctrls.clear();
      for (final cat in List<String>.from(data['categories'])) {
        ctrls[cat] = TextEditingController();
      }
    }
  }

  Map<String, String> _answers() =>
      {for (final e in ctrls.entries) e.key: e.value.text.trim()};

  bool _allComplete() {
    final letter = room!['letter'] as String;
    return ctrls.isNotEmpty &&
        ctrls.values.every((c) {
          // Solo se exige que empiece con la letra; si "parece palabra" lo
          // deciden los jugadores en la revisión (botón "Está bien").
          final w = normalize(c.text);
          return w.length >= 2 && w.startsWith(letter.toLowerCase());
        });
  }

  Future<void> _flush({bool submitted = false}) async {
    if (room == null || ctrls.isEmpty) return;
    final complete = _allComplete();
    await svc.saveAnswers(code, _answers(),
        finished: complete, submitted: submitted);
  }

  /// Botón "¡Páreme la mano!": lo presiona quien termina.
  Future<void> _parame() async {
    if (!_allComplete() || room!['status'] != 'playing') return;
    await _flush();
    await svc.triggerCountdown(code, svc.name);
  }

  void _onChanged(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 300), _flush);
  }

  void _tick() {
    final r = room;
    if (r == null || !mounted) return;
    final st = r['status'];
    final now = nowMs();
    if (st == 'playing' &&
        !timeoutTriggered &&
        now >= (r['roundEndsAt'] as int)) {
      timeoutTriggered = true;
      svc.triggerCountdown(code, '¡Se acabó el tiempo!');
    }
    if (st == 'counting') {
      final ends = r['countdownEndsAt'] as int;
      if (now >= ends && !submittedLocal) {
        submittedLocal = true;
        _flush(submitted: true);
      }
      // Solo el anfitrión controla el paso a votación y el cálculo de puntajes.
      if (isHost && now >= ends + 3000 && !votingStarted) {
        votingStarted = true;
        svc.startVoting(code);
      }
    }
    if (st == 'voting' && isHost && !scoringStarted) {
      final allVoted = playerDocs.isNotEmpty &&
          playerDocs
              .where((d) => d['cheated'] != true)
              .every((d) => d['voted'] == true);
      if (allVoted) {
        scoringStarted = true;
        svc.scoreRound(code);
      }
    }
    // Sonidos de la cuenta regresiva
    int? secs;
    var finalBuzz = false;
    if (st == 'counting') {
      secs = _secondsLeft(r['countdownEndsAt'] as int);
      finalBuzz = true;
    } else if (st == 'playing') {
      final s = _secondsLeft(r['roundEndsAt'] as int);
      if (s <= 10) secs = s;
    }
    if (secs != null && secs != _lastSecs) {
      _lastSecs = secs;
      if (secs > 0) {
        Sfx.play(st == 'counting' ? 'beep' : 'tick');
      } else if (finalBuzz) {
        Sfx.play('time_up');
      }
    }
    setState(() {});
  }

  int _secondsLeft(int endMs) {
    final ms = endMs - nowMs();
    return ms <= 0 ? 0 : (ms / 1000).ceil();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Sala ${widget.code}')),
      body: SafeArea(
        child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: svc.roomStream(code),
          builder: (context, snap) {
            if (!snap.hasData || !snap.data!.exists) {
              return const Center(child: CircularProgressIndicator());
            }
            _onRoom(snap.data!.data()!);
            switch (room!['status']) {
              case 'lobby':
                return _lobby();
              case 'playing':
              case 'counting':
                return _round();
              case 'voting':
                return _voting();
              case 'scoring':
                return const Center(
                    child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Calculando puntajes...'),
                  ],
                ));
              default:
                return _dashboard(finished: room!['status'] == 'finished');
            }
          },
        ),
      ),
    );
  }

  // ---------- Lobby ----------
  Widget _lobby() {
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
              const SizedBox(height: 16),
              Text('Jugadores (${players.length}/$maxPlayers)',
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
                  onPressed: players.length >= 2
                      ? () => svc.startRound(code, room!)
                      : null,
                  child: Text(players.length >= 2
                      ? 'Iniciar partida'
                      : 'Se necesitan al menos 2 jugadores'),
                )
              else
                const Text('Esperando que el anfitrión inicie...'),
            ],
          ),
        );
      },
    );
  }

  // ---------- Ronda ----------
  Widget _round() {
    final r = room!;
    final counting = r['status'] == 'counting';
    final letter = r['letter'] as String;
    final secs = counting
        ? _secondsLeft(r['countdownEndsAt'] as int)
        : _secondsLeft(r['roundEndsAt'] as int);
    final locked = submittedLocal || (counting && secs == 0) || drawing;
    final shown = counting ? secs : (secs > roundSeconds ? roundSeconds : secs);
    final cats = ctrls.keys.toList();
    return Stack(
      children: [
        Column(
          children: [
            if (counting)
              Container(
                width: double.infinity,
                color: Colors.red,
                padding: const EdgeInsets.all(12),
                child: Text(
                  '✋ ¡PÁREME LA MANO! (${r['countdownBy']})  —  $secs',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
            if (cheatedLocal)
              Container(
                width: double.infinity,
                color: Colors.orange,
                padding: const EdgeInsets.all(8),
                child: const Text(
                  'Saliste de la app: esta ronda vale 0 puntos.',
                  textAlign: TextAlign.center,
                ),
              ),
            Expanded(
              child: LinedPaper(
                child: ListView(
                  padding: const EdgeInsets.only(top: 10, bottom: 24),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(50, 4, 16, 6),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Ronda ${r['round']}/${r['totalRounds']}',
                              style: const TextStyle(
                                  fontFamily: kHandFont,
                                  fontSize: 24,
                                  color: Color(0xFF101010))),
                          Text(counting || drawing ? '' : '⏱ $shown s',
                              style: const TextStyle(
                                  fontFamily: kHandFont,
                                  fontSize: 26,
                                  color: Color(0xFF101010))),
                        ],
                      ),
                    ),
                    SketchTable(
                      cats: cats,
                      letter: letter,
                      letterShown: letterShown,
                      ctrls: ctrls,
                      locked: locked,
                      onChanged: _onChanged,
                      letterKey: letterKey,
                      scroll: hScroll,
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(50, 8, 16, 0),
                      child: Text(
                        'Escribe en cada casilla una palabra real que empiece con la letra.',
                        style: TextStyle(
                            fontFamily: kHandFont,
                            fontSize: 18,
                            color: Color(0xFF455A64)),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(50, 14, 16, 0),
                      child: Builder(builder: (context) {
                        final ready = !counting && !drawing && !locked && _allComplete();
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.red.shade700,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 22, vertical: 16),
                              ),
                              onPressed: ready ? _parame : null,
                              icon: const Text('✋', style: TextStyle(fontSize: 26)),
                              label: const Text('¡PÁREME LA MANO!',
                                  style: TextStyle(
                                      fontSize: 20, fontWeight: FontWeight.w900)),
                            ),
                            if (!ready && !counting && !drawing)
                              const Padding(
                                padding: EdgeInsets.only(top: 6),
                                child: Text(
                                  'Se activa cuando todas las casillas tienen una palabra válida.',
                                  style: TextStyle(
                                      fontFamily: kHandFont,
                                      fontSize: 16,
                                      color: Color(0xFF455A64)),
                                ),
                              ),
                          ],
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        if (drawing)
          Positioned.fill(
            child: LetterTombola(
              letter: letter,
              allLetters: letters,
              targetKey: letterKey,
              onDone: () {
                if (mounted) setState(() {
                  drawing = false;
                  letterShown = true;
                });
              },
            ),
          ),
      ],
    );
  }

  // ---------- Revisión (sin tiempo, todos ven todo) ----------
  Widget _voting() {
    final r = room!;
    final cats = List<String>.from(r['categories']);
    final letter = r['letter'] as String;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.playersStream(code),
      builder: (context, snap) {
        final all = [...(snap.data?.docs ?? [])]
          ..sort((x, y) => (x['joinedAt'] as int).compareTo(y['joinedAt'] as int));
        final active = all.where((d) => d['cheated'] != true).toList();
        final done = active.where((d) => d['voted'] == true).length;
        return Column(
          children: [
            Container(
              width: double.infinity,
              color: Colors.indigo,
              padding: const EdgeInsets.all(12),
              child: Text(
                'Revisen entre todos las palabras (la letra es $letter). '
                'Marquen las FALSAS. Sin prisa.  Listos: $done/${active.length}',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  for (final p in all)
                    Card(
                      color: p.id == svc.uid ? Colors.amber.shade50 : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                      p.id == svc.uid
                                          ? '${p['name']} (tú)'
                                          : '${p['name']}',
                                      style: Theme.of(context).textTheme.titleMedium),
                                ),
                                if (p['voted'] == true)
                                  const Chip(
                                      label: Text('Listo'),
                                      avatar: Icon(Icons.check, size: 16)),
                              ],
                            ),
                            if (p['cheated'] == true)
                              const Text('Salió de la app: sus palabras no valen.',
                                  style: TextStyle(color: Colors.red))
                            else
                              for (var ci = 0; ci < cats.length; ci++)
                                _voteRow(
                                    p.id,
                                    ci,
                                    cats[ci],
                                    letter,
                                    (Map<String, dynamic>.from(
                                            p['answers'] ?? {}))[cats[ci]]
                                        as String? ??
                                        ''),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: votedLocal
                          ? null
                          : () {
                              setState(() => votedLocal = true);
                              svc.saveVotes(code, myVotes, voted: true);
                            },
                      child: Text(votedLocal
                          ? 'Listo, esperando a los demás...'
                          : 'Ya revisé, estoy listo'),
                    ),
                  ),
                  if (isHost)
                    TextButton(
                      onPressed: () => svc.scoreRound(code),
                      child: const Text('Terminar la revisión ahora (anfitrión)'),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _voteRow(String pid, int ci, String cat, String letter, String word) {
    if (word.isEmpty) {
      return ListTile(
        dense: true,
        title: Text(cat),
        subtitle: const Text('(vacío)'),
      );
    }
    final formatOk = isValidWord(word, letter);
    final key = '$pid|$ci';
    final invalid = myVotes[key] == true;
    final mine = pid == svc.uid;
    final startsOk = normalize(word).startsWith(letter.toLowerCase());
    // Palabra que el filtro automático no reconoce pero que empieza bien:
    // los jugadores pueden decidir que "Está bien".
    final canApprove = !formatOk && startsOk && normalize(word).length >= 2;
    final approved = myVotes['$key|ok'] == true;
    final bad = invalid || (!formatOk && !approved);
    return ListTile(
      dense: true,
      title: Text(cat),
      subtitle: Text(
        formatOk
            ? word
            : (startsOk
                ? (approved
                    ? '$word  (tú dices que está bien)'
                    : '$word  (no parece una palabra; si está bien, toca "Está bien")')
                : '$word  (no empieza con $letter: no vale)'),
        style: TextStyle(
          decoration: bad ? TextDecoration.lineThrough : null,
          color: bad ? Colors.red : null,
        ),
      ),
      trailing: (formatOk && !mine)
          ? FilterChip(
              label: const Text('Falsa'),
              selected: invalid,
              onSelected: votedLocal
                  ? null
                  : (v) {
                      setState(() => myVotes[key] = v);
                      svc.saveVotes(code, myVotes);
                    },
            )
          : (canApprove && !mine)
              ? FilterChip(
                  label: const Text('Está bien'),
                  selected: approved,
                  onSelected: votedLocal
                      ? null
                      : (v) {
                          setState(() => myVotes['$key|ok'] = v);
                          svc.saveVotes(code, myVotes);
                        },
                )
              : null,
    );
  }

  // ---------- Dashboard ----------
  Widget _dashboard({required bool finished}) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: svc.playersStream(code),
      builder: (context, snap) {
        final docs = [...(snap.data?.docs ?? [])];
        final byRound = [...docs]..sort((a, b) =>
            (b['roundScore'] as int).compareTo(a['roundScore'] as int));
        final byTotal = [...docs]
          ..sort((a, b) => (b['total'] as int).compareTo(a['total'] as int));
        final t = Theme.of(context).textTheme;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (finished && byTotal.isNotEmpty)
              Card(
                color: Colors.amber.shade100,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('🏆 Ganador: ${byTotal.first['name']}',
                      textAlign: TextAlign.center, style: t.headlineSmall),
                ),
              ),
            Text('Puntajes de la ronda ${room!['round']}',
                style: t.titleLarge),
            const SizedBox(height: 8),
            for (final p in byRound)
              ListTile(
                title: Text(p['name']),
                subtitle: p['cheated'] == true
                    ? const Text('Salió de la app (0 puntos)')
                    : ((p.data()['rejected'] as List?)?.isNotEmpty ?? false)
                        ? Text(
                            'Palabras rechazadas: ${(p.data()['rejected'] as List).join(', ')}')
                        : null,
                trailing: Text('+${p['roundScore']}',
                    style: t.titleMedium),
              ),
            const Divider(height: 32),
            Text('Posiciones generales', style: t.titleLarge),
            const SizedBox(height: 8),
            for (var i = 0; i < byTotal.length; i++)
              ListTile(
                leading: CircleAvatar(child: Text('${i + 1}')),
                title: Text(byTotal[i]['name']),
                trailing: Text('${byTotal[i]['total']} pts',
                    style: t.titleMedium),
              ),
            const SizedBox(height: 16),
            if (!finished && isHost)
              FilledButton(
                onPressed: () => svc.startRound(code, room!),
                child: const Text('Siguiente ronda'),
              ),
            if (!finished && !isHost)
              const Center(child: Text('Esperando al anfitrión...')),
            if (finished)
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Salir'),
              ),
          ],
        );
      },
    );
  }
}
