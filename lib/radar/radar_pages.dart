import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../game_service.dart';
import '../sfx.dart';
import 'engine.dart';

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
        err = 'No existe una sala de Asalto Radar con ese código.';
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
            'Cada jugador esconde 6 módulos en un tablero de 8×8.\n\n'
            '🎯 Objetivos (gana quien destruya los 4 primero):\n'
            '💠 Núcleo (cruz de 5)\n🗼 Torre (línea de 4)\n📡 Antena (L de 3)\n'
            '🛡️ Blindado (2×2): cada casilla aguanta 2 impactos.\n\n'
            '⚠️ Señuelos:\n'
            '💣 Mina: quien la toca pierde su siguiente turno.\n'
            '🎁 Baliza: turno extra y te revela una casilla enemiga.\n\n'
            'En tu turno elige una acción y una casilla, y pulsa el botón grande:\n'
            '• Disparo: 1 casilla, sin límite.\n'
            '• 🔍 Escaneo (×2): cuántos objetivos hay en un área de 3×3.\n'
            '• ⚡ Onda (×2): cuántos objetivos hay en una fila o columna.\n'
            '• 🚀 Misil (×1): impacta una cruz de 5 casillas.\n\n'
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
      appBar: AppBar(title: const Text('Asalto Radar')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: Text('📡', style: TextStyle(fontSize: 56))),
            const SizedBox(height: 8),
            const Text(
              'Esconde tus módulos, escanea el tablero rival y destruye sus 4 objetivos antes que él. Partidas de 3 a 5 minutos.',
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
const Color _kWater = Color(0xFF14325C);

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

class _RadarMatchPageState extends State<RadarMatchPage> {
  final rng = Random();
  late Fleet mine = Fleet.random(rng);
  final view = EnemyView();
  final ammo = Ammo();

  // contra la PC
  Fleet? botFleet;
  EnemyView? botView;
  BotBrain? brain;
  Ammo? botAmmo;

  int mySeat = 0;
  int turn = 0;
  int streak = 0;
  String enemyName = 'PC';
  String status = 'playing'; // lobby | playing | finished
  int winner = -1;

  int tool = kFire;
  int sel = -1;
  int wvert = 0;
  bool busy = false;
  int myTurns = 0;

  String banner = 'Elige una casilla y dispara';
  Color bannerColor = Colors.blueGrey;
  int bannerKey = 0;
  final Set<int> flashEnemy = {};
  final Set<int> flashMine = {};

  Timer? ticker;
  int deadline = 0;
  int secsLeft = 25;
  bool endShown = false;

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
      botFleet = Fleet.random(rng);
      botView = EnemyView();
      brain = BotBrain(rng, level: widget.level);
      botAmmo = Ammo();
      turn = rng.nextInt(2);
      _newTurn();
      if (turn == 1) {
        _setBanner('La PC empieza…', Colors.blueGrey);
        Future<void>.delayed(const Duration(milliseconds: 1200), _botMove);
      } else {
        _setBanner('¡Empiezas tú! Elige una casilla.', Colors.indigo);
      }
    }
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void dispose() {
    ticker?.cancel();
    sub?.cancel();
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
    tool = kFire;
    sel = cand[rng.nextInt(cand.length)];
    _commit();
  }

  String _kindName(int k) => kKinds[k].name;

  /// Texto del resultado. [byMe] = lo hice yo.
  (String, Color) _describe(bool byMe, RAction a, Outcome o) {
    if (a.kind == kScan) {
      return byMe
          ? (
              '🔍 Escaneo en ${cellName(a.a)}: ${o.count} ${o.count == 1 ? 'módulo' : 'módulos'} en el área',
              Colors.teal
            )
          : ('🔍 El rival escaneó tu zona de ${cellName(a.a)}', Colors.blueGrey);
    }
    if (a.kind == kWave) {
      final name = a.b == 0 ? 'la fila ${a.a + 1}' : 'la columna ${'ABCDEFGH'[a.a]}';
      return byMe
          ? ('⚡ Onda: ${o.count} ${o.count == 1 ? 'módulo' : 'módulos'} en $name', Colors.teal)
          : ('⚡ El rival lanzó una onda sobre $name', Colors.blueGrey);
    }
    final prefix = a.kind == kMissile ? '🚀 ' : '';
    ShotOut? downReal, mine_, beacon, shield, hit, miss;
    var hits = 0;
    for (final s in o.shots) {
      if (s.result == kHit || s.result == kShield) hits++;
      if (s.modDown && s.modKind >= 0 && s.modKind < kRealKinds) downReal = s;
      if (s.result == kMine) mine_ = s;
      if (s.result == kBeacon) beacon = s;
      if (s.result == kShield) shield = s;
      if (s.result == kHit) hit = s;
      if (s.result == kMiss) miss = s;
    }
    if (downReal != null) {
      final n = _kindName(downReal.modKind);
      return byMe
          ? ('$prefix💥 ¡$n destruido!', Colors.green.shade700)
          : ('$prefix💥 ¡El rival destruyó tu $n!', Colors.red.shade700);
    }
    if (mine_ != null) {
      return byMe
          ? ('$prefix💣 ¡Trampa! Pierdes tu siguiente turno', Colors.red.shade700)
          : ('$prefix💣 El rival pisó una trampa: ¡juegas dos veces!', Colors.green.shade700);
    }
    if (beacon != null) {
      return byMe
          ? ('$prefix🎁 ¡Baliza! Turno extra y una pista 🎯', Colors.amber.shade800)
          : ('$prefix🎁 El rival halló una baliza: repite turno', Colors.amber.shade800);
    }
    if (shield != null) {
      return byMe
          ? ('$prefix🛡️ ¡Escudo activado! Aguanta un impacto más', Colors.cyan.shade700)
          : ('$prefix🛡️ ¡Tu escudo resistió!', Colors.cyan.shade700);
    }
    if (hit != null) {
      final extra = a.kind == kMissile ? ' ($hits casillas)' : '';
      return byMe
          ? ('$prefix💥 ¡Impacto!$extra', Colors.deepOrange)
          : ('$prefix💥 El rival te impactó$extra', Colors.deepOrange);
    }
    if (miss != null) {
      return byMe
          ? ('$prefix💧 Agua…', Colors.blueGrey)
          : ('$prefix💧 El rival falló', Colors.blueGrey);
    }
    return ('', Colors.blueGrey);
  }

  void _feedback(RAction a, Outcome o) {
    String snd = 'tick';
    var heavy = false;
    if (a.kind == kScan) {
      snd = 'beep';
    } else if (a.kind == kWave) {
      snd = 'round_start';
    } else {
      for (final s in o.shots) {
        if (s.modDown && s.modKind >= 0 && s.modKind < kRealKinds) {
          snd = 'chess_evaporate';
          heavy = true;
        } else if (s.result == kMine) {
          snd = 'alarm';
          heavy = true;
        } else if (s.result == kBeacon) {
          snd = 'bonus';
        } else if (s.result == kShield && snd == 'tick') {
          snd = 'sword_clash';
        } else if (s.result == kHit && (snd == 'tick' || snd == 'sword_clash')) {
          snd = 'capture';
          heavy = true;
        }
      }
      if (a.kind == kMissile && snd == 'tick') snd = 'chess_clash';
    }
    Sfx.play(snd);
    if (heavy) {
      HapticFeedback.heavyImpact();
    } else {
      HapticFeedback.lightImpact();
    }
  }

  // ------------------------------------------------------------------
  // Mi acción
  // ------------------------------------------------------------------

  RAction? _buildAction() {
    if (sel < 0) return null;
    if (tool == kWave) return RAction(kWave, wvert == 0 ? sel ~/ kN : sel % kN, wvert);
    if (tool == kFire && !view.canFire(sel)) return null;
    return RAction(tool, sel);
  }

  Future<void> _commit() async {
    if (busy || !myTurn) return;
    final a = _buildAction();
    if (a == null || ammo.left(a.kind) <= 0) return;
    setState(() => busy = true);
    if (!widget.online) {
      ammo.use(a.kind);
      final o = botFleet!.apply(a, rng);
      _applyMine(a, o);
      _afterLocal(mySeat, o);
    } else {
      final ok = await _sendOnline(a);
      if (!ok && mounted) setState(() => busy = false);
    }
  }

  void _applyMine(RAction a, Outcome o) {
    view.apply(a, o);
    myTurns++;
    final cells = a.kind == kScan
        ? boxOf(a.a)
        : a.kind == kWave
            ? lineOf(a.a, a.b)
            : [for (final s in o.shots) s.cell];
    final d = _describe(true, a, o);
    _feedback(a, o);
    setState(() {
      _flash(flashEnemy, cells);
      _setBanner(d.$1, d.$2);
      sel = -1;
      if (ammo.left(tool) <= 0) tool = kFire;
    });
  }

  void _afterLocal(int actor, Outcome o) {
    if (!mounted) return;
    if (o.defeated) {
      _finish(actor);
      return;
    }
    final nt = nextTurn(actor, o, streak);
    setState(() {
      turn = nt.$1;
      streak = nt.$2;
      busy = false;
      _newTurn();
    });
    if (turn == 1) {
      Future<void>.delayed(const Duration(milliseconds: 1300), _botMove);
    }
  }

  void _botMove() {
    if (!mounted || status != 'playing' || turn != 1 || widget.online) return;
    final a = brain!.think(botView!, botAmmo!);
    botAmmo!.use(a.kind);
    final o = mine.apply(a, rng);
    botView!.apply(a, o);
    brain!.observe(a, o, botView!);
    final cells = a.kind == kScan
        ? boxOf(a.a)
        : a.kind == kWave
            ? lineOf(a.a, a.b)
            : [for (final s in o.shots) s.cell];
    final d = _describe(false, a, o);
    _feedback(a, o);
    setState(() {
      _flash(flashMine, cells);
      _setBanner(d.$1, d.$2);
    });
    _afterLocal(1, o);
  }

  // ------------------------------------------------------------------
  // En línea
  // ------------------------------------------------------------------

  Future<bool> _sendOnline(RAction a) async {
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
          'act': {...a.toMap(), 'n': an + 1, 'by': mySeat},
        });
        ok = true;
      });
    } catch (_) {
      ok = false;
    }
    if (ok) ammo.use(a.kind);
    return ok;
  }

  /// El rival me disparó: resuelvo sobre MI flota y publico el resultado.
  Future<void> _resolveIncoming(Map<String, dynamic> act) async {
    final a = RAction.fromMap(act);
    final by = (act['by'] as num).toInt();
    final an = (act['n'] as num).toInt();
    final o = mine.apply(a, rng);
    final cells = a.kind == kScan
        ? boxOf(a.a)
        : a.kind == kWave
            ? lineOf(a.a, a.b)
            : [for (final s in o.shots) s.cell];
    final d = _describe(false, a, o);
    _feedback(a, o);
    if (mounted) {
      setState(() {
        _flash(flashMine, cells);
        _setBanner(d.$1, d.$2);
      });
    }
    final ref = svc.roomRef(code);
    try {
      await svc.db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        final doc = snap.data();
        if (doc == null) return;
        final rn = ((doc['res'] as Map?)?['n'] as num? ?? 0).toInt();
        if (rn >= an) return;
        final nt = nextTurn(by, o, (doc['streak'] as num? ?? 0).toInt());
        tx.update(ref, {
          'res': {...o.toMap(), 'n': an},
          'turn': nt.$1,
          'streak': nt.$2,
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
        _applyMine(RAction.fromMap(act), Outcome.fromMap(res));
        busy = false;
      }
    }
    if (st == 'playing') {
      turn = (d['turn'] as num? ?? 0).toInt();
      streak = (d['streak'] as num? ?? 0).toInt();
      final key = '$turn-$rn';
      if (key != lastKey) {
        lastKey = key;
        _newTurn();
        if (status != 'playing') {
          _setBanner(turn == mySeat ? '¡Empiezas tú! Elige una casilla.' : 'Empieza $enemyName…',
              Colors.indigo);
        }
      }
      status = 'playing';
      setState(() {});
    } else if (st == 'finished') {
      final w = (d['winner'] as num? ?? -1).toInt();
      _finish(w);
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
              ? 'Destruiste los 4 objetivos de $enemyName en $myTurns turnos.'
              : '$enemyName destruyó tus objetivos. Te quedaban ${mine.realAlive}.'),
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
  // Interfaz
  // ------------------------------------------------------------------

  Set<int> _preview() {
    if (sel < 0) return {};
    switch (tool) {
      case kScan:
        return boxOf(sel).toSet();
      case kMissile:
        return plusOf(sel).toSet();
      case kWave:
        return lineOf(wvert == 0 ? sel ~/ kN : sel % kN, wvert).toSet();
      default:
        return {sel};
    }
  }

  void _tapCell(int c) {
    if (status != 'playing') return;
    if (tool == kFire && !view.canFire(c)) return;
    HapticFeedback.selectionClick();
    setState(() => sel = c);
  }

  Widget _label(String t, double size, {bool strong = false}) => SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Text(t,
              style: TextStyle(
                  fontSize: size * 0.4,
                  fontWeight: strong ? FontWeight.bold : FontWeight.normal,
                  color: strong ? Colors.cyanAccent : Colors.white54)),
        ),
      );

  Widget _enemyCell(int c, double size, Set<int> preview) {
    final st = view.st[c];
    Color bg;
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
        bg = const Color(0xFF2E7D32);
        icon = view.kindAt[c] >= 0 ? kKinds[view.kindAt[c]].icon : '✔';
        break;
      case 5:
        bg = const Color(0xFF6A1B9A);
        icon = '💣';
        break;
      case 6:
        bg = const Color(0xFFF9A825);
        icon = '🎁';
        break;
      default:
        bg = view.scanned.contains(c) ? const Color(0xFF1E5A8E) : _kWater;
        if (view.targets.contains(c)) icon = '🎯';
    }
    final inPrev = preview.contains(c);
    final isSel = c == sel;
    final scanNum = view.scanAt[c];
    Widget child;
    if (st == 0 && scanNum >= 0 && icon.isEmpty) {
      child = Text('$scanNum',
          key: ValueKey('n$c$scanNum'),
          style: TextStyle(
              fontSize: size * 0.55,
              fontWeight: FontWeight.bold,
              color: Colors.cyanAccent));
    } else {
      child = Text(icon,
          key: ValueKey('i$c$st$icon'),
          style: TextStyle(
              fontSize: st == 1 ? size * 0.4 : size * 0.58,
              color: st == 1 ? Colors.lightBlueAccent : null));
    }
    return GestureDetector(
      onTap: () => _tapCell(c),
      child: AnimatedScale(
        scale: flashEnemy.contains(c) ? 1.2 : 1.0,
        duration: const Duration(milliseconds: 220),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          width: size,
          height: size,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(5),
            border: Border.all(
              color: isSel
                  ? Colors.amber
                  : inPrev
                      ? Colors.amber.withOpacity(0.7)
                      : Colors.white12,
              width: isSel ? 3 : inPrev ? 2 : 0.5,
            ),
            boxShadow: flashEnemy.contains(c)
                ? [const BoxShadow(color: Colors.white54, blurRadius: 10)]
                : null,
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            transitionBuilder: (w, anim) => ScaleTransition(scale: anim, child: w),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _enemyGrid(double side) {
    final cell = side / (kN + 1);
    final preview = _preview();
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Row(children: [
            SizedBox(width: cell, height: cell),
            for (var c = 0; c < kN; c++)
              view.colCount[c] >= 0
                  ? _label('${view.colCount[c]}', cell, strong: true)
                  : _label('ABCDEFGH'[c], cell),
          ]),
          for (var r = 0; r < kN; r++)
            Row(children: [
              view.rowCount[r] >= 0
                  ? _label('${view.rowCount[r]}', cell, strong: true)
                  : _label('${r + 1}', cell),
              for (var c = 0; c < kN; c++) _enemyCell(r * kN + c, cell, preview),
            ]),
        ],
      ),
    );
  }

  Widget _fleetGrid(double side) {
    final cell = side / kN;
    return Container(
      width: side,
      height: side,
      decoration: BoxDecoration(
        color: const Color(0xFF0A1A30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var r = 0; r < kN; r++)
            Row(children: [
              for (var c = 0; c < kN; c++) _fleetCell(r * kN + c, cell),
            ]),
        ],
      ),
    );
  }

  Widget _fleetCell(int c, double size) {
    final m = mine.cellMod[c];
    final shot = mine.shot[c];
    Color bg = _kWater;
    String icon = '';
    if (m >= 0) {
      final k = mine.modKind[m];
      bg = shot ? const Color(0xFF5D4037) : const Color(0xFF455A64);
      icon = shot ? '💥' : kKinds[k].icon;
      if (!shot && kKinds[k].hp > 1 && mine.hp[c] < kKinds[k].hp) {
        bg = const Color(0xFF00838F);
      }
    } else if (shot) {
      bg = const Color(0xFF0B1B33);
      icon = '•';
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      width: size,
      height: size,
      margin: const EdgeInsets.all(0.8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: flashMine.contains(c)
            ? Border.all(color: Colors.redAccent, width: 2.5)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(icon, style: TextStyle(fontSize: size * 0.55)),
    );
  }

  void _showMine() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Mi flota · objetivos en pie: ${mine.realAlive}/4',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              _fleetGrid(min(MediaQuery.of(context).size.width - 32, 340.0)),
              const SizedBox(height: 8),
              const Text('💠 Núcleo  🗼 Torre  📡 Antena  🛡️ Blindado  💣 Mina  🎁 Baliza',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hud() {
    final chips = <Widget>[];
    for (var k = 0; k < kRealKinds; k++) {
      final down = view.downKinds.contains(k);
      chips.add(Padding(
        padding: const EdgeInsets.only(right: 6),
        child: Opacity(
          opacity: down ? 0.35 : 1,
          child: Text(kKinds[k].icon,
              style: TextStyle(
                  fontSize: 22,
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
                  mt
                      ? (streak > 0 && !busy ? 'Tu turno (extra) · ${secsLeft}s' : 'Tu turno · ${secsLeft}s')
                      : 'Turno de $enemyName…',
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
          ...chips,
        ],
      ),
    );
  }

  Widget _toolBtn(int k, String icon, String name) {
    final left = ammo.left(k);
    final enabled = left > 0;
    final selected = tool == k;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Material(
          color: selected ? Colors.indigo : Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled
                ? () {
                    HapticFeedback.selectionClick();
                    setState(() => tool = k);
                  }
                : null,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: selected ? Colors.indigo : Colors.black26),
              ),
              child: Opacity(
                opacity: enabled ? 1 : 0.35,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(icon, style: const TextStyle(fontSize: 22)),
                    Text(name,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: selected ? Colors.white : Colors.black87)),
                    Text(k == kFire ? '∞' : '×$left',
                        style: TextStyle(
                            fontSize: 11,
                            color: selected ? Colors.white70 : Colors.black54)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String get _toolHelp {
    switch (tool) {
      case kScan:
        return 'Escaneo: cuántos objetivos hay en el área de 3×3 (gasta tu turno).';
      case kWave:
        return 'Onda: cuántos objetivos hay en una fila o columna (gasta tu turno).';
      case kMissile:
        return 'Misil: impacta una cruz de 5 casillas. Solo uno por partida.';
      default:
        return 'Disparo: golpea 1 casilla. Sin límite.';
    }
  }

  String get _fireLabel {
    if (!myTurn) return 'Esperando al rival…';
    if (busy) return 'Procesando…';
    if (sel < 0) return 'Toca una casilla';
    switch (tool) {
      case kScan:
        return '🔍 Escanear ${cellName(sel)}';
      case kWave:
        return wvert == 0 ? '⚡ Onda en fila ${sel ~/ kN + 1}' : '⚡ Onda en columna ${'ABCDEFGH'[sel % kN]}';
      case kMissile:
        return '🚀 Misil en ${cellName(sel)}';
      default:
        return '🎯 Disparar a ${cellName(sel)}';
    }
  }

  Widget _controls() {
    final canGo = myTurn && !busy && _buildAction() != null;
    return Container(
      color: Colors.grey.shade100,
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            _toolBtn(kFire, '🎯', 'Disparo'),
            _toolBtn(kScan, '🔍', 'Escaneo'),
            _toolBtn(kWave, '⚡', 'Onda'),
            _toolBtn(kMissile, '🚀', 'Misil'),
          ]),
          const SizedBox(height: 6),
          Text(_toolHelp,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.black54)),
          if (tool == kWave)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('Fila')),
                  ButtonSegment(value: 1, label: Text('Columna')),
                ],
                selected: {wvert},
                onSelectionChanged: (s) => setState(() => wvert = s.first),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: FilledButton(
              onPressed: canGo ? _commit : null,
              child: Text(_fireLabel, style: const TextStyle(fontSize: 18)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _lobby() {
    final seats = room == null ? 1 : (room!['seats'] as List).length;
    final isHost = room != null && room!['hostId'] == svc.uid;
    return ListView(
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
        const Text('Tu flota (solo tú la ves):', textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Center(child: _fleetGrid(min(MediaQuery.of(context).size.width - 80, 300.0))),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => setState(() => mine = Fleet.random(rng)),
          icon: const Icon(Icons.shuffle),
          label: const Text('Barajar mi flota'),
        ),
        const SizedBox(height: 8),
        if (isHost)
          FilledButton.icon(
            onPressed: seats == 2 ? () => RadarOnline.start(code) : null,
            icon: const Icon(Icons.play_arrow),
            label: const Text('Empezar partida'),
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
    final playing = status != 'lobby';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.online ? 'vs $enemyName' : 'vs PC'),
        actions: [
          if (playing)
            IconButton(
              tooltip: 'Mi flota',
              onPressed: _showMine,
              icon: Badge(
                label: Text('${mine.realAlive}'),
                child: const Icon(Icons.dashboard),
              ),
            ),
          IconButton(
            tooltip: 'Rendirme',
            onPressed: _confirmSurrender,
            icon: const Icon(Icons.flag),
          ),
        ],
      ),
      body: SafeArea(
        child: !playing
            ? _lobby()
            : Column(
                children: [
                  _hud(),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, box) {
                        final side = min(box.maxWidth - 16, box.maxHeight - 8);
                        return Center(child: _enemyGrid(max(side, 120.0)));
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
                              fontSize: 16,
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
