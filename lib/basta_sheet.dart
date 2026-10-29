import 'dart:math';
import 'package:flutter/material.dart';
import 'sfx.dart';

const _ink = Color(0xFF101010); // esfero negro (líneas y títulos)
const _writeInk = Color(0xFF1A237E); // esfero azul (lo que escribimos)
const kHandFont = 'PatrickHand';

/// Hoja de cuaderno con renglones y margen rojo.
class LinedPaper extends StatelessWidget {
  final Widget child;
  const LinedPaper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _PaperPainter(),
      child: child,
    );
  }
}

class _PaperPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFBFAF2));
    final line = Paint()
      ..color = const Color(0xFFA9CBE6)
      ..strokeWidth = 1.2;
    for (double y = 34; y < size.height; y += 30) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), line);
    }
    canvas.drawLine(
        const Offset(38, 0),
        Offset(38, size.height),
        Paint()
          ..color = const Color(0xFFE57373)
          ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Trazo de esfero: línea ligeramente torcida, con sobrante en las puntas
/// y pasada doble, como hecha a mano alzada.
void _pen(Canvas c, Offset a, Offset b, Random r, {double w = 2.4}) {
  final dir = b - a;
  final len = dir.distance;
  if (len < 1) return;
  final n = Offset(dir.dx / len, dir.dy / len);
  final perp = Offset(-n.dy, n.dx);
  final s = a - n * (3 + r.nextDouble() * 5);
  final e = b + n * (3 + r.nextDouble() * 5);
  for (var pass = 0; pass < 2; pass++) {
    final segs = max(4, (len / 32).round());
    final amp = pass == 0 ? 1.7 : 1.2;
    final bias = (r.nextDouble() - 0.5) * 3.2;
    Offset pt(int i) {
      final t = i / segs;
      final o = s + (e - s) * t;
      final j = (i == 0 || i == segs) ? 0.0 : (r.nextDouble() - 0.5) * 2 * amp;
      return o + perp * (j + bias * t + (pass == 1 ? 0.9 : 0));
    }

    var prev = pt(0);
    final path = Path()..moveTo(prev.dx, prev.dy);
    for (var i = 1; i <= segs; i++) {
      final cur = pt(i);
      final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      prev = cur;
    }
    path.lineTo(prev.dx, prev.dy);
    c.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = pass == 0 ? _ink : _ink.withOpacity(0.55)
          ..strokeWidth = pass == 0 ? w : w * 0.6);
  }
}

class _GridPainter extends CustomPainter {
  final double letterW, colW, headH, rowH;
  final int cols;
  _GridPainter(this.letterW, this.colW, this.headH, this.rowH, this.cols);

  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(7);
    final w = letterW + colW * cols;
    final h = headH + rowH;
    _pen(canvas, const Offset(0, 0), Offset(w, 0), r);
    _pen(canvas, Offset(0, headH), Offset(w, headH), r);
    _pen(canvas, Offset(0, h), Offset(w, h), r);
    _pen(canvas, const Offset(0, 0), Offset(0, h), r);
    _pen(canvas, Offset(w, 0), Offset(w, h), r);
    for (var k = 0; k < cols; k++) {
      final x = letterW + colW * k;
      if (k == cols - 1) continue; // el borde derecho ya está
      _pen(canvas, Offset(x, 0), Offset(x, h), r);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter o) =>
      o.letterW != letterW ||
      o.colW != colW ||
      o.headH != headH ||
      o.rowH != rowH ||
      o.cols != cols;
}

class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = Random(3);
    final c = size.center(Offset.zero);
    final rad = min(size.width, size.height) * 0.42;
    for (var pass = 0; pass < 2; pass++) {
      final path = Path();
      const n = 36;
      final start = r.nextDouble() * 6.28;
      for (var i = 0; i <= n + 3; i++) {
        final a = start + i / n * 6.2832;
        final rr = rad * (1 + 0.05 * sin(a * 2 + pass) + (r.nextDouble() - 0.5) * 0.04) +
            i * 0.12 * (pass == 0 ? 1 : 0.5);
        final p = c + Offset(cos(a), sin(a)) * rr;
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      canvas.drawPath(
          path,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..color = pass == 0 ? _ink : _ink.withOpacity(0.5)
            ..strokeWidth = pass == 0 ? 2.2 : 1.3);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// Tabla dibujada a mano: primera columna con la letra, luego una por categoría.
class SketchTable extends StatelessWidget {
  final List<String> cats;
  final String letter;
  final bool letterShown;
  final Map<String, TextEditingController> ctrls;
  final bool locked;
  final ValueChanged<String> onChanged;
  final GlobalKey letterKey;
  final ScrollController scroll;

  const SketchTable({
    super.key,
    required this.cats,
    required this.letter,
    required this.letterShown,
    required this.ctrls,
    required this.locked,
    required this.onChanged,
    required this.letterKey,
    required this.scroll,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      const pad = 14.0;
      const letterW = 74.0;
      const headH = 76.0;
      const rowH = 104.0;
      final avail = box.maxWidth - pad * 2;
      final colW = max(122.0, (avail - letterW) / cats.length);
      final w = letterW + colW * cats.length;
      return SingleChildScrollView(
        controller: scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.all(pad),
        child: SizedBox(
          width: w,
          height: headH + rowH,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _GridPainter(letterW, colW, headH, rowH, cats.length),
                ),
              ),
              // Encabezado
              Positioned(
                left: 0,
                top: 0,
                width: letterW,
                height: headH,
                child: Center(
                  child: Transform.rotate(
                    angle: -0.04,
                    child: const Text('Letra',
                        style: TextStyle(
                            fontFamily: kHandFont,
                            fontSize: 20,
                            color: _ink,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              for (var i = 0; i < cats.length; i++)
                Positioned(
                  left: letterW + colW * i,
                  top: 0,
                  width: colW,
                  height: headH,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Transform.rotate(
                        angle: ((i * 37) % 7 - 3) * 0.012,
                        child: Text(
                          cats[i],
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: kHandFont,
                              fontSize: 19,
                              height: 1.0,
                              color: _ink,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                ),
              // Celda de la letra
              Positioned(
                left: 0,
                top: headH,
                width: letterW,
                height: rowH,
                child: Center(
                  child: SizedBox(
                    key: letterKey,
                    width: 64,
                    height: 64,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 250),
                      opacity: letterShown ? 1 : 0,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOutBack,
                        scale: letterShown ? 1 : 1.6,
                        child: CustomPaint(
                          painter: _RingPainter(),
                          child: Center(
                            child: Text(letter,
                                style: const TextStyle(
                                    fontFamily: kHandFont,
                                    fontSize: 42,
                                    height: 1.0,
                                    color: _ink,
                                    fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Casillas para escribir
              for (var i = 0; i < cats.length; i++)
                Positioned(
                  left: letterW + colW * i,
                  top: headH,
                  width: colW,
                  height: rowH,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Transform.rotate(
                      angle: ((i * 53) % 5 - 2) * 0.01,
                      child: Center(
                        child: TextField(
                          controller: ctrls[cats[i]],
                          enabled: !locked,
                          onChanged: onChanged,
                          textAlign: TextAlign.center,
                          textCapitalization: TextCapitalization.sentences,
                          maxLines: 2,
                          minLines: 1,
                          cursorColor: _writeInk,
                          style: const TextStyle(
                              fontFamily: kHandFont,
                              fontSize: 25,
                              height: 1.05,
                              color: _writeInk),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

/// Tómbola con todas las letras: gira, sale una letra y vuela a la primera casilla.
class LetterTombola extends StatefulWidget {
  final String letter;
  final String allLetters;
  final GlobalKey targetKey;
  final VoidCallback onDone;
  const LetterTombola({
    super.key,
    required this.letter,
    required this.allLetters,
    required this.targetKey,
    required this.onDone,
  });

  @override
  State<LetterTombola> createState() => _LetterTombolaState();
}

class _LetterTombolaState extends State<LetterTombola>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4200))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onDone();
    });

  @override
  void initState() {
    super.initState();
    Sfx.play('tombola');
    Sfx.play('ball', delayMs: 2800);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Offset? _target() {
    try {
      final tb = widget.targetKey.currentContext?.findRenderObject() as RenderBox?;
      final me = context.findRenderObject() as RenderBox?;
      if (tb == null || me == null || !tb.attached) return null;
      return me.globalToLocal(tb.localToGlobal(tb.size.center(Offset.zero)));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) => LayoutBuilder(builder: (context, box) {
        final t = _c.value;
        final size = Size(box.maxWidth, box.maxHeight);
        final dim = t < 0.86 ? 1.0 : (1 - (t - 0.86) / 0.14);
        final drumC = Offset(size.width / 2, size.height * 0.36);
        final r = min(size.width * 0.34, 150.0);
        // Bola elegida
        double? ballScale;
        Offset? ballPos;
        if (t >= 0.60) {
          final out = Offset(drumC.dx + r * 0.2, drumC.dy + r * 1.35);
          final center = Offset(size.width / 2, size.height * 0.55);
          if (t < 0.74) {
            final k = Curves.easeOut.transform((t - 0.60) / 0.14);
            ballPos = Offset.lerp(drumC, out, k);
            ballScale = 0.5 + 0.4 * k;
          } else if (t < 0.88) {
            final k = Curves.easeOutBack.transform((t - 0.74) / 0.14);
            ballPos = Offset.lerp(out, center, k);
            ballScale = 0.9 + 1.3 * k;
          } else {
            final k = Curves.easeInOut.transform((t - 0.88) / 0.12);
            final tgt = _target() ?? Offset(60, size.height * 0.5);
            ballPos = Offset.lerp(center, tgt, k);
            ballScale = 2.2 - 1.6 * k;
          }
        }
        final calm = t < 0.5 ? 0.0 : min(1.0, (t - 0.5) / 0.12);
        return Stack(
          children: [
            Positioned.fill(
              child: ColoredBox(color: Colors.black.withOpacity(0.55 * dim)),
            ),
            Opacity(
              opacity: dim,
              child: CustomPaint(
                size: size,
                painter: _LetterDrumPainter(
                    t * 4.2, calm, widget.allLetters, drumC, r),
              ),
            ),
            if (ballPos != null)
              Positioned(
                left: ballPos.dx - 30 * ballScale!,
                top: ballPos.dy - 30 * ballScale,
                width: 60 * ballScale,
                height: 60 * ballScale,
                child: _LetterBall(widget.letter, 60 * ballScale),
              ),
            if (t < 0.6)
              Positioned(
                left: 0,
                right: 0,
                top: size.height * 0.36 + r * 1.55,
                child: const Text('Girando la tómbola...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontFamily: kHandFont,
                        fontSize: 26,
                        color: Colors.white,
                        decoration: TextDecoration.none)),
              ),
          ],
        );
      }),
    );
  }
}

class _LetterBall extends StatelessWidget {
  final String letter;
  final double size;
  const _LetterBall(this.letter, this.size);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.4, -0.5),
          colors: [Color(0xFFFFFFFF), Color(0xFFFFF3C4), Color(0xFFFFB300)],
          stops: [0.0, 0.5, 1.0],
        ),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8)],
      ),
      alignment: Alignment.center,
      child: Text(letter,
          style: TextStyle(
              fontFamily: kHandFont,
              fontSize: size * 0.62,
              height: 1.0,
              color: _ink,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.none)),
    );
  }
}

class _LetterDrumPainter extends CustomPainter {
  final double time;
  final double calm;
  final String letters;
  final Offset c;
  final double r;
  _LetterDrumPainter(this.time, this.calm, this.letters, this.c, this.r);

  static const _cols = [
    Color(0xFFEF5350),
    Color(0xFF42A5F5),
    Color(0xFF66BB6A),
    Color(0xFFFFCA28),
    Color(0xFFAB47BC),
    Color(0xFFFF7043),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final stand = Paint()
      ..color = const Color(0xFF6D4C41)
      ..strokeWidth = r * 0.08
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c + Offset(-r * 0.55, r * 0.85), c + Offset(-r * 0.8, r * 1.3), stand);
    canvas.drawLine(c + Offset(r * 0.55, r * 0.85), c + Offset(r * 0.8, r * 1.3), stand);
    canvas.drawLine(c + Offset(-r * 0.9, r * 1.3), c + Offset(r * 0.9, r * 1.3), stand);
    canvas.drawCircle(c, r, Paint()..color = Colors.white.withOpacity(0.18));
    final n = letters.length;
    for (var i = 0; i < n; i++) {
      final w = (1.4 + (i % 5) * 0.5) * (1 - 0.65 * calm);
      final a = i * 2.399 + time * w * 3;
      final rr = r * (0.2 + 0.58 * ((i * 0.6180339) % 1));
      final p = Offset(c.dx + cos(a) * rr, c.dy + sin(a * 1.31 + i) * rr * 0.9);
      final br = r * 0.15;
      final col = _cols[i % _cols.length];
      canvas.drawCircle(
          p,
          br,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(-0.4, -0.5),
              colors: [Color.lerp(col, Colors.white, 0.65)!, col],
            ).createShader(Rect.fromCircle(center: p, radius: br)));
      final tp = TextPainter(
        text: TextSpan(
            text: letters[i],
            style: TextStyle(
                fontFamily: kHandFont,
                fontSize: br * 1.35,
                color: Colors.white,
                fontWeight: FontWeight.w700)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
    }
    final ang = time * 4.2 * (1 - 0.7 * calm);
    final bar = Paint()
      ..color = const Color(0xFFB0BEC5)
      ..strokeWidth = r * 0.035
      ..strokeCap = StrokeCap.round;
    for (var k = 0; k < 6; k++) {
      final a = ang + k * pi / 3;
      canvas.drawLine(c, c + Offset(cos(a), sin(a)) * r, bar);
    }
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = const Color(0xFFECEFF1)
          ..strokeWidth = r * 0.06);
    canvas.drawCircle(c + Offset(cos(ang), sin(ang)) * r * 1.12, r * 0.09,
        Paint()..color = const Color(0xFFFFB300));
    canvas.drawCircle(c, r * 0.07, Paint()..color = const Color(0xFFECEFF1));
  }

  @override
  bool shouldRepaint(covariant _LetterDrumPainter old) => true;
}
