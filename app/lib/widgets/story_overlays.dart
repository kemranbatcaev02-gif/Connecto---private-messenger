import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_state.dart';

// ─────────────────────────────────────────────────────────────
// Наложения на историю: текст с эффектами, стикеры, погода, время.
// Хранятся JSON-ом: {type, x, y (доли экрана, центр), scale, rot, …}
// ─────────────────────────────────────────────────────────────

/// Стили текста.
const List<(String, String)> kStoryTextStyles = [
  ('plain', 'Обычный'),
  ('box', 'Плашка'),
  ('neon', 'Неон'),
  ('outline', 'Контур'),
  ('gradient', 'Радуга'),
  ('wave', 'Волна'),
  ('typewriter', 'Печать'),
];

const List<String> kStoryFonts = ['Manrope', 'Unbounded', 'Caveat', 'Montserrat', 'JetBrains Mono'];

const List<Color> kStoryColors = [
  Color(0xFFFFFFFF), Color(0xFF111111), Color(0xFFFF4D6D), Color(0xFFFF9F1C), Color(0xFFFFE14D),
  Color(0xFF2EE59D), Color(0xFF3ABEFF), Color(0xFF7B61FF), Color(0xFFFF6EC7),
];

/// Свои стикеры (пока немного — наборы добавим позже).
const List<(String, String)> kStoryStickers = [
  ('st_cat', 'Котик'),
  ('st_heart', 'Сердечко'),
  ('st_fire', 'Огонёк'),
  ('st_pizza', 'Пицца'),
  ('st_panda', 'Панда'),
  ('st_gamer', 'Геймер'),
  ('connecto', 'Connecto'),
  ('hello', 'Привет!'),
  ('cool', 'Круто!'),
];

const List<String> kStoryEmojis = [
  '🔥', '❤️', '😂', '😍', '🥳', '😎', '🤩', '😭', '👍', '🙏', '💯', '✨',
  '🎉', '🎂', '🌸', '🌈', '☀️', '🌙', '⭐', '⚡', '💎', '👑', '🚀', '🎮',
  '🏆', '⚽', '🏀', '🏋️', '🏊', '🎧', '🎸', '📸', '🍕', '🍔', '☕', '🍩',
  '🐶', '🐱', '🦊', '🐼', '🦄', '🐉', '💪', '👀', '🤝', '💬', '📍', '✈️',
];

Color _hex(String? s, [Color fb = Colors.white]) {
  if (s == null || s.isEmpty) return fb;
  final h = s.replaceAll('#', '');
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? fb : Color(v);
}

String colorHex(Color c) =>
    '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

TextStyle storyFont(String? family, {double size = 30, Color color = Colors.white, FontWeight w = FontWeight.w800}) {
  try {
    return GoogleFonts.getFont(family ?? 'Manrope', fontSize: size, color: color, fontWeight: w, height: 1.15);
  } catch (_) {
    return TextStyle(fontSize: size, color: color, fontWeight: w, height: 1.15);
  }
}

/// Слой со всеми наложениями (для просмотра — без жестов).
class StoryOverlayLayer extends StatelessWidget {
  final List<Map<String, dynamic>> overlays;
  final bool animate;
  const StoryOverlayLayer({super.key, required this.overlays, this.animate = true});

  @override
  Widget build(BuildContext context) {
    if (overlays.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      return Stack(
        clipBehavior: Clip.none,
        children: [
          for (final o in overlays)
            placeOverlay(
              o,
              c.biggest,
              StoryOverlayView(data: o, animate: animate, maxWidth: c.maxWidth * 0.86),
            ),
        ],
      );
    });
  }
}

/// Поставить элемент по его x/y/scale/rot.
Widget placeOverlay(Map<String, dynamic> o, Size size, Widget child) {
  final x = ((o['x'] as num?) ?? 0.5).toDouble();
  final y = ((o['y'] as num?) ?? 0.5).toDouble();
  final sc = ((o['scale'] as num?) ?? 1).toDouble();
  final rot = ((o['rot'] as num?) ?? 0).toDouble();
  return Positioned(
    left: x * size.width,
    top: y * size.height,
    child: FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: Transform.rotate(
        angle: rot,
        child: Transform.scale(scale: sc, child: child),
      ),
    ),
  );
}

/// Один элемент наложения.
class StoryOverlayView extends StatefulWidget {
  final Map<String, dynamic> data;
  final bool animate;
  final double maxWidth;
  const StoryOverlayView({super.key, required this.data, this.animate = true, this.maxWidth = 320});

  @override
  State<StoryOverlayView> createState() => _StoryOverlayViewState();
}

class _StoryOverlayViewState extends State<StoryOverlayView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 3));

  bool get _needsAnim {
    final t = widget.data['type'];
    if (t == 'sticker') return true;
    if (t != 'text') return false;
    return const {'neon', 'gradient', 'wave', 'typewriter'}.contains(widget.data['style']);
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StoryOverlayView old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.animate && _needsAnim && appState.motion;
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    return switch (d['type']) {
      'text' => AnimatedBuilder(animation: _c, builder: (_, __) => _text(d, _c.value)),
      'sticker' => AnimatedBuilder(
          animation: _c, builder: (_, __) => StorySticker(id: d['id'] as String? ?? 'hello', t: _c.value)),
      'emoji' => Text(d['emoji'] as String? ?? '✨',
          style: const TextStyle(fontSize: 72, shadows: [Shadow(blurRadius: 12, color: Color(0x55000000))])),
      'weather' => _WeatherChip(d: d),
      'time' => _TimeChip(d: d),
      _ => const SizedBox.shrink(),
    };
  }

  Widget _text(Map<String, dynamic> d, double t) {
    final text = (d['text'] as String? ?? '').trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final style = d['style'] as String? ?? 'plain';
    final color = _hex(d['color'] as String?);
    final font = d['font'] as String?;
    final base = storyFont(font, color: color);
    Widget w;
    switch (style) {
      case 'box':
        final dark = color.computeLuminance() > 0.55;
        w = Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(14)),
          child: Text(text,
              textAlign: TextAlign.center,
              style: storyFont(font, color: dark ? const Color(0xFF111111) : Colors.white, size: 26)),
        );
      case 'neon':
        final glow = 0.6 + 0.4 * math.sin(t * 2 * math.pi * 1.5).abs();
        w = Text(text,
            textAlign: TextAlign.center,
            style: base.copyWith(color: Colors.white, shadows: [
              Shadow(color: color.withValues(alpha: glow), blurRadius: 6),
              Shadow(color: color.withValues(alpha: glow), blurRadius: 16),
              Shadow(color: color.withValues(alpha: glow * 0.8), blurRadius: 32),
            ]));
      case 'outline':
        w = Stack(
          children: [
            Text(text,
                textAlign: TextAlign.center,
                style: base.copyWith(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = 5
                      ..color = color.computeLuminance() > 0.5 ? Colors.black : Colors.white)),
            Text(text, textAlign: TextAlign.center, style: base),
          ],
        );
      case 'gradient':
        w = ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (r) => LinearGradient(
            begin: Alignment(-1 + 2 * t - 1, 0),
            end: Alignment(1 + 2 * t - 1, 0),
            colors: const [
              Color(0xFFFF4D6D), Color(0xFFFFB347), Color(0xFFFFE14D), Color(0xFF2EE59D),
              Color(0xFF3ABEFF), Color(0xFF7B61FF), Color(0xFFFF4D6D),
            ],
            tileMode: TileMode.mirror,
          ).createShader(r),
          child: Text(text,
              textAlign: TextAlign.center,
              style: base.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 1)])),
        );
      case 'wave':
        final lines = text.split('\n');
        w = Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final line in lines)
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < line.characters.length; i++)
                    Transform.translate(
                      offset: Offset(0, math.sin(t * 2 * math.pi * 2 + i * 0.55) * 6),
                      child: Text(line.characters.elementAt(i),
                          style: base.copyWith(
                              shadows: const [Shadow(blurRadius: 8, color: Color(0x88000000))])),
                    ),
                ],
              ),
          ],
        );
      case 'typewriter':
        final chars = text.characters.length;
        // печатаем за первые 60% цикла, потом держим и мигаем курсором
        // без анимации (выключена в настройках) — сразу весь текст
        final k = widget.animate && _c.isAnimating ? math.min(1.0, t / 0.6) : 1.0;
        final n = math.max(0, math.min(chars, (chars * k).ceil()));
        final cursor = (t * 6).floor().isEven ? '▍' : ' ';
        w = Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('${text.characters.take(n)}$cursor',
              textAlign: TextAlign.left,
              style: storyFont('JetBrains Mono', color: color, size: 22, w: FontWeight.w700)),
        );
      default:
        w = Text(text,
            textAlign: TextAlign.center,
            style: base.copyWith(shadows: const [
              Shadow(blurRadius: 10, color: Color(0x99000000)),
              Shadow(blurRadius: 2, color: Color(0x66000000)),
            ]));
    }
    return ConstrainedBox(constraints: BoxConstraints(maxWidth: widget.maxWidth), child: w);
  }
}

/// Свои стикеры, нарисованные кодом (со своей анимацией).
class StorySticker extends StatelessWidget {
  final String id;
  final double t;
  final double size;
  const StorySticker({super.key, required this.id, this.t = 0, this.size = 1});

  @override
  Widget build(BuildContext context) {
    final wave = math.sin(t * 2 * math.pi);
    if (id.startsWith('st_')) {
      // картинка-стикер: мягко покачивается и «дышит»
      return Transform.rotate(
        angle: wave * 0.06,
        child: Transform.scale(
          scale: 1 + 0.03 * wave.abs(),
          child: Image.asset(
            'assets/stickers/$id.webp',
            width: 170 * size,
            height: 170 * size,
            filterQuality: FilterQuality.high,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => Text('✨', style: TextStyle(fontSize: 80 * size)),
          ),
        ),
      );
    }
    switch (id) {
      case 'connecto':
        final a = appState.accent;
        return Transform.rotate(
          angle: wave * 0.05,
          child: Container(
            padding: EdgeInsets.fromLTRB(10 * size, 8 * size, 16 * size, 8 * size),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [a, HSLColor.fromColor(a).withLightness(0.72).toColor()]),
              borderRadius: BorderRadius.circular(22 * size),
              boxShadow: [BoxShadow(color: a.withValues(alpha: 0.5), blurRadius: 18 * size)],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 34 * size,
                  height: 34 * size,
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: Text('C',
                      style: TextStyle(color: a, fontWeight: FontWeight.w900, fontSize: 20 * size)),
                ),
                SizedBox(width: 8 * size),
                Text('Connecto',
                    style: storyFont('Unbounded', size: 20 * size, color: Colors.white)),
              ],
            ),
          ),
        );
      case 'cool':
        return Transform.rotate(
          angle: -0.12 + wave * 0.06,
          child: Transform.scale(
            scale: 1 + 0.05 * wave.abs(),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 18 * size, vertical: 10 * size),
              decoration: BoxDecoration(
                color: const Color(0xFFFFE14D),
                borderRadius: BorderRadius.circular(8 * size),
                border: Border.all(color: Colors.black, width: 3 * size),
                boxShadow: [BoxShadow(color: Colors.black, offset: Offset(5 * size, 5 * size))],
              ),
              child: Text('КРУТО! 🔥',
                  style: storyFont('Unbounded', size: 22 * size, color: Colors.black, w: FontWeight.w900)),
            ),
          ),
        );
      default: // hello
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: 18 * size, vertical: 10 * size),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22 * size),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 14 * size)],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Привет!',
                      style: storyFont('Caveat', size: 30 * size, color: const Color(0xFF111111), w: FontWeight.w700)),
                  SizedBox(width: 6 * size),
                  Transform.rotate(
                    angle: wave * 0.5,
                    alignment: Alignment.bottomRight,
                    child: Text('👋', style: TextStyle(fontSize: 28 * size)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: 20 * size),
              child: CustomPaint(size: Size(18 * size, 12 * size), painter: _TailPainter()),
            ),
          ],
        );
    }
  }
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawPath(
      Path()
        ..moveTo(0, 0)
        ..lineTo(s.width, 0)
        ..lineTo(s.width * 0.2, s.height)
        ..close(),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Стили виджетов погоды/времени: glass → solid → minimal.
const List<String> kChipStyles = ['glass', 'solid', 'minimal'];

BoxDecoration _chipDeco(String style) => switch (style) {
      'solid' => BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
      'minimal' => const BoxDecoration(),
      _ => BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.45)),
        ),
    };

class _WeatherChip extends StatelessWidget {
  final Map<String, dynamic> d;
  const _WeatherChip({required this.d});

  @override
  Widget build(BuildContext context) {
    final style = d['style'] as String? ?? 'glass';
    final fg = style == 'solid' ? const Color(0xFF111111) : Colors.white;
    final city = (d['city'] as String? ?? '').trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: _chipDeco(style),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d['emoji'] as String? ?? '🌡', style: const TextStyle(fontSize: 34)),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${d['temp'] ?? 0}°',
                  style: storyFont('Unbounded', size: 26, color: fg, w: FontWeight.w800).copyWith(
                      shadows: style == 'minimal' ? const [Shadow(blurRadius: 10)] : null)),
              if (city.isNotEmpty || (d['text'] as String? ?? '').isNotEmpty)
                Text(city.isNotEmpty ? city : d['text'] as String,
                    style: TextStyle(
                        color: fg.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        shadows: style == 'minimal' ? const [Shadow(blurRadius: 8)] : null)),
            ],
          ),
        ],
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  final Map<String, dynamic> d;
  const _TimeChip({required this.d});

  @override
  Widget build(BuildContext context) {
    final style = d['style'] as String? ?? 'glass';
    final fg = style == 'solid' ? const Color(0xFF111111) : Colors.white;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: _chipDeco(style),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(d['time'] as String? ?? '',
              style: storyFont('Unbounded', size: 32, color: fg, w: FontWeight.w800)
                  .copyWith(shadows: style == 'minimal' ? const [Shadow(blurRadius: 10)] : null)),
          if ((d['date'] as String? ?? '').isNotEmpty)
            Text(d['date'] as String,
                style: TextStyle(color: fg.withValues(alpha: 0.85), fontWeight: FontWeight.w700, fontSize: 13)),
        ],
      ),
    );
  }
}
