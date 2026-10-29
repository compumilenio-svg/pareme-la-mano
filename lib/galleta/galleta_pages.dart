import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import '../game_service.dart';
import '../sfx.dart';
import 'engine.dart';

const Color _p1Color = Color(0xFF1565C0); // X
const Color _p2Color = Color(0xFFC62828); // O
const Color _paper = Color(0xFFFAF6E9);
const Color _cookie = Color(0xFFEBCB8B);

// ======================================================================
// Servicio en línea (Firestore)
// ======================================================================

class GalletaOnline {
  static Future<String> create(String playerName, String shape, int size) async {
    svc.name = playerName;
    String code;
    do {
      code = svc.newCode();
    } while ((await svc.roomRef(code).get()).exists);
    await svc.roomRef(code).set({
      'game': 'galleta',
      'hostId': svc.uid,
      'hostName': playerName,
      'guestId': '',
      'guestName': '',
      'status': 'lobby',
      'shape': shape,
      'size': size,
      'moves': <int>[],
      'moveN': 0,
      'createdAt': nowMs(),
    });
    return code;
  }

  /// null si todo bien, o un mensaje de error.
  static Future<String?> join(String code, String playerName) async {
    svc.name = playerName;
    code = code.trim().toUpperCase();
    final ref = svc.roomRef(code);
    String? err;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists || snap.data()!['game'] != 'galleta') {
        err = 'No existe una sala de La Galleta con ese código.';
        return;
      }
      final d = snap.data()!;
      if (d['hostId'] == svc.uid || d['guestId'] == svc.uid) return;
      if ((d['guestId'] as String).isNotEmpty) {
        err = 'La sala ya tiene dos jugadores.';
        return;
      }
      tx.update(ref, {
        'guestId': svc.uid,
        'guestName': playerName,
        'status': 'playing',
      });
    });
    return err;
  }

  static Future<bool> sendMove(
      String code, int edge, int expectedN, bool finished) async {
    final ref = svc.roomRef(code);
    var ok = false;
    await svc.db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final d = snap.data();
      if (d == null) return;
      final moves = List<int>.from(d['moves'] as List);
      if (moves.length != expectedN) return;
      moves.add(edge);
      tx.update(ref, {
        'moves': moves,
        'moveN': moves.length,
        'status': finished ? 'finished' : 'playing',
      });
      ok = true;
    });
    return ok;
  }
}

// ======================================================================
// Menú
// ======================================================================

class GalletaMenuPage extends StatefulWidget {
  const GalletaMenuPage({super.key});

  @override
  State<GalletaMenuPage> createState() => _GalletaMenuPageState();
}

class _GalletaMenuPageState extends State<GalletaMenuPage> {
  final String shape = 'galleta';
  int size = 1;
  int level = 2;
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
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
      final code = await GalletaOnline.create(name, shape, size);
      _open(GalletaMatchPage.online(code));
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
      final err = await GalletaOnline.join(code, name);
      if (err != null) {
        setState(() => error = err);
      } else {
        _open(GalletaMatchPage.online(code));
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
      appBar: AppBar(title: const Text('La Galleta')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Une puntos con rayas. Quien cierra un cuadrito se lo queda '
              '(X o O) y juega otra vez. Gana quien llene más cuadritos de la galleta.',
            ),
            const SizedBox(height: 16),
            Text('Tamaño de la galleta', style: t.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Pequeña')),
                ButtonSegment(value: 1, label: Text('Mediana')),
                ButtonSegment(value: 2, label: Text('Grande')),
              ],
              selected: {size},
              onSelectionChanged: (s) => setState(() => size = s.first),
            ),
            const Divider(height: 36),
            Text('Contra la computadora', style: t.titleLarge),
            const SizedBox(height: 8),
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
              onPressed: () =>
                  _open(GalletaMatchPage.vsAi(shape, size, level)),
              child: const Text('Jugar contra la computadora'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => _open(GalletaMatchPage.local(shape, size)),
              child: const Text('Dos jugadores en este celular'),
            ),
            const Divider(height: 36),
            Text('En línea con otra persona', style: t.titleLarge),
            const SizedBox(height: 4),
            const Text(
                'Quien crea la sala juega con la X y elige el tamaño.'),
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
// Partida
// ======================================================================

enum _Mode { ai, local, online }

class GalletaMatchPage extends StatefulWidget {
  final _Mode mode;
  final String shape;
  final int size;
  final int level;
  final String? roomCode;

  const GalletaMatchPage._(this.mode, this.shape, this.size, this.level,
      this.roomCode,
      {super.key});

  factory GalletaMatchPage.vsAi(String shape, int size, int level) =>
      GalletaMatchPage._(_Mode.ai, shape, size, level, null);
  factory GalletaMatchPage.local(String shape, int size) =>
      GalletaMatchPage._(_Mode.local, shape, size, 2, null);
  factory GalletaMatchPage.online(String code) =>
      GalletaMatchPage._(_Mode.online, 'galleta', 1, 2, code);

  @override
  State<GalletaMatchPage> createState() => _GalletaMatchPageState();
}

class _GalletaMatchPageState extends State<GalletaMatchPage>
    with SingleTickerProviderStateMixin {
  late GalletaGame g;
  late final AnimationController _pop;
  final Set<int> _popCells = {};
  bool thinking = false;
  bool endShown = false;
  Map<String, dynamic>? room;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? sub;
  String shapeId = 'galleta';
  int sizeIdx = 1;
  bool gameBuilt = false;
  final List<int> localMoves = []; // jugadas aplicadas aquí, en orden
  int pending = 0; // mis jugadas enviadas que el servidor aún no confirma
  Future<void> _sendChain = Future<void>.value();

  _Mode get mode => widget.mode;
  bool get online => mode == _Mode.online;
  String get code => widget.roomCode!;

  // Quién soy: 1 = X, 2 = O (solo importa contra la PC y en línea).
  int get me {
    if (mode == _Mode.online) {
      return room != null && room!['hostId'] == svc.uid ? 1 : 2;
    }
    return 1;
  }

  String nameOf(int p) {
    switch (mode) {
      case _Mode.ai:
        return p == 1 ? 'Tú' : 'Computadora';
      case _Mode.local:
        return p == 1 ? 'Jugador X' : 'Jugador O';
      case _Mode.online:
        if (room == null) return p == 1 ? 'X' : 'O';
        final n = (p == 1 ? room!['hostName'] : room!['guestName']) as String? ?? '';
        final base = n.isEmpty ? (p == 1 ? 'X' : 'O') : n;
        return p == me ? '$base (tú)' : base;
    }
  }

  @override
  void initState() {
    super.initState();
    _pop = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450))
      ..addListener(() {
        if (mounted) setState(() {});
      });
    if (online) {
      sub = svc.roomStream(code).listen(_onRoom);
    } else {
      shapeId = widget.shape;
      sizeIdx = widget.size;
      g = GalletaGame.shape(shapeId, sizeIdx);
      gameBuilt = true;
    }
  }

  @override
  void dispose() {
    sub?.cancel();
    _pop.dispose();
    super.dispose();
  }

  // ---------------- En línea ----------------

  void _onRoom(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists || !mounted) return;
    final d = snap.data()!;
    setState(() {
      room = d;
      if (!gameBuilt) {
        shapeId = d['shape'] as String;
        sizeIdx = d['size'] as int;
        g = GalletaGame.shape(shapeId, sizeIdx);
        gameBuilt = true;
      }
    });
    // Mientras mis jugadas se confirman no toco el tablero con datos viejos.
    if (pending > 0) return;
    _reconcile(List<int>.from(d['moves'] as List));
  }

  /// Deja el tablero igual a la lista de jugadas del servidor.
  void _reconcile(List<int> moves) {
    var prefix = moves.length >= localMoves.length;
    if (prefix) {
      for (var i = 0; i < localMoves.length; i++) {
        if (moves[i] != localMoves[i]) {
          prefix = false;
          break;
        }
      }
    }
    if (prefix) {
      for (var i = localMoves.length; i < moves.length; i++) {
        if (!g.isFree(moves[i])) {
          prefix = false;
          break;
        }
        _apply(moves[i], fromRemote: true);
      }
    }
    if (!prefix) _replayFrom(moves);
    _checkEnd();
  }

  void _replayFrom(List<int> moves) {
    setState(() {
      g = GalletaGame.replay(shapeId, sizeIdx, moves);
      localMoves
        ..clear()
        ..addAll(moves);
    });
  }

  // ---------------- Jugar ----------------

  bool get _started => !online || (room != null && room!['status'] != 'lobby');

  bool get _myTurn {
    if (!_started || g.over || thinking) return false;
    switch (mode) {
      case _Mode.ai:
        return g.turn == 1;
      case _Mode.local:
        return true;
      case _Mode.online:
        return g.turn == me && room!['status'] == 'playing';
    }
  }

  void _apply(int e, {bool fromRemote = false}) {
    final done = g.play(e);
    localMoves.add(e);
    if (done > 0) {
      _popCells
        ..clear()
        ..addAll([
          for (final c in g.cellsOfEdge(e))
            if (g.owner[c] != 0) c
        ]);
      _pop.forward(from: 0);
      Sfx.play('bonus');
    } else {
      Sfx.play('tick');
    }
    if (mounted) setState(() {});
  }

  void _onEdgeTap(int e) {
    if (!_myTurn || !g.isFree(e)) return;
    _apply(e);
    if (online) {
      final expected = g.moveCount - 1;
      final finished = g.over;
      pending++;
      // Las jugadas se envían una tras otra, en orden (al cerrar un cuadrito
      // se juega otra vez enseguida y no deben pisarse).
      _sendChain = _sendChain
          .then((_) => GalletaOnline.sendMove(code, e, expected, finished))
          .then((ok) async {
        if (!ok) {
          // Choque de jugadas: vuelve a la posición del servidor.
          final s = await svc.roomRef(code).get(const GetOptions(source: Source.server));
          if (mounted && s.exists) {
            _replayFrom(List<int>.from(s.data()!['moves'] as List));
          }
        }
      }).catchError((_) {}).whenComplete(() {
        pending--;
        if (pending <= 0 && mounted && room != null) {
          pending = 0;
          _reconcile(List<int>.from(room!['moves'] as List));
        }
      });
    }
    _checkEnd();
    _maybeAi();
  }

  void _maybeAi() {
    if (mode != _Mode.ai || g.over || g.turn != 2 || thinking) return;
    thinking = true;
    if (mounted) setState(() {});
    Future<void>.delayed(const Duration(milliseconds: 650), () async {
      if (!mounted) return;
      final e = await compute(galletaAiIsolate, <Object>[
        g.w,
        g.h,
        [for (final m in g.mask) m ? 1 : 0],
        List<int>.of(g.hor),
        List<int>.of(g.ver),
        List<int>.of(g.owner),
        g.turn,
        widget.level,
        Random().nextInt(1 << 30),
      ]);
      if (!mounted) return;
      thinking = false;
      if (e >= 0 && g.isFree(e)) _apply(e);
      _checkEnd();
      _maybeAi();
    });
  }

  void _checkEnd() {
    if (!g.over || endShown) return;
    endShown = true;
    final s1 = g.score1, s2 = g.score2;
    String title;
    if (s1 == s2) {
      title = '¡Empate!';
      Sfx.play('score', delayMs: 500);
    } else {
      final w = s1 > s2 ? 1 : 2;
      final iWon = mode == _Mode.local || w == me;
      title = mode == _Mode.local
          ? '¡Ganó ${nameOf(w)}!'
          : (iWon ? '¡Ganaste!' : 'Ganó ${nameOf(w)}');
      Sfx.play(iWon ? 'win' : 'lose', delayMs: 500);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text('X: $s1   ·   O: $s2'),
          actions: [
            if (!online)
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    g = GalletaGame.shape(shapeId, sizeIdx);
                    localMoves.clear();
                    endShown = false;
                    _popCells.clear();
                  });
                },
                child: const Text('Jugar otra vez'),
              ),
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
    });
  }

  // ---------------- Pantalla ----------------

  Widget _scoreTag(int p) {
    final active = !g.over && g.turn == p;
    final color = p == 1 ? _p1Color : _p2Color;
    final score = p == 1 ? g.score1 : g.score2;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: active ? color : color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color, width: 2),
      ),
      child: Text(
        '${p == 1 ? 'X' : 'O'} ${nameOf(p)}: $score',
        style: TextStyle(
            fontWeight: FontWeight.bold,
            color: active ? Colors.white : color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!gameBuilt || (online && room == null)) {
      return Scaffold(
        appBar: AppBar(title: const Text('La Galleta')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (online && room!['status'] == 'lobby') {
      return Scaffold(
        appBar: AppBar(title: Text('La Galleta · Sala $code')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Comparte este código:'),
                Text(code,
                    style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6)),
                const SizedBox(height: 12),
                const Text('Esperando al otro jugador...'),
                const SizedBox(height: 12),
                const CircularProgressIndicator(),
              ],
            ),
          ),
        ),
      );
    }
    String status;
    if (g.over) {
      status = 'Fin de la partida';
    } else if (mode == _Mode.ai) {
      status = g.turn == 1 ? 'Tu turno: traza una raya' : 'Piensa la computadora...';
    } else if (mode == _Mode.local) {
      status = 'Turno de ${nameOf(g.turn)}';
    } else {
      status = g.turn == me
          ? 'Tu turno: traza una raya'
          : 'Turno de ${nameOf(g.turn)}...';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(online ? 'La Galleta · Sala $code' : 'La Galleta'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [_scoreTag(1), _scoreTag(2)],
              ),
            ),
            Expanded(
              child: Container(
                color: _paper,
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4,
                  child: _BoardView(
                    game: g,
                    popCells: _popCells,
                    popT: _pop.value,
                    onEdge: _onEdgeTap,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(status, style: const TextStyle(fontSize: 17)),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// Tablero
// ======================================================================

class _BoardView extends StatelessWidget {
  final GalletaGame game;
  final Set<int> popCells;
  final double popT;
  final void Function(int edge) onEdge;
  const _BoardView({
    required this.game,
    required this.popCells,
    required this.popT,
    required this.onEdge,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final geo = _Geo(game, c.maxWidth, c.maxHeight);
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: (d) {
          final e = geo.nearestEdge(d.localPosition);
          if (e != null) onEdge(e);
        },
        child: CustomPaint(
          size: Size(c.maxWidth, c.maxHeight),
          painter: _BoardPainter(game, geo, popCells, popT),
        ),
      );
    });
  }
}

class _Geo {
  final GalletaGame g;
  late final double cell;
  late final double ox, oy;
  _Geo(this.g, double w, double h) {
    cell = min(w / (g.w + 1), h / (g.h + 1));
    ox = (w - cell * g.w) / 2;
    oy = (h - cell * g.h) / 2;
  }

  Offset dot(int r, int c) => Offset(ox + c * cell, oy + r * cell);

  /// Extremos de una arista.
  (Offset, Offset) ends(int e) {
    if (e < g.horCount) {
      final r = e ~/ g.w, c = e % g.w;
      return (dot(r, c), dot(r, c + 1));
    }
    final k = e - g.horCount;
    final r = k ~/ (g.w + 1), c = k % (g.w + 1);
    return (dot(r, c), dot(r + 1, c));
  }

  /// Arista libre más cercana al toque (con una tolerancia generosa).
  int? nearestEdge(Offset p) {
    int? best;
    var bestD = cell * 0.42;
    for (final e in g.usable) {
      if (g.edgeOwner(e) != 0) continue;
      final (a, b) = ends(e);
      final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      // Distancia al segmento: se usa el centro y la cercanía a la recta.
      final d = _distToSegment(p, a, b);
      final dm = (p - mid).distance;
      final score = d + dm * 0.15;
      if (score < bestD) {
        bestD = score;
        best = e;
      }
    }
    return best;
  }

  double _distToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) /
        (ab.dx * ab.dx + ab.dy * ab.dy);
    final tt = t.clamp(0.0, 1.0);
    final proj = Offset(a.dx + ab.dx * tt, a.dy + ab.dy * tt);
    return (p - proj).distance;
  }
}

class _BoardPainter extends CustomPainter {
  final GalletaGame g;
  final _Geo geo;
  final Set<int> popCells;
  final double popT;
  _BoardPainter(this.g, this.geo, this.popCells, this.popT);

  @override
  void paint(Canvas canvas, Size size) {
    // Papel cuadriculado
    final grid = Paint()
      ..color = const Color(0x22305A9E)
      ..strokeWidth = 1;
    for (var x = geo.ox % (geo.cell / 2); x < size.width; x += geo.cell / 2) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = geo.oy % (geo.cell / 2); y < size.height; y += geo.cell / 2) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    // Cuadritos de la galleta
    for (var r = 0; r < g.h; r++) {
      for (var c = 0; c < g.w; c++) {
        final i = r * g.w + c;
        if (!g.mask[i]) continue;
        final rect = Rect.fromLTWH(
            geo.ox + c * geo.cell, geo.oy + r * geo.cell, geo.cell, geo.cell);
        final own = g.owner[i];
        final fill = own == 0
            ? _cookie
            : (own == 1 ? _p1Color : _p2Color).withOpacity(0.18);
        canvas.drawRect(rect, Paint()..color = fill);
        if (own != 0) {
          var scale = 1.0;
          if (popCells.contains(i)) {
            scale = Curves.easeOutBack.transform(popT.clamp(0.0, 1.0));
          }
          _drawMark(canvas, rect.center, geo.cell * 0.32 * scale, own);
        }
      }
    }

    // Rayas libres (guía tenue)
    final faint = Paint()
      ..color = const Color(0x33000000)
      ..strokeWidth = 1.5;
    for (final e in g.usable) {
      if (g.edgeOwner(e) != 0) continue;
      final (a, b) = geo.ends(e);
      canvas.drawLine(a, b, faint);
    }

    // Rayas trazadas
    for (final e in g.usable) {
      final o = g.edgeOwner(e);
      if (o == 0) continue;
      final (a, b) = geo.ends(e);
      final isLast = e == g.lastEdge;
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = o == 1 ? _p1Color : _p2Color
            ..strokeWidth = isLast ? geo.cell * 0.16 : geo.cell * 0.11
            ..strokeCap = StrokeCap.round);
    }

    // Contorno de la galleta (ya dibujado)
    final edgePaint = Paint()
      ..color = const Color(0xFF3E2723)
      ..strokeWidth = geo.cell * 0.09
      ..strokeCap = StrokeCap.round;
    for (final e in g.border) {
      final (a, b) = geo.ends(e);
      canvas.drawLine(a, b, edgePaint);
    }

    // Puntos
    final dotPaint = Paint()..color = const Color(0xFF3E2723);
    final used = <int>{};
    for (final e in [...g.usable, ...g.border]) {
      final (a, b) = geo.ends(e);
      for (final p in [a, b]) {
        final key = (p.dy / geo.cell * 1000).round() * 100000 +
            (p.dx / geo.cell * 1000).round();
        if (used.add(key)) {
          canvas.drawCircle(p, geo.cell * 0.075, dotPaint);
        }
      }
    }
  }

  void _drawMark(Canvas canvas, Offset c, double r, int p) {
    final paint = Paint()
      ..color = p == 1 ? _p1Color : _p2Color
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.0, r * 0.28)
      ..strokeCap = StrokeCap.round;
    if (p == 1) {
      canvas.drawLine(c + Offset(-r, -r), c + Offset(r, r), paint);
      canvas.drawLine(c + Offset(-r, r), c + Offset(r, -r), paint);
    } else {
      canvas.drawCircle(c, r, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}
