import 'package:flutter/material.dart';

/// Datos de un participante sentado alrededor de la mesa.
class SeatSpec {
  final GlobalKey key;
  final String name;
  final int count; // cartas que tiene en la mano (se ven dadas la vuelta)
  final bool active;
  const SeatSpec(this.key, this.name, this.count, this.active);
}

enum _Side { top, left, right }

/// Reverso pequeño de carta.
Widget _miniBack({bool turned = false}) {
  final w = turned ? 44.0 : 30.0;
  final h = turned ? 30.0 : 44.0;
  return Container(
    width: w,
    height: h,
    decoration: BoxDecoration(
      color: const Color(0xFF1E3A8A),
      border: Border.all(color: Colors.white, width: 2),
      borderRadius: BorderRadius.circular(5),
      boxShadow: const [
        BoxShadow(color: Colors.black45, blurRadius: 3, offset: Offset(1, 2)),
      ],
    ),
    alignment: Alignment.center,
    child: Text('♠♥',
        style: TextStyle(
            color: Colors.white54, fontSize: turned ? 11 : 9, height: 1.0)),
  );
}

class _SeatHand extends StatelessWidget {
  final SeatSpec spec;
  final _Side side;
  const _SeatHand(this.spec, this.side);

  @override
  Widget build(BuildContext context) {
    final label = Container(
      constraints: const BoxConstraints(maxWidth: 92),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: spec.active ? Colors.orange.shade300 : Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: spec.active ? Colors.white : Colors.white24, width: 1.5),
      ),
      child: Text(
        spec.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
            color: spec.active ? Colors.black : Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold),
      ),
    );
    final n = spec.count;
    Widget cards;
    if (side == _Side.top) {
      const step = 18.0;
      cards = SizedBox(
        width: n == 0 ? 0 : 30 + (n - 1) * step,
        height: 44,
        child: Stack(children: [
          for (var i = 0; i < n; i++)
            Positioned(left: i * step, child: _miniBack()),
        ]),
      );
    } else {
      const step = 15.0;
      cards = SizedBox(
        width: 44,
        height: n == 0 ? 0 : 30 + (n - 1) * step,
        child: Stack(children: [
          for (var i = 0; i < n; i++)
            Positioned(top: i * step, child: _miniBack(turned: true)),
        ]),
      );
    }
    return Column(
      key: spec.key,
      mainAxisSize: MainAxisSize.min,
      children: [label, const SizedBox(height: 4), cards],
    );
  }
}

/// Mesa de madera con las cartas boca abajo de cada participante a su lado.
/// 1 rival: arriba. 3 participantes: izquierda, arriba (compañero) y derecha.
class WoodTable extends StatelessWidget {
  final List<SeatSpec> others;
  final Widget center;
  const WoodTable({super.key, required this.others, required this.center});

  @override
  Widget build(BuildContext context) {
    Widget? top, left, right;
    if (others.length == 1) {
      top = _SeatHand(others[0], _Side.top);
    } else if (others.length >= 3) {
      left = _SeatHand(others[0], _Side.left);
      top = _SeatHand(others[1], _Side.top);
      right = _SeatHand(others[2], _Side.right);
    } else if (others.length == 2) {
      left = _SeatHand(others[0], _Side.left);
      right = _SeatHand(others[1], _Side.right);
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF3E2410), width: 6),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 4)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _WoodPainter())),
            Column(
              children: [
                if (top != null)
                  Padding(padding: const EdgeInsets.only(top: 8), child: top),
                Expanded(
                  child: Row(
                    children: [
                      if (left != null)
                        Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Align(alignment: Alignment.center, child: left)),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, c) => Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                    maxWidth: c.maxWidth.isFinite ? c.maxWidth : 300),
                                child: DefaultTextStyle.merge(
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 16),
                                  child: center,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (right != null)
                        Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Align(alignment: Alignment.center, child: right)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Madera: tablones con vetas.
class _WoodPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF9C6B3A), Color(0xFF7B4B25), Color(0xFF8E5C30)],
          ).createShader(Offset.zero & size));
    // Tablones horizontales
    final plank = size.height / 6;
    final seam = Paint()
      ..color = const Color(0x553E2410)
      ..strokeWidth = 2;
    for (var i = 1; i < 6; i++) {
      canvas.drawLine(Offset(0, i * plank), Offset(size.width, i * plank), seam);
    }
    // Vetas
    final grain = Paint()
      ..color = const Color(0x22000000)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (var p = 0; p < 6; p++) {
      for (var k = 1; k <= 3; k++) {
        final y = p * plank + plank * k / 4;
        final path = Path()..moveTo(0, y);
        for (var x = 0.0; x <= size.width; x += 24) {
          path.lineTo(x, y + ((x ~/ 24 + p + k) % 3 - 1) * 1.5);
        }
        canvas.drawPath(path, grain);
      }
    }
    // Brillo suave en el centro
    canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..shader = RadialGradient(
            colors: [Colors.white.withOpacity(0.10), Colors.transparent],
          ).createShader(Offset.zero & size));
  }

  @override
  bool shouldRepaint(covariant _WoodPainter old) => false;
}
