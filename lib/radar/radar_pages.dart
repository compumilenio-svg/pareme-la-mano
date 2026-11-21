import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game_service.dart';
import '../sfx.dart';
import 'engine.dart';
import 'fx.dart';

// ======================================================================
// Servicio en línea (1 contra 1). Cada dispositivo guarda su flota en secreto
// y solo comparte el resultado de cada disparo recibido.
// ======================================================================

class RadarOnline {
  static Future<String> create(String name) async {
    svc.name = name;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'radar',
      'hostId': svc.uid,
      'status': 'lobby',
      'seats': [
        {'uid': svc.uid, 'name': name},
      ],
      'turn': 0,
      'streak': 0,
      'act': null,
      'res': null,
      'winner': -1,
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
      if (!snap.exists || snap.data()!['game'] != 'radar') {
        err = 'No existe una sala de Batalla naval con ese código.';
        return;
      }
      final d = snap.data()!;
      final seats = List<Map<String, dynamic>>.from(
          [for (final s in (d['seats'] as List)) Map<String, dynamic>.from(s as Map)]);
      if (seats.any((s) => s['uid'] == svc.uid)) return; // reingreso
      if (d['status'] != 'lobby') {
        err = 'La partida ya comenzó.';
        return;
      }
      if (seats.length >= 2) {
        err = 'La sala está llena (solo 2 jugadores).';
        return;
      }
      seats.add({'uid': svc.uid, 'name': name});
      tx.update(ref, {'seats': seats});
    });
    return err;
  }

  static Future<void> start(String code) => svc.roomRef(code).update({
        'status': 'playing',
        'turn': Random().nextInt(2),
        'streak': 0,
        'act': null,
        'res': null,
        'winner': -1,
      });

  static Future<void> surrender(String code, int winnerSeat) =>
      svc.roomRef(code).update({'status': 'finished', 'winner': winnerSeat});
}

// ======================================================================
// Menú
// ======================================================================

const List<String> kRadarLevels = ['Fácil', 'Normal'];

class RadarMenuPage extends StatefulWidget {
  const RadarMenuPage({super.key});

  @override
  State<RadarMenuPage> createState() => _RadarMenuPageState();
}

class _RadarMenuPageState extends State<RadarMenuPage> {
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  int level = 1;
  String? error;
  bool loading = false;

  String get _name => nameCtrl.text.trim().isEmpty ? 'Tú' : nameCtrl.text.trim();

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
      final code = await RadarOnline.create(name);
      _open(RadarMatchPage.online(code: code, name: name));
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
      final err = await RadarOnline.join(code, name);
      if (err != null) {
        setState(() => error = err);
      } else {
        _open(RadarMatchPage.online(code: code, name: name));
      }
    } catch (e) {
      setState(() => error = 'No se pudo entrar: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _help() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cómo se juega'),
        content: const SingleChildScrollView(
          child: Text(
            'Cada jugador tiene 5 barcos (de 5, 4, 3, 3 y 2 casillas) en un tablero de 10×10. '
            'Gana quien hunda toda la flota rival primero.\n\n'
            'Antes de empezar ubicas tu flota: arrastra los barcos, gíralos, y pon:\n'
            '🎭 3 señuelos en el agua: si el rival les dispara, ¡cree que impactó un barco!\n'
            '🛡️ 2 escudos sobre barcos: el escudo aguanta el primer disparo que reciba ese barco; '
            'ese turno el rival falla, el escudo se destruye y desde entonces el barco puede dañarse.\n\n'
            'Arriba está el tablero enemigo y abajo el tuyo. En el centro de cada tablero hay un cañón '
            'circular: toca una casilla del tablero enemigo y pulsa Disparar para lanzar el misil.\n\n'
            'Tienes 25 segundos por turno; si se acaba, la app dispara por ti.',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Entendido')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Batalla naval')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: Text('🚢', style: TextStyle(fontSize: 56))),
            const SizedBox(height: 8),
            const Text(
              'Batalla naval con cañones, señuelos y escudos. Hunde los 5 barcos rival antes que él.',
              textAlign: TextAlign.center,
            ),
            TextButton.icon(
              onPressed: _help,
              icon: const Icon(Icons.help_outline),
              label: const Text('Cómo se juega'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              inputFormatters: [LengthLimitingTextInputFormatter(20)],
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Tu nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            const Text('Dificultad de la PC', style: TextStyle(fontSize: 16)),
            const SizedBox(height: 6),
            SegmentedButton<int>(
              segments: [
                for (var i = 0; i < kRadarLevels.length; i++)
                  ButtonSegment(value: i, label: Text(kRadarLevels[i])),
              ],
              selected: {level},
              onSelectionChanged: (s) => setState(() => level = s.first),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () =>
                  _open(RadarMatchPage.local(name: _name, level: level)),
              icon: const Icon(Icons.smart_toy),
              label: const Text('Jugar contra la PC'),
            ),
            const Divider(height: 40),
            const Text('En línea 1 contra 1', style: TextStyle(fontSize: 18)),
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
// Partida (contra la PC o en línea)
// ======================================================================

const int _kTurnMs = 25000;
const Color _kWaterCell = Color(0x6614325C);
const int _kFlightMs = 800;
const int _kImpactMs = 900;

class RadarMatchPage extends StatefulWidget {
  final bool online;
  final String? code;
  final String name;
  final int level;
  const RadarMatchPage.local({super.key, required this.name, required this.level})
      : online = false,
        code = null;
  const RadarMatchPage.online({super.key, required this.code, required this.name})
      : online = true,
        level = 1;

  @override
  State<RadarMatchPage> createState() => _RadarMatchPageState();
}

class _RadarMatchPageState extends State<RadarMatchPage> with TickerProviderStateMixin {
  final rng = Random();
  late Fleet mine = Fleet.random(rng);
  final view = EnemyView();

  // contra la PC
  Fleet? botFleet;
  EnemyView? botView;
  BotBrain? brain;

  int mySeat = 0;
  int turn = 0;
  String enemyName = 'PC';
  String status = 'playing'; // setup | lobby | playing | finished
  int winner = -1;

  int sel = -1;
  bool busy = false;
  int myTurns = 0;

  String banner = 'Toca una casilla enemiga y dispara';
  Color bannerColor = Colors.blueGrey;
  int bannerKey = 0;
  final Set<int> flashEnemy = {};
  final Set<int> flashMine = {};

  Timer? ticker;
  int deadline = 0;
  int secsLeft = 25;
  bool endShown = false;

  // animaciones
  late final AnimationController flightCtl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: _kFlightMs));
  late final AnimationController impactCtl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: _kImpactMs));
  late final AnimationController pulseCtl =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController waveCtl =
      AnimationController(vsync: this, duration: const Duration(seconds: 7))..repeat();
  FxInfo? fx;
  Fleet? shownFleet;
  Future<void>? flightF;
  Future<void> _chain = Future<void>.value();

  // ubicar la flota
  int setupMode = 0; // 0 barcos · 1 señuelos · 2 escudos
  int selShip = -1;
  int dragShip = -1;
  int grabR = 0;
  int grabC = 0;
  int lastDragCell = -1;
  bool movedDrag = false;
  bool lockScroll = false;
  Offset downPos = Offset.zero;
  String setupMsg = 'Arrastra un barco, o toca uno y luego la casilla donde lo quieres.';

  // en línea
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
  Map<String, dynamic>? room;
  int appliedN = 0;
  int resolvedN = 0;
  String lastKey = '';
  String get code => widget.code ?? '';

  bool get myTurn => status == 'playing' && turn == mySeat;

  @override
  void initState() {
    super.initState();
    if (widget.online) {
      status = 'lobby';
      enemyName = 'Rival';
      sub = svc.roomStream(code).listen(_onRoom);
    } else {
      status = 'setup';
      botFleet = Fleet.random(rng);
      botView = EnemyView();
      brain = BotBrain(rng, level: widget.level);
    }
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void dispose() {
    ticker?.cancel();
    sub?.cancel();
    flightCtl.dispose();
    impactCtl.dispose();
    pulseCtl.dispose();
    waveCtl.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------
  // Utilidades
  // ------------------------------------------------------------------

  void _setBanner(String text, Color color) {
    banner = text;
    bannerColor = color;
    bannerKey++;
  }

  void _newTurn() {
    deadline = nowMs() + _kTurnMs;
    secsLeft = _kTurnMs ~/ 1000;
  }

  void _flash(Set<int> set, Iterable<int> cells) {
    set
      ..clear()
      ..addAll(cells);
    Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => set.clear());
    });
  }

  void _tick() {
    if (!mounted || status != 'playing') return;
    if (turn == mySeat && !busy) {
      final left = ((deadline - nowMs()) / 1000).ceil().clamp(0, 99).toInt();
      if (left != secsLeft) setState(() => secsLeft = left);
      if (nowMs() > deadline) _autoPlay();
    }
  }

  void _autoPlay() {
    final cand = [
      for (var c = 0; c < kCells; c++)
        if (view.canFire(c)) c,
    ];
    if (cand.isEmpty) return;
    sel = cand[rng.nextInt(cand.length)];
    _commit();
  }

  /// Texto del resultado. [byMe] = lo disparé yo.
  (String, Color) _describe(bool byMe, Outcome o) {
    final name = cellName(o.cell);
    if (o.res == kShield) {
      return byMe
          ? ('🛡️ ¡Escudo en $name! Tu disparo fue bloqueado y el escudo se destruyó',
              Colors.cyan.shade700)
          : ('🛡️ ¡Tu escudo te salvó en $name! Se destruyó', Colors.cyan.shade700);
    }
    if (o.sunk >= 0) {
      final n = kShips[o.sunk].name;
      return byMe
          ? ('💥 ¡Hundiste el $n!', Colors.green.shade700)
          : ('💥 ¡El rival hundió tu $n!', Colors.red.shade700);
    }
    if (o.res == kDecoy) {
      return byMe
          ? ('💥 ¡Impacto en $name!', Colors.deepOrange)
          : ('🎭 ¡Tu señuelo en $name engañó al rival!', Colors.green.shade700);
    }
    if (o.res == kHit) {
      return byMe
          ? ('💥 ¡Impacto en $name!', Colors.deepOrange)
          : ('💥 El rival te impactó en $name', Colors.deepOrange);
    }
    return byMe
        ? ('💧 Agua en $name', Colors.blueGrey)
        : ('💧 El rival falló en $name', Colors.blueGrey);
  }

  void _feedback(bool byMe, Outcome o) {
    String snd = 'tick';
    var heavy = false;
    if (o.res == kShield) {
      snd = 'sword_clash';
    } else if (o.sunk >= 0) {
      snd = 'chess_evaporate';
      heavy = true;
    } else if (o.res == kDecoy) {
      snd = byMe ? 'capture' : 'bonus';
      heavy = byMe;
    } else if (o.res == kHit) {
      snd = 'capture';
      heavy = true;
    }
    Sfx.play(snd);
    if (heavy) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  // ------------------------------------------------------------------
  // Mi disparo
  // ------------------------------------------------------------------

  Future<void> _commit() async {
    if (busy || !myTurn) return;
    if (sel < 0 || !view.canFire(sel)) return;
    final c = sel;
    setState(() => busy = true);
    HapticFeedback.mediumImpact();
    if (!widget.online) {
      final o = botFleet!.fire(c);
      await _flight(false, c);
      if (!mounted) return;
      _applyMine(o);
      await _impact(o);
      _clearFx();
      _afterLocal(mySeat, o);
    } else {
      flightF = _flight(false, c);
      final ok = await _sendOnline(c);
      if (!ok && mounted) {
        flightF = null;
        _clearFx();
        setState(() => busy = false);
      }
    }
  }

  void _applyMine(Outcome o) {
    view.apply(o.cell, o);
    myTurns++;
    final d = _describe(true, o);
    _feedback(true, o);
    setState(() {
      _flash(flashEnemy, [o.cell, ...o.sunkCells]);
      _setBanner(d.$1, d.$2);
      sel = -1;
    });
  }

  void _afterLocal(int actor, Outcome o) {
    if (!mounted) return;
    if (o.defeated) {
      _finish(actor);
      return;
    }
    setState(() {
      turn = 1 - actor;
      busy = false;
      _newTurn();
    });
    if (turn == 1) {
      Future<void>.delayed(const Duration(milliseconds: 700), _botMove);
    }
  }

  void _startLocal() {
    if (status != 'setup' || !mine.ready) return;
    setState(() {
      status = 'playing';
      selShip = -1;
      turn = rng.nextInt(2);
      _newTurn();
      if (turn == 1) {
        _setBanner('La PC empieza…', Colors.blueGrey);
      } else {
        _setBanner('¡Empiezas tú! Toca una casilla enemiga.', Colors.indigo);
      }
    });
    if (turn == 1) {
      Future<void>.delayed(const Duration(milliseconds: 1200), _botMove);
    }
  }

  void _botMove() {
    if (!mounted || status != 'playing' || turn != 1 || widget.online) return;
    final c = brain!.think(botView!);
    final pre = mine.copy();
    final o = mine.fire(c);
    final post = mine.copy();
    botView!.apply(c, o);
    brain!.observe(c, o, botView!);
    _enqueue(() => _incomingJob(o, pre, post, () async => _afterLocal(1, o)));
  }

  // ------------------------------------------------------------------
  // Animaciones (misil que sale de mi cañón / misil que llega del suyo)
  // ------------------------------------------------------------------

  void _enqueue(Future<void> Function() job) {
    _chain = _chain.then((_) async {
      if (!mounted) return;
      await job();
    }).catchError((Object _) {});
  }

  Future<void> _flight(bool incoming, int cell) async {
    if (!mounted) return;
    setState(() => fx = FxInfo(incoming, cell));
    flightCtl.forward(from: 0);
    pulseCtl.repeat();
    await Future<void>.delayed(const Duration(milliseconds: _kFlightMs));
  }

  Future<void> _impact(Outcome o) async {
    if (!mounted) return;
    setState(() => fx?.outcome = o);
    pulseCtl.stop();
    impactCtl.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: _kImpactMs + 150));
  }

  void _clearFx() {
    if (!mounted) return;
    setState(() {
      fx = null;
      shownFleet = null;
    });
    flightCtl.reset();
    impactCtl.reset();
    pulseCtl.stop();
  }

  /// El rival me dispara: su misil sale de su cañón (arriba) hacia mi tablero.
  Future<void> _incomingJob(
      Outcome o, Fleet pre, Fleet post, Future<void> Function() after) async {
    if (!mounted) return;
    setState(() {
      busy = true;
      shownFleet = pre;
      _setBanner('⚠️ ¡Misil enemigo en camino!', Colors.red.shade800);
    });
    HapticFeedback.mediumImpact();
    await _flight(true, o.cell);
    if (!mounted) return;
    final d = _describe(false, o);
    _feedback(false, o);
    setState(() {
      shownFleet = post;
      _flash(flashMine, [o.cell, ...o.sunkCells]);
      _setBanner(d.$1, d.$2);
    });
    await _impact(o);
    _clearFx();
    if (!mounted) return;
    setState(() => busy = false);
    await after();
  }

  /// Resultado de MI disparo (en línea): espera a que termine el vuelo y muestra el impacto.
  Future<void> _myResultJob(Outcome o) async {
    final f = flightF;
    flightF = null;
    if (f != null) {
      await f;
    } else {
      await _flight(false, o.cell);
    }
    if (!mounted) return;
    _applyMine(o);
    await _impact(o);
    _clearFx();
    if (mounted) setState(() => busy = false);
  }

  // ------------------------------------------------------------------
  // En línea
  // ------------------------------------------------------------------

  Future<bool> _sendOnline(int c) async {
    final ref = svc.roomRef(code);
    var ok = false;
    try {
      await svc.db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final d = snap.data();
        if (d == null) return;
        final an = ((d['act'] as Map?)?['n'] as num? ?? 0).toInt();
        final rn = ((d['res'] as Map?)?['n'] as num? ?? 0).toInt();
        if (d['status'] != 'playing' || (d['turn'] as num).toInt() != mySeat || an != rn) {
          return;
        }
        tx.update(ref, {
          'act': {'c': c, 'n': an + 1, 'by': mySeat},
        });
        ok = true;
      });
    } catch (_) {
      ok = false;
    }
    return ok;
  }

  /// El rival me disparó: resuelvo sobre MI flota, publico el resultado ya mismo
  /// y animo la llegada del misil en mi pantalla.
  void _resolveIncoming(Map<String, dynamic> act) {
    final c = (act['c'] as num).toInt();
    if (c < 0 || c >= kCells) return;
    final by = (act['by'] as num).toInt();
    final an = (act['n'] as num).toInt();
    final pre = mine.copy();
    final o = mine.fire(c);
    final post = mine.copy();
    _enqueue(() => _incomingJob(o, pre, post, () async {
          if (mounted && myTurn) setState(_newTurn);
        }));
    _publishResult(by, an, o);
  }

  Future<void> _publishResult(int by, int an, Outcome o) async {
    final ref = svc.roomRef(code);
    try {
      await svc.db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final doc = snap.data();
        if (doc == null) return;
        final rn = ((doc['res'] as Map?)?['n'] as num? ?? 0).toInt();
        if (rn >= an) return;
        tx.update(ref, {
          'res': {...o.toMap(), 'n': an},
          'turn': 1 - by,
          'streak': 0,
          if (o.defeated) 'status': 'finished',
          if (o.defeated) 'winner': by,
        });
      });
    } catch (_) {}
  }

  void _onRoom(DocumentSnapshot<Map<String, dynamic>> snap) {
    final d = snap.data();
    if (d == null || !mounted) return;
    room = d;
    final seats = [
      for (final s in (d['seats'] as List)) Map<String, dynamic>.from(s as Map),
    ];
    final me = seats.indexWhere((s) => s['uid'] == svc.uid);
    if (me < 0) return;
    mySeat = me;
    enemyName = seats.length > 1 ? (seats[1 - me]['name'] as String? ?? 'Rival') : 'Rival';
    final st = d['status'] as String? ?? 'lobby';
    final act = d['act'] as Map?;
    final res = d['res'] as Map?;
    final an = (act?['n'] as num? ?? 0).toInt();
    final rn = (res?['n'] as num? ?? 0).toInt();
    final by = (act?['by'] as num? ?? -1).toInt();
    if (st == 'playing' && act != null && an > rn && an > resolvedN && by >= 0 && by != mySeat) {
      resolvedN = an;
      _resolveIncoming(Map<String, dynamic>.from(act));
    }
    if ((st == 'playing' || st == 'finished') && res != null && rn > appliedN) {
      appliedN = rn;
      if (act != null && by == mySeat && rn == an) {
        final oo = Outcome.fromMap(Map<String, dynamic>.from(res));
        _enqueue(() => _myResultJob(oo));
      }
    }
    if (st == 'playing') {
      turn = (d['turn'] as num? ?? 0).toInt();
      final key = '$turn-$rn';
      if (key != lastKey) {
        lastKey = key;
        _newTurn();
        if (status != 'playing') {
          _setBanner(turn == mySeat ? '¡Empiezas tú! Toca una casilla enemiga.' : 'Empieza $enemyName…',
              Colors.indigo);
        }
      }
      status = 'playing';
      setState(() {});
    } else if (st == 'finished') {
      final w = (d['winner'] as num? ?? -1).toInt();
      _enqueue(() async => _finish(w));
    } else {
      status = 'lobby';
      setState(() {});
    }
  }

  // ------------------------------------------------------------------
  // Fin de partida
  // ------------------------------------------------------------------

  void _finish(int w) {
    if (endShown) return;
    endShown = true;
    final won = w == mySeat;
    setState(() {
      status = 'finished';
      winner = w;
      busy = false;
    });
    Sfx.play(won ? 'win' : 'lose');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dctx) => AlertDialog(
          title: Text(won ? '🏆 ¡Victoria!' : '💥 Derrota'),
          content: Text(won
              ? 'Hundiste toda la flota de $enemyName en $myTurns disparos.'
              : '$enemyName hundió toda tu flota.'),
          actions: [
            if (!widget.online)
              TextButton(
                onPressed: () {
                  Navigator.of(dctx).pop();
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) =>
                          RadarMatchPage.local(name: widget.name, level: widget.level)));
                },
                child: const Text('Jugar otra vez'),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(dctx).pop();
                Navigator.of(context).pop();
              },
              child: const Text('Salir'),
            ),
          ],
        ),
      );
    });
  }

  Future<void> _confirmSurrender() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (dctx) => AlertDialog(
        title: const Text('¿Rendirte?'),
        content: const Text('Perderás esta partida.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(false), child: const Text('Seguir')),
          TextButton(
              onPressed: () => Navigator.of(dctx).pop(true), child: const Text('Rendirme')),
        ],
      ),
    );
    if (yes != true) return;
    if (widget.online && status == 'playing') {
      try {
        await RadarOnline.surrender(code, 1 - mySeat);
      } catch (_) {}
    }
    endShown = true;
    if (mounted) Navigator.of(context).pop();
  }

  // ------------------------------------------------------------------
  // Tableros
  // ------------------------------------------------------------------

  void _tapCell(int c) {
    if (status != 'playing') return;
    if (!view.canFire(c)) return;
    HapticFeedback.selectionClick();
    setState(() => sel = c);
  }

  Widget _oceanBox(double side, double radius, Color border, Widget child) => Container(
        width: side,
        height: side,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border, width: 2),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius - 2),
          child: Stack(
            children: [
              Positioned.fill(child: CustomPaint(painter: OceanPainter(waveCtl))),
              child,
            ],
          ),
        ),
      );

  Widget _enemyCell(int c, double size) {
    final st = view.st[c];
    Color bg = _kWaterCell;
    String icon = '';
    switch (st) {
      case 1:
        bg = const Color(0xFF0B1B33);
        icon = '•';
        break;
      case 2:
        bg = const Color(0xFFE64A19);
        icon = '💥';
        break;
      case 3:
        bg = const Color(0xFF00838F);
        icon = '🛡️';
        break;
      case 4:
        bg = const Color(0xFF6D1B1B);
        icon = '🔥';
        break;
    }
    final isSel = c == sel;
    final fl = flashEnemy.contains(c);
    return GestureDetector(
      onTap: () => _tapCell(c),
      child: AnimatedScale(
        scale: fl ? 1.2 : 1.0,
        duration: const Duration(milliseconds: 220),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: size - 2,
          height: size - 2,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSel ? Colors.amber : Colors.white12,
              width: isSel ? 2.5 : 0.5,
            ),
            boxShadow: fl ? [const BoxShadow(color: Colors.white54, blurRadius: 8)] : null,
          ),
          alignment: Alignment.center,
          child: Text(icon,
              style: TextStyle(
                  fontSize: st == 1 ? size * 0.4 : size * 0.52,
                  color: st == 1 ? Colors.lightBlueAccent : null)),
        ),
      ),
    );
  }

  Widget _enemyGrid(double side) {
    return _oceanBox(
      side,
      10,
      Colors.redAccent,
      Column(
        children: [
          for (var r = 0; r < kN; r++)
            Row(children: [
              for (var c = 0; c < kN; c++) _enemyCell(r * kN + c, (side - 4) / kN),
            ]),
        ],
      ),
    );
  }

  Widget _myCell(int c, double size, Fleet f, bool edit) {
    final s = f.cellShip[c];
    final shot = f.shot[c];
    Color bg = _kWaterCell;
    String icon = '';
    if (s >= 0) {
      bg = shot ? const Color(0xFF5D4037) : const Color(0xFF607D8B);
      if (shot) {
        icon = '💥';
      } else if (f.shield[s]) {
        bg = const Color(0xFF00838F);
        if (f.shipCells[s].first == c) icon = '🛡️';
      }
    } else if (f.decoys.contains(c)) {
      icon = '🎭';
      if (shot) bg = const Color(0xFF3E2723);
    } else if (shot) {
      bg = const Color(0xFF0B1B33);
      icon = '•';
    }
    final picked = edit && s >= 0 && s == selShip;
    final shielded = s >= 0 && !shot && f.shield[s];
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: size - 1.6,
      height: size - 1.6,
      margin: const EdgeInsets.all(0.8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
        border: picked
            ? Border.all(color: Colors.amber, width: 2.5)
            : flashMine.contains(c)
                ? Border.all(color: Colors.redAccent, width: 2.5)
                : shielded
                    ? Border.all(color: Colors.cyanAccent, width: 1.5)
                    : Border.all(color: Colors.white12, width: 0.5),
      ),
      alignment: Alignment.center,
      child: Text(icon, style: TextStyle(fontSize: size * 0.5)),
    );
  }

  Widget _myGrid(double side, Fleet f, {bool edit = false}) {
    return _oceanBox(
      side,
      10,
      Colors.greenAccent,
      Column(
        children: [
          for (var r = 0; r < kN; r++)
            Row(children: [
              for (var c = 0; c < kN; c++) _myCell(r * kN + c, (side - 4) / kN, f, edit),
            ]),
        ],
      ),
    );
  }

  /// Pantalla dividida: enemigo arriba, mis barcos abajo, y un cañón circular
  /// en el centro de cada tablero desde donde salen los misiles.
  Widget _battleArea(double side, double gap, double width) {
    final cell = (side - 4) / kN;
    final ox = (width - side) / 2;
    return AnimatedBuilder(
      animation: impactCtl,
      builder: (context, child) {
        var dx = 0.0, dy = 0.0;
        final cur = fx;
        if (cur != null && cur.heavy && impactCtl.isAnimating) {
          final u = impactCtl.value;
          dx = sin(u * 50) * 7 * (1 - u);
          dy = cos(u * 43) * 5 * (1 - u);
        }
        return Transform.translate(offset: Offset(dx, dy), child: child);
      },
      child: SizedBox(
        width: width,
        height: side * 2 + gap,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(left: ox, top: 0, child: _enemyGrid(side)),
            Positioned(left: ox, top: side + gap, child: _myGrid(side, shownFleet ?? mine)),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: FxPainter(
                    fx: fx,
                    flight: flightCtl,
                    impact: impactCtl,
                    pulse: pulseCtl,
                    cell: cell,
                    side: side - 4,
                    enemyO: Offset(ox + 2, 2),
                    myO: Offset(ox + 2, side + gap + 2),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Ubicar la flota (barcos, señuelos y escudos)
  // ------------------------------------------------------------------

  int _cellAt(Offset p, double side) {
    final cell = (side - 4) / kN;
    final c = ((p.dx - 2) / cell).floor().clamp(0, kN - 1).toInt();
    final r = ((p.dy - 2) / cell).floor().clamp(0, kN - 1).toInt();
    return r * kN + c;
  }

  String get _modeHint {
    switch (setupMode) {
      case 1:
        return 'Toca casillas de agua para poner tus 3 señuelos 🎭 (el rival creerá que son barcos).';
      case 2:
        return 'Toca un barco para ponerle o quitarle un escudo 🛡️ (aguanta 1 disparo).';
      default:
        return 'Arrastra un barco, o toca uno y luego la casilla donde lo quieres.';
    }
  }

  void _downEdit(PointerDownEvent e, double side) {
    final c = _cellAt(e.localPosition, side);
    downPos = e.localPosition;
    setState(() {
      movedDrag = false;
      lastDragCell = c;
      dragShip = -1;
      lockScroll = setupMode == 0;
      if (setupMode == 0) {
        final s = mine.cellShip[c];
        if (s >= 0) {
          dragShip = s;
          selShip = s;
          final o = mine.originOf(s);
          grabR = c ~/ kN - o.$1;
          grabC = c % kN - o.$2;
          setupMsg = 'Arrástralo o usa «Girar». Toca otra casilla para moverlo ahí.';
          HapticFeedback.selectionClick();
        }
      }
    });
  }

  void _moveEdit(PointerMoveEvent e, double side) {
    if (setupMode != 0 || dragShip < 0) return;
    final c = _cellAt(e.localPosition, side);
    if (c == lastDragCell) return;
    lastDragCell = c;
    if (mine.moveShip(dragShip, c ~/ kN - grabR, c % kN - grabC)) movedDrag = true;
    setState(() {});
  }

  void _upEdit(PointerEvent e, double side) {
    final c = _cellAt(e.localPosition, side);
    final tap = (e.localPosition - downPos).distance < 14;
    setState(() {
      final wasDrag = dragShip >= 0;
      lockScroll = false;
      dragShip = -1;
      if (setupMode == 0) {
        if (!wasDrag && !movedDrag && selShip >= 0 && tap) {
          final len = kShips[selShip].len;
          final h = mine.isHoriz(selShip);
          final ok = mine.moveShip(
              selShip, c ~/ kN - (h ? 0 : len ~/ 2), c % kN - (h ? len ~/ 2 : 0));
          if (!ok) {
            HapticFeedback.heavyImpact();
            setupMsg = 'Ahí no cabe: choca con otro barco o con un señuelo.';
          } else {
            HapticFeedback.selectionClick();
            setupMsg = 'Listo. Puedes seguir moviendo o girando.';
          }
        }
      } else if (tap) {
        final err = setupMode == 1 ? mine.toggleDecoy(c) : mine.toggleShield(c);
        if (err != null) {
          HapticFeedback.heavyImpact();
        } else {
          HapticFeedback.selectionClick();
        }
        setupMsg = err ?? _modeHint;
      }
    });
  }

  void _rotateSel() {
    if (selShip < 0) return;
    final ok = mine.rotateShip(selShip);
    HapticFeedback.selectionClick();
    setState(() => setupMsg = ok ? 'Girado.' : 'No hay espacio para girarlo ahí.');
  }

  Widget _placement(double side) {
    return Column(
      children: [
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: 0, label: Text('⚓ Barcos', style: TextStyle(fontSize: 12))),
            ButtonSegment(
                value: 1,
                label: Text('🎭 Señuelos ${mine.decoyCount}/$kDecoyCount',
                    style: const TextStyle(fontSize: 12))),
            ButtonSegment(
                value: 2,
                label: Text('🛡️ Escudos ${mine.shieldCount}/$kShieldCount',
                    style: const TextStyle(fontSize: 12))),
          ],
          selected: {setupMode},
          onSelectionChanged: (s) => setState(() {
            setupMode = s.first;
            setupMsg = _modeHint;
          }),
        ),
        const SizedBox(height: 8),
        Text(setupMsg,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Colors.black54)),
        const SizedBox(height: 8),
        Center(
          child: Listener(
            onPointerDown: (e) => _downEdit(e, side),
            onPointerMove: (e) => _moveEdit(e, side),
            onPointerUp: (e) => _upEdit(e, side),
            onPointerCancel: (e) => setState(() {
              lockScroll = false;
              dragShip = -1;
            }),
            child: _myGrid(side, mine, edit: true),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: setupMode == 0 && selShip >= 0 ? _rotateSel : null,
              icon: const Icon(Icons.rotate_right),
              label: const Text('Girar'),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                mine = Fleet.random(rng);
                selShip = -1;
                setupMsg = 'Flota barajada. Ajústala como quieras.';
              }),
              icon: const Icon(Icons.shuffle),
              label: const Text('Barajar'),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text('Barcos: 5 · 4 · 3 · 3 · 2 casillas',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _setup() {
    final side = min(MediaQuery.of(context).size.width - 40, 360.0);
    return ListView(
      physics: lockScroll ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Ubica tu flota',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _placement(side),
        const SizedBox(height: 14),
        SizedBox(
          height: 54,
          child: FilledButton.icon(
            onPressed: mine.ready ? _startLocal : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(mine.ready ? '¡A la batalla!' : 'Pon 3 señuelos y 2 escudos',
                style: const TextStyle(fontSize: 18)),
          ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------
  // HUD y controles
  // ------------------------------------------------------------------

  Widget _hud() {
    final chips = <Widget>[];
    for (var k = 0; k < kShips.length; k++) {
      final down = view.sunkShips.contains(k);
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Opacity(
          opacity: down ? 0.35 : 1,
          child: Text('▮' * kShips[k].len,
              style: TextStyle(
                  fontSize: 11,
                  color: Colors.red.shade700,
                  decoration: down ? TextDecoration.lineThrough : null)),
        ),
      ));
    }
    final mt = myTurn;
    return Container(
      color: mt ? Colors.indigo.shade50 : Colors.grey.shade200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mt ? 'Tu turno · ${secsLeft}s' : 'Turno de $enemyName…',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: mt ? Colors.indigo : Colors.black54),
                ),
                LinearProgressIndicator(
                  value: mt ? (secsLeft / (_kTurnMs / 1000)).clamp(0.0, 1.0).toDouble() : 0.0,
                  minHeight: 3,
                  color: secsLeft <= 5 ? Colors.red : Colors.indigo,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('Flota enemiga', style: TextStyle(fontSize: 10, color: Colors.black54)),
              Wrap(children: chips),
            ],
          ),
        ],
      ),
    );
  }

  String get _fireLabel {
    if (!myTurn) return 'Esperando al rival…';
    if (busy) return 'Disparando…';
    if (sel < 0) return 'Toca una casilla enemiga';
    return '🎯 Disparar a ${cellName(sel)}';
  }

  Widget _controls() {
    final canGo = myTurn && !busy && sel >= 0 && view.canFire(sel);
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: FilledButton(
          onPressed: canGo ? _commit : null,
          child: Text(_fireLabel, style: const TextStyle(fontSize: 18)),
        ),
      ),
    );
  }

  Widget _lobby() {
    final seats = room == null ? 1 : (room!['seats'] as List).length;
    final isHost = room != null && room!['hostId'] == svc.uid;
    return ListView(
      physics: lockScroll ? const NeverScrollableScrollPhysics() : const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Código de sala', textAlign: TextAlign.center),
        Text(code,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 44, fontWeight: FontWeight.bold, letterSpacing: 6)),
        const SizedBox(height: 8),
        Text(seats < 2 ? 'Esperando al rival… ($seats/2)' : 'Rival: $enemyName',
            textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 16),
        const Text('Ubica tu flota (solo tú la ves):',
            textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        _placement(min(MediaQuery.of(context).size.width - 64, 340.0)),
        const SizedBox(height: 8),
        if (isHost)
          FilledButton.icon(
            onPressed: seats == 2 && mine.ready ? () => RadarOnline.start(code) : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(mine.ready ? 'Empezar partida' : 'Pon 3 señuelos y 2 escudos'),
          )
        else
          const Text('Espera a que el anfitrión empiece la partida.',
              textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text(
            'Tu flota queda guardada solo en tu dispositivo. Si cierras la app durante la partida, no podrás volver a entrar.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final playing = status != 'lobby' && status != 'setup';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.online ? 'vs $enemyName' : 'vs PC'),
        actions: [
          IconButton(
            tooltip: 'Rendirme',
            onPressed: _confirmSurrender,
            icon: const Icon(Icons.flag),
          ),
        ],
      ),
      body: SafeArea(
        child: !playing
            ? (status == 'setup' ? _setup() : _lobby())
            : Column(
                children: [
                  _hud(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        const gap = 10.0;
                        final side = max(
                            100.0, min(box.maxWidth - 16, (box.maxHeight - gap - 4) / 2));
                        return Center(child: _battleArea(side, gap, box.maxWidth));
                      },
                    ),
                  ),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Container(
                      key: ValueKey(bannerKey),
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                      color: bannerColor,
                      child: Text(banner,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                  _controls(),
                ],
              ),
      ),
    );
  }
}
