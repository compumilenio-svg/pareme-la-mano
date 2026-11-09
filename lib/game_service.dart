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
const englishCategory = 'Palabra o verbo en inglés';
const categoriesPerRound = 6; // + la categoría fija en inglés
const voteSeconds = 30;
const roundSeconds = 90;
const tombolaMs = 4500; // la tómbola de letras gira antes de empezar a escribir
const countdownSeconds = 10;
const totalRounds = 10;
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

/// Empieza con la letra de la ronda y parece una palabra de verdad
/// (no una serie de letras sin sentido).
bool isValidWord(String word, String letter) {
  final w = normalize(word);
  return w.length >= 2 &&
      w.startsWith(letter.toLowerCase()) &&
      looksLikeWord(word);
}

const _vowels = 'aeiouy';
const _kbRows = ['qwertyuiop', 'asdfghjkl', 'zxcvbnm', 'abcdefghijklmnopqrstuvwxyz'];

/// Filtro contra letras al azar: exige vocales, sin rachas imposibles,
/// sin repeticiones raras ni teclas seguidas del teclado.
bool looksLikeWord(String raw) {
  final w = normalize(raw.replaceAll(RegExp(r"['\-]"), ' '));
  if (w.length < 2) return false;
  if (RegExp(r'[^a-z ]').hasMatch(w)) return false;
  final tokens = w.split(' ').where((t) => t.isNotEmpty).toList();
  if (tokens.isEmpty) return false;
  for (final t in tokens) {
    if (!_tokenOk(t)) return false;
  }
  return true;
}

bool _tokenOk(String t) {
  if (t.length < 2) return false;
  var vowels = 0;
  var cRun = 0, vRun = 0, maxC = 0, maxV = 0;
  for (final ch in t.split('')) {
    if (_vowels.contains(ch)) {
      vowels++;
      vRun++;
      cRun = 0;
    } else {
      cRun++;
      vRun = 0;
    }
    if (cRun > maxC) maxC = cRun;
    if (vRun > maxV) maxV = vRun;
  }
  if (vowels == 0) return false;
  if (t.length >= 5 && vowels * 8 < t.length) return false;
  if (maxC >= 5 || (maxC == 4 && t.length < 7)) return false;
  if (maxV >= 4) return false;
  if (RegExp(r'(.)\1\1').hasMatch(t)) return false;
  for (var i = 0; i + 1 < t.length; i++) {
    if (t[i] == t[i + 1] && !'clrneo'.contains(t[i])) return false;
  }
  if (t.length >= 5 && t.split('').toSet().length <= 2) return false;
  if (t.length >= 6 && RegExp(r'^(.{3,})\1').hasMatch(t)) return false;
  if (RegExp(r'(.{2})\1\1').hasMatch(t)) return false;
  for (final row in _kbRows) {
    final rev = row.split('').reversed.join();
    for (var i = 0; i + 4 <= t.length; i++) {
      final seg = t.substring(i, i + 4);
      if (seg == 'erty') continue; // liberty, property, poverty
      if (row.contains(seg) || rev.contains(seg)) return false;
    }
  }
  return true;
}

int nowMs() => DateTime.now().millisecondsSinceEpoch;

class GameService {
  final db = FirebaseFirestore.instance;
  String uid = '';
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

  String newCode() {
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
        'votes': <String, bool>{},
        'voted': false,
        'rejected': <String>[],
        'joinedAt': nowMs(),
      };

  Future<String> createRoom(String playerName) async {
    name = playerName;
    String code;
    do {
      code = newCode();
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
    if (!snap.exists || snap.data()!['game'] != null) {
      return 'No existe una sala con ese código.';
    }
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

  Future<void> startRound(String code, Map<String, dynamic> roomIn) async {
    // Leo la sala actual: así nunca se repite una letra ni se arranca dos veces.
    final room = (await roomRef(code).get()).data() ?? roomIn;
    if (room['status'] == 'playing' || room['status'] == 'counting') return;
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
        'votes': <String, bool>{},
        'voted': false,
        'rejected': <String>[],
      });
    }
    batch.update(roomRef(code), {
      'status': 'playing',
      'round': round,
      'letter': letter,
      'categories': [...cats.take(categoriesPerRound), englishCategory],
      'usedLetters': FieldValue.arrayUnion([letter]),
      'roundEndsAt': nowMs() + roundSeconds * 1000 + tombolaMs,
      'countdownEndsAt': 0,
      'countdownBy': '',
      'votingEndsAt': 0,
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

  /// Pasa de "conteo" a "votación" (solo la primera llamada tiene efecto).
  Future<void> startVoting(String code) async {
    await db.runTransaction((tx) async {
      final snap = await tx.get(roomRef(code));
      if (snap.data()?['status'] != 'counting') return;
      tx.update(roomRef(code), {
        'status': 'voting',
        'votingEndsAt': 0, // la revisión no tiene tiempo límite
      });
    });
  }

  Future<void> saveVotes(String code, Map<String, bool> votes,
      {bool voted = false}) {
    return playersRef(code).doc(uid).update({'votes': votes, 'voted': voted});
  }

  /// Calcula puntajes. Solo la primera llamada tiene efecto.
  Future<void> scoreRound(String code) async {
    var mine = false;
    await db.runTransaction((tx) async {
      final snap = await tx.get(roomRef(code));
      if (snap.data()?['status'] != 'voting') return;
      tx.update(roomRef(code), {'status': 'scoring'});
      mine = true;
    });
    if (!mine) return;

    final room = (await roomRef(code).get()).data()!;
    final letter = room['letter'] as String;
    final cats = List<String>.from(room['categories']);
    final players = await playersRef(code).get();

    // Una palabra es inválida si la mayoría de los OTROS jugadores la votó inválida.
    bool invalidByVote(String targetId, int catIdx) {
      final voters = players.docs.where((q) => q.id != targetId).toList();
      if (voters.isEmpty) return false;
      var bad = 0;
      for (final q in voters) {
        final v = Map<String, dynamic>.from(q.data()['votes'] ?? {});
        if (v['$targetId|$catIdx'] == true) bad++;
      }
      return bad * 2 > voters.length;
    }

    // Palabra que el filtro automático no reconoce pero la mayoría de los
    // OTROS jugadores marcó como "Está bien" en la revisión.
    bool okByVote(String targetId, int catIdx) {
      final voters = players.docs.where((q) => q.id != targetId).toList();
      if (voters.isEmpty) return false;
      var ok = 0;
      for (final q in voters) {
        final v = Map<String, dynamic>.from(q.data()['votes'] ?? {});
        if (v['$targetId|$catIdx|ok'] == true) ok++;
      }
      return ok * 2 > voters.length;
    }

    bool counts_(Map<String, dynamic> d, String id, int ci, String w) {
      if (d['cheated'] == true) return false;
      final n = normalize(w);
      if (n.length < 2 || !n.startsWith(letter.toLowerCase())) return false;
      if (!looksLikeWord(w) && !okByVote(id, ci)) return false;
      return !invalidByVote(id, ci);
    }

    // Cuenta cuántos jugadores escribieron cada palabra válida.
    final counts = <String, Map<String, int>>{};
    for (var ci = 0; ci < cats.length; ci++) {
      final cat = cats[ci];
      counts[cat] = {};
      for (final p in players.docs) {
        final d = p.data();
        final ans = Map<String, dynamic>.from(d['answers'] ?? {});
        final w = ans[cat] as String? ?? '';
        if (!counts_(d, p.id, ci, w)) continue;
        final key = normalize(w);
        counts[cat]![key] = (counts[cat]![key] ?? 0) + 1;
      }
    }

    final batch = db.batch();
    for (final p in players.docs) {
      final d = p.data();
      var score = 0;
      final rejected = <String>[];
      final ans = Map<String, dynamic>.from(d['answers'] ?? {});
      for (var ci = 0; ci < cats.length; ci++) {
        final cat = cats[ci];
        final w = ans[cat] as String? ?? '';
        if (w.isEmpty || d['cheated'] == true) continue;
        if (!counts_(d, p.id, ci, w)) {
          rejected.add('$cat: $w');
          continue;
        }
        final n = counts[cat]![normalize(w)] ?? 1;
        score += n == 1 ? pointsUnique : pointsRepeated;
      }
      batch.update(p.reference, {
        'roundScore': score,
        'rejected': rejected,
        'total': (d['total'] as int? ?? 0) + score,
      });
    }
    final isLast = (room['round'] as int) >= (room['totalRounds'] as int);
    batch.update(roomRef(code), {'status': isLast ? 'finished' : 'results'});
    await batch.commit();
  }
}

final svc = GameService();
