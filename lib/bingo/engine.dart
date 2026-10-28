import 'dart:math';

// Bingo de 75 bolas: cartilla de 5x5 con centro libre.
// B 1-15, I 16-30, N 31-45, G 46-60, O 61-75.

const String bingoLetters = 'BINGO';
const int bingoBalls = 75;

String bingoLetter(int n) => bingoLetters[((n - 1) ~/ 15).clamp(0, 4)];

/// 25 números en filas (0 = casilla libre del centro).
List<int> generateBingoCard(Random rng) {
  final card = List<int>.filled(25, 0);
  for (var c = 0; c < 5; c++) {
    final pool = [for (var i = 1; i <= 15; i++) c * 15 + i]..shuffle(rng);
    for (var r = 0; r < 5; r++) {
      card[r * 5 + c] = pool[r];
    }
  }
  card[12] = 0;
  return card;
}

String cardToString(List<int> card) => card.join(',');

List<int> cardFromString(String s) => [for (final x in s.split(',')) int.parse(x)];

List<bool> freshMarks() => List<bool>.generate(25, (i) => i == 12);

String marksToString(List<bool> m) => m.map((b) => b ? '1' : '0').join();

List<bool> marksFromString(String s) {
  final out = [for (var i = 0; i < s.length; i++) s[i] == '1'];
  while (out.length < 25) {
    out.add(false);
  }
  out[12] = true;
  return out;
}

bool cardComplete(List<bool> marks) => marks.every((b) => b);

/// Válido si todos los números de la cartilla ya salieron.
bool validBingo(List<int> card, Set<int> drawn) =>
    card.every((n) => n == 0 || drawn.contains(n));

String money(int cents) => '\$${(cents / 100).toStringAsFixed(2)}';

/// Convierte "0.50", "0,5" o "$1" en centavos. null si no es válido.
int? parseCents(String s) {
  final t = s.replaceAll('\$', '').replaceAll(',', '.').trim();
  final v = double.tryParse(t);
  if (v == null || v < 0 || v > 1000) return null;
  return (v * 100).round();
}
