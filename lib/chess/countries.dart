import 'piece_sizes.dart';

class ChessCountry {
  final String id;
  final String name;
  const ChessCountry(this.id, this.name);

  String asset(int type) => 'assets/chess/${id}_${pieceNames[type]}.png';
  List<int> size(int type) => pieceSizes['${id}_${pieceNames[type]}']!;
}

const pieceNames = ['', 'pawn', 'knight', 'bishop', 'rook', 'queen', 'king'];

const chessCountries = <ChessCountry>[
  ChessCountry('peru', 'Perú'),
  ChessCountry('ecuador', 'Ecuador'),
  ChessCountry('mexico', 'México'),
  ChessCountry('egipto', 'Egipto'),
  ChessCountry('japon', 'Japón'),
  ChessCountry('inglaterra', 'Inglaterra'),
];

ChessCountry countryById(String id) =>
    chessCountries.firstWhere((c) => c.id == id, orElse: () => chessCountries.first);
