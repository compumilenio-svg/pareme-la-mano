// Pruebas del motor del Bingo (se ejecutan en la compilación en la nube).
import 'dart:math';
import '../lib/bingo/engine.dart';

void expect(bool c, String msg) {
  if (!c) throw StateError('FALLÓ: $msg');
}

void main() {
  final rng = Random(3);
  for (var k = 0; k < 200; k++) {
    final card = generateBingoCard(rng);
    expect(card.length == 25, 'tamaño');
    expect(card[12] == 0, 'centro libre');
    final nums = card.where((n) => n != 0).toList();
    expect(nums.toSet().length == 24, 'números repetidos');
    for (var i = 0; i < 25; i++) {
      if (i == 12) continue;
      final col = i % 5;
      expect(card[i] > col * 15 && card[i] <= col * 15 + 15, 'columna $col fuera de rango');
    }
    expect(cardFromString(cardToString(card)).join() == card.join(), 'ida y vuelta');
  }
  expect(bingoLetter(1) == 'B' && bingoLetter(15) == 'B', 'B');
  expect(bingoLetter(16) == 'I' && bingoLetter(45) == 'N' && bingoLetter(75) == 'O', 'letras');
  final card = generateBingoCard(rng);
  final marks = freshMarks();
  expect(!cardComplete(marks), 'cartilla vacía no está completa');
  for (var i = 0; i < 25; i++) {
    marks[i] = true;
  }
  expect(cardComplete(marks), 'cartilla llena');
  expect(marksFromString(marksToString(marks)).every((b) => b), 'marcas ida y vuelta');
  final drawn = card.where((n) => n != 0).toSet();
  expect(validBingo(card, drawn), 'bingo válido');
  drawn.remove(card[0]);
  expect(!validBingo(card, drawn), 'bingo inválido');
  expect(parseCents('0.50') == 50 && parseCents('\$1') == 100 && parseCents('0,5') == 50, 'dinero');
  expect(parseCents('abc') == null, 'dinero inválido');
  expect(money(50) == '\$0.50', 'formato');
  print('Todas las pruebas del Bingo pasaron');
}
