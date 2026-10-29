import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'bingo/bingo_pages.dart';
import 'chess/chess_pages.dart';
import 'cuarenta/cuarenta_page.dart';
import 'galleta/galleta_pages.dart';
import 'parchis/parchis_pages.dart';
import 'game_service.dart';
import 'room_page.dart';
import 'sfx.dart';

// Configuración de Firebase (proyecto "Noche de juegos").
const firebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyBX3CI9jMar84VqDp0dOLvgy5nQJLxyblY',
  appId: '1:193388031430:android:ff899dda0f13aec56d56c7',
  messagingSenderId: '193388031430',
  projectId: 'noche-de-juegos-99b2e',
  storageBucket: 'noche-de-juegos-99b2e.firebasestorage.app',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Si Firebase aún no está configurado, el Cuarenta (sin conexión) igual funciona.
  try {
    await Firebase.initializeApp(options: firebaseOptions);
    await svc.signIn();
  } catch (_) {}
  runApp(const ParemeApp());
}

class ParemeApp extends StatelessWidget {
  const ParemeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Noche de juegos',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepOrange,
        useMaterial3: true,
      ),
      home: const MenuPage(),
    );
  }
}

class MenuPage extends StatelessWidget {
  const MenuPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Noche de Juegos',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: Sfx.enabled,
            builder: (context, on, _) => IconButton(
              tooltip: on ? 'Silenciar sonidos' : 'Activar sonidos',
              icon: Icon(on ? Icons.volume_up : Icons.volume_off),
              onPressed: () {
                Sfx.enabled.value = !on;
                if (!on) Sfx.play('tick');
              },
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const _TitleBanner(),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Text('✋', style: TextStyle(fontSize: 32)),
                title: const Text('Páreme la mano'),
                subtitle: const Text('Multijugador en línea (2 a 8) · 10 rondas'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const HomePage()),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Text('🃏', style: TextStyle(fontSize: 32)),
                title: const Text('Cuarenta'),
                subtitle: const Text('Contra bots o en línea, solo o en parejas'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const CuarentaSetupPage()),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Text('♟️', style: TextStyle(fontSize: 32)),
                title: const Text('Ajedrez de naciones'),
                subtitle: const Text(
                    'Tablero 3D, piezas de cada país · contra la PC o en línea'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ChessMenuPage()),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Text('🍪', style: TextStyle(fontSize: 32)),
                title: const Text('La Galleta'),
                subtitle: const Text(
                    'Timbiriche: une puntos y llena cuadritos · vs PC o en línea'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const GalletaMenuPage()),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Text('🎲', style: TextStyle(fontSize: 32)),
                title: const Text('Parchís'),
                subtitle: const Text(
                    '4 fichas con temáticas · peleas al comer · vs PC o en línea'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ParchisMenuPage()),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Text('🎱', style: TextStyle(fontSize: 32)),
                title: const Text('Bingo'),
                subtitle: const Text(
                    'Bot cantor con voz · cartillas, premio y bolas en vivo · en línea'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const BingoMenuPage()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String? error;
  bool loading = false;

  Future<void> _create() async {
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return setState(() => error = 'Escribe tu nombre.');
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final code = await svc.createRoom(name);
      _open(code);
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
      final err = await svc.joinRoom(code, name);
      if (err != null) {
        setState(() => error = err);
      } else {
        _open(code);
      }
    } catch (e) {
      setState(() => error = 'No se pudo entrar: $e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _open(String code) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => RoomPage(code: code)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                children: [
                  const Text('✋', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 8),
                  Text('¡Páreme la mano!',
                      style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 24),
                  TextField(
                    controller: nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Tu nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: loading ? null : _create,
                    icon: const Icon(Icons.add),
                    label: const Text('Crear sala'),
                  ),
                  const Divider(height: 40),
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
                    onPressed: loading ? null : _join,
                    icon: const Icon(Icons.login),
                    label: const Text('Unirme'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  if (loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: CircularProgressIndicator(),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}


/// Título llamativo de la app: letras con degradado animado, brillo y juegos alrededor.
class _TitleBanner extends StatefulWidget {
  const _TitleBanner();
  @override
  State<_TitleBanner> createState() => _TitleBannerState();
}

class _TitleBannerState extends State<_TitleBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(seconds: 4))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _word(String text, double size, double shift) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (r) => LinearGradient(
        colors: const [
          Color(0xFFFFEB3B),
          Color(0xFFFF9800),
          Color(0xFFFF4081),
          Color(0xFFFFEB3B),
        ],
        stops: const [0.0, 0.35, 0.7, 1.0],
        transform: GradientRotation(_c.value * 6.2832 + shift),
      ).createShader(r),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
          height: 1.0,
          shadows: const [
            Shadow(color: Color(0xFF3E1A00), offset: Offset(0, 4), blurRadius: 0),
            Shadow(color: Color(0xAAFFC107), blurRadius: 18),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final bounce = 1 + 0.04 * sin(_c.value * 6.2832 * 2);
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF1A237E), Color(0xFF6A1B9A), Color(0xFFAD1457)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF9800)
                    .withOpacity(0.35 + 0.25 * sin(_c.value * 6.2832)),
                blurRadius: 22,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Column(
            children: [
              Transform.scale(
                scale: bounce,
                child: const Text('🎲  🃏  ♟️  🍪  🎱',
                    style: TextStyle(fontSize: 26)),
              ),
              const SizedBox(height: 6),
              _word('NOCHE', 46, 0),
              const SizedBox(height: 2),
              _word('DE JUEGOS', 40, 1.5),
              const SizedBox(height: 6),
              const Text('¡Reúne a tu gente y a jugar!',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
      },
    );
  }
}
