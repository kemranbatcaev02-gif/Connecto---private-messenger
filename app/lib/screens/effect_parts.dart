part of 'chat_screen.dart';

// ─────────────────────────────────────────────────────────────
// Эффекты сообщений: полноэкранные частицы при получении.
// Физика с сопротивлением воздуха (частицы плавно тормозят и падают с
// предельной скоростью), мягкое появление/исчезание, эмодзи рисуются из
// готовых картинок — без тяжёлых слоёв на каждую частицу.
// ─────────────────────────────────────────────────────────────

class _Fx {
  final String id;
  final String emoji;
  final String title;
  final bool premium;
  const _Fx(this.id, this.emoji, this.title, {this.premium = false});
}

const List<_Fx> kFx = [
  _Fx('confetti', '🎉', 'Конфетти'),
  _Fx('hearts', '❤️', 'Сердца'),
  _Fx('fire', '🔥', 'Огонь'),
  _Fx('snow', '❄️', 'Снег'),
  _Fx('balloons', '🎈', 'Шарики'),
  _Fx('fireworks', '🎆', 'Салют', premium: true),
  _Fx('money', '💸', 'Деньги', premium: true),
  _Fx('lightning', '⚡', 'Молния', premium: true),
  _Fx('rainbow', '🌈', 'Радуга', premium: true),
  _Fx('stars', '🌠', 'Звездопад', premium: true),
  _Fx('sakura', '🌸', 'Сакура', premium: true),
];

_Fx? fxOf(String? id) {
  for (final f in kFx) {
    if (f.id == id) return f;
  }
  return null;
}

/// Проиграть эффект поверх всего экрана.
void playEffect(BuildContext context, String? id) {
  if (id == null || fxOf(id) == null || !appState.motion) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => IgnorePointer(
      child: _EffectLayer(
        id: id,
        onDone: () {
          if (entry.mounted) entry.remove();
        },
      ),
    ),
  );
  overlay.insert(entry);
  HapticFeedback.mediumImpact();
}

class _P {
  double x, y, vx, vy, rot, vr, size, delay, phase, life, depth;
  final String? emoji;
  final Color color;
  _P(this.x, this.y, this.vx, this.vy,
      {this.rot = 0,
      this.vr = 0,
      this.size = 10,
      this.delay = 0,
      this.phase = 0,
      this.life = 3,
      this.depth = 1,
      this.emoji,
      this.color = Colors.white});
}

class _EffectLayer extends StatefulWidget {
  final String id;
  final VoidCallback onDone;
  const _EffectLayer({required this.id, required this.onDone});
  @override
  State<_EffectLayer> createState() => _EffectLayerState();
}

double _fxDuration(String id) => switch (id) {
      'snow' => 4.2,
      'balloons' => 4.4,
      'fireworks' => 4.4,
      'sakura' => 4.4,
      'stars' => 3.8,
      'money' => 3.6,
      'rainbow' => 3.6,
      'lightning' => 2.6,
      _ => 3.3,
    };

class _EffectLayerState extends State<_EffectLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: Duration(milliseconds: (_fxDuration(widget.id) * 1000).round()));
  List<_P>? _parts;
  Size _size = Size.zero;
  final _rnd = math.Random();

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _r(double a, double b) => a + _rnd.nextDouble() * (b - a);

  static const _bright = [
    Color(0xFFFF3B6B), Color(0xFFFFA43B), Color(0xFFFFE53B), Color(0xFF3BFF8A),
    Color(0xFF3BC4FF), Color(0xFF8A3BFF), Color(0xFFFF6BD6), Color(0xFFFFFFFF),
  ];

  List<_P> _make(Size s) {
    final w = s.width, h = s.height;
    final list = <_P>[];
    switch (widget.id) {
      case 'confetti':
        // две «пушки» снизу + лёгкий дождь сверху
        for (var i = 0; i < 120; i++) {
          final left = i.isEven;
          final ang = left ? _r(-1.4, -0.85) : _r(-2.3, -1.75);
          final sp = _r(900, 1500);
          list.add(_P(left ? -6 : w + 6, h * 0.9, math.cos(ang) * sp, math.sin(ang) * sp,
              rot: _r(0, 6), vr: _r(-8, 8), size: _r(7, 13), delay: _r(0, 0.18),
              phase: _r(0, 6), life: _r(2.6, 3.2), color: _bright[_rnd.nextInt(_bright.length)]));
        }
        for (var i = 0; i < 40; i++) {
          list.add(_P(_r(0, w), _r(-h * 0.25, -10), _r(-40, 40), _r(40, 120),
              rot: _r(0, 6), vr: _r(-6, 6), size: _r(6, 11), delay: _r(0.3, 1.1),
              phase: _r(0, 6), life: _r(2, 2.4), color: _bright[_rnd.nextInt(_bright.length)]));
        }
        break;
      case 'hearts':
        const e = ['❤️', '💖', '💕', '💗', '💘', '💓'];
        for (var i = 0; i < 38; i++) {
          final ang = _r(-2.2, -0.95);
          final sp = _r(160, 380);
          list.add(_P(w / 2 + _r(-40, 40), h * 0.62, math.cos(ang) * sp, math.sin(ang) * sp,
              size: _r(22, 44), delay: _r(0.1, 1.2), phase: _r(0, 6), life: _r(1.8, 2.4),
              vr: _r(-0.6, 0.6), emoji: e[_rnd.nextInt(e.length)]));
        }
        break;
      case 'fire':
        for (var i = 0; i < 30; i++) {
          list.add(_P(_r(-10, w + 10), h + 30, _r(-20, 20), _r(-560, -360),
              size: _r(26, 52), delay: _r(0, 0.9), phase: _r(0, 6), life: _r(1.3, 1.9),
              emoji: '🔥'));
        }
        for (var i = 0; i < 70; i++) {
          // искры
          list.add(_P(_r(0, w), h + 10, _r(-40, 40), _r(-700, -380),
              size: _r(1.5, 3.5), delay: _r(0, 1.6), phase: _r(0, 6), life: _r(0.9, 1.6),
              color: [const Color(0xFFFFD166), const Color(0xFFFF8A3D), const Color(0xFFFFF1B8)][
                  _rnd.nextInt(3)]));
        }
        break;
      case 'snow':
        const e = ['❄️', '❅', '❆'];
        for (var i = 0; i < 90; i++) {
          final depth = _r(0.35, 1); // дальние — мельче и медленнее
          list.add(_P(_r(0, w), _r(-h * 0.7, -20), _r(-15, 15), 60 + 140 * depth,
              size: (i % 3 == 0 ? 10 : 4) + 16 * depth, delay: _r(0, 0.6), phase: _r(0, 6),
              vr: _r(-1, 1), depth: depth, life: 4.2,
              emoji: i % 3 == 0 ? e[_rnd.nextInt(e.length)] : null));
        }
        break;
      case 'balloons':
        const e = ['🎈', '🎈', '🎈', '🎉'];
        for (var i = 0; i < 22; i++) {
          list.add(_P(_r(0, w), h + 60, _r(-12, 12), _r(-260, -170),
              size: _r(34, 58), delay: _r(0, 1.4), phase: _r(0, 6), life: 4.4,
              vr: _r(-0.3, 0.3), emoji: e[_rnd.nextInt(e.length)]));
        }
        break;
      case 'fireworks':
        for (var b = 0; b < 6; b++) {
          final cx = _r(w * 0.15, w * 0.85), cy = _r(h * 0.14, h * 0.45);
          final col = _bright[_rnd.nextInt(_bright.length - 1)];
          final col2 = _bright[_rnd.nextInt(_bright.length)];
          final launch = b * 0.45; // ракета взлетает 0.55 с
          // ракета
          list.add(_P(cx + _r(-30, 30), h + 10, cx, cy,
              delay: launch, life: 0.55, size: 2.5, color: col, phase: -1));
          final n = 54;
          for (var i = 0; i < n; i++) {
            final ang = i / n * 2 * math.pi + _r(-0.05, 0.05);
            final sp = _r(160, 360);
            list.add(_P(cx, cy, math.cos(ang) * sp, math.sin(ang) * sp,
                size: _r(1.8, 3.4), delay: launch + 0.55, life: _r(1.3, 1.8), phase: _r(0, 6),
                color: i % 3 == 0 ? col2 : col));
          }
        }
        break;
      case 'money':
        const e = ['💸', '💵', '💰', '💶'];
        for (var i = 0; i < 30; i++) {
          list.add(_P(_r(0, w), _r(-h * 0.5, -30), _r(-30, 30), _r(200, 380),
              size: _r(24, 42), delay: _r(0, 0.9), rot: _r(-0.6, 0.6), vr: _r(-2.5, 2.5),
              phase: _r(0, 6), life: 3.6, emoji: e[_rnd.nextInt(e.length)]));
        }
        for (var i = 0; i < 26; i++) {
          // золотые монеты, вращаются ребром
          list.add(_P(_r(0, w), _r(-h * 0.4, -20), _r(-20, 20), _r(260, 460),
              size: _r(9, 15), delay: _r(0, 1.1), phase: _r(0, 6), vr: _r(5, 10), life: 3.6,
              color: const Color(0xFFFFC928)));
        }
        break;
      case 'lightning':
        for (var i = 0; i < 3; i++) {
          list.add(_P(_r(w * 0.15, w * 0.85), 0, 0, 0,
              delay: 0.35 + i * 0.42, phase: _r(0, 100000), life: 0.5));
        }
        break;
      case 'rainbow':
        for (var i = 0; i < 40; i++) {
          list.add(_P(_r(0, w), _r(h * 0.1, h * 0.8), 0, 0,
              size: _r(12, 26), delay: _r(0.3, 2.2), phase: _r(0, 6), life: _r(0.8, 1.4),
              emoji: '✨'));
        }
        break;
      case 'stars':
        for (var i = 0; i < 60; i++) {
          // мерцающий фон
          list.add(_P(_r(0, w), _r(0, h * 0.7), 0, 0,
              size: _r(0.8, 2.2), delay: _r(0, 0.8), phase: _r(0, 6), life: 3.8));
        }
        for (var i = 0; i < 9; i++) {
          // падающие звёзды
          final sp = _r(700, 1000);
          list.add(_P(_r(w * 0.2, w * 1.1), _r(-40, h * 0.3), -sp * 0.8, sp * 0.55,
              size: _r(2.2, 3.4), delay: 0.25 + i * _r(0.25, 0.4), life: _r(0.7, 1.0),
              phase: 1, color: const Color(0xFFFFF4C2)));
        }
        break;
      case 'sakura':
        for (var i = 0; i < 70; i++) {
          final depth = _r(0.4, 1);
          list.add(_P(_r(-w * 0.2, w), _r(-h * 0.6, -20), _r(20, 80), 70 + 110 * depth,
              size: 6 + 9 * depth, delay: _r(0, 1.0), phase: _r(0, 6), rot: _r(0, 6),
              vr: _r(-3, 3), depth: depth, life: 4.4,
              color: [const Color(0xFFFFC1D6), const Color(0xFFFF9EBB), const Color(0xFFFFE0EA)][
                  _rnd.nextInt(3)],
              emoji: i % 9 == 0 ? '🌸' : null));
        }
        break;
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final s = MediaQuery.of(context).size;
    if (_parts == null || s != _size) {
      _size = s;
      _parts = _make(s);
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: s,
        painter: _FxPainter(widget.id, _parts!, _c, _fxDuration(widget.id),
            MediaQuery.of(context).devicePixelRatio),
      ),
    );
  }
}

/// Эмодзи, заранее нарисованные в картинки (быстро рисуются с любой прозрачностью).
final Map<String, ui.Image> _emojiImages = {};

ui.Image _emojiImage(String emoji, double size, double dpr) {
  final px = (size * dpr).round().clamp(8, 256).toInt();
  final key = '$emoji|$px';
  final cached = _emojiImages[key];
  if (cached != null) return cached;
  final tp = TextPainter(
    text: TextSpan(text: emoji, style: TextStyle(fontSize: px.toDouble())),
    textDirection: TextDirection.ltr,
  )..layout();
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  tp.paint(canvas, Offset.zero);
  final img = rec
      .endRecording()
      .toImageSync(tp.width.ceil().clamp(1, 400).toInt(), tp.height.ceil().clamp(1, 400).toInt());
  if (_emojiImages.length > 160) _emojiImages.clear();
  return _emojiImages[key] = img;
}

class _FxPainter extends CustomPainter {
  final String id;
  final List<_P> parts;
  final Animation<double> anim;
  final double total;
  final double dpr;

  _FxPainter(this.id, this.parts, this.anim, this.total, this.dpr) : super(repaint: anim);

  /// Плавно 0→1→0 за время жизни частицы.
  static double _env(double lt, double life, {double fin = 0.18, double fout = 0.45}) {
    if (lt <= 0 || lt >= life) return 0;
    final a = (lt / fin).clamp(0.0, 1.0);
    final b = ((life - lt) / fout).clamp(0.0, 1.0);
    return Curves.easeOut.transform(math.min(a, b));
  }

  /// Движение с сопротивлением воздуха: скорость гаснет, частица падает с предельной скоростью.
  static Offset _drag(_P p, double lt, double k, double g) {
    final e = 1 - math.exp(-k * lt);
    final vt = g / k;
    return Offset(p.x + p.vx / k * e, p.y + (p.vy - vt) / k * e + vt * lt);
  }

  void _emoji(Canvas c, _P p, double x, double y, double alpha, {double scale = 1, double rot = 0}) {
    if (alpha <= 0.01) return;
    final img = _emojiImage(p.emoji!, p.size, dpr);
    final w = img.width / dpr * scale, h = img.height / dpr * scale;
    c.save();
    c.translate(x, y);
    if (rot != 0) c.rotate(rot);
    c.drawImageRect(
      img,
      Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
      Rect.fromCenter(center: Offset.zero, width: w, height: h),
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0))
        ..filterQuality = FilterQuality.medium,
    );
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = anim.value * total;
    final w = size.width, h = size.height;
    final end = total - t; // сколько осталось до конца эффекта
    final globalFade = (end / 0.5).clamp(0.0, 1.0);
    final paint = Paint();
    switch (id) {
      case 'confetti':
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0 || lt >= p.life) continue;
          final o = _drag(p, lt, 1.9, 520);
          final sway = math.sin(lt * 5 + p.phase) * 18 * math.min(1.0, lt);
          final a = _env(lt, p.life, fin: 0.05) * globalFade;
          paint.color = p.color.withValues(alpha: a);
          canvas.save();
          canvas.translate(o.dx + sway, o.dy);
          canvas.rotate(p.rot + p.vr * lt);
          // «переворот» бумажки
          final flip = 0.25 + 0.75 * math.cos(lt * 9 + p.phase).abs();
          canvas.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55 * flip),
                  const Radius.circular(2)),
              paint);
          canvas.restore();
        }
        break;
      case 'hearts':
        // большое сердце-пульс в начале
        if (t < 1.1) {
          final k = t / 1.1;
          final pop = Curves.easeOutBack.transform((k * 2.2).clamp(0.0, 1.0));
          final beat = 1 + 0.12 * math.sin(k * math.pi * 4);
          final a = (1 - Curves.easeIn.transform(k)).clamp(0.0, 1.0);
          _emoji(canvas, _P(0, 0, 0, 0, size: 110, emoji: '❤️'), w / 2, h * 0.5, a,
              scale: 0.4 + 0.8 * pop * beat);
        }
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0 || lt >= p.life) continue;
          final o = _drag(p, lt, 0.9, -40);
          final sway = math.sin(lt * 3 + p.phase) * 26;
          final pop = Curves.easeOutBack.transform((lt / 0.35).clamp(0.0, 1.0));
          _emoji(canvas, p, o.dx + sway, o.dy, _env(lt, p.life) * globalFade,
              scale: pop, rot: math.sin(lt * 2 + p.phase) * 0.25);
        }
        break;
      case 'fire':
        final glow = math.min(1.0, t * 2.5) * globalFade;
        final flick = 0.85 + 0.15 * math.sin(t * 23) * math.sin(t * 7);
        final rect = Rect.fromLTWH(0, h * 0.45, w, h * 0.55);
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                const Color(0xFFFF4D1F).withValues(alpha: 0.5 * glow * flick),
                const Color(0xFFFF9A3D).withValues(alpha: 0.18 * glow * flick),
                Colors.transparent,
              ],
            ).createShader(rect),
        );
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0 || lt >= p.life) continue;
          final wob = math.sin(lt * 9 + p.phase);
          final x = p.x + p.vx * lt + wob * (p.emoji != null ? 10 : 6);
          final y = p.y + p.vy * lt;
          final k = lt / p.life;
          if (p.emoji != null) {
            // пламя растёт, потом сжимается и гаснет
            final sc = 0.5 + math.sin(k * math.pi) * 0.7;
            _emoji(canvas, p, x, y, _env(lt, p.life) * globalFade, scale: sc);
          } else {
            final a = _env(lt, p.life, fin: 0.05) * (0.6 + 0.4 * wob.abs()) * globalFade;
            paint
              ..color = p.color.withValues(alpha: a)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5);
            canvas.drawCircle(Offset(x, y), p.size * (1 - k * 0.6), paint);
            paint.maskFilter = null;
          }
        }
        break;
      case 'snow':
        // лёгкая морозная дымка по краям
        final frost = math.min(1.0, t * 1.5) * globalFade;
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              radius: 1.0,
              colors: [Colors.transparent, const Color(0xFFDCEBFF).withValues(alpha: 0.22 * frost)],
              stops: const [0.6, 1],
            ).createShader(Offset.zero & size),
        );
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0) continue;
          final x = p.x + p.vx * lt + math.sin(lt * (1.2 + p.depth) + p.phase) * 22 * p.depth;
          final y = p.y + p.vy * lt;
          if (y > h + 40) continue;
          final a = _env(lt, total - p.delay, fin: 0.4, fout: 0.8) * (0.45 + 0.55 * p.depth);
          if (p.emoji != null) {
            _emoji(canvas, p, x, y, a, rot: p.vr * lt);
          } else {
            paint
              ..color = Colors.white.withValues(alpha: a * 0.9)
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, (1 - p.depth) * 2.5 + 0.3);
            canvas.drawCircle(Offset(x, y), p.size * 0.28, paint);
            paint.maskFilter = null;
          }
        }
        break;
      case 'balloons':
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0) continue;
          final x = p.x + p.vx * lt + math.sin(lt * 1.4 + p.phase) * 24;
          final y = p.y + p.vy * lt - 18 * lt * lt; // разгоняются вверх
          if (y < -120) continue;
          final a = _env(lt, total - p.delay, fin: 0.3, fout: 0.6);
          final rot = math.sin(lt * 1.4 + p.phase) * 0.18 + p.vr * 0.2;
          // ниточка
          paint
            ..color = Colors.white.withValues(alpha: 0.5 * a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1;
          final bx = x - math.sin(rot) * p.size * 0.45;
          final by = y + p.size * 0.5;
          canvas.drawPath(
              Path()
                ..moveTo(bx, by)
                ..quadraticBezierTo(bx + math.sin(lt * 3 + p.phase) * 10, by + 26, bx, by + 50),
              paint);
          paint.style = PaintingStyle.fill;
          _emoji(canvas, p, x, y, a, rot: rot);
        }
        break;
      case 'fireworks':
        for (final p in parts) {
          final lt = t - p.delay;
          if (p.phase == -1 && lt >= p.life && lt < p.life + 0.18) {
            // вспышка в точке взрыва
            final k = (lt - p.life) / 0.18;
            canvas.drawCircle(
                Offset(p.vx, p.vy),
                30 + k * 90,
                Paint()
                  ..color = p.color.withValues(alpha: 0.35 * (1 - k))
                  ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 22));
            continue;
          }
          if (lt <= 0 || lt >= p.life) continue;
          if (p.phase == -1) {
            // ракета: из (x,y) в (vx,vy), за собой — хвост
            final k = Curves.easeOutCubic.transform(lt / p.life);
            final x = p.x + (p.vx - p.x) * k, y = p.y + (p.vy - p.y) * k;
            final pk = Curves.easeOutCubic.transform(math.max(0, lt - 0.12) / p.life);
            final px = p.x + (p.vx - p.x) * pk, py = p.y + (p.vy - p.y) * pk;
            canvas.drawLine(
                Offset(px, py),
                Offset(x, y),
                Paint()
                  ..shader = LinearGradient(colors: [
                    p.color.withValues(alpha: 0),
                    Colors.white.withValues(alpha: 0.9),
                  ]).createShader(Rect.fromPoints(Offset(px, py), Offset(x, y)))
                  ..strokeWidth = 2.6
                  ..strokeCap = StrokeCap.round);
            continue;
          }
          final o = _drag(p, lt, 1.7, 160);
          final a = (1 - Curves.easeIn.transform(lt / p.life)) * globalFade;
          final tw = 0.6 + 0.4 * math.sin(lt * 30 + p.phase); // искрение
          paint.color = p.color.withValues(alpha: a * tw);
          canvas.drawCircle(o, p.size, paint);
          paint.color = p.color.withValues(alpha: a * 0.3);
          final back = _drag(p, math.max(0, lt - 0.08), 1.7, 160);
          canvas.drawLine(back, o, paint..strokeWidth = p.size * 0.9);
        }
        break;
      case 'money':
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0) continue;
          final flutter = math.sin(lt * 2.2 + p.phase);
          final x = p.x + p.vx * lt + flutter * 26;
          final y = p.y + p.vy * lt + 40 * lt * lt;
          if (y > h + 60) continue;
          final a = _env(lt, total - p.delay, fin: 0.2, fout: 0.5);
          if (p.emoji != null) {
            _emoji(canvas, p, x, y, a, rot: p.rot + flutter * 0.5);
          } else {
            // монета ребром: сжимается по ширине
            final sx = math.cos(lt * p.vr + p.phase);
            final r = p.size;
            canvas.save();
            canvas.translate(x, y);
            canvas.scale(sx.abs() * 0.9 + 0.1, 1);
            canvas.drawCircle(Offset.zero, r,
                Paint()..color = (sx > 0 ? const Color(0xFFFFC928) : const Color(0xFFE0A100)).withValues(alpha: a));
            canvas.drawCircle(
                Offset.zero,
                r * 0.72,
                Paint()
                  ..color = const Color(0xFFFFE58A).withValues(alpha: a)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = r * 0.14);
            canvas.restore();
          }
        }
        break;
      case 'lightning':
        // небо темнеет перед ударами
        final dark = (math.min(1.0, t / 0.3) * globalFade) * 0.35;
        canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF0B0F2A).withValues(alpha: dark));
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0 || lt >= p.life) continue;
          // мерцание: 2 вспышки подряд
          final flick = lt < 0.08 ? 1.0 : (lt < 0.14 ? 0.35 : (lt < 0.22 ? 0.9 : 1 - (lt - 0.22) / (p.life - 0.22)));
          final a = flick.clamp(0.0, 1.0);
          if (lt < 0.1) {
            canvas.drawRect(Offset.zero & size,
                Paint()..color = Colors.white.withValues(alpha: 0.4 * (1 - lt / 0.1)));
          }
          final rnd = math.Random(p.phase.toInt());
          final bolt = Path()..moveTo(p.x, 0);
          final branches = <Path>[];
          var x = p.x;
          var y = 0.0;
          while (y < h * 0.66) {
            y += 26 + rnd.nextDouble() * 36;
            x += (rnd.nextDouble() - 0.5) * 64;
            bolt.lineTo(x, y);
            if (rnd.nextDouble() < 0.28) {
              final b = Path()..moveTo(x, y);
              var bx = x, by = y;
              final dir = rnd.nextBool() ? 1 : -1;
              for (var j = 0; j < 3 + rnd.nextInt(3); j++) {
                by += 18 + rnd.nextDouble() * 22;
                bx += dir * (10 + rnd.nextDouble() * 26);
                b.lineTo(bx, by);
              }
              branches.add(b);
            }
          }
          final glowP = Paint()
            ..color = const Color(0xFFB8C7FF).withValues(alpha: a * 0.7)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 12
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
          final core = Paint()
            ..color = Colors.white.withValues(alpha: a)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeJoin = StrokeJoin.round;
          canvas.drawPath(bolt, glowP);
          canvas.drawPath(bolt, core);
          for (final b in branches) {
            canvas.drawPath(b, glowP..strokeWidth = 6);
            canvas.drawPath(b, core..strokeWidth = 1.4);
          }
        }
        break;
      case 'rainbow':
        const colors = [
          Color(0xFFFF3B3B), Color(0xFFFF9F1C), Color(0xFFFFE53B), Color(0xFF2ECC71),
          Color(0xFF3BA9FF), Color(0xFF5B5BFF), Color(0xFFA23BFF),
        ];
        final grow = Curves.easeOutCubic.transform((t / 1.2).clamp(0.0, 1.0));
        final center = Offset(w / 2, h * 0.8);
        final bandW = math.min(18.0, w * 0.04);
        for (var i = 0; i < colors.length; i++) {
          final r = w * 0.64 - i * bandW;
          canvas.drawArc(
            Rect.fromCircle(center: center, radius: r),
            math.pi,
            math.pi * grow,
            false,
            Paint()
              ..color = colors[i].withValues(alpha: 0.72 * globalFade)
              ..style = PaintingStyle.stroke
              ..strokeWidth = bandW + 1
              ..strokeCap = StrokeCap.round,
          );
        }
        // блик бежит по радуге
        if (grow >= 1) {
          final k = ((t - 1.2) / 1.4).clamp(0.0, 1.0);
          final ang = math.pi + math.pi * k;
          final r = w * 0.64 - bandW * 3;
          canvas.drawCircle(
              center + Offset(math.cos(ang) * r, math.sin(ang) * r),
              bandW * 4,
              Paint()
                ..color = Colors.white.withValues(alpha: 0.35 * globalFade * math.sin(k * math.pi))
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
        }
        // облачка на концах
        final cloud = _P(0, 0, 0, 0, size: 54, emoji: '☁️');
        _emoji(canvas, cloud, center.dx - w * 0.64 + bandW * 3, center.dy - 4, grow * globalFade);
        if (grow >= 0.98) {
          _emoji(canvas, cloud, center.dx + w * 0.64 - bandW * 3, center.dy - 4, globalFade);
        }
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0 || lt >= p.life) continue;
          final e = _env(lt, p.life, fin: 0.3, fout: 0.4);
          _emoji(canvas, p, p.x, p.y, e * globalFade, scale: 0.6 + 0.6 * e);
        }
        break;
      case 'stars':
        // ночное небо сверху
        final sky = math.min(1.0, t / 0.4) * globalFade;
        final rect = Rect.fromLTWH(0, 0, w, h * 0.8);
        canvas.drawRect(
            rect,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [const Color(0xFF0B1030).withValues(alpha: 0.55 * sky), Colors.transparent],
              ).createShader(rect));
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0) continue;
          if (p.phase != 1) {
            final tw = 0.4 + 0.6 * (math.sin(lt * 4 + p.phase) * 0.5 + 0.5);
            paint.color = Colors.white.withValues(alpha: tw * sky);
            canvas.drawCircle(Offset(p.x, p.y), p.size, paint);
            continue;
          }
          if (lt >= p.life) continue;
          final head = Offset(p.x + p.vx * lt, p.y + p.vy * lt);
          final tail = Offset(p.x + p.vx * math.max(0, lt - 0.22), p.y + p.vy * math.max(0, lt - 0.22));
          final a = _env(lt, p.life, fin: 0.08, fout: 0.3);
          canvas.drawLine(
              tail,
              head,
              Paint()
                ..shader = LinearGradient(colors: [
                  p.color.withValues(alpha: 0),
                  p.color.withValues(alpha: a),
                ]).createShader(Rect.fromPoints(tail, head))
                ..strokeWidth = p.size
                ..strokeCap = StrokeCap.round);
          canvas.drawCircle(
              head,
              p.size * 2.2,
              Paint()
                ..color = Colors.white.withValues(alpha: a * 0.8)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        }
        break;
      case 'sakura':
        final glowA = math.min(1.0, t / 0.6) * globalFade;
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..shader = RadialGradient(
              center: const Alignment(0, -1),
              radius: 1.2,
              colors: [const Color(0xFFFFC1D6).withValues(alpha: 0.16 * glowA), Colors.transparent],
            ).createShader(Offset.zero & size),
        );
        for (final p in parts) {
          final lt = t - p.delay;
          if (lt <= 0) continue;
          final x = p.x + p.vx * lt + math.sin(lt * 1.8 + p.phase) * 30 * p.depth;
          final y = p.y + p.vy * lt;
          if (y > h + 40) continue;
          final a = _env(lt, total - p.delay, fin: 0.35, fout: 0.7) * (0.55 + 0.45 * p.depth);
          if (p.emoji != null) {
            _emoji(canvas, p, x, y, a, rot: p.rot + p.vr * lt * 0.3, scale: 1.4);
            continue;
          }
          // лепесток: овал с вырезом, кружится и «переворачивается»
          canvas.save();
          canvas.translate(x, y);
          canvas.rotate(p.rot + p.vr * lt);
          canvas.scale(1, 0.35 + 0.65 * math.cos(lt * 3 + p.phase).abs());
          final s = p.size;
          final petal = Path()
            ..moveTo(0, -s)
            ..quadraticBezierTo(s * 0.9, -s * 0.2, 0, s)
            ..quadraticBezierTo(-s * 0.9, -s * 0.2, 0, -s)
            ..close();
          canvas.drawPath(petal, Paint()..color = p.color.withValues(alpha: a));
          canvas.restore();
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _FxPainter old) => true;
}

// ─────────────────────────────────────────────────────────────
// Капсула времени
// ─────────────────────────────────────────────────────────────

String _capsuleLeft(Duration d) {
  if (d.isNegative) return 'сейчас откроется';
  final days = d.inDays, hours = d.inHours % 24, mins = d.inMinutes % 60, secs = d.inSeconds % 60;
  if (days > 0) return '$days д $hours ч';
  if (hours > 0) return '$hours ч ${mins.toString().padLeft(2, '0')} мин';
  return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
}

String _capsuleDate(DateTime d) {
  const months = [
    'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
    'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
  ];
  final l = d.toLocal();
  return '${l.day} ${months[l.month - 1]} ${l.year}, '
      '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Запечатанная капсула: переливается, показывает сколько осталось (кольцом и цифрами),
/// а в момент открытия трясётся и «взрывается» — только потом показывает сообщение.
class _CapsuleSealed extends StatefulWidget {
  final DateTime openAt;
  final DateTime createdAt;
  final VoidCallback onOpened;
  const _CapsuleSealed({required this.openAt, required this.createdAt, required this.onOpened});
  @override
  State<_CapsuleSealed> createState() => _CapsuleSealedState();
}

class _CapsuleSealedState extends State<_CapsuleSealed> with TickerProviderStateMixin {
  late final AnimationController _loop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 4000));
  late final AnimationController _open =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  Timer? _t;
  bool _fired = false;

  @override
  void initState() {
    super.initState();
    if (appState.motion) _loop.repeat();
    _t = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = widget.openAt.difference(DateTime.now());
      if (left.inMilliseconds <= 0 && !_fired) {
        _fired = true;
        HapticFeedback.mediumImpact();
        if (appState.motion) {
          _open.forward().whenComplete(() {
            HapticFeedback.heavyImpact();
            widget.onOpened();
          });
        } else {
          widget.onOpened();
        }
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    _loop.dispose();
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.openAt.difference(DateTime.now());
    final total = widget.openAt.difference(widget.createdAt).inSeconds;
    final passed = DateTime.now().difference(widget.createdAt).inSeconds;
    final progress = total <= 0 ? 1.0 : (passed / total).clamp(0.0, 1.0);
    return AnimatedBuilder(
      animation: Listenable.merge([_loop, _open]),
      builder: (context, _) {
        final t = _loop.value;
        final o = _open.value;
        final a = t * 2 * math.pi;
        // тряска перед открытием, потом вспышка
        final shake = o < 0.7 ? math.sin(o * 60) * 6 * (o / 0.7) : 0.0;
        final burst = o < 0.7 ? 0.0 : ((o - 0.7) / 0.3).clamp(0.0, 1.0);
        return Container(
          width: 240,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: const [Color(0xFF2B1B54), Color(0xFF5B2A86), Color(0xFFB0457A), Color(0xFF2B1B54)],
              stops: const [0, 0.4, 0.75, 1],
              begin: Alignment(math.cos(a), math.sin(a)),
              end: Alignment(-math.cos(a), -math.sin(a)),
            ),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFFB0457A).withValues(alpha: 0.35 + 0.15 * math.sin(a * 2) + 0.4 * burst),
                  blurRadius: 18 + 20 * burst),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              // искорки вокруг (бесшовный цикл)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _CapsuleSparks(t: t, burst: burst)),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // кольцо: сколько времени уже прошло
                            CustomPaint(
                              size: const Size(56, 56),
                              painter: _CapsuleRing(progress: progress, t: t),
                            ),
                            Transform.translate(
                              offset: Offset(shake, -3 * math.sin(a * 2)),
                              child: Transform.rotate(
                                angle: math.sin(a) * 0.08 + shake * 0.02,
                                child: Transform.scale(
                                  scale: 1 + 0.35 * Curves.easeOutBack.transform(burst),
                                  child: Opacity(
                                      opacity: 1 - burst * 0.9,
                                      child: const Text('📦', style: TextStyle(fontSize: 30))),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(o > 0 ? 'Открывается…' : 'Капсула времени',
                                style: const TextStyle(
                                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15.5)),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(o > 0 ? AppIcons.sparkles : AppIcons.lock,
                                    color: Colors.white70, size: 13),
                                const SizedBox(width: 4),
                                Text(o > 0 ? 'печать снята' : 'запечатана',
                                    style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.12))),
                    child: Row(
                      children: [
                        const Icon(AppIcons.timer, color: Colors.white, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (c, an) => FadeTransition(
                              opacity: an,
                              child: SlideTransition(
                                position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(an),
                                child: c,
                              ),
                            ),
                            child: Text(
                              _capsuleLeft(left),
                              key: ValueKey(_capsuleLeft(left)),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17,
                                  fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                          ),
                        ),
                        Text('${(progress * 100).round()}%',
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('Откроется ${_capsuleDate(widget.openAt)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Кольцо прогресса вокруг коробки + бегущий огонёк.
class _CapsuleRing extends CustomPainter {
  final double progress, t;
  _CapsuleRing({required this.progress, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 2.5;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = Colors.white.withValues(alpha: 0.15));
    final sweep = 2 * math.pi * progress;
    canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: const [Color(0xFFFFD1E8), Color(0xFFFFFFFF), Color(0xFFFFD1E8)],
            transform: GradientRotation(t * 2 * math.pi),
          ).createShader(Rect.fromCircle(center: c, radius: r)));
    // огонёк на конце дуги
    final ang = -math.pi / 2 + sweep;
    canvas.drawCircle(
        c + Offset(math.cos(ang) * r, math.sin(ang) * r),
        3.2,
        Paint()
          ..color = Colors.white
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2));
  }

  @override
  bool shouldRepaint(covariant _CapsuleRing old) => old.t != t || old.progress != progress;
}

/// Искорки внутри карточки капсулы; при открытии — разлетаются.
class _CapsuleSparks extends CustomPainter {
  final double t, burst;
  _CapsuleSparks({required this.t, required this.burst});

  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(7);
    for (var i = 0; i < 12; i++) {
      final x0 = rnd.nextDouble() * size.width;
      final y0 = rnd.nextDouble() * size.height;
      final freq = 1 + rnd.nextInt(2);
      final ph = rnd.nextDouble();
      final tw = math.pow(math.sin(((t * freq + ph) % 1.0) * math.pi), 2).toDouble();
      final dx = (x0 - 28) * burst * 0.6, dy = (y0 - 28) * burst * 0.6;
      final r = 1.2 + 1.8 * tw + 2 * burst;
      canvas.drawCircle(Offset(x0 + dx, y0 + dy), r,
          Paint()..color = Colors.white.withValues(alpha: (0.2 + 0.6 * tw) * (1 - burst * 0.7)));
    }
  }

  @override
  bool shouldRepaint(covariant _CapsuleSparks old) => old.t != t || old.burst != burst;
}

/// Короткий остаток времени до исчезновения: «59 с», «12 мин», «5 ч», «3 д».
String _ttlLeft(DateTime at) {
  final d = at.difference(DateTime.now());
  if (d.inSeconds < 60) return '${d.inSeconds.clamp(0, 59)} с';
  if (d.inMinutes < 60) return '${d.inMinutes} мин';
  if (d.inHours < 24) return '${d.inHours} ч';
  return '${d.inDays} д';
}

const Map<int, String> kTtlNames = {
  0: 'Выключено',
  60: '1 минута',
  3600: '1 час',
  86400: '1 день',
  604800: '1 неделя',
};
