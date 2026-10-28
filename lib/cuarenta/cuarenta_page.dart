import 'dart:async';
import 'package:flutter/material.dart';
import 'bot.dart';
import 'engine.dart';
import 'card_fx.dart';
import '../sfx.dart';
import 'online.dart';

const rulesText = '''
• Baraja de 52 sin 8, 9 y 10: quedan 40 cartas (A a 7, J, Q, K).
• 5 cartas por jugador. Con 2 jugadores son 4 repartos por mano; con 4, son 2.
• Juega primero el de la derecha del repartidor.
• Levantar: por pareo (carta igual), por suma (dos cartas de la mesa que sumen tu carta; J, Q y K no suman) y por escalera (la carta siguiente en orden y las que continúen, se levantan solas).
• Trío de entrada: 2 puntos. Cuatro iguales de entrada: 10 puntos.
• Caída: 2. Limpia: 2. Caída y limpia juntas: 2.
• Al terminar la mano, con 20 cartas: 6 puntos, y +1 por carta extra (si queda impar, sube al par).
• Con 30 puntos o más ya no se cobra cartón.
• En línea: crea una sala y comparte el código; en parejas, el segundo en entrar es el compañero del anfitrión.
• Se gana la chica al llegar a 40. La grande es al mejor de 3 chicas.
''';

class CuarentaSetupPage extends StatefulWidget {
  const CuarentaSetupPage({super.key});

  @override
  State<CuarentaSetupPage> createState() => _CuarentaSetupPageState();
}

class _CuarentaSetupPageState extends State<CuarentaSetupPage> {
  int players = 2;
  bool grande = false;
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String? error;
  bool loading = false;

  Future<void> _createOnline() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final code = await CuarentaOnline.create(name, players, grande);
      _openRoom(code);
    } catch (e) {
      setState(() => error = 'No se pudo crear la sala: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _joinOnline() async {
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
      final err = await CuarentaOnline.join(code, name);
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
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CuarentaRoomPage(code: code)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cuarenta')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ListView(
            children: [
              const Text('Jugadores', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 2, label: Text('Tú vs 1 bot')),
                  ButtonSegment(value: 4, label: Text('En parejas (4)')),
                ],
                selected: {players},
                onSelectionChanged: (s) => setState(() => players = s.first),
              ),
              if (players == 4)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Tu compañero y los dos rivales son bots. Tú juegas con el asiento de abajo.'),
                ),
              const SizedBox(height: 24),
              const Text('Formato', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Chica (a 40)')),
                  ButtonSegment(value: true, label: Text('Grande (mejor de 3)')),
                ],
                selected: {grande},
                onSelectionChanged: (s) => setState(() => grande = s.first),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) =>
                      CuarentaGamePage(numPlayers: players, grande: grande),
                )),
                child: const Text('Jugar contra bots'),
              ),
              const Divider(height: 40),
              const Text('Jugar en línea con otras personas',
                  style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text(
                  'Usa el modo y el formato de arriba. Los asientos que no ocupe nadie los juegan bots.'),
              const SizedBox(height: 12),
              TextField(
                controller: nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Tu nombre',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: loading ? null : _createOnline,
                icon: const Icon(Icons.add),
                label: const Text('Crear sala'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: codeCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 5,
                decoration: const InputDecoration(
                  labelText: 'Código de sala',
                  border: OutlineInputBorder(),
                ),
              ),
              OutlinedButton.icon(
                onPressed: loading ? null : _joinOnline,
                icon: const Icon(Icons.login),
                label: const Text('Unirme a una sala'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child:
                      Text(error!, style: const TextStyle(color: Colors.red)),
                ),
              if (loading)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Center(child: CircularProgressIndicator()),
                ),
              const SizedBox(height: 24),
              const Text('Reglas usadas', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 8),
              const Text(rulesText),
            ],
          ),
        ),
      ),
    );
  }
}

class CuarentaGamePage extends StatefulWidget {
  final int numPlayers;
  final bool grande;
  const CuarentaGamePage(
      {super.key, required this.numPlayers, required this.grande});

  @override
  State<CuarentaGamePage> createState() => _CuarentaGamePageState();
}

class _CuarentaGamePageState extends State<CuarentaGamePage>
    with CardFx<CuarentaGamePage> {
  late CuarentaGame g;
  late List<String> seatNames;
  final teamNames = const ['Nosotros', 'Ellos'];
  final List<String> log = [];
  int wins0 = 0;
  int wins1 = 0;
  Timer? botTimer;

  @override
  void initState() {
    super.initState();
    seatNames = widget.numPlayers == 4
        ? ['Tú', 'Rival 1', 'Compañero', 'Rival 2']
        : ['Tú', 'Bot'];
    g = CuarentaGame(widget.numPlayers, seatNames, teamNames);
    log.addAll(g.events);
    _scheduleBot();
  }

  @override
  void dispose() {
    botTimer?.cancel();
    super.dispose();
  }

  void _scheduleBot() {
    if (g.winnerTeam != null || g.current == 0) return;
    botTimer?.cancel();
    botTimer = Timer(const Duration(milliseconds: 1700), () {
      if (!mounted || g.winnerTeam != null || g.current == 0) return;
      _apply(chooseBotMove(g));
    });
  }

  void _apply(Move m) {
    final seat = g.current;
    final desc = m.isCapture
        ? '${seatNames[seat]} jugó ${m.card.label} y levantó ${m.captured.map((c) => c.label).join(' + ')}'
        : '${seatNames[seat]} dejó ${m.card.label}';
    final ev = g.play(m);
    setState(() {
      log.add(desc);
      log.addAll(ev);
    });
    if (g.winnerTeam != null) {
      _chicaEnded();
    } else {
      _scheduleBot();
    }
  }

  Future<void> _chicaEnded() async {
    final w = g.winnerTeam!;
    if (w == 0) {
      wins0++;
    } else {
      wins1++;
    }
    final matchOver = !widget.grande || wins0 >= 2 || wins1 >= 2;
    Sfx.play(w == 0 ? 'win' : 'lose', delayMs: 900);
    final title = w == 0 ? '¡Ganaron ustedes!' : 'Ganaron los rivales';
    final body = widget.grande
        ? 'Chicas: Nosotros $wins0 - Ellos $wins1'
        : 'Marcador final: ${g.scores[0]} - ${g.scores[1]}';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(matchOver ? 'Salir' : 'Siguiente chica'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (matchOver) {
      Navigator.of(context).pop();
    } else {
      g.resetChica();
      setState(() {
        log
          ..clear()
          ..addAll(g.events);
      });
      _scheduleBot();
    }
  }

  Future<void> _onTapCard(PCard c) async {
    if (g.winnerTeam != null || g.current != 0) return;
    final moves = g.movesForCard(c);
    Move? chosen;
    if (moves.length == 1) {
      chosen = moves.first;
    } else {
      chosen = await showModalBottomSheet<Move>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in moves)
                ListTile(
                  title: Text(m.isCapture
                      ? 'Levantar: ${m.captured.map((x) => x.label).join(' + ')}${g.isCaida(m) ? '  ¡caída!' : ''}'
                      : 'Dejar ${c.label} en la mesa'),
                  onTap: () => Navigator.pop(ctx, m),
                ),
            ],
          ),
        ),
      );
    }
    if (chosen != null && mounted) _apply(chosen);
  }

  Widget _cardView(PCard c, {VoidCallback? onTap}) {
    return Opacity(
      opacity: fxHidden(c.id) ? 0 : 1,
      child: GestureDetector(
      onTap: onTap,
      child: Container(
        key: fxCardKey(c.id),
        width: 54,
        height: 78,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black54),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text(
          c.label,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: c.isRed ? Colors.red : Colors.black,
          ),
        ),
      ),
    ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myTurn = g.current == 0 && g.winnerTeam == null;
    fxSync(g, 0);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cuarenta'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Reglas'),
                content: const SingleChildScrollView(child: Text(rulesText)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cerrar'))
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          key: fxStackKey,
          children: [
            Positioned.fill(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Text('Nosotros: ${g.scores[0]}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                  if (widget.grande) Text('Chicas $wins0 - $wins1'),
                  Text('Ellos: ${g.scores[1]}',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                for (var s = 1; s < widget.numPlayers; s++)
                  Chip(
                    key: fxSeatKey(s),
                    backgroundColor:
                        g.current == s ? Colors.orange.shade200 : null,
                    label: Text('${seatNames[s]} (${g.hands[s].length})'),
                  ),
              ],
            ),
            Expanded(
              child: Center(
                child: g.table.isEmpty
                    ? const Text('Mesa vacía')
                    : Wrap(
                        alignment: WrapAlignment.center,
                        children: [for (final c in g.table) _cardView(c)],
                      ),
              ),
            ),
            Container(
              width: double.infinity,
              color: Colors.black12,
              padding: const EdgeInsets.all(8),
              child: Text(
                log.length <= 4
                    ? log.join('\n')
                    : log.sublist(log.length - 4).join('\n'),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(myTurn ? 'Tu turno' : 'Esperando...'),
            ),
            Wrap(
              key: fxHandKey,
              alignment: WrapAlignment.center,
              children: [
                for (final c in g.hands[0])
                  _cardView(c, onTap: myTurn ? () => _onTapCard(c) : null),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
            ),
            Positioned.fill(child: fxOverlay()),
          ],
        ),
      ),
    );
  }
}
