// Datos de los 16 equipos de la Copa (nombres de clubes y jugadores como datos
// públicos; SIN escudos, logos ni patrocinadores). Camisetas dibujadas por código
// con los colores del club: son aproximaciones, no el diseño oficial.

class TeamInfo {
  final String key;
  final String name;
  final String country;
  final String flag;
  final int rank; // ranking Conmebol de clubes 2026 (1 = mejor)
  final bool rankKnown;
  final int primary;
  final int secondary;
  final int sleeve;
  final int shorts;
  final int socks;
  final int pattern; // ver KitSpec en art.dart
  final String gk;
  final List<String> takers; // 11 pateadores
  final String barra; // estilo de hinchada: sur, samba, andino
  const TeamInfo({
    required this.key,
    required this.name,
    required this.country,
    required this.flag,
    required this.rank,
    this.rankKnown = true,
    required this.primary,
    required this.secondary,
    required this.sleeve,
    required this.shorts,
    required this.socks,
    required this.pattern,
    required this.gk,
    required this.takers,
    required this.barra,
  });

  /// 0 (más fácil) a 1 (más difícil), según el ranking.
  double get strength => ((36 - rank) / 35).clamp(0.0, 1.0).toDouble();
}

const int kPatSolid = 0;
const int kPatStripes = 1;
const int kPatHoops = 2;
const int kPatHalves = 3;
const int kPatSash = 4;
const int kPatChest = 5;
const int kPatCenter = 6;
const int kPatTri = 7;

const List<TeamInfo> kTeams = [
  TeamInfo(
    key: 'ldu', name: 'Liga de Quito', country: 'Ecuador', flag: '🇪🇨', rank: 10,
    primary: 0xFFFFFFFF, secondary: 0xFF1B3A8C, sleeve: 0xFF1B3A8C,
    shorts: 0xFFFFFFFF, socks: 0xFFFFFFFF, pattern: kPatSolid, barra: 'andino',
    gk: 'A. Domínguez',
    takers: ['Deyverson', 'J. Corozo', 'K. Pineda', 'Y. Quiñónez', 'M. Estrada',
      'A. Tobar', 'J. Pretell', 'P. Ortiz', 'E. Castillo', 'M. Weigandt', 'R. Adé'],
  ),
  TeamInfo(
    key: 'bsc', name: 'Barcelona SC', country: 'Ecuador', flag: '🇪🇨', rank: 28,
    primary: 0xFFF2C500, secondary: 0xFF111111, sleeve: 0xFFF2C500,
    shorts: 0xFF111111, socks: 0xFFF2C500, pattern: kPatSolid, barra: 'andino',
    gk: 'G. Cevallos',
    takers: ['D. Benedetto', 'K. Caicedo', 'L. Cano', 'J. Perlaza', 'T. Martínez',
      'J. Báez', 'J. Medina', 'Á. Rangel', 'E. Esterilla', 'H. Villalba', 'J. Intriago'],
  ),
  TeamInfo(
    key: 'idv', name: 'Independiente del Valle', country: 'Ecuador', flag: '🇪🇨', rank: 16,
    primary: 0xFF151515, secondary: 0xFF1E88E5, sleeve: 0xFF151515,
    shorts: 0xFF151515, socks: 0xFF151515, pattern: kPatCenter, barra: 'andino',
    gk: 'A. Quintana',
    takers: ['J. Sornoza', 'J. Cazares', 'D. Reasco', 'E. Pata', 'S. Góngora',
      'J. Arroyo', 'R. Schunke', 'J. Carabalí', 'J. Viacava', 'A. Rodríguez', 'M. Perelló'],
  ),
  TeamInfo(
    key: 'bol', name: 'Bolívar', country: 'Bolivia', flag: '🇧🇴', rank: 23,
    primary: 0xFF4FA8E8, secondary: 0xFFFFFFFF, sleeve: 0xFF4FA8E8,
    shorts: 0xFFFFFFFF, socks: 0xFF4FA8E8, pattern: kPatSolid, barra: 'andino',
    gk: 'Arquero',
    takers: ['X. Arreaga', 'C. Alemán', 'Jugador 3', 'Jugador 4', 'Jugador 5',
      'Jugador 6', 'Jugador 7', 'Jugador 8', 'Jugador 9', 'Jugador 10', 'Jugador 11'],
  ),
  TeamInfo(
    key: 'boc', name: 'Boca Juniors', country: 'Argentina', flag: '🇦🇷', rank: 4,
    primary: 0xFF0B2E6B, secondary: 0xFFF6C500, sleeve: 0xFF0B2E6B,
    shorts: 0xFF0B2E6B, socks: 0xFF0B2E6B, pattern: kPatChest, barra: 'sur',
    gk: 'A. Marchesín',
    takers: ['M. Merentiel', 'L. Paredes', 'M. Giménez', 'E. Valencia', 'C. Palacios',
      'A. Velasco', 'R. Battaglia', 'L. Blanco', 'N. Figal', 'A. Costa', 'S. Ascacíbar'],
  ),
  TeamInfo(
    key: 'riv', name: 'River Plate', country: 'Argentina', flag: '🇦🇷', rank: 3,
    primary: 0xFFFFFFFF, secondary: 0xFFD0021B, sleeve: 0xFFFFFFFF,
    shorts: 0xFF111111, socks: 0xFFFFFFFF, pattern: kPatSash, barra: 'sur',
    gk: 'E. Centurión',
    takers: ['S. Driussi', 'R. Borré', 'Á. Correa', 'T. Almada', 'M. Acuña',
      'N. Otamendi', 'L. Martínez Quarta', 'M. Arambarri', 'G. Montiel', 'A. Moreno', 'J. Meza'],
  ),
  TeamInfo(
    key: 'est', name: 'Estudiantes de La Plata', country: 'Argentina', flag: '🇦🇷', rank: 18,
    primary: 0xFFD0021B, secondary: 0xFFFFFFFF, sleeve: 0xFFD0021B,
    shorts: 0xFF111111, socks: 0xFFD0021B, pattern: kPatStripes, barra: 'sur',
    gk: 'F. Muslera',
    takers: ['L. Alario', 'E. Cetré', 'J. Correa', 'J. Soler', 'B. Aguirre',
      'Jalil Elías', 'E. Piovi', 'M. Rojo', 'R. Funes Mori', 'M. Desábato', 'L. González Pírez'],
  ),
  TeamInfo(
    key: 'fla', name: 'Flamengo', country: 'Brasil', flag: '🇧🇷', rank: 2,
    primary: 0xFFD0021B, secondary: 0xFF111111, sleeve: 0xFFD0021B,
    shorts: 0xFFFFFFFF, socks: 0xFF111111, pattern: kPatHoops, barra: 'samba',
    gk: 'A. Rossi',
    takers: ['Pedro', 'Bruno Henrique', 'G. de Arrascaeta', 'Lucas Paquetá', 'Samuel Lino',
      'Luiz Araújo', 'Jorginho', 'Saúl', 'Léo Pereira', 'Danilo', 'Alex Sandro'],
  ),
  TeamInfo(
    key: 'pal', name: 'Palmeiras', country: 'Brasil', flag: '🇧🇷', rank: 1,
    primary: 0xFF0B7A3B, secondary: 0xFFFFFFFF, sleeve: 0xFF0B7A3B,
    shorts: 0xFFFFFFFF, socks: 0xFF0B7A3B, pattern: kPatSolid, barra: 'samba',
    gk: 'Carlos Miguel',
    takers: ['Vitor Roque', 'Felipe Anderson', 'J. Arias', 'J. López', 'Paulinho',
      'Andreas Pereira', 'Marlon Freitas', 'Murilo', 'J. Piquerez', 'Khellven', 'R. Sosa'],
  ),
  TeamInfo(
    key: 'flu', name: 'Fluminense', country: 'Brasil', flag: '🇧🇷', rank: 11,
    primary: 0xFF7A1B2E, secondary: 0xFF0B7A3B, sleeve: 0xFF7A1B2E,
    shorts: 0xFFFFFFFF, socks: 0xFFFFFFFF, pattern: kPatTri, barra: 'samba',
    gk: 'Fábio',
    takers: ['Hulk', 'Y. Soteldo', 'J. Savarino', 'Ganso', 'G. Cano',
      'A. Canobbio', 'Thiago Silva', 'G. Arana', 'Martinelli', 'Otávio', 'Renê'],
  ),
  TeamInfo(
    key: 'spa', name: 'São Paulo', country: 'Brasil', flag: '🇧🇷', rank: 7,
    primary: 0xFFFFFFFF, secondary: 0xFFD0021B, sleeve: 0xFFFFFFFF,
    shorts: 0xFFFFFFFF, socks: 0xFFFFFFFF, pattern: kPatChest, barra: 'samba',
    gk: 'Rafael',
    takers: ['J. Calleri', 'Lucas Moura', 'Luciano', 'André Silva', 'Cauly',
      'Wendell', 'R. Tolói', 'Pablo Maia', 'Marcos Antônio', 'Artur', 'Victor Sá'],
  ),
  TeamInfo(
    key: 'cor', name: 'Corinthians', country: 'Brasil', flag: '🇧🇷', rank: 22,
    primary: 0xFFFFFFFF, secondary: 0xFF111111, sleeve: 0xFFFFFFFF,
    shorts: 0xFF111111, socks: 0xFFFFFFFF, pattern: kPatSolid, barra: 'samba',
    gk: 'Hugo Souza',
    takers: ['Yuri Alberto', 'M. Depay', 'J. Lingard', 'R. Garro', 'Raniele',
      'Matheus Bidu', 'Matheuzinho', 'A. Ramalho', 'G. Henrique', 'Breno Bidon', 'A. Carrillo'],
  ),
  TeamInfo(
    key: 'uch', name: 'U. de Chile', country: 'Chile', flag: '🇨🇱', rank: 35, rankKnown: false,
    primary: 0xFF1E3E8F, secondary: 0xFFD0021B, sleeve: 0xFF1E3E8F,
    shorts: 0xFF1E3E8F, socks: 0xFF1E3E8F, pattern: kPatSolid, barra: 'sur',
    gk: 'G. Castellón',
    takers: ['C. Aránguiz', 'A. Arce', 'M. Guerrero', 'E. Vargas', 'J. Lucero',
      'I. Vásquez', 'M. Zaldivia', 'I. Lichnovsky', 'M. Díaz', 'M. Riquelme', 'N. Fernández'],
  ),
  TeamInfo(
    key: 'col', name: 'Colo-Colo', country: 'Chile', flag: '🇨🇱', rank: 25,
    primary: 0xFFFFFFFF, secondary: 0xFF111111, sleeve: 0xFFFFFFFF,
    shorts: 0xFF111111, socks: 0xFFFFFFFF, pattern: kPatSolid, barra: 'sur',
    gk: 'Vozinha',
    takers: ['A. Vidal', 'J. Correa', 'F. Garrido', 'D. Saavedra', 'M. Bolados',
      'A. Olguín', 'I. Román', 'J. Villagra', 'C. Aquino', 'F. Marchant', 'M. Fernández'],
  ),
  TeamInfo(
    key: 'cer', name: 'Cerro Porteño', country: 'Paraguay', flag: '🇵🇾', rank: 20,
    primary: 0xFF123A8A, secondary: 0xFF8B1A2B, sleeve: 0xFF123A8A,
    shorts: 0xFF123A8A, socks: 0xFF123A8A, pattern: kPatStripes, barra: 'sur',
    gk: 'R. Fernández',
    takers: ['M. Klimowicz', 'I. Aliseda', 'J. Morel', 'P. Vegetti', 'J. Iturbe',
      'S. Araújo', 'A. Cristaldo', 'E. Almendra', 'B. Riveros', 'A. Espínola', 'G. Benítez'],
  ),
  TeamInfo(
    key: 'nac', name: 'Nacional (URU)', country: 'Uruguay', flag: '🇺🇾', rank: 8,
    primary: 0xFFFFFFFF, secondary: 0xFF1E3E8F, sleeve: 0xFFFFFFFF,
    shorts: 0xFF1E3E8F, socks: 0xFFFFFFFF, pattern: kPatSolid, barra: 'sur',
    gk: 'A. Martín',
    takers: ['M. Silvera', 'N. Gelos', 'P. Núñez', 'T. Correa', 'M. Gómez',
      'B. Zuculini', 'R. Botta', 'L. Boggio', 'A. Rogel', 'S. Coates', 'E. Ancheta'],
  ),
];

int teamIndexByKey(String k) => kTeams.indexWhere((t) => t.key == k);

const List<int> kGkColors = [
  0xFFFF7A00,
  0xFF9ACD32,
  0xFFE91E8C,
  0xFF00BCD4,
  0xFF8E24AA,
];

int gkColorFor(int team) {
  final c = kGkColors[team % kGkColors.length];
  return c == kTeams[team].primary ? kGkColors[(team + 1) % kGkColors.length] : c;
}
