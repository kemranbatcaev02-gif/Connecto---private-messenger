import 'dart:math' as math;
import 'dart:ui' show MaskFilter, BlurStyle;

import 'package:flutter/material.dart';

import '../app_state.dart';
import 'gift_widgets.dart';

// Оформление подарков: фон плашки × эффект частиц × анимация предмета.
// Подарок из админки хранит bg / fx / anim / symbol — приложение рисует всё само,
// поэтому новые сочетания появляются у всех без обновления.
// Всё зациклено на 6 секунд с целыми частотами — анимация без «шва».

class GiftStyleOpt {
  final String id;
  final String name;
  const GiftStyleOpt(this.id, this.name);
}

const List<GiftStyleOpt> kGiftBackdrops = [
  GiftStyleOpt('auto', 'Классика'),
  GiftStyleOpt('none', 'Без фона'),
  GiftStyleOpt('soft', 'Мягкий'),
  GiftStyleOpt('glow', 'Свечение'),
  GiftStyleOpt('gradient', 'Градиент'),
  GiftStyleOpt('aurora', 'Сияние'),
  GiftStyleOpt('rays', 'Лучи'),
  GiftStyleOpt('starry', 'Звёздная ночь'),
  GiftStyleOpt('gold', 'Золото'),
  GiftStyleOpt('neon', 'Неон'),
  GiftStyleOpt('holo', 'Голограмма'),
  GiftStyleOpt('pattern', 'Узор'),
  GiftStyleOpt('velvet', 'Бархат'),
  GiftStyleOpt('sunset', 'Закат'),
];

const List<GiftStyleOpt> kGiftEffects = [
  GiftStyleOpt('auto', 'Классика'),
  GiftStyleOpt('none', 'Без эффекта'),
  GiftStyleOpt('sparkles', 'Искры'),
  GiftStyleOpt('stars', 'Звёзды'),
  GiftStyleOpt('bubbles', 'Пузырьки'),
  GiftStyleOpt('snow', 'Снег'),
  GiftStyleOpt('embers', 'Угольки'),
  GiftStyleOpt('fireflies', 'Светлячки'),
  GiftStyleOpt('hearts', 'Сердечки'),
  GiftStyleOpt('confetti', 'Конфетти'),
  GiftStyleOpt('orbit', 'Орбита'),
  GiftStyleOpt('shine', 'Блик'),
  GiftStyleOpt('float', 'Свой символ'),
];

const List<GiftStyleOpt> kGiftAnims = [
  GiftStyleOpt('auto', 'Классика'),
  GiftStyleOpt('none', 'Стоит'),
  GiftStyleOpt('float', 'Парит'),
  GiftStyleOpt('bounce', 'Прыгает'),
  GiftStyleOpt('pulse', 'Пульс'),
  GiftStyleOpt('swing', 'Качается'),
  GiftStyleOpt('wobble', 'Танцует'),
  GiftStyleOpt('spin', 'Кружится'),
];

String giftStyleName(List<GiftStyleOpt> list, String? id) =>
    list.firstWhere((o) => o.id == (id ?? 'auto'), orElse: () => list.first).name;

/// У подарка задано своё оформление (иначе — классический вид по редкости).
bool giftHasCustomStyle(Map<String, dynamic> g) {
  bool set(String k) {
    final v = g[k];
    return v is String && v.isNotEmpty && v != 'auto';
  }

  return set('bg') || set('fx') || set('anim');
}

/// Что выбрать по умолчанию для новой редкости (в админке).
({String bg, String fx, String anim}) giftDefaultStyle(String rarity) => switch (rarity) {
      'rare' => (bg: 'gradient', fx: 'sparkles', anim: 'float'),
      'epic' => (bg: 'aurora', fx: 'orbit', anim: 'swing'),
      'legendary' => (bg: 'rays', fx: 'stars', anim: 'pulse'),
      _ => (bg: 'glow', fx: 'sparkles', anim: 'float'),
    };

// ── детерминированный «случай»: одинаковая картинка на всех устройствах ──
double _rnd(int seed, int i, int k) {
  var x = (seed * 73856093) ^ (i * 19349663) ^ (k * 83492791);
  x = (x ^ (x >> 13)) * 1274126177;
  x = x ^ (x >> 16);
  return (x & 0xFFFFFF) / 0xFFFFFF;
}

Color _lighten(Color c, double v) {
  final h = HSLColor.fromColor(c);
  return h.withLightness((h.lightness + v).clamp(0.0, 1.0)).toColor();
}

Color _darken(Color c, double v) => _lighten(c, -v);

/// Подарок в своём оформлении.
class GiftCustomArt extends StatefulWidget {
  final Map<String, dynamic> gift;
  final double size;
  final bool animate;
  const GiftCustomArt({super.key, required this.gift, required this.size, this.animate = true});

  @override
  State<GiftCustomArt> createState() => _GiftCustomArtState();
}

class _GiftCustomArtState extends State<GiftCustomArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 6000));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant GiftCustomArt old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final run = widget.animate && appState.motion;
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
    if (!run) _c.value = 0.15; // статичный кадр — красивый, а не «нулевой»
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  String _v(String k, String def) {
    final v = widget.gift[k];
    return v is String && v.isNotEmpty && v != 'auto' ? v : def;
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gift;
    final s = widget.size;
    final rarity = g['rarity'] as String? ?? 'common';
    final def = giftDefaultStyle(rarity);
    final bg = _v('bg', def.bg);
    final fx = _v('fx', def.fx);
    final anim = _v('anim', def.anim);
    final id = g['id'] as String? ?? '';
    final emoji = g['emoji'] as String? ?? '🎁';
    final symbol = (g['symbol'] as String?)?.trim();
    final custom = (g['colors'] as List?)?.whereType<String>().map(hexColor).toList();
    final base = rarityColor(rarity == 'common' ? 'common' : rarity);
    final c0 = custom != null && custom.isNotEmpty
        ? custom[0]
        : (rarity == 'common' ? appState.accent : _lighten(base, 0.12));
    final c1 = custom != null && custom.length > 1 ? custom[1] : _darken(c0, 0.28);
    final seed = id.hashCode;
    final r = BorderRadius.circular(s * 0.28);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final plate = bg != 'none';

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final wave = math.sin(t * 2 * math.pi * 2);
          final up = (wave + 1) / 2;
          // предмет
          double lift = 0, scale = 1, angle = 0, flip = 1;
          switch (anim) {
            case 'float':
              lift = 0.035 * up;
              break;
            case 'bounce':
              final b = (math.sin(t * 2 * math.pi * 3)).abs();
              lift = 0.07 * b;
              scale = 1 + 0.03 * (1 - b);
              break;
            case 'pulse':
              scale = 1 + 0.06 * up;
              break;
            case 'swing':
              angle = math.sin(t * 2 * math.pi * 2) * 0.12;
              lift = 0.015 * up;
              break;
            case 'wobble':
              angle = math.sin(t * 2 * math.pi * 3) * 0.08;
              scale = 1 + 0.04 * math.sin(t * 2 * math.pi * 6).abs();
              lift = 0.02 * up;
              break;
            case 'spin':
              flip = math.cos(t * 2 * math.pi); // поворот вокруг вертикальной оси
              lift = 0.02 * up;
              break;
          }
          final img = s * 0.8;
          Widget object = GiftImage(
              id: id, emoji: emoji, size: img, url: g['image_url'] as String?);
          if (anim == 'spin') {
            object = Transform.scale(
              scaleX: flip.abs() < 0.08 ? 0.08 : flip.abs(),
              scaleY: 1,
              child: object,
            );
          }
          final objectLayer = Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                bottom: s * 0.085,
                child: Container(
                  width: img * (0.6 - lift * 0.9),
                  height: s * 0.07,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(s),
                    gradient: RadialGradient(colors: [
                      Colors.black.withValues(alpha: (0.3 - lift * 1.2).clamp(0.0, 1.0)),
                      Colors.black.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, -lift * s),
                child: Transform.rotate(
                  angle: angle,
                  child: Transform.scale(scale: scale, child: object),
                ),
              ),
            ],
          );
          final behind = fx != 'snow' && fx != 'confetti' && fx != 'shine' && fx != 'sparkles';
          final stack = Stack(
            fit: StackFit.expand,
            children: [
              if (plate)
                CustomPaint(
                    painter: _Backdrop(
                        kind: bg, t: t, c0: c0, c1: c1, seed: seed, dark: dark,
                        symbol: symbol)),
              if (behind || fx == 'orbit')
                CustomPaint(
                    painter: _Particles(
                        kind: fx, t: t, c0: c0, seed: seed, front: false, symbol: symbol,
                        onPlate: plate)),
              if (g['object'] != false) objectLayer,
              if (!behind || fx == 'orbit')
                CustomPaint(
                    painter: _Particles(
                        kind: fx, t: t, c0: c0, seed: seed, front: true, symbol: symbol,
                        onPlate: plate)),
            ],
          );
          if (!plate) return SizedBox(width: s, height: s, child: stack);
          final legendary = rarity == 'legendary';
          return Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              borderRadius: r,
              border: legendary
                  ? Border.all(
                      color: const Color(0xFFFFE9A6).withValues(alpha: 0.75 + 0.25 * up),
                      width: math.max(1.2, s * 0.018))
                  : (rarity == 'epic'
                      ? Border.all(color: _lighten(c0, 0.2).withValues(alpha: 0.55), width: 1)
                      : null),
              boxShadow: rarity == 'common' || s < 44
                  ? null
                  : [
                      BoxShadow(
                        color: c0.withValues(alpha: (legendary ? 0.45 : 0.3) + 0.15 * up),
                        blurRadius: s * (legendary ? 0.3 : 0.2),
                        offset: Offset(0, s * 0.05),
                      ),
                    ],
            ),
            child: ClipRRect(borderRadius: r, child: stack),
          );
        },
      ),
    );
  }
}

// ═════════════════════════════════ фоны ═════════════════════════════════

class _Backdrop extends CustomPainter {
  final String kind;
  final double t;
  final Color c0, c1;
  final int seed;
  final bool dark;
  final String? symbol;
  _Backdrop(
      {required this.kind,
      required this.t,
      required this.c0,
      required this.c1,
      required this.seed,
      required this.dark,
      this.symbol});

  static final Map<String, TextPainter> _glyphs = {};

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final w = size.width;
    final a = t * 2 * math.pi;
    final p = Paint();
    switch (kind) {
      case 'soft':
        final b = dark ? Colors.white : Colors.black;
        p.shader = RadialGradient(
          center: const Alignment(0, -0.35),
          radius: 0.9,
          colors: [b.withValues(alpha: dark ? 0.12 : 0.04), b.withValues(alpha: dark ? 0.05 : 0.08)],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        // мягкий цветной ореол за предметом
        p.shader = RadialGradient(colors: [
          c0.withValues(alpha: 0.22 + 0.06 * math.sin(a * 2)),
          c0.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: rect.center, radius: w * 0.45));
        canvas.drawCircle(rect.center, w * 0.45, p);
        break;
      case 'glow':
        p.shader = RadialGradient(
          center: Alignment(0, -0.1 + 0.05 * math.sin(a)),
          radius: 0.85,
          colors: [_lighten(c0, 0.18), c0, c1],
          stops: const [0, 0.5, 1],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        break;
      case 'gradient':
        p.shader = LinearGradient(
          begin: Alignment(math.cos(a), math.sin(a)),
          end: Alignment(-math.cos(a), -math.sin(a)),
          colors: [_lighten(c0, 0.08), c1],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        break;
      case 'aurora':
        canvas.drawRect(rect, Paint()..color = _darken(c1, 0.12));
        final blobs = [
          (c0, 0.0, 0.42),
          (_lighten(c0, 0.2), 0.33, 0.36),
          (Color.lerp(c0, const Color(0xFF7DF9FF), 0.45)!, 0.66, 0.34),
        ];
        for (final (col, ph, rad) in blobs) {
          final ang = a + ph * 2 * math.pi;
          final c = Offset(w * (0.5 + 0.28 * math.cos(ang)), w * (0.5 + 0.22 * math.sin(ang * 2)));
          p.shader = RadialGradient(colors: [col.withValues(alpha: 0.85), col.withValues(alpha: 0)])
              .createShader(Rect.fromCircle(center: c, radius: w * rad * 1.5));
          canvas.drawCircle(c, w * rad * 1.5, p);
        }
        break;
      case 'rays':
        p.shader = RadialGradient(colors: [_lighten(c0, 0.15), c1]).createShader(rect);
        canvas.drawRect(rect, p);
        final c = rect.center;
        final rp = Paint()..color = Colors.white.withValues(alpha: 0.13);
        const n = 12;
        for (var i = 0; i < n; i++) {
          final s0 = a / 3 + i * 2 * math.pi / n;
          final path = Path()
            ..moveTo(c.dx, c.dy)
            ..lineTo(c.dx + w * math.cos(s0), c.dy + w * math.sin(s0))
            ..lineTo(c.dx + w * math.cos(s0 + 0.2), c.dy + w * math.sin(s0 + 0.2))
            ..close();
          canvas.drawPath(path, rp);
        }
        p.shader = RadialGradient(
                colors: [Colors.white.withValues(alpha: 0.35), Colors.white.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: c, radius: w * 0.35));
        canvas.drawCircle(c, w * 0.35, p);
        break;
      case 'starry':
        p.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFF060816), Color.lerp(c1, const Color(0xFF0B1030), 0.5)!],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        p.shader = RadialGradient(colors: [c0.withValues(alpha: 0.45), c0.withValues(alpha: 0)])
            .createShader(Rect.fromCircle(center: rect.center, radius: w * 0.42));
        canvas.drawCircle(rect.center, w * 0.42, p);
        final sp = Paint()..color = Colors.white;
        for (var i = 0; i < 26; i++) {
          final x = _rnd(seed, i, 1) * w, y = _rnd(seed, i, 2) * w;
          final tw = math.pow(math.sin(((t * (1 + i % 3) + _rnd(seed, i, 3)) % 1) * math.pi), 2);
          sp.color = Colors.white.withValues(alpha: 0.25 + 0.75 * tw.toDouble());
          canvas.drawCircle(Offset(x, y), w * (0.006 + 0.008 * _rnd(seed, i, 4)), sp);
        }
        break;
      case 'gold':
        p.shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF4C2), Color(0xFFF5C451), Color(0xFFB7791F), Color(0xFFFFE08A)],
          stops: [0, 0.35, 0.7, 1],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        _sweep(canvas, size, t, 0.45);
        break;
      case 'neon':
        canvas.drawRect(rect, Paint()..color = const Color(0xFF07060F));
        p.shader = RadialGradient(colors: [c0.withValues(alpha: 0.35), c0.withValues(alpha: 0)])
            .createShader(rect);
        canvas.drawRect(rect, p);
        final pulse = 0.6 + 0.4 * math.sin(a * 2).abs();
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..color = _lighten(c0, 0.15).withValues(alpha: pulse)
          ..maskFilter = MaskFilter.blur(BlurStyle.solid, w * 0.03);
        canvas.drawCircle(rect.center, w * 0.38, ring);
        break;
      case 'holo':
        p.shader = SweepGradient(
          transform: GradientRotation(a),
          colors: const [
            Color(0xFFFFB3E6), Color(0xFFB3D9FF), Color(0xFFB3FFE0),
            Color(0xFFFFF5B3), Color(0xFFFFB3E6),
          ],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        canvas.drawRect(rect, Paint()..color = Colors.white.withValues(alpha: 0.25));
        _sweep(canvas, size, t, 0.35);
        break;
      case 'pattern':
        p.shader = RadialGradient(colors: [_lighten(c0, 0.1), c1]).createShader(rect);
        canvas.drawRect(rect, p);
        final sym = (symbol == null || symbol!.isEmpty) ? '✦' : symbol!;
        final tp = _glyph(sym, w * 0.11, Colors.white.withValues(alpha: 0.18));
        final step = w / 4;
        final off = (t * step) % step;
        for (var row = -1; row < 5; row++) {
          for (var col = -1; col < 5; col++) {
            final x = col * step + (row.isEven ? 0 : step / 2) + off;
            final y = row * step + off;
            tp.paint(canvas, Offset(x - tp.width / 2, y - tp.height / 2));
          }
        }
        break;
      case 'velvet':
        p.shader = RadialGradient(
          center: const Alignment(0, -0.2),
          radius: 0.95,
          colors: [_darken(c0, 0.05), _darken(c1, 0.18), const Color(0xFF050308)],
          stops: const [0, 0.6, 1],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        break;
      case 'sunset':
        p.shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_lighten(c0, 0.2), c0, c1],
        ).createShader(rect);
        canvas.drawRect(rect, p);
        final sun = Offset(w * 0.5, w * (0.62 + 0.03 * math.sin(a)));
        p.shader = RadialGradient(colors: [
          const Color(0xFFFFF1B8).withValues(alpha: 0.9),
          const Color(0xFFFFC46B).withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: sun, radius: w * 0.4));
        canvas.drawCircle(sun, w * 0.4, p);
        break;
      default:
        canvas.drawRect(rect, Paint()..color = c0);
    }
  }

  /// Бегущий диагональный блик.
  static void _sweep(Canvas canvas, Size size, double t, double alpha) {
    final w = size.width;
    final x = -w + (t * 2 % 1) * w * 3;
    final paint = Paint()
      ..shader = LinearGradient(colors: [
        Colors.white.withValues(alpha: 0),
        Colors.white.withValues(alpha: alpha),
        Colors.white.withValues(alpha: 0),
      ]).createShader(Rect.fromLTWH(x, 0, w * 0.5, w));
    canvas.save();
    canvas.translate(x + w * 0.25, w / 2);
    canvas.rotate(0.5);
    canvas.translate(-(x + w * 0.25), -w / 2);
    canvas.drawRect(Rect.fromLTWH(x, -w, w * 0.5, w * 3), paint);
    canvas.restore();
  }

  static TextPainter _glyph(String s, double size, Color color) {
    final key = '$s|${size.round()}|${color.toARGB32()}';
    return _glyphs[key] ??= (TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size, color: color)),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  @override
  bool shouldRepaint(covariant _Backdrop o) =>
      o.t != t || o.kind != kind || o.c0 != c0 || o.c1 != c1 || o.symbol != symbol;
}

// ═════════════════════════════════ частицы ═════════════════════════════════

class _Particles extends CustomPainter {
  final String kind;
  final double t;
  final Color c0;
  final int seed;
  final bool front;
  final String? symbol;
  final bool onPlate;
  _Particles(
      {required this.kind,
      required this.t,
      required this.c0,
      required this.seed,
      required this.front,
      this.symbol,
      required this.onPlate});

  static final Map<String, TextPainter> _glyphs = {};

  Color get _ink => onPlate ? Colors.white : _lighten(c0, 0.1);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final p = Paint();
    switch (kind) {
      case 'sparkles':
        for (var i = 0; i < 9; i++) {
          final tw = _tw(i, 1 + i % 2);
          if (tw < 0.05) continue;
          final pos = Offset(w * (0.1 + 0.8 * _rnd(seed, i, 1)), w * (0.1 + 0.8 * _rnd(seed, i, 2)));
          p.color = _ink.withValues(alpha: tw);
          _star4(canvas, pos, w * (0.018 + 0.02 * _rnd(seed, i, 3)) * (0.5 + tw), p);
        }
        break;
      case 'stars':
        for (var i = 0; i < 7; i++) {
          final tw = _tw(i, 1);
          final ang = (t + i / 7) * 2 * math.pi;
          final rad = w * (0.34 + 0.06 * _rnd(seed, i, 1));
          final pos = Offset(w / 2 + rad * math.cos(ang), w / 2 + rad * 0.8 * math.sin(ang));
          p.color = const Color(0xFFFFE27A).withValues(alpha: 0.4 + 0.6 * tw);
          _star5(canvas, pos, w * (0.03 + 0.015 * tw), p);
        }
        break;
      case 'bubbles':
        p
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, w * 0.008);
        for (var i = 0; i < 9; i++) {
          final sp = 1 + i % 2;
          final y = 1.1 - ((t * sp + _rnd(seed, i, 1)) % 1) * 1.25;
          final x = 0.12 + 0.76 * _rnd(seed, i, 2) + 0.03 * math.sin((t * 2 + i) * 2 * math.pi);
          final rr = w * (0.02 + 0.035 * _rnd(seed, i, 3));
          p.color = _ink.withValues(alpha: 0.55 * _fade(y));
          canvas.drawCircle(Offset(w * x, w * y), rr, p);
          canvas.drawCircle(Offset(w * x - rr * 0.35, w * y - rr * 0.35), rr * 0.18,
              Paint()..color = Colors.white.withValues(alpha: 0.7 * _fade(y)));
        }
        break;
      case 'snow':
        p.color = Colors.white;
        for (var i = 0; i < 16; i++) {
          final sp = 1 + i % 2;
          final y = -0.05 + ((t * sp + _rnd(seed, i, 1)) % 1) * 1.1;
          final x = _rnd(seed, i, 2) + 0.04 * math.sin((t * 3 + _rnd(seed, i, 3)) * 2 * math.pi);
          p.color = Colors.white.withValues(alpha: 0.9 * _fade(y));
          canvas.drawCircle(Offset(w * (x % 1), w * y), w * (0.008 + 0.012 * _rnd(seed, i, 4)), p);
        }
        break;
      case 'embers':
        for (var i = 0; i < 12; i++) {
          final y = 1.05 - ((t * (1 + i % 3) + _rnd(seed, i, 1)) % 1) * 1.15;
          final x = 0.15 + 0.7 * _rnd(seed, i, 2) + 0.05 * math.sin((t * 2 + i) * 2 * math.pi);
          final col = Color.lerp(const Color(0xFFFFD166), const Color(0xFFFF5E3A), _rnd(seed, i, 3))!;
          p
            ..color = col.withValues(alpha: 0.9 * _fade(y))
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.008);
          canvas.drawCircle(Offset(w * x, w * y), w * (0.01 + 0.012 * _rnd(seed, i, 4)), p);
        }
        break;
      case 'fireflies':
        for (var i = 0; i < 9; i++) {
          final ph = _rnd(seed, i, 1) * 2 * math.pi;
          final x = 0.5 + 0.38 * math.sin(t * 2 * math.pi + ph) * _rnd(seed, i, 2);
          final y = 0.5 + 0.36 * math.cos(t * 2 * math.pi * 2 + ph) * _rnd(seed, i, 3);
          final tw = _tw(i, 2);
          p
            ..color = const Color(0xFFE8FF8A).withValues(alpha: 0.3 + 0.7 * tw)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.012);
          canvas.drawCircle(Offset(w * x, w * y), w * 0.018, p);
        }
        break;
      case 'hearts':
        for (var i = 0; i < 8; i++) {
          final y = 1.05 - ((t * (1 + i % 2) + _rnd(seed, i, 1)) % 1) * 1.15;
          final x = 0.12 + 0.76 * _rnd(seed, i, 2) + 0.04 * math.sin((t * 2 + i) * 2 * math.pi);
          p.color = Color.lerp(const Color(0xFFFF5E8A), const Color(0xFFFFB3C7), _rnd(seed, i, 3))!
              .withValues(alpha: 0.9 * _fade(y));
          _heart(canvas, Offset(w * x, w * y), w * (0.035 + 0.025 * _rnd(seed, i, 4)), p);
        }
        break;
      case 'confetti':
        const cols = [
          Color(0xFFFF5E8A), Color(0xFFFFD166), Color(0xFF4ADE80),
          Color(0xFF60A5FA), Color(0xFFC084FC),
        ];
        for (var i = 0; i < 16; i++) {
          final y = -0.05 + ((t * (1 + i % 2) + _rnd(seed, i, 1)) % 1) * 1.1;
          final x = _rnd(seed, i, 2);
          canvas.save();
          canvas.translate(w * x, w * y);
          canvas.rotate((t * (2 + i % 3) + _rnd(seed, i, 3)) * 2 * math.pi);
          p.color = cols[i % cols.length].withValues(alpha: 0.95 * _fade(y));
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: w * 0.035, height: w * 0.018), p);
          canvas.restore();
        }
        break;
      case 'orbit':
        final c = Offset(w / 2, w / 2);
        final ring = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, w * 0.01)
          ..color = _ink.withValues(alpha: 0.35);
        // кольцо рисуем половинками: задняя — за предметом, передняя — перед ним
        final oval = Rect.fromCenter(center: c, width: w * 0.86, height: w * 0.3);
        canvas.save();
        canvas.translate(c.dx, c.dy);
        canvas.rotate(-0.35);
        canvas.translate(-c.dx, -c.dy);
        canvas.drawArc(oval, front ? 0 : math.pi, math.pi, false, ring);
        for (var i = 0; i < 3; i++) {
          final ang = (t * (i.isEven ? 1 : 2) + i / 3) * 2 * math.pi;
          final inFront = math.sin(ang) > 0;
          if (inFront != front) continue;
          final pos = Offset(c.dx + w * 0.43 * math.cos(ang), c.dy + w * 0.15 * math.sin(ang));
          final dot = Paint()
            ..color = _ink
            ..maskFilter = MaskFilter.blur(BlurStyle.solid, w * 0.012);
          canvas.drawCircle(pos, w * (0.02 + 0.008 * math.sin(ang)), dot);
        }
        canvas.restore();
        break;
      case 'shine':
        _Backdrop._sweep(canvas, size, t, 0.5);
        final tw = _tw(0, 2);
        p.color = Colors.white.withValues(alpha: tw);
        _star4(canvas, Offset(w * 0.68, w * 0.28), w * 0.04 * (0.4 + tw), p);
        break;
      case 'float':
        final sym = (symbol == null || symbol!.isEmpty) ? '✨' : symbol!;
        for (var i = 0; i < 6; i++) {
          final y = 1.05 - ((t * (1 + i % 2) + _rnd(seed, i, 1)) % 1) * 1.15;
          final x = 0.1 + 0.8 * _rnd(seed, i, 2) + 0.05 * math.sin((t * 2 + i) * 2 * math.pi);
          final fs = w * (0.08 + 0.05 * _rnd(seed, i, 3));
          final tp = _glyph(sym, fs);
          canvas.save();
          canvas.translate(w * x, w * y);
          canvas.rotate(0.3 * math.sin((t * 2 + i / 6) * 2 * math.pi));
          canvas.saveLayer(null, Paint()..color = Colors.white.withValues(alpha: 0.85 * _fade(y)));
          tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
          canvas.restore();
          canvas.restore();
        }
        break;
    }
  }

  /// Мерцание 0..1..0 с целой частотой.
  double _tw(int i, int freq) =>
      math.pow(math.sin(((t * freq + _rnd(seed, i, 9)) % 1.0) * math.pi), 2).toDouble();

  /// Прозрачность у краёв (частица плавно появляется и исчезает).
  static double _fade(double y) => (math.min(y + 0.05, 1.05 - y) * 6).clamp(0.0, 1.0);

  static void _star4(Canvas canvas, Offset p, double r, Paint paint) {
    canvas.drawPath(
      Path()
        ..moveTo(p.dx, p.dy - r * 2)
        ..quadraticBezierTo(p.dx, p.dy, p.dx + r * 2, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + r * 2)
        ..quadraticBezierTo(p.dx, p.dy, p.dx - r * 2, p.dy)
        ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - r * 2)
        ..close(),
      paint,
    );
  }

  static void _star5(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? r : r * 0.45;
      final a = -math.pi / 2 + i * math.pi / 5;
      final pt = Offset(c.dx + rr * math.cos(a), c.dy + rr * math.sin(a));
      if (i == 0) {
        path.moveTo(pt.dx, pt.dy);
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
    }
    canvas.drawPath(path..close(), paint);
  }

  static void _heart(Canvas canvas, Offset c, double s, Paint paint) {
    final path = Path()
      ..moveTo(c.dx, c.dy + s * 0.35)
      ..cubicTo(c.dx - s * 0.9, c.dy - s * 0.2, c.dx - s * 0.35, c.dy - s * 0.85, c.dx, c.dy - s * 0.3)
      ..cubicTo(c.dx + s * 0.35, c.dy - s * 0.85, c.dx + s * 0.9, c.dy - s * 0.2, c.dx, c.dy + s * 0.35)
      ..close();
    canvas.drawPath(path, paint);
  }

  static TextPainter _glyph(String s, double size) {
    final key = '$s|${size.round()}';
    if (_glyphs.length > 64) _glyphs.clear();
    return _glyphs[key] ??= (TextPainter(
      text: TextSpan(text: s, style: TextStyle(fontSize: size)),
      textDirection: TextDirection.ltr,
    )..layout());
  }

  @override
  bool shouldRepaint(covariant _Particles o) =>
      o.t != t || o.kind != kind || o.c0 != c0 || o.front != front || o.symbol != symbol;
}
