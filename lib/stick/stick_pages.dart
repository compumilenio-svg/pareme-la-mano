// Pantallas de "Monigote de combate": menú, armería y el juego.
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../music.dart';
import '../sfx.dart';
import 'engine.dart';
import 'stick_art.dart';

/// Progreso guardado en el dispositivo (monedas, récord, armas y mejoras).
class StickSave {
  int coins = 0;
  int best = 0;
  List<String> owned = ['palo'];
  String weapon = 'palo';
  int dmgLvl = 0;
  int hpLvl = 0;
  int spdLvl = 0;
  static const int maxLvl = 10;

  static Future<StickSave> load() async {
    final s = StickSave();
    try {
      final sp = await SharedPreferences.getInstance();
      s.coins = sp.getInt('st_coins') ?? 0;
      s.best = sp.getInt('st_best') ?? 0;
      s.owned = sp.getStringList('st_owned') ?? ['palo'];
      s.weapon = sp.getString('st_weapon') ?? 'palo';
      s.dmgLvl = sp.getInt('st_dmg') ?? 0;
      s.hpLvl = sp.getInt('st_hp') ?? 0;
      s.spdLvl = sp.getInt('st_spd') ?? 0;
    } catch (_) {}
    if (!s.owned.contains('palo')) s.owned.add('palo');
    if (!s.owned.contains(s.weapon)) s.weapon = 'palo';
    return s;
  }

  Future<void> save() async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt('st_coins', coins);
      await sp.setInt('st_best', best);
      await sp.setStringList('st_owned', owned);
      await sp.setString('st_weapon', weapon);
      await sp.setInt('st_dmg', dmgLvl);
      await sp.setInt('st_hp', hpLvl);
      await sp.setInt('st_spd', spdLvl);
    } catch (_) {}
  }

  StickStats stats() => StickStats(
        maxHp: 100.0 + 15.0 * hpLvl,
        dmgMul: 1.0 + 0.12 * dmgLvl,
        speedMul: 1.0 + 0.05 * spdLvl,
        weapon: weaponById(weapon),
      );

  static int upgradeCost(int lvl) => (40 * pow(1.45, lvl)).round();
}

// ============================================================ MENÚ
class StickMenuPage extends StatefulWidget {
  const StickMenuPage({super.key});

  @override
  State<StickMenuPage> createState() => _StickMenuPageState();
}

class _StickMenuPageState extends State<StickMenuPage> with SingleTickerProviderStateMixin {
  late final AnimationController _anim =
      AnimationController(vsync: this, duration: const Duration(seconds: 10))..repeat();
  StickSave? sv;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await StickSave.load();
    if (mounted) setState(() => sv = s);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _howTo() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cómo se juega'),
        content: const SingleChildScrollView(
          child: Text(
            'Sobrevive a oleadas de enemigos y vence al jefe cada 5 oleadas.\n\n'
            '◀ ▶  Avanzar y retroceder\n'
            '▲  Saltar (esquiva piedras bajas y golpes)\n'
            '▼  Agacharte (esquiva piedras altas y reduce el daño)\n'
            '⚔  Golpear con tu arma. Tres golpes seguidos hacen un combo muy fuerte. '
            'Agachado das un barrido que tumba; en el aire, un golpe más potente.\n\n'
            'Con un golpe puedes desviar las piedras que lanzan.\n'
            'Los perros corren hacia ti: si muerden a la pierna ¡SALTA!, si se lanzan hacia arriba ¡AGÁCHATE!\n'
            'Cada 3 oleadas llegan murciélagos: vuelan alto y caen en picado, ¡AGÁCHATE! o salta para golpearlos en el aire.\n'
            'Cuando un lanzador prepare la piedra verás si debes AGACHARTE o SALTAR.\n'
            'El jefe avisa su carga: esquívala y golpéalo cuando quede cansado.\n\n'
            'Con las monedas compras armas y mejoras en la Armería.\n\n'
            'En computador: flechas o A/D para moverte, W/espacio saltar, S agacharte, '
            'J o Z para golpear.',
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = sv;
    return Scaffold(
      appBar: AppBar(title: const Text('Monigote de combate'), actions: const [MusicButton()]),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 200,
                width: double.infinity,
                child: CustomPaint(
                  painter: StickPreviewPainter(_anim, weaponById(s?.weapon ?? 'palo')),
                ),
              ),
            ),
            const SizedBox(height: 14),
            if (s != null)
              Text('Récord: oleada ${s.best}   ·   Monedas: ${s.coins} 🪙',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: s == null
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => StickGamePage(save: s)));
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.sports_martial_arts),
              label: const Padding(padding: EdgeInsets.all(10), child: Text('¡A pelear!', style: TextStyle(fontSize: 18))),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: s == null
                  ? null
                  : () async {
                      await Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => StickShopPage(save: s)));
                      if (mounted) setState(() {});
                    },
              icon: const Icon(Icons.storefront),
              label: const Padding(padding: EdgeInsets.all(8), child: Text('Armería (armas y mejoras)')),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _howTo,
              icon: const Icon(Icons.help_outline),
              label: const Text('Cómo se juega'),
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================================== ARMERÍA
class StickShopPage extends StatefulWidget {
  final StickSave save;
  const StickShopPage({super.key, required this.save});

  @override
  State<StickShopPage> createState() => _StickShopPageState();
}

class _StickShopPageState extends State<StickShopPage> {
  StickSave get sv => widget.save;

  void _buyWeapon(WeaponDef w) {
    if (sv.owned.contains(w.id) || sv.coins < w.price) return;
    setState(() {
      sv.coins -= w.price;
      sv.owned.add(w.id);
      sv.weapon = w.id;
    });
    sv.save();
    Sfx.play('coin');
  }

  void _upgrade(int which) {
    final lvl = which == 0 ? sv.dmgLvl : (which == 1 ? sv.hpLvl : sv.spdLvl);
    if (lvl >= StickSave.maxLvl) return;
    final cost = StickSave.upgradeCost(lvl);
    if (sv.coins < cost) return;
    setState(() {
      sv.coins -= cost;
      if (which == 0) sv.dmgLvl++;
      if (which == 1) sv.hpLvl++;
      if (which == 2) sv.spdLvl++;
    });
    sv.save();
    Sfx.play('bonus');
  }

  Widget _up(int which, String name, String desc, int lvl) {
    final maxed = lvl >= StickSave.maxLvl;
    final cost = StickSave.upgradeCost(lvl);
    return Card(
      child: ListTile(
        title: Text('$name  (nivel $lvl/${StickSave.maxLvl})'),
        subtitle: Text(desc),
        trailing: maxed
            ? const Text('MÁX')
            : FilledButton(
                onPressed: sv.coins >= cost ? () => _upgrade(which) : null,
                child: Text('$cost 🪙'),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Armería')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Center(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('Monedas: ${sv.coins} 🪙',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 8, 4, 4),
              child: Text('Armas', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            for (final w in kWeapons)
              Card(
                child: ListTile(
                  title: Text(w.name),
                  subtitle: Text('${w.desc}\nDaño ${w.dmg.round()} · Alcance ${w.reach.round()} · '
                      'Golpe ${(w.swing * 1000).round()} ms'),
                  isThreeLine: true,
                  trailing: sv.weapon == w.id
                      ? const Text('Equipada ✓')
                      : sv.owned.contains(w.id)
                          ? OutlinedButton(
                              onPressed: () {
                                setState(() => sv.weapon = w.id);
                                sv.save();
                              },
                              child: const Text('Equipar'))
                          : FilledButton(
                              onPressed: sv.coins >= w.price ? () => _buyWeapon(w) : null,
                              child: Text('${w.price} 🪙')),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 12, 4, 4),
              child: Text('Mejoras', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
            _up(0, 'Fuerza', '+12 % de daño por nivel', sv.dmgLvl),
            _up(1, 'Vida', '+15 de vida máxima por nivel', sv.hpLvl),
            _up(2, 'Agilidad', '+5 % de velocidad por nivel', sv.spdLvl),
          ],
        ),
      ),
    );
  }
}

// ============================================================ JUEGO
class StickGamePage extends StatefulWidget {
  final StickSave save;
  const StickGamePage({super.key, required this.save});

  @override
  State<StickGamePage> createState() => _StickGamePageState();
}

class _StickGamePageState extends State<StickGamePage> with SingleTickerProviderStateMixin {
  late StickWorld world;
  final StickFx fx = StickFx();
  final StickInput input = StickInput();
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier<int>(0);
  final FocusNode _focus = FocusNode();
  Duration _last = Duration.zero;
  Phase _shown = Phase.between;
  bool _paused = false;
  int _banked = 0;
  int _seed = DateTime.now().millisecondsSinceEpoch & 0xFFFF;
  final Map<String, int> _lastSfx = {};
  // entrada táctil y de teclado
  bool tl = false, tr = false, tc = false;
  bool kl = false, kr = false, kc = false;
  bool jumpReq = false, atkReq = false;

  StickSave get sv => widget.save;

  @override
  void initState() {
    super.initState();
    world = StickWorld(sv.stats(), seed: _seed);
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]).catchError((Object _) {});
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _repaint.dispose();
    SystemChrome.setPreferredOrientations(DeviceOrientation.values).catchError((Object _) {});
    super.dispose();
  }

  void _restart() {
    _seed++;
    world = StickWorld(sv.stats(), seed: _seed);
    _banked = 0;
    _shown = Phase.between;
    _paused = false;
    tl = tr = tc = kl = kr = kc = false;
    jumpReq = atkReq = false;
    setState(() {});
  }

  void _tick(Duration el) {
    var dt = (el - _last).inMicroseconds / 1e6;
    _last = el;
    if (dt <= 0) return;
    if (dt > 0.05) dt = 0.05;
    if (_paused) return;
    input.left = tl || kl;
    input.right = tr || kr;
    input.crouch = tc || kc;
    if (jumpReq) {
      input.jump = true;
      jumpReq = false;
    }
    if (atkReq) {
      input.attack = true;
      atkReq = false;
    }
    world.step(dt, input);
    input.clearEdges();
    _consume();
    fx.update(dt);
    _repaint.value++;
    if (world.phase != _shown) {
      final prev = _shown;
      _shown = world.phase;
      if (_shown == Phase.over) {
        _bank();
      } else if (_shown == Phase.between && prev == Phase.playing && world.wave > 0) {
        fx.showBanner('¡Oleada ${world.wave} superada!');
      }
      setState(() {});
    }
  }

  void _sfx(String name) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - (_lastSfx[name] ?? 0) < 90) return;
    _lastSfx[name] = now;
    Sfx.play(name);
  }

  void _consume() {
    for (final ev in world.events) {
      switch (ev.type) {
        case Ev.hit:
          fx.burst(ev.x, ev.y, const Color(0xFFFFE082), 6);
          fx.floater('${ev.v}', ev.x, ev.y - 10, Colors.white);
          _sfx('sword_hit');
          break;
        case Ev.bigHit:
          fx.burst(ev.x, ev.y, const Color(0xFFFFAB40), 14, speed: 170);
          fx.floater('${ev.v}!', ev.x, ev.y - 12, const Color(0xFFFFAB40));
          fx.shake = 0.7;
          _sfx('kick');
          break;
        case Ev.hurt:
          fx.burst(ev.x, ev.y, const Color(0xFFEF5350), 10);
          fx.floater('-${ev.v}', ev.x, ev.y - 14, const Color(0xFFEF5350));
          fx.shake = 0.9;
          _sfx('sword_clash');
          HapticFeedback.mediumImpact();
          break;
        case Ev.kill:
          fx.burst(ev.x, ev.y, const Color(0xFFFFFFFF), 10, speed: 150);
          if (ev.v == EKind.boss.index) {
            fx.shake = 1.0;
            _sfx('bonus');
          }
          break;
        case Ev.coin:
          fx.floater('+${ev.v}🪙', ev.x, ev.y, Colors.amberAccent);
          _sfx('coin');
          break;
        case Ev.parry:
          fx.burst(ev.x, ev.y, const Color(0xFF80DEEA), 8);
          _sfx('sword_clash');
          break;
        case Ev.wave:
          fx.showBanner('OLEADA ${ev.v}');
          _sfx('round_start');
          break;
        case Ev.boss:
          fx.showBanner('¡JEFE!');
          break;
        case Ev.over:
          _sfx('lose');
          break;
        case Ev.swing:
        case Ev.jump:
        case Ev.rock:
          break;
      }
    }
    world.events.clear();
  }

  void _bank() {
    final delta = world.coins - _banked;
    _banked = world.coins;
    sv.coins += delta;
    if (world.wave > sv.best) sv.best = world.wave;
    sv.save();
  }

  void _revive() {
    if (world.revived || sv.coins < 50) return;
    sv.coins -= 50;
    sv.save();
    world.revive();
    _shown = Phase.playing;
    setState(() {});
  }

  // -------------------------------------------------------------- entrada
  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    final k = e.logicalKey;
    final down = e is KeyDownEvent || e is KeyRepeatEvent;
    final up = e is KeyUpEvent;
    if (k == LogicalKeyboardKey.arrowLeft || k == LogicalKeyboardKey.keyA) {
      if (down) kl = true;
      if (up) kl = false;
    } else if (k == LogicalKeyboardKey.arrowRight || k == LogicalKeyboardKey.keyD) {
      if (down) kr = true;
      if (up) kr = false;
    } else if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.keyS) {
      if (down) kc = true;
      if (up) kc = false;
    } else if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.keyW || k == LogicalKeyboardKey.space) {
      if (e is KeyDownEvent) jumpReq = true;
    } else if (k == LogicalKeyboardKey.keyJ ||
        k == LogicalKeyboardKey.keyZ ||
        k == LogicalKeyboardKey.keyX ||
        k == LogicalKeyboardKey.keyK ||
        k == LogicalKeyboardKey.enter) {
      if (down) atkReq = true;
    } else if (k == LogicalKeyboardKey.escape || k == LogicalKeyboardKey.keyP) {
      if (e is KeyDownEvent) setState(() => _paused = !_paused);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _round(IconData icon, double size, Color color, void Function(bool) change, {String? label}) {
    return Listener(
      onPointerDown: (_) => change(true),
      onPointerUp: (_) => change(false),
      onPointerCancel: (_) => change(false),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.38),
          border: Border.all(color: color.withOpacity(0.9), width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }

  Widget _movePad(double h) {
    final w = h * 2.3;
    void upd(Offset p, bool down) {
      if (!down) {
        tl = false;
        tr = false;
        return;
      }
      tl = p.dx < w / 2;
      tr = !tl;
    }

    return Listener(
      onPointerDown: (e) => upd(e.localPosition, true),
      onPointerMove: (e) => upd(e.localPosition, true),
      onPointerUp: (_) => upd(Offset.zero, false),
      onPointerCancel: (_) => upd(Offset.zero, false),
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(h / 2),
          color: Colors.white.withOpacity(0.14),
          border: Border.all(color: Colors.white54, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Icon(Icons.arrow_left, color: Colors.white, size: h * 0.8),
            Icon(Icons.arrow_right, color: Colors.white, size: h * 0.8),
          ],
        ),
      ),
    );
  }

  Widget _actions(double unit) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _round(Icons.keyboard_arrow_up, unit * 0.95, Colors.lightBlueAccent, (d) {
              if (d) jumpReq = true;
            }),
            SizedBox(height: unit * 0.18),
            _round(Icons.keyboard_arrow_down, unit * 0.95, Colors.tealAccent, (d) => tc = d),
          ],
        ),
        SizedBox(width: unit * 0.2),
        _round(Icons.sports_martial_arts, unit * 1.45, Colors.redAccent, (d) {
          if (d) atkReq = true;
        }),
      ],
    );
  }

  Widget _gameBox() {
    return AspectRatio(
      aspectRatio: kW / kH,
      child: CustomPaint(
        painter: StickPainter(world, fx, 0, _repaint),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _overlay() {
    if (_paused) {
      return _card('Pausa', [
        FilledButton(onPressed: () => setState(() => _paused = false), child: const Text('Continuar')),
        OutlinedButton(onPressed: _restart, child: const Text('Reiniciar')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Salir')),
      ]);
    }
    if (world.phase == Phase.over) {
      return _card('¡Derrotado!', [
        Text('Oleada alcanzada: ${world.wave}   ·   Bajas: ${world.kills}\n'
            'Monedas ganadas: +${world.coins} 🪙   ·   Récord: ${sv.best}',
            textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
        FilledButton(onPressed: _restart, child: const Text('Reintentar')),
        if (!world.revived)
          OutlinedButton(
            onPressed: sv.coins >= 50 ? _revive : null,
            child: Text('Revivir (50 🪙)  ·  tienes ${sv.coins}'),
          ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Salir')),
      ]);
    }
    return const SizedBox.shrink();
  }

  Widget _card(String title, List<Widget> kids) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 330),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.black.withOpacity(0.82), borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            for (final k in kids) Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: k),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: SafeArea(
          child: LayoutBuilder(builder: (context, cs) {
            final land = cs.maxWidth > cs.maxHeight;
            final unit = land ? min(64.0, cs.maxHeight * 0.17) : 62.0;
            final pause = Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                color: Colors.white70,
                icon: const Icon(Icons.pause_circle_outline),
                onPressed: () => setState(() => _paused = true),
              ),
            );
            final back = Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                color: Colors.white70,
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
            );
            if (land) {
              return Stack(
                children: [
                  Center(child: _gameBox()),
                  Positioned(left: 16, bottom: 12, child: _movePad(unit * 1.05)),
                  Positioned(right: 16, bottom: 12, child: _actions(unit)),
                  pause,
                  back,
                  _overlay(),
                ],
              );
            }
            return Stack(
              children: [
                Column(
                  children: [
                    _gameBox(),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [_movePad(unit), _actions(unit)],
                        ),
                      ),
                    ),
                  ],
                ),
                pause,
                back,
                _overlay(),
              ],
            );
          }),
        ),
      ),
    );
  }
}
