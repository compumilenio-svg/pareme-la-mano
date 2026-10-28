import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'game_service.dart';

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

  String get code => widget.code;
  bool get isHost => room?['hostId'] == svc.uid;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker?.cancel();
    debounce?.cancel();
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

  void _onRoom(Map<String, dynamic> data) {
    room = data;
    final round = data['round'] as int;
    if (data['status'] == 'playing' && round != loadedRound) {
      loadedRound = round;
      submittedLocal = false;
      timeoutTriggered = false;
      completeTriggered = false;
      scoringStarted = false;
      cheatedLocal = false;
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
        ctrls.values.every((c) => isValidWord(c.text, letter));
  }

  Future<void> _flush({bool submitted = false}) async {
    if (room == null || ctrls.isEmpty) return;
    final complete = _allComplete();
    await svc.saveAnswers(code, _answers(),
        finished: complete, submitted: submitted);
    if (complete && !completeTriggered && room!['status'] == 'playing') {
      completeTriggered = true;
      await svc.triggerCountdown(code, svc.name);
    }
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
      // Solo el anfitrión calcula los puntajes (las reglas de Firestore así lo exigen).
      if (isHost && now >= ends + 3000 && !scoringStarted) {
        scoringStarted = true;
        svc.scoreRound(code);
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
    final locked = submittedLocal || (counting && secs == 0);
    return Column(
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
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Ronda ${r['round']}/${r['totalRounds']}'),
              Text(letter,
                  style: const TextStyle(
                      fontSize: 56, fontWeight: FontWeight.bold)),
              Text(counting ? '' : '⏱ $secs s',
                  style: const TextStyle(fontSize: 20)),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final e in ctrls.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: e.value,
                    enabled: !locked,
                    onChanged: _onChanged,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: e.key,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
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
