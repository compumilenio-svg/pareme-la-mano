import 'dart:math';

// =============================================================================
// Mente brillante: retos de lógica, deducción, patrones, estrategia y
// pensamiento lateral. Todo corre en el teléfono (sin internet).
// Este archivo NO usa Flutter para poder probarlo con `dart run`.
// =============================================================================

// ---------------------------------------------------------------------------
// 1) ¿Quién es el culpable?  (deducción)
// Regla del juego: SOLO EL CULPABLE MIENTE; todos los demás dicen la verdad.
// Cada caso se genera al azar y se comprueba que tenga UNA sola solución.
// ---------------------------------------------------------------------------

const List<String> kSuspectNames = [
  'Ana', 'Bruno', 'Carla', 'Diego', 'Elena', 'Felipe', 'Gaby', 'Hugo', 'Inés', 'Jorge',
];

const List<String> kSuspectEmojis = [
  '👩', '👨', '👧', '👦', '🧑', '👵', '👴', '🧒', '👱', '🧔',
];

class Scenario {
  final String title;
  final String intro;
  const Scenario(this.title, this.intro);
}

const List<Scenario> kScenarios = [
  Scenario('El pastel desaparecido',
      'Anoche desapareció el pastel de cumpleaños de la abuela. Solo estas personas estuvieron en la casa.'),
  Scenario('La ventana rota',
      'Alguien rompió con una pelota la ventana del vecino. Los sospechosos jugaban en la calle.'),
  Scenario('El trofeo perdido',
      'El trofeo del campeonato del barrio ya no está en la vitrina del club. Solo ellos tenían llave.'),
  Scenario('La bocina de la fiesta',
      'Alguien se llevó la bocina del salón comunal antes de la fiesta. Solo ellos pasaron por ahí.'),
  Scenario('El café derramado',
      'Alguien derramó café sobre los planos de la oficina y se fue sin decir nada. Solo ellos estaban en el piso.'),
  Scenario('El gol anulado',
      'Alguien desinfló a propósito el balón antes del partido final. Solo ellos entraron al camerino.'),
];

class Statement {
  /// 0: «X es inocente» · 1: «Fue X» · 2: «Fue X o fue Y» · 3: «No fue ni X ni Y»
  final int kind;
  final int a;
  final int b;
  const Statement(this.kind, this.a, this.b);

  /// ¿La frase es verdadera si el culpable fuera [culprit]?
  bool truthAt(int culprit) {
    switch (kind) {
      case 0:
        return culprit != a;
      case 1:
        return culprit == a;
      case 2:
        return culprit == a || culprit == b;
      default:
        return culprit != a && culprit != b;
    }
  }
}

class CulpritCase {
  final Scenario scenario;
  final List<String> names;
  final List<String> emojis;
  final List<Statement> statements;
  final int culprit;
  const CulpritCase(this.scenario, this.names, this.emojis, this.statements, this.culprit);

  int get count => names.length;

  /// Culpables posibles que no contradicen ninguna frase según la regla.
  List<int> consistentCulprits() {
    final out = <int>[];
    for (var c = 0; c < count; c++) {
      var ok = true;
      for (var i = 0; i < count; i++) {
        if (statements[i].truthAt(c) != (i != c)) {
          ok = false;
          break;
        }
      }
      if (ok) out.add(c);
    }
    return out;
  }

  String _who(int speaker, int x) => x == speaker ? 'yo' : names[x];

  /// Lo que dice el sospechoso [speaker], en español.
  String say(int speaker) {
    final s = statements[speaker];
    switch (s.kind) {
      case 0:
        return s.a == speaker ? 'Yo soy inocente.' : '${names[s.a]} es inocente.';
      case 1:
        return s.a == speaker ? 'Fui yo.' : 'Fue ${names[s.a]}.';
      case 2:
        return 'Fue ${_who(speaker, s.a)} o fue ${_who(speaker, s.b)}.';
      default:
        return 'No fue ni ${_who(speaker, s.a)} ni ${_who(speaker, s.b)}.';
    }
  }

  /// Explicación paso a paso de la solución.
  List<String> explain() {
    final lines = <String>[];
    for (var i = 0; i < count; i++) {
      lines.add(i == culprit
          ? '${names[i]}: «${say(i)}» → es FALSO, miente: es el culpable.'
          : '${names[i]}: «${say(i)}» → es verdad (con ${names[culprit]} como culpable).');
    }
    lines.add('Con cualquier otro culpable alguien se contradice, así que solo puede ser ${names[culprit]}.');
    return lines;
  }

  /// [level] 0 = 4 sospechosos, 1 = 5, 2 = 6.
  static CulpritCase generate(int level, Random rng) {
    final n = 4 + level.clamp(0, 2).toInt();
    final order = [for (var i = 0; i < kSuspectNames.length; i++) i]..shuffle(rng);
    final names = [for (var i = 0; i < n; i++) kSuspectNames[order[i]]];
    final emojis = [for (var i = 0; i < n; i++) kSuspectEmojis[order[i]]];
    final scenario = kScenarios[rng.nextInt(kScenarios.length)];
    for (var attempt = 0; attempt < 20000; attempt++) {
      final culprit = rng.nextInt(n);
      final sts = <Statement>[];
      var ok = true;
      for (var i = 0; i < n; i++) {
        final needTrue = i != culprit;
        Statement? found;
        for (var t = 0; t < 60; t++) {
          final kind = rng.nextInt(4);
          final a = rng.nextInt(n);
          final b = rng.nextInt(n);
          if (kind >= 2 && a == b) continue;
          if (kind == 1 && a == i) continue;
          final st = Statement(kind, a, b);
          if (st.truthAt(culprit) == needTrue) {
            found = st;
            break;
          }
        }
        if (found == null) {
          ok = false;
          break;
        }
        sts.add(found);
      }
      if (!ok) continue;
      final c = CulpritCase(scenario, names, emojis, sts, culprit);
      final cons = c.consistentCulprits();
      if (cons.length == 1 && cons.first == culprit) return c;
    }
    // Caso de respaldo (nunca debería usarse): 4 sospechosos con solución única.
    final sts = <Statement>[
      const Statement(1, 1, 0), // 0: «Fue 1» (falso => 0 es culpable)... se verifica abajo
      const Statement(0, 1, 0),
      const Statement(0, 0, 0),
      const Statement(0, 0, 0),
    ];
    return CulpritCase(scenario, names.sublist(0, 4), emojis.sublist(0, 4), sts, 0);
  }
}

// ---------------------------------------------------------------------------
// 2) Patrones numéricos
// ---------------------------------------------------------------------------

class PatternQ {
  final List<int> shown;
  final int answer;
  final List<int> options;
  final String rule;
  const PatternQ(this.shown, this.answer, this.options, this.rule);
}

const List<int> _primes = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31];

PatternQ makePattern(int level, Random rng) {
  final pools = <List<int>>[
    [0, 1, 2],
    [0, 1, 2, 3, 4, 5, 10],
    [3, 4, 5, 6, 7, 8, 9, 10],
  ];
  final pool = pools[level.clamp(0, 2).toInt()];
  final kind = pool[rng.nextInt(pool.length)];
  final shownCount = level == 0 ? 5 : 6;
  final total = shownCount + 1;
  final t = <int>[];
  var rule = '';
  switch (kind) {
    case 0:
      final a0 = rng.nextInt(20) + 1;
      final d = rng.nextInt(9) + 2;
      for (var i = 0; i < total; i++) {
        t.add(a0 + d * i);
      }
      rule = 'Cada número es el anterior más $d.';
      break;
    case 1:
      final a0 = rng.nextInt(4) + 1;
      final r = level == 0 ? 2 : 2 + rng.nextInt(2);
      var v = a0;
      for (var i = 0; i < total; i++) {
        t.add(v);
        v *= r;
      }
      rule = 'Cada número es el anterior multiplicado por $r.';
      break;
    case 2:
      final s = rng.nextInt(5) + 1;
      for (var i = 0; i < total; i++) {
        t.add((s + i) * (s + i));
      }
      rule = 'Son cuadrados consecutivos: $s×$s, ${s + 1}×${s + 1}, ${s + 2}×${s + 2}…';
      break;
    case 3:
      final x0 = rng.nextInt(4) + 1;
      final x1 = rng.nextInt(4) + 2;
      t.add(x0);
      t.add(x1);
      for (var i = 2; i < total; i++) {
        t.add(t[i - 1] + t[i - 2]);
      }
      rule = 'Cada número es la suma de los dos anteriores.';
      break;
    case 4:
      final k = rng.nextInt(3) + 1;
      final inc = rng.nextInt(2) + 1;
      var v = rng.nextInt(10) + 1;
      t.add(v);
      for (var i = 0; i < total - 1; i++) {
        v += k + i * inc;
        t.add(v);
      }
      rule = 'Lo que se suma va creciendo: primero $k, luego ${k + inc}, luego ${k + 2 * inc}…';
      break;
    case 5:
      final s = rng.nextInt(3) + 1;
      for (var i = 0; i < total; i++) {
        final n = s + i;
        t.add(n * (n + 1) ~/ 2);
      }
      rule = 'Son números triangulares: se suma 1, luego 2, luego 3… (cada vez un número más).';
      break;
    case 6:
      final add = rng.nextInt(4) + 1;
      var v = rng.nextInt(4) + 2;
      for (var i = 0; i < total; i++) {
        t.add(v);
        v = i.isEven ? v + add : v * 2;
      }
      rule = 'Se alternan dos pasos: sumar $add y multiplicar por 2.';
      break;
    case 7:
      final s = rng.nextInt(3);
      for (var i = 0; i < total; i++) {
        t.add(_primes[s + i]);
      }
      rule = 'Son los números primos: solo se dividen entre 1 y entre sí mismos.';
      break;
    case 8:
      final s = rng.nextInt(2) + 1;
      for (var i = 0; i < total; i++) {
        t.add((s + i) * (s + i) * (s + i));
      }
      rule = 'Son cubos consecutivos: $s×$s×$s, ${s + 1}×${s + 1}×${s + 1}…';
      break;
    case 9:
      final b1 = rng.nextInt(5) + 1;
      final up = rng.nextInt(3) + 2;
      final b2 = 30 + rng.nextInt(10);
      final down = rng.nextInt(3) + 2;
      for (var i = 0; i < total; i++) {
        if (i.isEven) {
          t.add(b1 + up * (i ~/ 2));
        } else {
          t.add(b2 - down * (i ~/ 2));
        }
      }
      rule = 'Hay dos series mezcladas: una sube de $up en $up y la otra baja de $down en $down.';
      break;
    default:
      final c = [-1, 1, 2][rng.nextInt(3)];
      var v = rng.nextInt(3) + 1;
      for (var i = 0; i < total; i++) {
        t.add(v);
        v = v * 2 + c;
      }
      final sign = c < 0 ? 'menos ${-c}' : 'más $c';
      rule = 'Cada número es el anterior por 2, $sign.';
      break;
  }
  final answer = t[shownCount];
  final shown = t.sublist(0, shownCount);
  final lastDiff = t[shownCount - 1] - t[shownCount - 2];
  final cands = <int>[
    answer + 1,
    answer - 1,
    answer + 2,
    answer - 2,
    t[shownCount - 1] + lastDiff,
    t[shownCount - 1] * 2,
    answer + 10,
    answer - 10,
    answer + 5,
    answer * 2,
  ]..shuffle(rng);
  final opts = <int>{answer};
  for (final c in cands) {
    if (opts.length >= 4) break;
    if (c != answer) opts.add(c);
  }
  var extra = 3;
  while (opts.length < 4) {
    opts.add(answer + extra);
    extra += 2;
  }
  final options = opts.toList()..shuffle(rng);
  return PatternQ(shown, answer, options, rule);
}

// ---------------------------------------------------------------------------
// 3) Duelo de estrategia (juego de Nim contra la PC, que juega perfecto)
// ---------------------------------------------------------------------------

class NimMove {
  final int heap;
  final int take;
  const NimMove(this.heap, this.take);
}

class NimGame {
  final List<int> heaps;
  final int maxTake; // 0 = sin límite
  final bool misere; // true: quien toma la última pierde
  NimGame(this.heaps, this.maxTake, this.misere);

  bool get over => heaps.every((h) => h == 0);
  int get total => heaps.fold<int>(0, (a, b) => a + b);

  bool canTake(int heap, int take) =>
      heap >= 0 &&
      heap < heaps.length &&
      take >= 1 &&
      take <= heaps[heap] &&
      (maxTake == 0 || take <= maxTake);

  bool applyMove(int heap, int take) {
    if (!canTake(heap, take)) return false;
    heaps[heap] -= take;
    return true;
  }

  int get _xor => heaps.fold<int>(0, (a, b) => a ^ b);

  /// ¿Quien mueve ahora puede ganar jugando bien?
  bool get moverWins {
    if (over) return misere; // el anterior tomó la última
    if (heaps.length == 1 && maxTake > 0) {
      final n = heaps[0];
      final m = maxTake;
      return misere ? (n - 1) % (m + 1) != 0 : n % (m + 1) != 0;
    }
    return _xor != 0;
  }

  /// Mejor jugada (o una cualquiera si la posición está perdida).
  NimMove bestMove(Random rng) {
    if (heaps.length == 1 && maxTake > 0) {
      final n = heaps[0];
      final m = maxTake;
      final r = misere ? (n - 1) % (m + 1) : n % (m + 1);
      if (r > 0) return NimMove(0, r);
      return NimMove(0, 1 + rng.nextInt(min(m, n)));
    }
    final x = _xor;
    if (x != 0) {
      for (var i = 0; i < heaps.length; i++) {
        final target = heaps[i] ^ x;
        if (target < heaps[i]) return NimMove(i, heaps[i] - target);
      }
    }
    final alive = [
      for (var i = 0; i < heaps.length; i++)
        if (heaps[i] > 0) i
    ];
    final h = alive[rng.nextInt(alive.length)];
    return NimMove(h, 1 + rng.nextInt(heaps[h]));
  }

  String get ruleText {
    final lim = maxTake == 0 ? 'cuantas quieras de UN solo montón' : 'de 1 a $maxTake de un montón';
    return misere
        ? 'Por turnos, cada uno toma $lim. ¡Quien toma la ÚLTIMA piedra pierde!'
        : 'Por turnos, cada uno toma $lim. ¡Quien toma la ÚLTIMA piedra gana!';
  }

  String hintText() {
    if (heaps.length == 1 && maxTake > 0) {
      final m = maxTake;
      return misere
          ? 'Busca dejar siempre una cantidad que sea 1 más un múltiplo de ${m + 1} (1, ${m + 2}, ${2 * m + 3}…).'
          : 'Busca dejar siempre un múltiplo de ${m + 1} (${m + 1}, ${2 * (m + 1)}, ${3 * (m + 1)}…).';
    }
    return 'Escribe cada montón en binario y suma sin llevar (XOR). Si dejas el resultado en 0, vas ganando.';
  }

  /// [level] 0 = un montón (gana el último), 1 = un montón (pierde el último),
  /// 2 = tres montones. Siempre empieza el jugador desde una posición ganadora.
  static NimGame generate(int level, Random rng) {
    switch (level.clamp(0, 2).toInt()) {
      case 0:
        final opts = [for (var n = 13; n <= 22; n++) if (n % 4 != 0) n];
        return NimGame([opts[rng.nextInt(opts.length)]], 3, false);
      case 1:
        final opts = [for (var n = 14; n <= 23; n++) if (n % 4 != 1) n];
        return NimGame([opts[rng.nextInt(opts.length)]], 3, true);
      default:
        for (var i = 0; i < 1000; i++) {
          final h = [rng.nextInt(7) + 1, rng.nextInt(7) + 1, rng.nextInt(7) + 1];
          if ((h[0] ^ h[1] ^ h[2]) != 0 && h[0] + h[1] + h[2] >= 8) {
            return NimGame(h, 0, false);
          }
        }
        return NimGame([3, 4, 5], 0, false);
    }
  }
}

// ---------------------------------------------------------------------------
// 4) Pensamiento lateral: preguntas de Sí / No y luego se adivina la historia
// ---------------------------------------------------------------------------

class LateralQuestion {
  final String text;
  final int answer; // 0 Sí · 1 No · 2 No importa
  const LateralQuestion(this.text, this.answer);
}

class LateralPuzzle {
  final String title;
  final String story;
  final List<LateralQuestion> questions;
  final List<String> options;
  final int correct;
  final String explanation;
  const LateralPuzzle(
      this.title, this.story, this.questions, this.options, this.correct, this.explanation);
}

const List<String> kYesNo = ['Sí', 'No', 'No importa'];

const List<LateralPuzzle> kLateral = [
  LateralPuzzle(
    'El hombre del ascensor',
    'Un hombre vive en el piso 20. Todas las mañanas baja en ascensor hasta la planta baja. '
        'Al volver, sube en el ascensor solo hasta el piso 12 y el resto lo sube por las escaleras. '
        'Pero si llueve o si hay alguien más en el ascensor, llega hasta el piso 20. ¿Por qué?',
    [
      LateralQuestion('¿Está enfermo o tiene miedo a las alturas?', 1),
      LateralQuestion('¿Lo hace para hacer ejercicio?', 1),
      LateralQuestion('¿Tiene que ver con su estatura?', 0),
      LateralQuestion('¿El ascensor está dañado?', 1),
      LateralQuestion('¿Cuando llueve lleva algo que le ayuda?', 0),
      LateralQuestion('¿El color de la ropa importa?', 2),
    ],
    [
      'Es muy bajito y solo alcanza el botón del piso 12; con paraguas o ayuda llega al 20.',
      'Le falta dinero para pagar el ascensor completo.',
      'El ascensor solo sube hasta el piso 12 si está vacío.',
      'Le gusta saludar a su vecino del piso 12.',
    ],
    0,
    'El hombre es de baja estatura: desde el ascensor solo alcanza el botón del piso 12. '
        'Cuando llueve usa su paraguas para presionar el botón del 20, y si hay alguien más, esa persona lo presiona por él.',
  ),
  LateralPuzzle(
    'El hombre en el campo',
    'Encuentran a un hombre muerto en medio de un campo abierto, sin huellas a su alrededor ni construcciones cerca. '
        'En su mano tiene un fósforo (cerillo) sin quemar. ¿Qué pasó?',
    [
      LateralQuestion('¿Murió de forma natural?', 1),
      LateralQuestion('¿Cayó desde un lugar alto?', 0),
      LateralQuestion('¿Había más personas con él antes de caer?', 0),
      LateralQuestion('¿Usó el fósforo para hacer fuego?', 1),
      LateralQuestion('¿Fue un sorteo entre varias personas?', 0),
      LateralQuestion('¿Importa que no haya huellas?', 0),
    ],
    [
      'Viajaba en un globo que perdía altura, sortearon con fósforos quién saltaba y le tocó el más corto.',
      'Se perdió en el campo y murió de frío.',
      'Alguien lo asesinó y borró las huellas.',
      'Un rayo lo alcanzó mientras encendía un fósforo.',
    ],
    0,
    'Iba en un globo aerostático que perdía altura. Para que los demás se salvaran, alguien debía saltar: '
        'sortearon con fósforos y le tocó el más corto. Cayó desde el cielo, por eso no hay huellas.',
  ),
  LateralPuzzle(
    'El auto y el hotel',
    'Un hombre empuja su auto hasta la puerta de un hotel. En cuanto llega, se da cuenta de que está arruinado. ¿Por qué?',
    [
      LateralQuestion('¿El auto es de verdad?', 1),
      LateralQuestion('¿Es parte de un juego?', 0),
      LateralQuestion('¿Perdió dinero real?', 1),
      LateralQuestion('¿Es un juego de mesa?', 0),
      LateralQuestion('¿Alguien lo robó?', 1),
      LateralQuestion('¿Tiene que ver con comprar y vender propiedades?', 0),
    ],
    [
      'Juega al Monopoly: su ficha es el auto y cae en un hotel ajeno que no puede pagar.',
      'Se quedó sin gasolina y no tiene para pagar la habitación.',
      'Un ladrón le robó la billetera dentro del hotel.',
      'El hotel le cobró una multa por estacionar mal.',
    ],
    0,
    'Está jugando Monopoly. Su ficha (el auto) cayó en una casilla con un hotel ajeno y no tiene dinero para pagar el alquiler.',
  ),
  LateralPuzzle(
    'El vaso de agua',
    'Una mujer entra a un bar y pide un vaso de agua. El camarero saca de pronto un arma y le apunta. '
        'Ella dice «gracias» y se va tranquila. ¿Por qué?',
    [
      LateralQuestion('¿Se conocían de antes?', 1),
      LateralQuestion('¿Ella tenía algún problema físico en ese momento?', 0),
      LateralQuestion('¿El camarero quería robarle?', 1),
      LateralQuestion('¿El susto le sirvió a ella?', 0),
      LateralQuestion('¿Tenía sed de verdad?', 1),
      LateralQuestion('¿Tiene que ver con el hipo?', 0),
    ],
    [
      'Tenía hipo y el susto se lo quitó; el camarero lo supo y por eso ya no necesitaba el agua.',
      'Era una actriz ensayando una escena.',
      'El camarero era policía y la protegía.',
      'Ella le pagó con dinero falso y él la dejó ir.',
    ],
    0,
    'La mujer tenía hipo. El camarero notó que pedía agua para quitárselo y pensó que un buen susto serviría mejor. '
        'Funcionó, y por eso ella le dio las gracias.',
  ),
  LateralPuzzle(
    'Solo cinco cumpleaños',
    'María acaba de cumplir 20 años, pero dice que solo ha celebrado 5 cumpleaños en su vida y no está mintiendo. ¿Cómo es posible?',
    [
      LateralQuestion('¿Estuvo enferma o inconsciente varios años?', 1),
      LateralQuestion('¿Tiene que ver con el calendario?', 0),
      LateralQuestion('¿Nació en una fecha especial?', 0),
      LateralQuestion('¿Cambió de país o de planeta?', 1),
      LateralQuestion('¿Su cumpleaños no existe todos los años?', 0),
      LateralQuestion('¿Importa el nombre del mes?', 2),
    ],
    [
      'Nació un 29 de febrero, que solo existe cada 4 años.',
      'Su familia solo celebra los cumpleaños múltiplos de 4.',
      'Perdió varios años de memoria por un accidente.',
      'Cuenta los años de otra forma, en otro calendario.',
    ],
    0,
    'Nació el 29 de febrero. Ese día solo existe en los años bisiestos, es decir cada 4 años: en 20 años solo hay 5 de esos cumpleaños.',
  ),
  LateralPuzzle(
    'La carrera de los caballos',
    'Dos hombres compiten en una carrera de caballos con una regla rara: gana quien llegue ÚLTIMO a la meta. '
        'Los dos avanzan lentísimo, sin decidirse. Un sabio les dice dos palabras y los dos salen a todo galope. ¿Qué les dijo?',
    [
      LateralQuestion('¿El sabio les ofreció dinero?', 1),
      LateralQuestion('¿Tiene que ver con los caballos?', 0),
      LateralQuestion('¿Tuvieron que hacer algo entre ellos?', 0),
      LateralQuestion('¿Cambió la regla de la carrera?', 1),
      LateralQuestion('¿Cada uno quería ahora que perdiera el otro?', 0),
      LateralQuestion('¿Importaba quién era más rápido?', 2),
    ],
    [
      '«Cambien caballos»: ahora cada uno gana si el caballo del otro llega último, así que cada uno corre con el ajeno.',
      '«Corran rápido»: les dio miedo perder el premio.',
      '«Empiecen ya»: la regla dice que quien sale primero gana.',
      '«Sin premio»: al no haber premio ya no les importó.',
    ],
    0,
    'Les dijo «cambien caballos». Como gana quien llega último con el caballo del otro, ahora cada uno quiere que SU propio caballo (el que monta el rival) llegue de último, y para eso cada uno corre a toda velocidad.',
  ),
  LateralPuzzle(
    'Bajo la lluvia sin paraguas',
    'Un hombre sale a la calle con una lluvia muy fuerte, sin paraguas, sin sombrero ni gorra y sin refugiarse. '
        'Se empapa la ropa, pero ni un solo cabello de su cabeza se moja. ¿Cómo?',
    [
      LateralQuestion('¿Se tapó con alguna cosa?', 1),
      LateralQuestion('¿Tiene que ver con su cabeza o su aspecto?', 0),
      LateralQuestion('¿Lleva una peluca o un sombrero oculto?', 1),
      LateralQuestion('¿Estaba bajo un techo?', 1),
      LateralQuestion('¿Es normal que no tenga algo en la cabeza?', 0),
      LateralQuestion('¿Importa el color del cielo?', 2),
    ],
    [
      'Es calvo: no tiene cabellos que mojarse.',
      'La lluvia caía al revés.',
      'Usa un gel que repele el agua.',
      'Corre tan rápido que la lluvia no lo alcanza.',
    ],
    0,
    'Es calvo. No tiene cabellos en la cabeza, así que ninguno puede mojarse.',
  ),
];

// ---------------------------------------------------------------------------
// 5) Acertijos de lógica y matemáticas (opción múltiple, con pista y explicación)
// ---------------------------------------------------------------------------

class RiddleQ {
  final String text;
  final List<String> options;
  final int correct;
  final String hint;
  final String explanation;
  const RiddleQ(this.text, this.options, this.correct, this.hint, this.explanation);
}

const List<RiddleQ> kRiddles = [
  RiddleQ(
    'Un caracol quiere salir de un pozo de 10 metros. De día sube 3 metros y de noche resbala 2. ¿Cuántos días tarda en salir?',
    ['7 días', '8 días', '9 días', '10 días'],
    1,
    'Piensa qué pasa el último día: ¿ese día todavía alcanza a resbalar?',
    'Cada día completo gana 1 metro. Tras 7 días lleva 7 metros; el día 8 sube 3 y llega a 10 antes de que llegue la noche. Son 8 días.',
  ),
  RiddleQ(
    'Si 3 gatos cazan 3 ratones en 3 minutos, ¿cuántos gatos hacen falta para cazar 100 ratones en 100 minutos?',
    ['100 gatos', '33 gatos', '3 gatos', '1 gato'],
    2,
    'Averigua cuántos ratones caza UN gato en 3 minutos.',
    'Cada gato caza 1 ratón cada 3 minutos. En 100 minutos cada gato caza unos 33 ratones, así que con 3 gatos se cazan 100 ratones. Siguen siendo 3 gatos.',
  ),
  RiddleQ(
    'Un bate y una pelota cuestan 1,10 dólares juntos. El bate cuesta 1 dólar MÁS que la pelota. ¿Cuánto cuesta la pelota?',
    ['10 centavos', '5 centavos', '1 centavo', '15 centavos'],
    1,
    'Si la pelota costara 10 centavos, ¿cuánto costaría el bate y cuánto sumarían?',
    'Si la pelota cuesta 5 centavos, el bate cuesta 1,05 y juntos suman 1,10. Con 10 centavos sumarían 1,20.',
  ),
  RiddleQ(
    'Un padre tiene 36 años y su hijo 6. ¿Dentro de cuántos años la edad del padre será el triple de la del hijo?',
    ['6 años', '9 años', '12 años', '3 años'],
    1,
    'Prueba con 9 años: ¿cuánto tendría cada uno?',
    'Dentro de 9 años el padre tendrá 45 y el hijo 15, y 45 es el triple de 15.',
  ),
  RiddleQ(
    'En una reunión hay 10 personas y cada pareja se saluda con un solo apretón de manos. ¿Cuántos apretones hay en total?',
    ['100', '90', '45', '20'],
    2,
    'Cada persona saluda a 9, pero así cada saludo se cuenta dos veces.',
    '10 × 9 = 90 saludos contados dos veces (uno por cada persona), entonces 90 ÷ 2 = 45 apretones.',
  ),
  RiddleQ(
    'Un reloj tarda 6 segundos en dar las 6 campanadas (la primera suena en el segundo 0). ¿Cuánto tarda en dar las 12?',
    ['12 segundos', '13,2 segundos', '11 segundos', '14,4 segundos'],
    1,
    'Cuenta los espacios (silencios) entre campanadas, no las campanadas.',
    'Entre 6 campanadas hay 5 silencios: 6 ÷ 5 = 1,2 segundos cada uno. Entre 12 campanadas hay 11 silencios: 11 × 1,2 = 13,2 segundos.',
  ),
  RiddleQ(
    'Un nenúfar duplica su tamaño cada día. Si tarda 30 días en cubrir todo el lago, ¿cuándo cubre la mitad?',
    ['Día 15', 'Día 20', 'Día 28', 'Día 29'],
    3,
    'Si cada día duplica, ¿cómo estaba el día anterior al último?',
    'El último día duplica y cubre todo el lago, así que el día anterior (el 29) cubría justo la mitad.',
  ),
  RiddleQ(
    '¿Cuántos cuadrados (de cualquier tamaño) hay en un tablero de 3 × 3 cuadritos?',
    ['9', '13', '14', '18'],
    2,
    'Cuenta por tamaños: 1×1, 2×2 y 3×3.',
    '9 cuadritos de 1×1, más 4 de 2×2, más 1 de 3×3: 9 + 4 + 1 = 14.',
  ),
  RiddleQ(
    'Se corta una cuerda de 60 cm en dos partes y una mide el doble que la otra. ¿Cuánto mide la parte más larga?',
    ['30 cm', '35 cm', '40 cm', '45 cm'],
    2,
    'En total son 3 partes iguales: dos para la larga y una para la corta.',
    '60 ÷ 3 = 20 cm es la parte corta, así que la larga mide 40 cm.',
  ),
  RiddleQ(
    'Al lanzar dos dados y sumar los puntos, ¿qué resultado es el más probable?',
    ['6', '7', '8', '12'],
    1,
    'Cuenta de cuántas formas distintas se puede obtener cada suma.',
    'El 7 se logra de 6 formas (1+6, 2+5, 3+4, 4+3, 5+2, 6+1), más que cualquier otra suma.',
  ),
  RiddleQ(
    '¿Cuántas veces aparece el dígito 9 al escribir todos los números del 1 al 100?',
    ['10', '11', '19', '20'],
    3,
    'Cuenta por separado el 9 de las unidades y el 9 de las decenas.',
    'En las unidades: 9, 19, 29… 99 son 10 veces. En las decenas: del 90 al 99 son otras 10 veces. En total 20 (el 99 tiene dos).',
  ),
  RiddleQ(
    'Un granjero tiene 17 ovejas y todas menos 9 se mueren. ¿Cuántas ovejas le quedan?',
    ['8', '9', '17', '0'],
    1,
    'Lee con calma: «todas menos 9»…',
    '«Todas menos 9» significa que sobreviven 9. Le quedan 9 ovejas.',
  ),
  RiddleQ(
    'Miras un retrato y dices: «No tengo hermanos ni hermanas, pero el padre de ese hombre es el hijo de mi padre». ¿Quién está en el retrato?',
    ['Yo mismo', 'Mi hijo', 'Mi padre', 'Mi sobrino'],
    1,
    '«El hijo de mi padre», sin hermanos, solo puedes ser tú.',
    'El hijo de tu padre eres tú (no tienes hermanos). Entonces tú eres el padre del hombre del retrato: es tu hijo.',
  ),
  RiddleQ(
    'Tienes una caja con 3 bolas rojas y 3 azules, y sacas sin mirar. ¿Cuántas bolas debes sacar como mínimo para asegurar que tienes 2 del mismo color?',
    ['2', '3', '4', '5'],
    1,
    'Piensa en el peor caso: ¿qué pasa si las dos primeras son de colores distintos?',
    'Con 2 bolas podrían ser de distinto color, pero con la tercera ya tienes sí o sí dos iguales (solo hay dos colores).',
  ),
  RiddleQ(
    'Hoy es miércoles. ¿Qué día de la semana será dentro de 100 días?',
    ['Jueves', 'Viernes', 'Sábado', 'Domingo'],
    1,
    'Las semanas tienen 7 días: ¿qué sobra al dividir 100 entre 7?',
    '100 = 14 semanas completas (98 días) + 2 días. Dos días después del miércoles es viernes.',
  ),
];
