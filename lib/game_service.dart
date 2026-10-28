import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---- Configuración del juego ----
const allCategories = [
  'Nombre',
  'Apellido',
  'Animal',
  'Fruta o verdura',
  'País o ciudad',
  'Objeto',
  'Profesión',
  'Color',
];
const categoriesPerRound = 6;
const roundSeconds = 90;
const countdownSeconds = 10;
const totalRounds = 5;
const maxPlayers = 8;
const pointsUnique = 100;
const pointsRepeated = 50;
// Letras sin las más difíciles (K, Q, W, X, Y, Z, Ñ, H, J, Ñ)
const letters = 'ABCDEFGILMNOPRSTUV';

String normalize(String s) {
  const from = 'áàäâéèëêíìïîóòöôúùüûñ';
  const to = 'aaaaeeeeiiiioooouuuun';
  var r = s.trim().toLowerCase();
  for (var i = 0; i < from.length; i++) {
    r = r.replaceAll(from[i], to[i]);
  }
  return r.replaceAll(RegExp(r'\s+'), ' ');
}

bool isValidWord(String word, String letter) {
  final w = normalize(word);
  return w.length >= 2 && w.startsWith(letter.toLowerCase());
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

class GameService {
  final db = FirebaseFirestore.instance;
  late final String uid;
  String name = '';

  Future<void> signIn() async {
    final auth = FirebaseAuth.instance;
    if (auth.currentUser == null) await auth.signInAnonymously();
    uid = auth.currentUser!.uid;
  }

  DocumentReference<Map<String, dynamic>> roomRef(String code) =>
      db.collection('rooms').doc(code);
  CollectionReference<Map<String, dynamic>> playersRef(String code) =>
      roomRef(code).collection('players');

  Stream<DocumentSnapshot<Map<String, dynamic>>> roomStream(String code) =>
      roomRef(code).snapshots();
  Stream<QuerySnapshot<Map<String, dynamic>>> playersStream(String code) =>
      playersRef(code).snapshots();

  String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random();
    return List.generate(5, (_) => chars[r.nextInt(chars.length)]).join();
  }

  Map<String, dynamic> _newPlayer() => {
        'name': name,
        'total': 0,
        'roundScore': 0,
        'answers': <String, String>{},
        'finished': false,
        'submitted': false,
        'cheated': false,
        'joinedAt': nowMs(),
      };

  Future<String> createRoom(String playerName) async {
    name = playerName;
    String code;
    do {
      code = _newCode();
    } while ((await roomRef(code).get()).exists);
    await roomRef(code).set({
      'hostId': uid,
      'status': 'lobby',
      'round': 0,
      'totalRounds': totalRounds,
      'letter': '',
      'categories': <String>[],
      'usedLetters': <String>[],
      'roundEndsAt': 0,
      'countdownEndsAt': 0,
      'countdownBy': '',
      'createdAt': nowMs(),
    });
    await playersRef(code).doc(uid).set(_newPlayer());
    return code;
  }

  /// Devuelve null si todo bien, o un mensaje de error.
  Future<String?> joinRoom(String code, String playerName) async {
    name = playerName;
    code = code.trim().toUpperCase();
    final snap = await roomRef(code).get();
    if (!snap.exists) return 'No existe una sala con ese código.';
    final existing = await playersRef(code).doc(uid).get();
    if (existing.exists) return null; // reingreso
    if (snap.data()!['status'] != 'lobby') {
      return 'La partida ya comenzó.';
    }
    final count = (await playersRef(code).get()).size;
    if (count >= maxPlayers) return 'La sala está llena (máx. $maxPlayers).';
    await playersRef(code).doc(uid).set(_newPlayer());
    return null;
  }

  Future<void> startRound(String code, Map<String, dynamic> room) async {
    final used = List<String>.from(room['usedLetters'] ?? []);
    final available =
        letters.split('').where((l) => !used.contains(l)).toList();
    final pool = available.isEmpty ? letters.split('') : available;
    final letter = pool[Random().nextInt(pool.length)];
    final cats = List<String>.from(allCategories)..shuffle();
    final round = (room['round'] as int) + 1;

    final players = await playersRef(code).get();
    final batch = db.batch();
    for (final p in players.docs) {
      batch.update(p.reference, {
        'answers': <String, String>{},
        'finished': false,
        'submitted': false,
        'cheated': false,
        'roundScore': 0,
      });
    }
    batch.update(roomRef(code), {
      'status': 'playing',
      'round': round,
      'letter': letter,
      'categories': cats.take(categoriesPerRound).toList(),
      'usedLetters': FieldValue.arrayUnion([letter]),
      'roundEndsAt': nowMs() + roundSeconds * 1000,
      'countdownEndsAt': 0,
      'countdownBy': '',
    });
    await batch.commit();
  }

  Future<void> saveAnswers(String code, Map<String, String> answers,
      {bool finished = false, bool submitted = false}) {
    return playersRef(code).doc(uid).update({
      'answers': answers,
      'finished': finished,
      if (submitted) 'submitted': true,
    });
  }

  Future<void> markCheated(String code) =>
      playersRef(code).doc(uid).update({'cheated': true});

  /// Inicia el conteo "¡Páreme la mano!". Es idempotente.
  Future<void> triggerCountdown(String code, String by) async {
    await db.runTransaction((tx) async {
      final snap = await tx.get(roomRef(code));
      if (snap.data()?['status'] != 'playing') return;
      tx.update(roomRef(code), {
        'status': 'counting',
        'countdownEndsAt': nowMs() + countdownSeconds * 1000,
        'countdownBy': by,
      });
    });
  }

  /// Calcula puntajes. Solo la primera llamada tiene efecto.
  Future<void> scoreRound(String code) async {
    var mine = false;
    await db.runTransaction((tx) async {
      final snap = await tx.get(roomRef(code));
      if (snap.data()?['status'] != 'counting') return;
      tx.update(roomRef(code), {'status': 'scoring'});
      mine = true;
    });
    if (!mine) return;

    final room = (await roomRef(code).get()).data()!;
    final letter = room['letter'] as String;
    final cats = List<String>.from(room['categories']);
    final players = await playersRef(code).get();

    // Cuenta cuántos jugadores (no tramposos) escribieron cada palabra.
    final counts = <String, Map<String, int>>{};
    for (final cat in cats) {
      counts[cat] = {};
      for (final p in players.docs) {
        final d = p.data();
        if (d['cheated'] == true) continue;
        final ans = Map<String, dynamic>.from(d['answers'] ?? {});
        final w = ans[cat] as String? ?? '';
        if (!isValidWord(w, letter)) continue;
        final key = normalize(w);
        counts[cat]![key] = (counts[cat]![key] ?? 0) + 1;
      }
    }

    final batch = db.batch();
    for (final p in players.docs) {
      final d = p.data();
      var score = 0;
      if (d['cheated'] != true) {
        final ans = Map<String, dynamic>.from(d['answers'] ?? {});
        for (final cat in cats) {
          final w = ans[cat] as String? ?? '';
          if (!isValidWord(w, letter)) continue;
          final n = counts[cat]![normalize(w)] ?? 1;
          score += n == 1 ? pointsUnique : pointsRepeated;
        }
      }
      batch.update(p.reference, {
        'roundScore': score,
        'total': (d['total'] as int? ?? 0) + score,
      });
    }
    final isLast = (room['round'] as int) >= (room['totalRounds'] as int);
    batch.update(roomRef(code), {'status': isLast ? 'finished' : 'results'});
    await batch.commit();
  }
}

final svc = GameService();
