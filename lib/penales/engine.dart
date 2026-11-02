import 'dart:math';
import 'teams.dart';

/// Arco dividido en 6 zonas: 2 filas (arriba/abajo) x 3 columnas.
/// zona = fila * 3 + columna (0 = arriba izquierda, 5 = abajo derecha).
const int kZones = 6;
const int kCupTeams = 8;
const List<String> kPhaseNames = ['Cuartos de final', 'Semifinal', 'Final'];

List<int> _il(String s) =>
    s.isEmpty ? <int>[] : [for (final x in s.split(',')) int.parse(x)];
String _si(List<int> l) => l.join(',');

/// Torneo de penales (8 equipos: cuartos, semifinales y final).
/// Cada equipo ocupa un "puesto" (slot 0..7) controlado por una persona o la PC.
class Penales {
  final List<int> teams; // equipo (índice en kTeams) de cada puesto
  final List<String> ctrl; // uid de quien lo controla, o 'bot'
  final List<String> owners; // nombre de la persona (o 'PC')
  List<int> order; // puestos que juegan esta fase, de dos en dos
  int phase;
  int mi; // número de partido dentro de la fase
  List<int> winners;
  List<String> results; // "fase,a,b,golesA,golesB,ganador"
  String stage; // toss, pick, show, mend, tend
  int a, b; // puestos del partido actual
  int first; // 0 patea primero el puesto a, 1 el b (sorteo de la moneda)
  List<int> goals;
  List<int> taken;
  List<List<int>> used;
  List<List<int>> kzHist;
  List<List<int>> shotRes; // 1 gol, 0 fallo, por lado
  int pickKick, pickShooter, pickKeep;
  int lastSide, lastShooter, lastKZ, lastGZ;
  bool lastGoal;
  int matchWinner; // puesto ganador del partido actual (-1 si sigue)
  int champion;
  int seq;
  final Random rng;

  Penales._(this.teams, this.ctrl, this.owners, this.rng)
      : order = [],
        phase = 0,
        mi = 0,
        winners = [],
        results = [],
        stage = 'toss',
        a = 0,
        b = 1,
        first = 0,
        goals = [0, 0],
        taken = [0, 0],
        used = [<int>[], <int>[]],
        kzHist = [<int>[], <int>[]],
        shotRes = [<int>[], <int>[]],
        pickKick = -1,
        pickShooter = -1,
        pickKeep = -1,
        lastSide = 0,
        lastShooter = 0,
        lastKZ = 0,
        lastGZ = 0,
        lastGoal = false,
        matchWinner = -1,
        champion = -1,
        seq = 0;

  factory Penales.create(List<int> teams, List<String> ctrl, List<String> owners,
      {Random? rng}) {
    assert(teams.length == kCupTeams);
    final g = Penales._(teams, ctrl, owners, rng ?? Random());
    g.order = [for (var i = 0; i < kCupTeams; i++) i]..shuffle(g.rng);
    g._nextMatch();
    return g;
  }

  // ---------------------------------------------------------------- consultas

  TeamInfo teamOf(int slot) => kTeams[teams[slot]];
  bool isBot(int slot) => ctrl[slot] == 'bot';
  int slotOf(String uid) => ctrl.indexOf(uid);

  /// Lado (0 = puesto a, 1 = puesto b) que patea ahora.
  int get kickerSide {
    final t = taken[0] + taken[1];
    return t % 2 == 0 ? first : 1 - first;
  }

  int slotOfSide(int side) => side == 0 ? a : b;
  int get kickerSlot => slotOfSide(kickerSide);
  int get keeperSlot => slotOfSide(1 - kickerSide);
  bool get ready => pickKick >= 0 && pickKeep >= 0;
  bool get finished => stage == 'tend';
  String get phaseName => kPhaseNames[phase.clamp(0, 2).toInt()];
  bool get anyHumanAlive {
    for (final s in order) {
      if (!isBot(s) && !_eliminated(s)) return true;
    }
    return false;
  }

  bool isOut(int slot) => _eliminated(slot);

  bool _eliminated(int slot) {
    // Un puesto sigue vivo si juega esta fase y no perdió ya su partido.
    if (!order.contains(slot)) return true;
    for (final r in results) {
      final p = r.split(',');
      if (int.parse(p[0]) != phase) continue;
      final x = int.parse(p[1]), y = int.parse(p[2]), w = int.parse(p[5]);
      if ((x == slot || y == slot) && w != slot) return true;
    }
    return false;
  }

  /// Pateadores libres de un lado (índices en la lista de la camiseta).
  List<int> freeTakers(int side) {
    final t = teamOf(slotOfSide(side)).takers.length;
    final free = [
      for (var i = 0; i < t; i++)
        if (!used[side].contains(i)) i
    ];
    return free.isEmpty ? [for (var i = 0; i < t; i++) i] : free;
  }

  int defaultShooter(int side) => freeTakers(side).first;

  // ---------------------------------------------------------------- partidos

  void _nextMatch() {
    while (true) {
      if (mi * 2 >= order.length) {
        if (order.length == 2) {
          champion = winners.isEmpty ? order[0] : winners[0];
          stage = 'tend';
          return;
        }
        order = List<int>.of(winners);
        winners = [];
        mi = 0;
        phase++;
        continue;
      }
      a = order[mi * 2];
      b = order[mi * 2 + 1];
      goals = [0, 0];
      taken = [0, 0];
      used = [<int>[], <int>[]];
      kzHist = [<int>[], <int>[]];
      shotRes = [<int>[], <int>[]];
      pickKick = pickShooter = pickKeep = -1;
      matchWinner = -1;
      first = rng.nextInt(2); // moneda al aire
      if (isBot(a) && isBot(b)) {
        _simulate();
        _record();
        mi++;
        continue;
      }
      stage = 'toss';
      return;
    }
  }

  void _simulate() {
    var guard = 0;
    while (matchWinner < 0 && guard++ < 200) {
      autoPick(force: true);
      _shoot();
    }
  }

  void _record() {
    results.add('$phase,$a,$b,${goals[0]},${goals[1]},$matchWinner');
    winners.add(matchWinner);
  }

  // ---------------------------------------------------------------- jugadas

  int botKickZone(int slot) {
    final s = teamOf(slot).strength;
    final w = [
      for (var z = 0; z < kZones; z++) (z % 3 == 1) ? 1.0 : 1.0 + 0.4 * s
    ];
    var r = rng.nextDouble() * w.reduce((x, y) => x + y);
    for (var z = 0; z < kZones; z++) {
      r -= w[z];
      if (r <= 0) return z;
    }
    return kZones - 1;
  }

  /// El arquero rival de más ranking "lee" mejor las costumbres del pateador.
  int botKeepZone(int keeperSlot, int kickerSide) {
    final hist = kzHist[kickerSide];
    final p = 0.05 + 0.35 * teamOf(keeperSlot).strength;
    if (hist.length >= 2 && rng.nextDouble() < p) {
      final cnt = List<int>.filled(kZones, 0);
      for (final z in hist) {
        cnt[z]++;
      }
      final mx = cnt.reduce(max);
      final best = [
        for (var z = 0; z < kZones; z++)
          if (cnt[z] == mx) z
      ];
      return best[rng.nextInt(best.length)];
    }
    return rng.nextInt(kZones);
  }

  /// La PC completa sus jugadas. Con [force] también las de personas
  /// (se usa si alguien no elige a tiempo).
  void autoPick({bool force = false}) {
    if (stage != 'pick' && !(force && matchWinner < 0)) return;
    final ks = kickerSide;
    final kSlot = slotOfSide(ks);
    final gSlot = slotOfSide(1 - ks);
    if (pickKick < 0 && (force || isBot(kSlot))) {
      pickKick = botKickZone(kSlot);
      if (pickShooter < 0) pickShooter = defaultShooter(ks);
    }
    if (pickKeep < 0 && (force || isBot(gSlot))) {
      pickKeep = botKeepZone(gSlot, ks);
    }
  }

  bool humanKick(int zone, int shooter) {
    if (stage != 'pick' || pickKick >= 0 || zone < 0 || zone >= kZones) return false;
    final free = freeTakers(kickerSide);
    pickShooter = free.contains(shooter) ? shooter : free.first;
    pickKick = zone;
    return true;
  }

  bool humanKeep(int zone) {
    if (stage != 'pick' || pickKeep >= 0 || zone < 0 || zone >= kZones) return false;
    pickKeep = zone;
    return true;
  }

  /// Si ambos eligieron, patea. Devuelve true si se resolvió el tiro.
  bool resolve() {
    if (stage != 'pick' || !ready) return false;
    _shoot();
    stage = 'show';
    seq++;
    return true;
  }

  void _shoot() {
    final side = kickerSide;
    final goal = pickKick != pickKeep;
    final shooter = pickShooter >= 0 ? pickShooter : defaultShooter(side);
    if (goal) goals[side]++;
    taken[side]++;
    shotRes[side].add(goal ? 1 : 0);
    kzHist[side].add(pickKick);
    used[side].add(shooter);
    if (used[side].length >= teamOf(slotOfSide(side)).takers.length) {
      used[side] = <int>[];
    }
    lastSide = side;
    lastShooter = shooter;
    lastKZ = pickKick;
    lastGZ = pickKeep;
    lastGoal = goal;
    pickKick = pickShooter = pickKeep = -1;
    final w = _decide();
    matchWinner = w == null ? -1 : slotOfSide(w);
  }

  /// Reglas: 5 tiros por equipo, se corta cuando ya no se puede alcanzar,
  /// y después muerte súbita (tanda pareja).
  int? _decide() {
    final ra = max(0, 5 - taken[0]);
    final rb = max(0, 5 - taken[1]);
    if (taken[0] < 5 || taken[1] < 5) {
      if (goals[0] > goals[1] + rb) return 0;
      if (goals[1] > goals[0] + ra) return 1;
      return null;
    }
    if (taken[0] == taken[1] && goals[0] != goals[1]) {
      return goals[0] > goals[1] ? 0 : 1;
    }
    return null;
  }

  /// Avanza la pantalla: moneda -> tiro -> resultado -> fin del partido -> siguiente.
  void advance() {
    switch (stage) {
      case 'toss':
        stage = 'pick';
        break;
      case 'show':
        stage = matchWinner >= 0 ? 'mend' : 'pick';
        break;
      case 'mend':
        _record();
        mi++;
        _nextMatch();
        break;
      default:
        return;
    }
    seq++;
  }

  // ---------------------------------------------------------------- guardado

  Map<String, dynamic> toMap() => {
        'teams': teams,
        'ctrl': ctrl,
        'owners': owners,
        'order': order,
        'phase': phase,
        'mi': mi,
        'winners': winners,
        'results': results,
        'stage': stage,
        'a': a,
        'b': b,
        'first': first,
        'goals': _si(goals),
        'taken': _si(taken),
        'used0': _si(used[0]),
        'used1': _si(used[1]),
        'kz0': _si(kzHist[0]),
        'kz1': _si(kzHist[1]),
        'res0': _si(shotRes[0]),
        'res1': _si(shotRes[1]),
        'pickKick': pickKick,
        'pickShooter': pickShooter,
        'pickKeep': pickKeep,
        'lastSide': lastSide,
        'lastShooter': lastShooter,
        'lastKZ': lastKZ,
        'lastGZ': lastGZ,
        'lastGoal': lastGoal,
        'matchWinner': matchWinner,
        'champion': champion,
        'seq': seq,
      };

  static List<int> _ints(dynamic v) =>
      [for (final x in (v as List)) (x as num).toInt()];

  factory Penales.fromMap(Map<String, dynamic> m) {
    final g = Penales._(
      _ints(m['teams']),
      [for (final x in (m['ctrl'] as List)) x as String],
      [for (final x in (m['owners'] as List)) x as String],
      Random(),
    );
    g.order = _ints(m['order']);
    g.phase = (m['phase'] as num).toInt();
    g.mi = (m['mi'] as num).toInt();
    g.winners = _ints(m['winners']);
    g.results = [for (final x in (m['results'] as List? ?? const [])) x as String];
    g.stage = m['stage'] as String;
    g.a = (m['a'] as num).toInt();
    g.b = (m['b'] as num).toInt();
    g.first = (m['first'] as num).toInt();
    g.goals = _il(m['goals'] as String);
    g.taken = _il(m['taken'] as String);
    g.used = [_il(m['used0'] as String), _il(m['used1'] as String)];
    g.kzHist = [_il(m['kz0'] as String), _il(m['kz1'] as String)];
    g.shotRes = [_il(m['res0'] as String), _il(m['res1'] as String)];
    g.pickKick = (m['pickKick'] as num).toInt();
    g.pickShooter = (m['pickShooter'] as num).toInt();
    g.pickKeep = (m['pickKeep'] as num).toInt();
    g.lastSide = (m['lastSide'] as num).toInt();
    g.lastShooter = (m['lastShooter'] as num).toInt();
    g.lastKZ = (m['lastKZ'] as num).toInt();
    g.lastGZ = (m['lastGZ'] as num).toInt();
    g.lastGoal = m['lastGoal'] == true;
    g.matchWinner = (m['matchWinner'] as num).toInt();
    g.champion = (m['champion'] as num).toInt();
    g.seq = (m['seq'] as num).toInt();
    return g;
  }
}

/// Completa con equipos al azar hasta 8. [chosen] = equipos de las personas.
List<int> fillTeams(List<int> chosen, Random rng) {
  final out = List<int>.of(chosen);
  final rest = [
    for (var i = 0; i < kTeams.length; i++)
      if (!out.contains(i)) i
  ]..shuffle(rng);
  while (out.length < kCupTeams) {
    out.add(rest.removeLast());
  }
  return out;
}
