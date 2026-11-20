import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../sfx.dart';
import 'engine.dart';

// =============================================================================
// Mente brillante: menú y pantallas de cada reto (todo se juega sin internet).
// =============================================================================

/// Aciertos de esta sesión (se reinician al cerrar la app).
class MenteStats {
  static final Map<String, int> wins = {};
  static void add(String key, [int n = 1]) => wins[key] = (wins[key] ?? 0) + n;
  static int of(String key) => wins[key] ?? 0;
}

class MenteMenuPage extends StatefulWidget {
  const MenteMenuPage({super.key});

  @override
  State<MenteMenuPage> createState() => _MenteMenuPageState();
}

class _MenteMenuPageState extends State<MenteMenuPage> {
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) setState(() {});
  }

  Widget _card(String emoji, String title, String subtitle, String statKey, Widget page) {
    final n = MenteStats.of(statKey);
    return Card(
      child: ListTile(
        leading: Text(emoji, style: const TextStyle(fontSize: 34)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(n > 0 ? '$subtitle\nAciertos hoy: $n' : subtitle),
        isThreeLine: n > 0,
        trailing: const Icon(Icons.chevron_right),
        onTap: () => _open(page),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mente brillante')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 10),
            child: Text(
              'Retos de lógica, deducción, patrones, estrategia y pensamiento lateral. '
              'Se juega solo y sin internet.',
              style: TextStyle(fontSize: 15),
            ),
          ),
          _card('🕵️', '¿Quién es el culpable?',
              'Interroga a los sospechosos y deduce quién miente', 'culpable', const CulpritPage()),
          _card('🔢', 'Patrones numéricos',
              '8 series por ronda: descubre qué número sigue', 'patrones',
              const QuizPage.patterns()),
          _card('♟️', 'Duelo de estrategia',
              'Juega contra la PC: solo gana quien piensa varios pasos adelante', 'nim',
              const NimPage()),
          _card('💡', 'Pensamiento lateral',
              'Haz preguntas de Sí o No y adivina la historia', 'lateral',
              const LateralPage()),
          _card('🧩', 'Acertijos de lógica y mates',
              '8 acertijos por ronda con pista y explicación', 'acertijos',
              const QuizPage.riddles()),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Piezas comunes
// -----------------------------------------------------------------------------

class _LevelPicker extends StatelessWidget {
  final String title;
  final String intro;
  final List<String> names;
  final List<String> descs;
  final void Function(int) onPick;
  const _LevelPicker({
    required this.title,
    required this.intro,
    required this.names,
    required this.descs,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(intro, style: const TextStyle(fontSize: 15)),
        const SizedBox(height: 16),
        for (var i = 0; i < names.length; i++)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(names[i], style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(descs[i]),
              onTap: () => onPick(i),
            ),
          ),
      ],
    );
  }
}

// =============================================================================
// 1) ¿Quién es el culpable?
// =============================================================================

class CulpritPage extends StatefulWidget {
  const CulpritPage({super.key});

  @override
  State<CulpritPage> createState() => _CulpritPageState();
}

class _CulpritPageState extends State<CulpritPage> {
  final Random rng = Random();
  int? level;
  CulpritCase? kase;
  final Set<int> asked = {};
  final Set<int> cleared = {};
  int tries = 0;
  bool done = false;
  static const int maxTries = 2;

  void _start(int lv) {
    setState(() {
      level = lv;
      kase = CulpritCase.generate(lv, rng);
      asked.clear();
      cleared.clear();
      tries = 0;
      done = false;
    });
  }

  Future<void> _accuse(int i) async {
    final c = kase;
    if (c == null || done) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('¿Acusar a ${c.names[i]}?'),
        content: const Text('Solo tienes 2 intentos por caso.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sí, acusar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    if (i == c.culprit) {
      setState(() => done = true);
      MenteStats.add('culpable');
      Sfx.play('win');
      await _showResult(true);
    } else {
      setState(() {
        tries++;
        cleared.add(i);
        asked.add(i);
      });
      if (tries >= maxTries) {
        setState(() => done = true);
        Sfx.play('lose');
        await _showResult(false);
      } else {
        Sfx.play('lose');
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
              content: Text('${c.names[i]} no es el culpable. Te queda 1 intento.')));
      }
    }
  }

  Future<void> _showResult(bool won) async {
    final c = kase!;
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(won ? '¡Caso resuelto! 🎉' : 'Se escapó... 😕'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('El culpable era ${c.names[c.culprit]}.',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final l in c.explain())
                Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(l)),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).pop();
              },
              child: const Text('Salir')),
          FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _start(level ?? 0);
              },
              child: const Text('Otro caso')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = kase;
    return Scaffold(
      appBar: AppBar(
        title: const Text('¿Quién es el culpable?'),
        actions: [
          if (c != null)
            IconButton(
              tooltip: 'Cambiar de nivel',
              icon: const Icon(Icons.tune),
              onPressed: () => setState(() => kase = null),
            ),
        ],
      ),
      body: c == null ? _picker() : _caseView(c),
    );
  }

  Widget _picker() => _LevelPicker(
        title: 'Elige la dificultad',
        intro: 'En cada caso hay un solo culpable. Interroga a todos: '
            'el culpable siempre miente y los demás siempre dicen la verdad. '
            'Usa la lógica para descubrirlo.',
        names: const ['Fácil', 'Medio', 'Difícil'],
        descs: const ['4 sospechosos', '5 sospechosos', '6 sospechosos'],
        onPick: _start,
      );

  Widget _caseView(CulpritCase c) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(c.scenario.title,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(c.scenario.intro),
                const SizedBox(height: 8),
                const Text('📌 Regla: solo el CULPABLE miente. Los demás dicen la verdad.',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text('Intentos de acusación: ${maxTries - tries} de $maxTries',
              style: const TextStyle(fontSize: 14)),
        ),
        for (var i = 0; i < c.count; i++) _suspect(c, i),
        const SizedBox(height: 8),
        const Text(
          'Consejo: prueba con cada sospechoso como culpable y mira si alguna frase se contradice.',
          style: TextStyle(color: Colors.black54),
        ),
      ],
    );
  }

  Widget _suspect(CulpritCase c, int i) {
    final isAsked = asked.contains(i);
    final isCleared = cleared.contains(i);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(c.emojis[i], style: const TextStyle(fontSize: 34)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    c.names[i],
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      decoration: isCleared ? TextDecoration.lineThrough : null,
                      color: isCleared ? Colors.grey : null,
                    ),
                  ),
                ),
                if (isCleared) const Text('Descartado'),
              ],
            ),
            const SizedBox(height: 6),
            if (isAsked)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text('💬 «${c.say(i)}»', style: const TextStyle(fontSize: 17)),
              ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                if (!isAsked)
                  FilledButton.tonalIcon(
                    onPressed: done ? null : () => setState(() => asked.add(i)),
                    icon: const Icon(Icons.record_voice_over),
                    label: const Text('Interrogar'),
                  ),
                OutlinedButton(
                  onPressed: done
                      ? null
                      : () => setState(() {
                            if (isCleared) {
                              cleared.remove(i);
                            } else {
                              cleared.add(i);
                            }
                          }),
                  child: Text(isCleared ? 'Quitar descarte' : 'Descartar'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                  onPressed: done ? null : () => _accuse(i),
                  child: const Text('Acusar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 2) y 5) Cuestionarios de opción múltiple: patrones numéricos y acertijos
// =============================================================================

class _QItem {
  final String prompt;
  final Widget? header;
  final List<String> options;
  final int correct;
  final String hint;
  final String explanation;
  _QItem({
    required this.prompt,
    this.header,
    required this.options,
    required this.correct,
    required this.hint,
    required this.explanation,
  });
}

class QuizPage extends StatefulWidget {
  final bool patterns;
  const QuizPage.patterns({super.key}) : patterns = true;
  const QuizPage.riddles({super.key}) : patterns = false;

  @override
  State<QuizPage> createState() => _QuizPageState();
}

class _QuizPageState extends State<QuizPage> {
  static const int rounds = 8;
  final Random rng = Random();
  int? level; // solo para patrones
  List<_QItem> items = [];
  int idx = 0;
  int score = 0;
  int? chosen;
  bool hintShown = false;
  bool finished = false;

  String get _title => widget.patterns ? 'Patrones numéricos' : 'Acertijos de lógica y mates';
  String get _statKey => widget.patterns ? 'patrones' : 'acertijos';

  @override
  void initState() {
    super.initState();
    if (!widget.patterns) _begin();
  }

  void _begin() {
    final list = <_QItem>[];
    if (widget.patterns) {
      for (var i = 0; i < rounds; i++) {
        list.add(_patternItem(makePattern(level ?? 0, rng)));
      }
    } else {
      final pool = List<RiddleQ>.of(kRiddles)..shuffle(rng);
      for (final r in pool.take(rounds)) {
        list.add(_riddleItem(r));
      }
    }
    setState(() {
      items = list;
      idx = 0;
      score = 0;
      chosen = null;
      hintShown = false;
      finished = false;
    });
  }

  _QItem _riddleItem(RiddleQ r) {
    // Se barajan las opciones para que la correcta no siempre esté en el mismo sitio.
    final order = [for (var i = 0; i < r.options.length; i++) i]..shuffle(rng);
    return _QItem(
      prompt: r.text,
      options: [for (final i in order) r.options[i]],
      correct: order.indexOf(r.correct),
      hint: r.hint,
      explanation: r.explanation,
    );
  }

  _QItem _patternItem(PatternQ q) {
    final diffs = <String>[];
    for (var i = 1; i < q.shown.length; i++) {
      final d = q.shown[i] - q.shown[i - 1];
      diffs.add(d >= 0 ? '+$d' : '$d');
    }
    return _QItem(
      prompt: '¿Qué número sigue en la serie?',
      header: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final n in q.shown) _numBox('$n', false),
          _numBox('?', true),
        ],
      ),
      options: [for (final o in q.options) '$o'],
      correct: q.options.indexOf(q.answer),
      hint: 'Mira cuánto cambia de un número al siguiente: ${diffs.join('  ')}',
      explanation: 'La respuesta es ${q.answer}. ${q.rule}',
    );
  }

  Widget _numBox(String t, bool q) => Container(
        constraints: const BoxConstraints(minWidth: 46),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: q ? Colors.amber.shade200 : Colors.indigo.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: q ? Colors.orange : Colors.indigo.shade200, width: 2),
        ),
        child: Text(t,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      );

  void _choose(int k) {
    if (chosen != null) return;
    setState(() {
      chosen = k;
      if (k == items[idx].correct) {
        score++;
      }
    });
    Sfx.play(k == items[idx].correct ? 'score' : 'lose');
  }

  void _next() {
    if (idx + 1 >= items.length) {
      MenteStats.add(_statKey, score);
      Sfx.play(score >= (rounds * 0.6).ceil() ? 'win' : 'lose');
      setState(() => finished = true);
    } else {
      setState(() {
        idx++;
        chosen = null;
        hintShown = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (widget.patterns && level == null) {
      body = _LevelPicker(
        title: 'Elige la dificultad',
        intro: 'Son $rounds series. Descubre la regla y elige el número que sigue.',
        names: const ['Fácil', 'Medio', 'Difícil'],
        descs: const [
          'Sumas, multiplicaciones y cuadrados',
          'Fibonacci, triangulares y diferencias que crecen',
          'Series mezcladas, primos, cubos y pasos alternados',
        ],
        onPick: (lv) {
          level = lv;
          _begin();
        },
      );
    } else if (finished) {
      body = _result();
    } else if (items.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = _question(items[idx]);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (widget.patterns && level != null)
            IconButton(
              tooltip: 'Cambiar de nivel',
              icon: const Icon(Icons.tune),
              onPressed: () => setState(() {
                level = null;
                items = [];
              }),
            ),
        ],
      ),
      body: body,
    );
  }

  Widget _question(_QItem it) {
    final answered = chosen != null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Pregunta ${idx + 1} de ${items.length}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const Spacer(),
            Text('Aciertos: $score'),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(value: (idx + (answered ? 1 : 0)) / items.length),
        const SizedBox(height: 16),
        Text(it.prompt, style: const TextStyle(fontSize: 19, height: 1.3)),
        if (it.header != null) ...[
          const SizedBox(height: 14),
          it.header!,
        ],
        const SizedBox(height: 16),
        for (var k = 0; k < it.options.length; k++)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                  backgroundColor: !answered
                      ? null
                      : (k == it.correct
                          ? Colors.green.shade200
                          : (k == chosen ? Colors.red.shade200 : null)),
                ),
                onPressed: answered ? null : () => _choose(k),
                child: Text(it.options[k],
                    textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
              ),
            ),
          ),
        const SizedBox(height: 4),
        if (!answered)
          TextButton.icon(
            onPressed: () => setState(() => hintShown = true),
            icon: const Icon(Icons.lightbulb_outline),
            label: const Text('Ver una pista'),
          ),
        if (hintShown && !answered)
          Card(
            color: Colors.yellow.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('💡 ${it.hint}'),
            ),
          ),
        if (answered) ...[
          Card(
            color: chosen == it.correct ? Colors.green.shade50 : Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(chosen == it.correct ? '¡Correcto! 🎉' : 'Casi... 🤔',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  Text(it.explanation),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _next,
            child: Text(idx + 1 >= items.length ? 'Ver resultado' : 'Siguiente'),
          ),
        ],
      ],
    );
  }

  Widget _result() {
    final total = items.length;
    final msg = score == total
        ? '¡Perfecto! Mente brillante de verdad.'
        : score >= (total * 0.6).ceil()
            ? '¡Muy bien! Vas por buen camino.'
            : 'Sigue practicando: cada acertijo entrena tu mente.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🏆', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 8),
            Text('$score de $total',
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(msg, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _begin,
              icon: const Icon(Icons.refresh),
              label: const Text('Jugar otra ronda'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Volver al menú'),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 3) Duelo de estrategia (Nim contra la PC)
// =============================================================================

class NimPage extends StatefulWidget {
  const NimPage({super.key});

  @override
  State<NimPage> createState() => _NimPageState();
}

class _NimPageState extends State<NimPage> {
  final Random rng = Random();
  int? level;
  NimGame? game;
  int selHeap = -1;
  int selFrom = -1;
  bool thinking = false;
  bool ended = false;
  String msg = '';
  bool hintShown = false;
  Timer? aiTimer;

  @override
  void dispose() {
    aiTimer?.cancel();
    super.dispose();
  }

  void _start(int lv) {
    aiTimer?.cancel();
    setState(() {
      level = lv;
      game = NimGame.generate(lv, rng);
      selHeap = -1;
      selFrom = -1;
      thinking = false;
      ended = false;
      hintShown = false;
      msg = 'Empiezas tú. ¡Piensa bien tu primera jugada!';
    });
  }

  int get _selCount {
    final g = game;
    if (g == null || selHeap < 0 || selFrom < 0) return 0;
    return g.heaps[selHeap] - selFrom;
  }

  void _tapStone(int h, int j) {
    final g = game;
    if (g == null || thinking || ended) return;
    setState(() {
      selHeap = h;
      selFrom = j;
    });
    final n = g.heaps[h] - j;
    if (g.maxTake > 0 && n > g.maxTake) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            duration: const Duration(milliseconds: 1200),
            content: Text('Solo puedes tomar de 1 a ${g.maxTake} piedras.')));
    }
  }

  void _take() {
    final g = game;
    if (g == null || thinking || ended) return;
    final n = _selCount;
    if (!g.canTake(selHeap, n)) return;
    g.applyMove(selHeap, n);
    Sfx.play('tick');
    setState(() {
      selHeap = -1;
      selFrom = -1;
      hintShown = false;
      msg = 'Tomaste $n. Piensa la PC...';
    });
    if (g.over) {
      _finish(!g.misere);
      return;
    }
    setState(() => thinking = true);
    aiTimer?.cancel();
    aiTimer = Timer(const Duration(milliseconds: 1000), _aiMove);
  }

  void _aiMove() {
    final g = game;
    if (!mounted || g == null) return;
    final m = g.bestMove(rng);
    g.applyMove(m.heap, m.take);
    Sfx.play('card_place');
    setState(() {
      thinking = false;
      msg = g.heaps.length > 1
          ? 'La PC tomó ${m.take} del montón ${m.heap + 1}. Tu turno.'
          : 'La PC tomó ${m.take}. Tu turno.';
    });
    if (g.over) _finish(g.misere);
  }

  Future<void> _finish(bool playerWon) async {
    setState(() => ended = true);
    if (playerWon) MenteStats.add('nim');
    Sfx.play(playerWon ? 'win' : 'lose');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(playerWon ? '¡Ganaste! 🎉' : 'La PC ganó 🤖'),
        content: Text(playerWon
            ? 'Planeaste varios pasos adelante y eso fue lo que decidió la partida.'
            : 'La PC juega perfecto. ¡Pero tú empezaste en una posición ganadora! '
                'Prueba otra vez y pide una pista antes de mover.'),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.of(context).pop();
              },
              child: const Text('Salir')),
          FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                _start(level ?? 0);
              },
              child: const Text('Otra partida')),
        ],
      ),
    );
  }

  void _showHint() {
    final g = game;
    if (g == null || thinking || ended) return;
    setState(() => hintShown = true);
  }

  @override
  Widget build(BuildContext context) {
    final g = game;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Duelo de estrategia'),
        actions: [
          if (g != null)
            IconButton(
              tooltip: 'Cambiar de nivel',
              icon: const Icon(Icons.tune),
              onPressed: () {
                aiTimer?.cancel();
                setState(() {
                  game = null;
                  level = null;
                  thinking = false;
                });
              },
            ),
        ],
      ),
      body: g == null ? _picker() : _board(g),
    );
  }

  Widget _picker() => _LevelPicker(
        title: 'Elige el duelo',
        intro: 'Juegas contra la PC, que no se equivoca. Siempre empiezas en una '
            'posición ganadora: si juegas bien cada turno, ganas.',
        names: const ['Fácil', 'Medio', 'Difícil'],
        descs: const [
          'Un montón de piedras, tomas de 1 a 3. Gana quien toma la última.',
          'Un montón, tomas de 1 a 3. ¡Pierde quien toma la última!',
          'Tres montones: tomas las que quieras de UN montón. Gana quien toma la última.',
        ],
        onPick: _start,
      );

  Widget _board(NimGame g) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: Colors.indigo.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(g.ruleText, style: const TextStyle(fontSize: 16)),
          ),
        ),
        const SizedBox(height: 8),
        Text(msg, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text('Toca una piedra: se elige esa y todas las que están después en su montón.',
            style: TextStyle(color: Colors.black54)),
        const SizedBox(height: 10),
        for (var h = 0; h < g.heaps.length; h++) _heap(g, h),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (thinking || ended || _selCount == 0 || !g.canTake(selHeap, _selCount))
              ? null
              : _take,
          icon: const Icon(Icons.back_hand),
          label: Text(_selCount == 0 ? 'Elige piedras' : 'Tomar $_selCount'),
        ),
        const SizedBox(height: 8),
        if (thinking)
          const Center(child: Text('🤖 La PC está pensando...', style: TextStyle(fontSize: 16))),
        TextButton.icon(
          onPressed: (thinking || ended) ? null : _showHint,
          icon: const Icon(Icons.lightbulb_outline),
          label: const Text('Ver una pista'),
        ),
        if (hintShown)
          Card(
            color: Colors.yellow.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('💡 ${g.hintText()}'),
            ),
          ),
      ],
    );
  }

  Widget _heap(NimGame g, int h) {
    final n = g.heaps[h];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(g.heaps.length > 1 ? 'Montón ${h + 1}: $n' : 'Piedras: $n',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (n == 0)
              const Text('(vacío)', style: TextStyle(color: Colors.black45))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var j = 0; j < n; j++)
                    GestureDetector(
                      onTap: () => _tapStone(h, j),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: (selHeap == h && j >= selFrom)
                              ? Colors.amber
                              : Colors.blueGrey.shade300,
                          border: Border.all(color: Colors.blueGrey.shade700, width: 2),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 4) Pensamiento lateral
// =============================================================================

class LateralPage extends StatefulWidget {
  const LateralPage({super.key});

  @override
  State<LateralPage> createState() => _LateralPageState();
}

class _LateralPageState extends State<LateralPage> {
  final Random rng = Random();
  late List<int> order;
  int pos = 0;
  final Set<int> asked = {};
  bool guessing = false;
  int triesLeft = 2;
  bool done = false;
  bool won = false;
  int? wrongPick;

  LateralPuzzle get puzzle => kLateral[order[pos]];

  @override
  void initState() {
    super.initState();
    order = [for (var i = 0; i < kLateral.length; i++) i]..shuffle(rng);
  }

  void _reset() {
    asked.clear();
    guessing = false;
    triesLeft = 2;
    done = false;
    won = false;
    wrongPick = null;
  }

  void _nextStory() {
    setState(() {
      pos++;
      if (pos >= order.length) {
        order.shuffle(rng);
        pos = 0;
      }
      _reset();
    });
  }

  void _pick(int k) {
    final p = puzzle;
    if (done) return;
    if (k == p.correct) {
      setState(() {
        done = true;
        won = true;
        guessing = false;
      });
      MenteStats.add('lateral');
      Sfx.play('win');
    } else {
      Sfx.play('lose');
      setState(() {
        triesLeft--;
        wrongPick = k;
        if (triesLeft <= 0) {
          done = true;
          won = false;
          guessing = false;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = puzzle;
    return Scaffold(
      appBar: AppBar(title: const Text('Pensamiento lateral')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Historia ${pos + 1} de ${order.length}',
              style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 4),
          Text(p.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Card(
            color: Colors.purple.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(p.story, style: const TextStyle(fontSize: 17, height: 1.35)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Pregunta lo que quieras (solo se responde Sí, No o No importa) y luego adivina qué pasó.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 10),
          if (!guessing && !done) ..._questions(p),
          if (guessing && !done) ..._options(p),
          if (done) ..._ending(p),
        ],
      ),
    );
  }

  List<Widget> _questions(LateralPuzzle p) {
    return [
      for (var i = 0; i < p.questions.length; i++)
        Card(
          child: ListTile(
            title: Text(p.questions[i].text),
            trailing: asked.contains(i)
                ? Chip(
                    label: Text(kYesNo[p.questions[i].answer],
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    backgroundColor: p.questions[i].answer == 0
                        ? Colors.green.shade100
                        : (p.questions[i].answer == 1
                            ? Colors.red.shade100
                            : Colors.grey.shade300),
                  )
                : const Icon(Icons.help_outline),
            onTap: asked.contains(i)
                ? null
                : () {
                    Sfx.play('tick');
                    setState(() => asked.add(i));
                  },
          ),
        ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: () => setState(() => guessing = true),
        icon: const Icon(Icons.psychology),
        label: const Text('Creo saber qué pasó'),
      ),
    ];
  }

  List<Widget> _options(LateralPuzzle p) {
    return [
      Text('¿Qué pasó en realidad? (te quedan $triesLeft intento${triesLeft == 1 ? '' : 's'})',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      if (wrongPick != null)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Esa no era. ¡Prueba otra!', style: TextStyle(color: Colors.red)),
        ),
      const SizedBox(height: 8),
      for (var k = 0; k < p.options.length; k++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.all(14),
                backgroundColor: wrongPick == k ? Colors.red.shade100 : null,
              ),
              onPressed: wrongPick == k ? null : () => _pick(k),
              child: Text(p.options[k], style: const TextStyle(fontSize: 16)),
            ),
          ),
        ),
      TextButton(
        onPressed: () => setState(() => guessing = false),
        child: const Text('Volver a las preguntas'),
      ),
    ];
  }

  List<Widget> _ending(LateralPuzzle p) {
    return [
      Card(
        color: won ? Colors.green.shade50 : Colors.orange.shade50,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(won ? '¡Lo descubriste! 🎉' : 'Esta vez no salió 😕',
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(p.explanation, style: const TextStyle(fontSize: 16, height: 1.35)),
            ],
          ),
        ),
      ),
      const SizedBox(height: 10),
      FilledButton.icon(
        onPressed: _nextStory,
        icon: const Icon(Icons.navigate_next),
        label: const Text('Otra historia'),
      ),
    ];
  }
}
