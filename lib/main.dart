import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'chess/chess_pages.dart';
import 'cuarenta/cuarenta_page.dart';
import 'game_service.dart';
import 'room_page.dart';

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
      appBar: AppBar(title: const Text('Noche de juegos')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
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
