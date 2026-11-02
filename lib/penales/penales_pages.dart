import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../game_service.dart';
import '../music.dart';
import '../sfx.dart';
import 'art.dart';
import 'engine.dart';
import 'teams.dart';

const int kMaxHumans = 8;

// ======================================================================
// Servicio en línea (sala con hasta 8 personas)
// ======================================================================

class PenalesOnline {
  static List<Map<String, dynamic>> seatsOf(Map<String, dynamic> d) => [
        for (final s in (d['seats'] as List? ?? const []))
          Map<String, dynamic>.from(s as Map)
      ];

  static Future<String> create(String name, int team) async {
    svc.name = name;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'penales',
      'hostId': svc.uid,
      'status': 'lobby',
      'seats': [
        {'uid': svc.uid, 'name': name, 'team': team}
      ],
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
      if (!snap.exists || snap.data()!['game'] != 'penales') {
        err = 'No existe una sala de Penales con ese código.';
        return;
      }
      final d = snap.data()!;
      final seats = seatsOf(d);
      if (seats.any((s) => s['uid'] == svc.uid)) return; // reingreso
      if (d['status'] != 'lobby') {
        err = 'El torneo ya comenzó.';
        return;
      }
      if (seats.length >= kMaxHumans) {
        err = 'La sala está llena (máx. $kMaxHumans).';
        return;
      }
      tx.update(ref, {
        'seats': [
          ...seats,
          {'uid': svc.uid, 'name': name, 'team': -1}
        ],
      });
    });
    return err;
  }

  /// Elige equipo si nadie más lo tiene. Devuelve false si ya está tomado.
  static Future<bool> chooseTeam(String code, int team) async {
    final ref = svc.roomRef(code);
    var ok = false;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final seats = seatsOf(snap.data()!);
      if (seats.any((s) => s['team'] == team && s['uid'] != svc.uid)) return;
      for (final s in seats) {
        if (s['uid'] == svc.uid) s['team'] = team;
      }
      tx.update(ref, {'seats': seats});
      ok = true;
    });
    return ok;
  }

  static Future<String?> start(String code) async {
    final ref = svc.roomRef(code);
    String? err;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data()!;
      final seats = seatsOf(d);
      if (seats.any((s) => (s['team'] as num).toInt() < 0)) {
        err = 'Todos deben elegir su equipo.';
        return;
      }
      final rng = Random();
      final chosen = [for (final s in seats) (s['team'] as num).toInt()];
      final teams = fillTeams(chosen, rng);
      final ctrl = [
        for (final s in seats) s['uid'] as String,
        for (var i = seats.length; i < kCupTeams; i++) 'bot'
      ];
      final owners = [
        for (final s in seats) s['name'] as String,
        for (var i = seats.length; i < kCupTeams; i++) 'PC'
      ];
      final g = Penales.create(teams, ctrl, owners, rng: rng);
      tx.update(ref, {
        'status': g.finished ? 'finished' : 'playing',
        'state': g.toMap(),
      });
    });
    return err;
  }
}

// ======================================================================
// Elección de equipo
// ======================================================================

String _stars(TeamInfo t) {
  final n = (1 + (t.strength * 4).round()).clamp(1, 5).toInt();
  return '★' * n + '☆' * (5 - n);
}

class TeamGrid extends StatelessWidget {
  final int selected;
  final Set<int> taken;
  final ValueChanged<int> onPick;
  const TeamGrid(
      {super.key, required this.selected, required this.taken, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 4,
      childAspectRatio: 0.62,
      mainAxisSpacing: 6,
      crossAxisSpacing: 6,
      children: [
        for (var i = 0; i < kTeams.length; i++)
          _tile(context, i),
      ],
    );
  }

  Widget _tile(BuildContext context, int i) {
    final t = kTeams[i];
    final sel = i == selected;
    final off = taken.contains(i);
    return Opacity(
      opacity: off ? 0.35 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: off ? null : () => onPick(i),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: sel ? Colors.amber.shade100 : Colors.white,
            border: Border.all(
                color: sel ? Colors.amber.shade800 : Colors.black12, width: sel ? 3 : 1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Expanded(child: KitIcon(team: t, size: 64)),
              Text('${t.flag} ${t.name}',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold)),
              Text(_stars(t),
                  style: TextStyle(fontSize: 10, color: Colors.orange.shade800)),
            ],
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// Menú
// ======================================================================

class PenalesMenuPage extends StatefulWidget {
  const PenalesMenuPage({super.key});

  @override
  State<PenalesMenuPage> createState() => _PenalesMenuPageState();
}

class _PenalesMenuPageState extends State<PenalesMenuPage> {
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  int team = -1;
  String? error;
  bool loading = false;

  String get _name => nameCtrl.text.trim().isEmpty ? 'Tú' : nameCtrl.text.trim();

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  void _solo() {
    if (team < 0) return setState(() => error = 'Primero elige tu equipo.');
    setState(() => error = null);
    _open(PenalesPage.local(name: _name, myTeam: team));
  }

  Future<void> _create() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final code = await PenalesOnline.create(name, team);
      _open(PenalesPage.online(code));
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
    if (code.length != 5) return setState(() => error = 'El código tiene 5 caracteres.');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final err = await PenalesOnline.join(code, name);
      if (err != null) {
        setState(() => error = err);
      } else {
        _open(PenalesPage.online(code));
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
      appBar: AppBar(title: const Text('⚽ Penales Libertadores')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
                'Cuartos de final, semifinales y final. Si no hay 8 jugadores, la PC completa el torneo. '
                'Mientras mejor ranking tenga el rival, mejor lee tus patadas.',
                style: TextStyle(color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Tu nombre', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 14),
            const Text('Elige tu equipo', style: TextStyle(fontSize: 18)),
            const Text('Las estrellas son la dificultad según el ranking Conmebol 2026.',
                style: TextStyle(fontSize: 12, color: Colors.black54)),
            const SizedBox(height: 8),
            TeamGrid(
                selected: team,
                taken: const {},
                onPick: (i) => setState(() => team = i)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _solo,
              icon: const Icon(Icons.sports_soccer),
              label: const Text('Jugar el torneo (tú contra la PC)'),
            ),
            const Divider(height: 32),
            const Text('En línea con familia y amigos (hasta 8)',
                style: TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: loading ? null : _create,
              icon: const Icon(Icons.add),
              label: const Text('Crear sala'),
            ),
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
            const SizedBox(height: 16),
            const Text(
                'Los uniformes están dibujados con los colores de cada club (no son los diseños oficiales '
                'ni llevan escudos). Los nombres de jugadores salen de las plantillas publicadas y pueden '
                'haber cambiado.',
                style: TextStyle(fontSize: 11, color: Colors.black45)),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Partida (local y en línea)
// ======================================================================

typedef _Mut = bool Function(Penales g);

class PenalesPage extends StatefulWidget {
  final String? code;
  final String name;
  final int myTeam;
  const PenalesPage.local({super.key, required this.name, required this.myTeam})
      : code = null;
  const PenalesPage.online(String this.code, {super.key})
      : name = '',
        myTeam = -1;

  @override
  State<PenalesPage> createState() => _PenalesPageState();
}

/// Duración de la cuenta regresiva (pito + 3, 2, 1) antes de cada tiro.
const int kCountMs = 4200;
/// Duración de la jugada animada.
const int kShotMs = 4200;

class _PenalesPageState extends State<PenalesPage> with TickerProviderStateMixin {
  bool get online => widget.code != null;
  String get _uid => online ? svc.uid : 'me';

  Penales? g;
  Map<String, dynamic>? room;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
  Timer? ticker;
  bool _busy = false;
  int _lastSeq = -1;
  String _lastStage = '';
  int _stageSince = 0;
  bool _musicOn = false;

  int _selZone = -1;
  int _selShooter = -1;
  int _autoSeq = -1;
  double _celStart = 0;

  late final AnimationController _clock;
  late final AnimationController _shot;

  double get _now => _clock.value * 600.0;
  bool get _isHost => !online || (room?['hostId'] == svc.uid);

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: const Duration(seconds: 600))
      ..repeat();
    _shot = AnimationController(vsync: this, duration: const Duration(milliseconds: kShotMs));
    if (!online) {
      final rng = Random();
      final teams = fillTeams([widget.myTeam], rng);
      final g0 = Penales.create(
        teams,
        ['me', for (var i = 1; i < kCupTeams; i++) 'bot'],
        [widget.name, for (var i = 1; i < kCupTeams; i++) 'PC'],
        rng: rng,
      );
      _onState(g0, notify: false);
    } else {
      sub = svc.roomStream(widget.code!).listen(_onRoom);
    }
    ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  @override
  void dispose() {
    sub?.cancel();
    ticker?.cancel();
    _clock.dispose();
    _shot.dispose();
    Ambient.stop();
    super.dispose();
  }

  // ------------------------------------------------------------ estado

  void _onRoom(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || !mounted) return;
    final d = snap.data()!;
    room = d;
    final st = d['state'];
    if (st != null) {
      _onState(Penales.fromMap(Map<String, dynamic>.from(st as Map)));
    } else {
      setState(() {});
    }
  }

  void _onState(Penales gm, {bool notify = true}) {
    final prevStage = _lastStage;
    g = gm;
    if (gm.seq != _lastSeq || gm.stage != _lastStage) {
      _lastSeq = gm.seq;
      _lastStage = gm.stage;
      _stageSince = nowMs();
      _enter(gm, prevStage);
    }
    if (!_musicOn) {
      final slot = gm.slotOf(_uid);
      final team = slot >= 0 ? gm.teamOf(slot) : kTeams[gm.teams[gm.a]];
      _musicOn = true;
      Ambient.start('barra_${team.barra}', volume: 0.30);
    }
    if (notify && mounted) setState(() {});
  }

  void _enter(Penales gm, String prev) {
    switch (gm.stage) {
      case 'toss':
        _selZone = -1;
        Sfx.play('coin');
        break;
      case 'pick':
        _selZone = -1;
        _selShooter = -1;
        _autoSeq = -1;
        Sfx.play('whistle');
        break;
      case 'show':
        _shot.forward(from: 0);
        Sfx.play('kick', delayMs: 1600);
        if (gm.lastGoal) {
          Sfx.play('net', delayMs: 2250);
          Sfx.play('goal_roar', delayMs: 2300);
        } else {
          Sfx.play('save_groan', delayMs: 2250);
        }
        break;
      case 'mend':
        _celStart = _now;
        Sfx.play('cheer_win', delayMs: 200);
        break;
      case 'tend':
        _celStart = _now;
        Sfx.play('applause');
        Sfx.play('cheer_win', delayMs: 400);
        break;
      default:
        break;
    }
  }

  /// Aplica un cambio al estado (local o con transacción en línea).
  Future<void> _act(_Mut fn, {int? seq, bool wait = false}) async {
    if (_busy) {
      if (!wait) return;
      while (_busy) {
        await Future<void>.delayed(const Duration(milliseconds: 40));
      }
    }
    _busy = true;
    try {
      if (!online) {
        final gm = g!;
        if (seq != null && gm.seq != seq) return;
        if (fn(gm)) _onState(gm);
      } else {
        final ref = svc.roomRef(widget.code!);
        await svc.db.runTransaction((tx) async {
          final snap = await tx.get(ref);
          final d = snap.data();
          if (d == null || d['state'] == null) return;
          final gm = Penales.fromMap(Map<String, dynamic>.from(d['state'] as Map));
          if (seq != null && gm.seq != seq) return;
          if (!fn(gm)) return;
          tx.update(ref, {
            'state': gm.toMap(),
            'status': gm.finished ? 'finished' : 'playing',
          });
        });
      }
    } catch (_) {
      // se reintenta en el siguiente ciclo
    } finally {
      _busy = false;
    }
  }

  /// Reloj del anfitrión: completa jugadas de la PC, resuelve y avanza.
  void _tick() {
    final gm = g;
    if (gm == null || !mounted || gm.finished) return;
    final el = nowMs() - _stageSince;
    // Al terminar la cuenta, lo que tengas marcado se envía solo.
    if (gm.stage == 'pick' && el >= kCountMs - 300 && _autoSeq != gm.seq) {
      final me = gm.slotOf(_uid);
      if (me >= 0 && _selZone >= 0) {
        if (gm.kickerSlot == me && gm.pickKick < 0) {
          _autoSeq = gm.seq;
          _confirmKick(gm);
        } else if (gm.keeperSlot == me && gm.pickKeep < 0) {
          _autoSeq = gm.seq;
          _confirmKeep(gm);
        }
      }
    }
    if (!_isHost) return;
    switch (gm.stage) {
      case 'toss':
        if (el > 3300) _act((x) {
          x.advance();
          return true;
        }, seq: gm.seq);
        break;
      case 'pick':
        final botNeeded = (gm.pickKick < 0 && gm.isBot(gm.kickerSlot)) ||
            (gm.pickKeep < 0 && gm.isBot(gm.keeperSlot));
        if (gm.ready) {
          if (el >= kCountMs) _act((x) => x.resolve(), seq: gm.seq);
        } else if (botNeeded) {
          _act((x) {
            x.autoPick();
            return true;
          }, seq: gm.seq);
        } else if (el > kCountMs + 1500) {
          _act((x) {
            x.autoPick(force: true);
            return true;
          }, seq: gm.seq);
        }
        break;
      case 'show':
        if (el > kShotMs + 1000) _act((x) {
          x.advance();
          return true;
        }, seq: gm.seq);
        break;
      case 'mend':
        if (el > 6500) _act((x) {
          x.advance();
          return true;
        }, seq: gm.seq);
        break;
      default:
        break;
    }
  }

  // ------------------------------------------------------------ acciones

  void _confirmKick(Penales gm) {
    if (_selZone < 0) return;
    final shooter = _selShooter >= 0 ? _selShooter : gm.defaultShooter(gm.kickerSide);
    final zone = _selZone;
    final seq = gm.seq;
    _act((x) => x.humanKick(zone, shooter), seq: seq, wait: true);
  }

  void _confirmKeep(Penales gm) {
    if (_selZone < 0) return;
    final zone = _selZone;
    final seq = gm.seq;
    _act((x) => x.humanKeep(zone), seq: seq, wait: true);
  }

  // ------------------------------------------------------------ pantallas

  @override
  Widget build(BuildContext context) {
    final gm = g;
    final r = room;
    if (online && (r == null || gm == null)) {
      if (r != null && r['status'] == 'lobby') return _lobby(r);
      return Scaffold(
        appBar: AppBar(title: const Text('Penales')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (gm == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF0B1226),
      appBar: AppBar(
        title: Text(gm.finished ? 'Fin del torneo' : gm.phaseName),
        actions: [
          IconButton(
            tooltip: 'Llaves del torneo',
            icon: const Icon(Icons.account_tree),
            onPressed: () => _showBracket(gm),
          ),
          const MusicButton(),
        ],
      ),
      body: SafeArea(child: _playView(gm)),
    );
  }

  // ---- Sala de espera en línea

  Widget _lobby(Map<String, dynamic> r) {
    final seats = PenalesOnline.seatsOf(r);
    final me = seats.where((s) => s['uid'] == svc.uid).toList();
    final myTeam = me.isEmpty ? -1 : (me.first['team'] as num).toInt();
    final taken = {
      for (final s in seats)
        if (s['uid'] != svc.uid && (s['team'] as num).toInt() >= 0)
          (s['team'] as num).toInt()
    };
    final host = r['hostId'] == svc.uid;
    return Scaffold(
      appBar: AppBar(title: Text('Sala ${widget.code}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Comparte este código con los demás jugadores:'),
          Center(
            child: SelectableText(widget.code!,
                style: const TextStyle(
                    fontSize: 40, fontWeight: FontWeight.bold, letterSpacing: 6)),
          ),
          const SizedBox(height: 8),
          for (final s in seats)
            ListTile(
              dense: true,
              leading: (s['team'] as num).toInt() >= 0
                  ? KitIcon(team: kTeams[(s['team'] as num).toInt()], size: 36)
                  : const Icon(Icons.help_outline),
              title: Text(s['name'] as String),
              subtitle: Text((s['team'] as num).toInt() >= 0
                  ? kTeams[(s['team'] as num).toInt()].name
                  : 'Eligiendo equipo…'),
            ),
          Text('${seats.length} de $kMaxHumans jugadores. Los equipos que falten los pone la PC.',
              style: const TextStyle(color: Colors.black54)),
          const Divider(height: 28),
          const Text('Tu equipo', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 6),
          TeamGrid(
            selected: myTeam,
            taken: taken,
            onPick: (i) async {
              final ok = await PenalesOnline.chooseTeam(widget.code!, i);
              if (!ok && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Ese equipo ya lo eligió otra persona.')));
              }
            },
          ),
          const SizedBox(height: 14),
          if (host)
            FilledButton.icon(
              onPressed: () async {
                final err = await PenalesOnline.start(widget.code!);
                if (err != null && mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(err)));
                }
              },
              icon: const Icon(Icons.play_arrow),
              label: const Text('Empezar el torneo'),
            )
          else
            const Center(child: Text('Esperando que el anfitrión empiece…')),
        ],
      ),
    );
  }

  // ---- Torneo en juego

  Widget _playView(Penales gm) {
    final mySlot = gm.slotOf(_uid);
    final inCelebration = gm.stage == 'mend' || gm.stage == 'tend';
    return Column(
      children: [
        if (!gm.finished) _scoreboard(gm),
        Expanded(
          child: LayoutBuilder(builder: (context, box) {
            final size = Size(box.maxWidth, box.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: inCelebration
                      ? _celebration(gm)
                      : GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (d) => _tapScene(gm, mySlot, size, d.localPosition),
                          child: _scene(gm, mySlot),
                        ),
                ),
                if (gm.stage == 'toss') Positioned.fill(child: _tossOverlay(gm)),
                if (gm.stage == 'pick') Positioned.fill(child: _countdown(gm)),
                if (gm.stage == 'show') _shotBanner(gm),
                if (inCelebration) _celebrationText(gm),
              ],
            );
          }),
        ),
        _bottom(gm, mySlot),
      ],
    );
  }

  Widget _scene(Penales gm, int mySlot) {
    final show = gm.stage == 'show';
    final side = show ? gm.lastSide : gm.kickerSide;
    final kSlot = gm.slotOfSide(side);
    final gSlot = gm.slotOfSide(1 - side);
    final kTeam = gm.teams[kSlot];
    final gTeam = gm.teams[gSlot];
    final shooter = show
        ? gm.lastShooter
        : (kSlot == mySlot && _selShooter >= 0
            ? _selShooter
            : (gm.pickShooter >= 0 ? gm.pickShooter : gm.defaultShooter(side)));
    final name = kTeams[kTeam].takers[shooter.clamp(0, kTeams[kTeam].takers.length - 1).toInt()];
    final myPicking = gm.stage == 'pick' &&
        ((kSlot == mySlot && gm.pickKick < 0) || (gSlot == mySlot && gm.pickKeep < 0));
    return AnimatedBuilder(
      animation: Listenable.merge([_clock, _shot]),
      builder: (context, _) {
        final anim = show
            ? ShotAnim(_shot.value, gm.lastKZ, gm.lastGZ, gm.lastGoal)
            : ShotAnim.idle;
        final cheer = show && gm.lastGoal && _shot.value > 0.5 ? 1.0 : 0.0;
        return CustomPaint(
          painter: PenaltyScenePainter(
            kicker: Kit.of(kTeams[kTeam]),
            keeper: Kit.keeper(gTeam),
            home: Color(kTeams[kTeam].primary == 0xFFFFFFFF
                ? kTeams[kTeam].secondary
                : kTeams[kTeam].primary),
            away: Color(kTeams[gTeam].primary == 0xFFFFFFFF
                ? kTeams[gTeam].secondary
                : kTeams[gTeam].primary),
            shot: anim,
            hover: myPicking ? _selZone : -1,
            showZones: myPicking || (show && _shot.value < 0.36),
            kickerName: name,
            keeperName: kTeams[gTeam].gk,
            clock: _now,
            cheer: cheer,
          ),
        );
      },
    );
  }

  void _tapScene(Penales gm, int mySlot, Size size, Offset p) {
    if (gm.stage != 'pick' || mySlot < 0) return;
    final iKick = gm.kickerSlot == mySlot && gm.pickKick < 0;
    final iKeep = gm.keeperSlot == mySlot && gm.pickKeep < 0;
    if (!iKick && !iKeep) return;
    final z = GoalGeom.zoneAt(size, p);
    if (z >= 0) setState(() => _selZone = z);
  }

  Widget _celebration(Penales gm) {
    final tend = gm.stage == 'tend';
    final winnerSlot = tend ? gm.champion : gm.matchWinner;
    final loserSlot = winnerSlot == gm.a ? gm.b : gm.a;
    final wTeam = gm.teams[winnerSlot];
    final lTeam = gm.teams[loserSlot < 0 ? winnerSlot : loserSlot];
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) => CustomPaint(
        painter: CelebrationPainter(
          kit: Kit.of(kTeams[wTeam]),
          keeper: Kit.keeper(wTeam),
          away: Color(kTeams[lTeam].primary == 0xFFFFFFFF
              ? kTeams[lTeam].secondary
              : kTeams[lTeam].primary),
          t: max(0.0, _now - _celStart),
          clock: _now,
          trophy: tend,
        ),
      ),
    );
  }

  Widget _celebrationText(Penales gm) {
    final tend = gm.stage == 'tend';
    final slot = tend ? gm.champion : gm.matchWinner;
    final team = gm.teamOf(slot);
    final isFinal = tend || gm.phase >= 2;
    final next = gm.phase == 0 ? 'a semifinales' : 'a la final';
    final owner = gm.owners[slot];
    return Positioned(
      left: 0,
      right: 0,
      top: 8,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isFinal ? '🏆 ¡CAMPEÓN! 🏆' : '¡CLASIFICA $next!',
                style: const TextStyle(
                    color: Colors.amber, fontSize: 22, fontWeight: FontWeight.w900),
              ),
              Text('${team.flag} ${team.name}${owner == 'PC' ? '' : '  ·  $owner'}',
                  style: const TextStyle(color: Colors.white, fontSize: 18)),
              if (!isFinal)
                Text(
                    'Marcador: ${gm.goals[0]} - ${gm.goals[1]}  (${gm.teamOf(gm.a).name} vs ${gm.teamOf(gm.b).name})',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _countdown(Penales gm) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _clock,
        builder: (context, _) {
          final el = nowMs() - _stageSince;
          if (el >= kCountMs) return const SizedBox.shrink();
          String txt;
          double size;
          double k = 0;
          if (el < 1000) {
            txt = '¡Prepárense!';
            size = 34;
          } else {
            final idx = (el - 1000) ~/ 900;
            k = ((el - 1000) % 900) / 900.0;
            txt = idx == 0 ? '3' : (idx == 1 ? '2' : (idx == 2 ? '1' : '¡YA!'));
            size = idx >= 3 ? 70 : 130;
          }
          final scale = 1.0 + 0.5 * (1 - k);
          return Align(
            alignment: const Alignment(0, -0.25),
            child: Opacity(
              opacity: (1.0 - 0.45 * k).clamp(0.0, 1.0).toDouble(),
              child: Transform.scale(
                scale: el < 1000 ? 1.0 : scale,
                child: Text(txt,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: size,
                        fontWeight: FontWeight.w900,
                        shadows: const [
                          Shadow(color: Colors.black, blurRadius: 14),
                          Shadow(color: Colors.black, blurRadius: 4),
                        ])),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tossOverlay(Penales gm) {
    final first = gm.teamOf(gm.slotOfSide(gm.first));
    return AnimatedBuilder(
      animation: _clock,
      builder: (context, _) {
        final el = nowMs() - _stageSince;
        final flipping = el < 1900;
        return Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${gm.phaseName}: ${gm.teamOf(gm.a).name} vs ${gm.teamOf(gm.b).name}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..scale(1.0, flipping ? cos(_now * 14).abs().clamp(0.08, 1.0).toDouble() : 1.0)
                  ..translate(0.0, flipping ? -sin(el / 1900 * pi) * 70 : 0.0),
                child: const Text('🪙', style: TextStyle(fontSize: 90)),
              ),
              const SizedBox(height: 16),
              Text(
                flipping
                    ? 'Moneda al aire…'
                    : 'Patea primero ${first.flag} ${first.name}',
                style: const TextStyle(
                    color: Colors.amber, fontSize: 22, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _shotBanner(Penales gm) {
    return AnimatedBuilder(
      animation: _shot,
      builder: (context, _) {
        if (_shot.value < 0.54) return const SizedBox.shrink();
        final slotK = gm.slotOfSide(gm.lastSide);
        final slotG = gm.slotOfSide(1 - gm.lastSide);
        final kt = gm.teamOf(slotK), gt = gm.teamOf(slotG);
        final txt = gm.lastGoal
            ? '¡GOOOL!  ${kt.takers[gm.lastShooter.clamp(0, 10).toInt()]}'
            : '¡ATAJÓ ${gt.gk.toUpperCase()}!';
        return Positioned(
          left: 0,
          right: 0,
          top: 10,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: (gm.lastGoal ? Colors.green : Colors.red.shade700)
                    .withOpacity(0.92),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(txt,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900)),
            ),
          ),
        );
      },
    );
  }

  Widget _scoreboard(Penales gm) {
    Widget side(int s) {
      final slot = gm.slotOfSide(s);
      final t = gm.teamOf(slot);
      final active = gm.stage == 'pick' && gm.kickerSide == s;
      final res = gm.shotRes[s];
      final n = max(5, res.length);
      return Expanded(
        child: Container(
          margin: const EdgeInsets.all(4),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF263B73) : const Color(0xFF16213F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: active ? Colors.amber : Colors.white12, width: active ? 2 : 1),
          ),
          child: Column(
            children: [
              Text('${t.flag} ${t.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
              if (gm.owners[slot] != 'PC')
                Text(gm.owners[slot],
                    style: const TextStyle(color: Colors.amber, fontSize: 11)),
              Text('${gm.goals[s]}',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 3,
                children: [
                  for (var i = 0; i < n; i++)
                    Icon(
                      i < res.length
                          ? (res[i] == 1 ? Icons.circle : Icons.cancel)
                          : Icons.circle_outlined,
                      size: 13,
                      color: i < res.length
                          ? (res[i] == 1 ? Colors.greenAccent : Colors.redAccent)
                          : Colors.white38,
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Row(children: [side(0), side(1)]);
  }

  Widget _bottom(Penales gm, int mySlot) {
    final panel = Container(
      width: double.infinity,
      color: const Color(0xFF111A33),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: _bottomContent(gm, mySlot),
    );
    return panel;
  }

  Widget _bottomContent(Penales gm, int mySlot) {
    const white = TextStyle(color: Colors.white, fontSize: 15);
    if (gm.finished) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Campeón: ${gm.teamOf(gm.champion).name}',
              style: white.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.exit_to_app),
            label: const Text('Volver al menú'),
          ),
        ],
      );
    }
    if (gm.stage != 'pick') {
      final out = mySlot >= 0 && gm.isOut(mySlot);
      return Text(
          out ? 'Tu equipo quedó eliminado. Sigue mirando el torneo.' : 'Atento a la tanda…',
          textAlign: TextAlign.center,
          style: white);
    }
    final iKick = gm.kickerSlot == mySlot;
    final iKeep = gm.keeperSlot == mySlot;
    if (iKick && gm.pickKick < 0) {
      final team = gm.teamOf(mySlot);
      final free = gm.freeTakers(gm.kickerSide);
      final sel = _selShooter >= 0 && free.contains(_selShooter)
          ? _selShooter
          : gm.defaultShooter(gm.kickerSide);
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('¡Te toca patear! Elige pateador y toca la zona. Se envía solo al llegar a 0.', style: white),
          const SizedBox(height: 4),
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (var i = 0; i < team.takers.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(team.takers[i], style: const TextStyle(fontSize: 12)),
                      selected: i == sel,
                      onSelected: free.contains(i)
                          ? (_) => setState(() => _selShooter = i)
                          : null,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          FilledButton.icon(
            onPressed: _selZone < 0 ? null : () => _confirmKick(gm),
            icon: const Icon(Icons.sports_soccer),
            label: Text(_selZone < 0 ? 'Toca una zona del arco' : '¡PATEAR a la zona ${_selZone + 1}!'),
          ),
        ],
      );
    }
    if (iKeep && gm.pickKeep < 0) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('¡Te toca atajar con ${gm.teamOf(mySlot).gk}! Toca hacia dónde lanzarte. Se envía solo al llegar a 0.',
              style: white, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          FilledButton.icon(
            onPressed: _selZone < 0 ? null : () => _confirmKeep(gm),
            icon: const Icon(Icons.back_hand),
            label: Text(_selZone < 0 ? 'Toca una zona del arco' : '¡LANZARME a la zona ${_selZone + 1}!'),
          ),
        ],
      );
    }
    if (iKick || iKeep) {
      return const Text('Listo. Esperando al rival…',
          textAlign: TextAlign.center, style: white);
    }
    return Text(
        'Mirando: patea ${gm.teamOf(gm.kickerSlot).name} contra ${gm.teamOf(gm.keeperSlot).name}…',
        textAlign: TextAlign.center,
        style: white);
  }

  void _showBracket(Penales gm) {
    String nm(int slot) {
      final t = gm.teamOf(slot);
      final o = gm.owners[slot];
      return '${t.flag} ${t.name}${o == 'PC' ? '' : ' ($o)'}';
    }

    final rows = <Widget>[];
    for (var p = 0; p < 3; p++) {
      final list = [
        for (final r in gm.results)
          if (r.startsWith('$p,')) r.split(',').map(int.parse).toList()
      ];
      final playing = !gm.finished && gm.phase == p && gm.stage != 'tend';
      if (list.isEmpty && !playing) continue;
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 4),
        child: Text(kPhaseNames[p],
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ));
      for (final r in list) {
        rows.add(Text(
            '${nm(r[1])}  ${r[3]} - ${r[4]}  ${nm(r[2])}\n   ✔ ${gm.teamOf(r[5]).name}',
            style: const TextStyle(fontSize: 13)));
      }
      if (playing) {
        rows.add(Text('▶ En juego: ${nm(gm.a)}  ${gm.goals[0]} - ${gm.goals[1]}  ${nm(gm.b)}',
            style: const TextStyle(fontSize: 13, color: Colors.deepOrange)));
      }
    }
    if (gm.finished) {
      rows.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('🏆 Campeón: ${nm(gm.champion)}',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      ));
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Llaves del torneo'),
        content: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  }
}
