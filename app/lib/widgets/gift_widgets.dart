import 'dart:math' as math;
import 'dart:ui' show MaskFilter, BlurStyle;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../theme.dart';
import '../screens/wallet_screen.dart';
import 'gift_reveal.dart';
import 'gift_styles.dart';
import 'ui.dart';

export 'gift_reveal.dart';
export 'gift_styles.dart';

/// '#RRGGBB' → Color.
Color hexColor(String hex) {
  final h = hex.replaceAll('#', '');
  return Color(int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16) ?? 0xFF6366F1);
}

// ─────────────────────────────────────────────────────────────
// Кристалл — премиальная внутренняя валюта
// ─────────────────────────────────────────────────────────────

class CoinIcon extends StatelessWidget {
  final double size;
  const CoinIcon({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return CrystalIcon(size: size);
  }
}

/// Сияющий многогранный кристалл — премиальная валюта Connecto.
class CrystalIcon extends StatelessWidget {
  final double size;
  const CrystalIcon({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: const _CrystalPainter(),
    );
  }
}

class _CrystalPainter extends CustomPainter {
  const _CrystalPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // Внешнее свечение для крупных кристаллов
    if (w >= 24) {
      final glowPaint = Paint()
        ..color = const Color(0xFF38BDF8).withValues(alpha: 0.35)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.22);
      canvas.drawCircle(Offset(w * 0.5, h * 0.48), w * 0.38, glowPaint);
    }

    // Точки огранки кристалла (классический бриллиант / кристалл)
    final pTopL = Offset(w * 0.25, h * 0.14);
    final pTopR = Offset(w * 0.75, h * 0.14);
    final pMidL = Offset(w * 0.08, h * 0.42);
    final pMidR = Offset(w * 0.92, h * 0.42);
    final pBottom = Offset(w * 0.50, h * 0.92);

    final pTableL = Offset(w * 0.35, h * 0.14);
    final pTableR = Offset(w * 0.65, h * 0.14);
    final pInnerL = Offset(w * 0.36, h * 0.42);
    final pInnerR = Offset(w * 0.64, h * 0.42);

    void drawFacet(List<Offset> points, List<Color> colors, [Alignment begin = Alignment.topLeft, Alignment end = Alignment.bottomRight]) {
      final path = Path()..moveTo(points[0].dx, points[0].dy);
      for (var i = 1; i < points.length; i++) {
        path.lineTo(points[i].dx, points[i].dy);
      }
      path.close();
      final bounds = path.getBounds();
      final paint = Paint()
        ..shader = LinearGradient(begin: begin, end: end, colors: colors).createShader(bounds)
        ..style = PaintingStyle.fill;
      canvas.drawPath(path, paint);
    }

    // 1. Нижние грани (павильон)
    // Нижняя левая грань (глубокий индиго / ультрамарин)
    drawFacet([pMidL, pInnerL, pBottom], const [Color(0xFF0284C7), Color(0xFF0369A1)]);
    // Нижняя центральная грань (яркий электрик-циан)
    drawFacet([pInnerL, pInnerR, pBottom], const [Color(0xFF38BDF8), Color(0xFF0284C7)]);
    // Нижняя правая грань (насыщенный синий с фиолетовым переливом)
    drawFacet([pInnerR, pMidR, pBottom], const [Color(0xFF0284C7), Color(0xFF4338CA)]);

    // 2. Верхние грани (корона)
    // Верхняя левая грань
    drawFacet([pTopL, pTableL, pInnerL, pMidL], const [Color(0xFFBAE6FD), Color(0xFF38BDF8)]);
    // Верхняя центральная грань (столб / стол)
    drawFacet([pTableL, pTableR, pInnerR, pInnerL], const [Color(0xFFE0F2FE), Color(0xFF7DD3FC)]);
    // Верхняя правая грань
    drawFacet([pTableR, pTopR, pMidR, pInnerR], const [Color(0xFF7DD3FC), Color(0xFF6366F1)]);

    // 3. Тонкие световые рёбра (specular lines)
    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.035).clamp(0.8, 2.0)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final outerPath = Path()
      ..moveTo(pTopL.dx, pTopL.dy)
      ..lineTo(pTopR.dx, pTopR.dy)
      ..lineTo(pMidR.dx, pMidR.dy)
      ..lineTo(pBottom.dx, pBottom.dy)
      ..lineTo(pMidL.dx, pMidL.dy)
      ..close();
    canvas.drawPath(outerPath, edgePaint);

    final innerLines = Path()
      ..moveTo(pInnerL.dx, pInnerL.dy)
      ..lineTo(pBottom.dx, pBottom.dy)
      ..moveTo(pInnerR.dx, pInnerR.dy)
      ..lineTo(pBottom.dx, pBottom.dy)
      ..moveTo(pInnerL.dx, pInnerL.dy)
      ..lineTo(pInnerR.dx, pInnerR.dy)
      ..moveTo(pTableL.dx, pTableL.dy)
      ..lineTo(pInnerL.dx, pInnerL.dy)
      ..moveTo(pTableR.dx, pTableR.dy)
      ..lineTo(pInnerR.dx, pInnerR.dy);
    canvas.drawPath(innerLines, Paint()
      ..color = Colors.white.withValues(alpha: 0.40)
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.025).clamp(0.6, 1.4));

    // 4. Искорка / блик в углу кристалла (для эффекта сияния)
    if (w >= 14) {
      final sX = w * 0.72;
      final sY = h * 0.22;
      final sR = w * 0.12;
      final starPaint = Paint()..color = Colors.white.withValues(alpha: 0.95);
      final star = Path()
        ..moveTo(sX, sY - sR)
        ..quadraticBezierTo(sX, sY, sX + sR, sY)
        ..quadraticBezierTo(sX, sY, sX, sY + sR)
        ..quadraticBezierTo(sX, sY, sX - sR, sY)
        ..quadraticBezierTo(sX, sY, sX, sY - sR)
        ..close();
      canvas.drawPath(star, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class CoinAmount extends StatelessWidget {
  final int amount;
  final double size;
  final Color? color;
  final bool plus;
  const CoinAmount(this.amount, {super.key, this.size = 15, this.color, this.plus = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CoinIcon(size: size * 1.15),
        SizedBox(width: size * 0.3),
        Text('${plus && amount > 0 ? '+' : ''}${fmtCoins(amount)}',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: size, color: color)),
      ],
    );
  }
}

String fmtCoins(int n) {
  final s = n.abs().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(' ');
    b.write(s[i]);
  }
  return n < 0 ? '−$b' : b.toString();
}

// ─────────────────────────────────────────────────────────────
// Подарок: чем дороже, тем эффектнее
// ─────────────────────────────────────────────────────────────

const Map<String, List<Color>> _giftColors = {
  'bouquet': [Color(0xFFFFA2C0), Color(0xFFFF5E8A)],
  'cake': [Color(0xFFFFC37D), Color(0xFFFF7A59)],
  'gamepad': [Color(0xFF6E9BFF), Color(0xFF7B5BFF)],
  'champagne': [Color(0xFF6BE3C4), Color(0xFF2A9D8F)],
  'ring': [Color(0xFFC6A2FF), Color(0xFF6A5BFF)],
  'trophy': [Color(0xFFFFC56B), Color(0xFFFF6A3D)],
  'rocket': [Color(0xFF5CC8FF), Color(0xFF8E54E9)],
  'diamond': [Color(0xFFE3FAFF), Color(0xFFFFD86B), Color(0xFFB8860B)],
  'crown': [Color(0xFFFFF0B3), Color(0xFFFFC928), Color(0xFFB8860B)],
  'dragon': [Color(0xFFFFD38A), Color(0xFFFF6B3D), Color(0xFF9E1B1B)],
};

/// Сезонный подарок: «до 01.11» (или «ещё 5 ч», если осталось меньше суток).
String? giftSaleCorner(Map<String, dynamic> g) {
  final until = parseServerTime(g['sale_until'] as String? ?? '');
  if (until == null) return null;
  final left = until.difference(DateTime.now());
  if (left.isNegative) return null;
  if (left.inHours < 24) return 'ещё ${math.max(1, left.inHours)} ч';
  return 'до ${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')}';
}

String rarityName(String r) => switch (r) {
      'rare' => 'Редкий',
      'epic' => 'Эпический',
      'legendary' => 'Легендарный',
      _ => 'Обычный',
    };

Color rarityColor(String r) => switch (r) {
      'rare' => const Color(0xFF3B82F6),
      'epic' => const Color(0xFFA855F7),
      'legendary' => const Color(0xFFF5A60B),
      _ => const Color(0xFF64748B),
    };

/// Подарки, у которых есть картинка (assets/gifts/<id>.webp).
const Set<String> kGiftImages = {
  'rose', 'chocolate', 'coffee', 'balloon', 'teddy', 'bouquet', 'cake', 'gamepad',
  'champagne', 'ring', 'trophy', 'rocket', 'diamond', 'crown', 'dragon',
};

/// Картинка подарка: загруженная из админки (url), встроенная или эмодзи.
class GiftImage extends StatelessWidget {
  final String id;
  final String emoji;
  final double size;
  final String? url;
  const GiftImage(
      {super.key, required this.id, required this.emoji, required this.size, this.url});

  @override
  Widget build(BuildContext context) {
    final fallback = Text(emoji, style: TextStyle(fontSize: size * 0.62));
    final dpr = MediaQuery.maybeOf(context)?.devicePixelRatio ?? 3;
    final u = url;
    if (u != null && u.isNotEmpty) {
      return Image.network(
        u.startsWith('http') ? u : '$kBaseUrl$u',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        gaplessPlayback: true,
        cacheWidth: math.min(640, (size * dpr).round()),
        errorBuilder: (_, __, ___) => Center(child: fallback),
        loadingBuilder: (_, child, p) => p == null ? child : Center(child: fallback),
      );
    }
    if (!kGiftImages.contains(id)) return fallback;
    return Image.asset(
      'assets/gifts/$id.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
      gaplessPlayback: true,
      cacheWidth: math.min(640, (size * dpr).round()),
      errorBuilder: (_, __, ___) => Center(child: fallback),
    );
  }
}

class GiftArt extends StatefulWidget {
  final Map<String, dynamic> gift;
  final double size;
  final bool animate;
  /// Улучшенный (уникальный) подарок: {no, backdrop:{colors}, pattern:{symbol}}.
  final Map<String, dynamic>? unique;
  const GiftArt(
      {super.key, required this.gift, this.size = 72, this.animate = true, this.unique});

  @override
  State<GiftArt> createState() => _GiftArtState();
}

class _GiftArtState extends State<GiftArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 6000));

  String get _rarity => widget.gift['rarity'] as String? ?? 'common';

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant GiftArt old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    // обычные подарки в маленьких плитках не анимируем — экономим батарею
    // своё оформление рисует GiftCustomArt со своим таймером — этот не крутим
    final run = widget.animate &&
        appState.motion &&
        !(widget.unique == null && giftHasCustomStyle(widget.gift)) &&
        (_rarity != 'common' || widget.unique != null || widget.size >= 90);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Предмет с мягкой тенью «на полу»: чем выше подпрыгнул — тем тень меньше.
  Widget _object(double s, String id, String emoji, double lift, {double scale = 1, double angle = 0}) {
    final img = s * 0.8;
    return Stack(
      alignment: Alignment.center,
      children: [
        Positioned(
          bottom: s * 0.085,
          child: Container(
            width: img * (0.62 - lift * 0.9),
            height: s * 0.07,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(s),
              gradient: RadialGradient(colors: [
                Colors.black.withValues(alpha: (0.32 - lift * 1.2).clamp(0.0, 1.0)),
                Colors.black.withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(0, -lift * s),
          child: Transform.rotate(
            angle: angle,
            child: Transform.scale(
              scale: scale,
              child: GiftImage(
                  id: id, emoji: emoji, size: img, url: widget.gift['image_url'] as String?),
            ),
          ),
        ),
      ],
    );
  }

  /// Уникальный подарок: фон-градиент, кольца узора, свечение и блик.
  Widget _uniqueArt(double s, String id, String emoji, BorderRadius r) {
    final u = widget.unique!;
    final cs = ((u['backdrop'] as Map?)?['colors'] as List?)
            ?.map((e) => hexColor(e as String))
            .toList() ??
        [appState.accent, const Color(0xFF111827)];
    final symbol = (u['pattern'] as Map?)?['symbol'] as String? ?? '✦';
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final wave = math.sin(t * 2 * math.pi * 2);
          return Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              borderRadius: r,
              gradient: RadialGradient(
                center: const Alignment(0, -0.1),
                radius: 0.95,
                colors: [
                  Color.lerp(cs[0], Colors.white, 0.22)!,
                  cs[0],
                  cs.length > 1 ? cs[1] : cs[0],
                ],
                stops: const [0, 0.45, 1],
              ),
              boxShadow: [
                BoxShadow(
                    color: cs[0].withValues(alpha: 0.45 + 0.15 * (wave + 1) / 2),
                    blurRadius: s * 0.28,
                    offset: Offset(0, s * 0.04)),
              ],
            ),
            child: ClipRRect(
              borderRadius: r,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _PatternRings(t: t, symbol: symbol, size: s)),
                  _object(s, id, emoji, 0.015 + 0.015 * (wave + 1) / 2),
                  CustomPaint(painter: _GiftFront(t: t, rarity: 'legendary', seed: symbol.hashCode)),
                  if (u['no'] != null && s >= 90)
                    Positioned(
                      right: s * 0.07,
                      top: s * 0.06,
                      child: Text('#${u['no']}',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.92),
                              fontWeight: FontWeight.w900,
                              fontSize: s * 0.085,
                              shadows: const [Shadow(blurRadius: 6)])),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    final emoji = widget.gift['emoji'] as String? ?? '🎁';
    final id = widget.gift['id'] as String? ?? '';
    final r = BorderRadius.circular(s * 0.28);
    if (widget.unique != null) return _uniqueArt(s, id, emoji, r);
    if (giftHasCustomStyle(widget.gift)) {
      return GiftCustomArt(gift: widget.gift, size: s, animate: widget.animate);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (_rarity == 'common') {
      // обычные — спокойная плашка с мягким светом, подарок чуть «дышит»
      final base = Theme.of(context).colorScheme.onSurface;
      return RepaintBoundary(
        child: Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 0.9,
              colors: [
                base.withValues(alpha: dark ? 0.12 : 0.04),
                base.withValues(alpha: dark ? 0.05 : 0.08),
              ],
            ),
          ),
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) {
              final w = (math.sin(_c.value * 2 * math.pi * 2) + 1) / 2;
              return _object(s, id, emoji, 0.012 * w);
            },
          ),
        ),
      );
    }
    // цвета из админки ("colors": ["#FF8A00", "#7C2D12"]) важнее встроенных
    final custom = (widget.gift['colors'] as List?)
        ?.whereType<String>()
        .map(hexColor)
        .toList();
    final colors = (custom != null && custom.length >= 2 ? custom : null) ??
        _giftColors[id] ??
        (_rarity == 'legendary'
            ? const [Color(0xFFFFF0B3), Color(0xFFFFC928), Color(0xFFB8860B)]
            : [appState.accent, HSLColor.fromColor(appState.accent).withLightness(0.35).toColor()]);
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          // все частоты целые — в конце круга всё ровно как в начале
          final wave = math.sin(t * 2 * math.pi * 2);
          final up = (wave + 1) / 2;
          final lift = switch (_rarity) { 'rare' => 0.03, 'epic' => 0.035, _ => 0.03 } * up;
          final glow = _rarity == 'legendary' ? 0.45 + 0.25 * up : 0.3 + 0.1 * up;
          Gradient bg;
          if (_rarity == 'legendary') {
            final a = t * 2 * math.pi;
            bg = RadialGradient(
              center: Alignment(0.25 * math.cos(a), -0.3 + 0.1 * math.sin(a)),
              radius: 1.0,
              colors: colors,
            );
          } else if (_rarity == 'epic') {
            final a = t * 2 * math.pi;
            bg = LinearGradient(
              begin: Alignment(math.cos(a), math.sin(a)),
              end: Alignment(-math.cos(a), -math.sin(a)),
              colors: colors,
            );
          } else {
            bg = LinearGradient(
                colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight);
          }
          return Container(
            width: s,
            height: s,
            decoration: BoxDecoration(
              gradient: bg,
              borderRadius: r,
              border: _rarity == 'legendary'
                  ? Border.all(color: const Color(0xFFFFE9A6), width: math.max(1.2, s * 0.02))
                  : null,
              boxShadow: [
                BoxShadow(
                  color: colors[1].withValues(alpha: glow),
                  blurRadius: s * (_rarity == 'legendary' ? 0.32 : 0.2),
                  offset: Offset(0, s * 0.05),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: r,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(painter: _GiftFx(t: t, rarity: _rarity, seed: id.hashCode)),
                  _object(
                    s,
                    id,
                    emoji,
                    lift,
                    scale: _rarity == 'legendary' ? 1 + 0.03 * wave : 1,
                    angle: _rarity == 'epic' ? math.sin(t * 2 * math.pi) * 0.06 : 0,
                  ),
                  CustomPaint(painter: _GiftFront(t: t, rarity: _rarity, seed: id.hashCode)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Мерцание 0..1..0 с целой частотой — бесшовно.
double _twinkle(double t, int freq, double phase) =>
    math.pow(math.sin(((t * freq + phase) % 1.0) * math.pi), 2).toDouble();

void _sparkle(Canvas canvas, Offset p, double r, Paint paint) {
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

/// Эффекты ЗА предметом. Все движения зациклены без рывков:
/// скорости целые, прозрачность плавно уходит в ноль на концах пути.
class _GiftFx extends CustomPainter {
  final double t;
  final String rarity;
  final int seed;
  _GiftFx({required this.t, required this.rarity, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final w = size.width;
    final a = t * 2 * math.pi;

    // мягкий свет за предметом (дышит)
    final pulse = (math.sin(a * 2) + 1) / 2;
    canvas.drawCircle(
      c,
      w * (0.42 + 0.04 * pulse),
      Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.26 + 0.1 * pulse),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: w * 0.46)),
    );

    if (rarity == 'rare') {
      // светлое кольцо, медленно поворачивается (1 оборот за круг)
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(a);
      canvas.drawCircle(
        Offset.zero,
        w * 0.36,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * 0.025
          ..shader = SweepGradient(colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.45),
            Colors.white.withValues(alpha: 0),
          ], stops: const [0.2, 0.5, 0.8])
              .createShader(Rect.fromCircle(center: Offset.zero, radius: w * 0.36)),
      );
      canvas.restore();
    }

    if (rarity == 'legendary') {
      // лучи: за круг поворачиваются ровно на один луч — шва не видно
      const n = 12;
      final rays = Paint()
        ..shader = RadialGradient(colors: [
          Colors.white.withValues(alpha: 0.3),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: w * 0.75));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(t * 2 * math.pi / n);
      for (var i = 0; i < n; i++) {
        final ang = i * 2 * math.pi / n;
        canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..lineTo(math.cos(ang - 0.1) * w, math.sin(ang - 0.1) * w)
            ..lineTo(math.cos(ang + 0.1) * w, math.sin(ang + 0.1) * w)
            ..close(),
          rays,
        );
      }
      canvas.restore();
    }

    // поднимающиеся пузырьки (редкие) и золотая пыль (легендарные)
    if (rarity == 'rare' || rarity == 'legendary') {
      final rnd = math.Random(seed);
      final n = rarity == 'legendary' ? 14 : 8;
      final col = rarity == 'legendary' ? const Color(0xFFFFF3C4) : Colors.white;
      for (var i = 0; i < n; i++) {
        final px0 = w * (0.1 + rnd.nextDouble() * 0.8);
        final speed = 1 + rnd.nextInt(2);
        final phase = rnd.nextDouble();
        final r0 = w * (0.012 + rnd.nextDouble() * 0.02);
        final life = (t * speed + phase) % 1.0;
        final fade = math.sin(life * math.pi); // 0 → 1 → 0
        final px = px0 + math.sin(life * 2 * math.pi + i) * w * 0.03;
        final py = size.height * (1.05 - life * 1.1);
        if (rarity == 'rare') {
          canvas.drawCircle(
              Offset(px, py),
              r0 * (0.7 + 0.3 * fade),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = math.max(0.8, w * 0.006)
                ..color = col.withValues(alpha: 0.55 * fade));
        } else {
          canvas.drawCircle(Offset(px, py), r0 * 0.6 * (0.5 + 0.5 * fade),
              Paint()..color = col.withValues(alpha: 0.7 * fade));
        }
      }
    }

    // эпические: искры на орбите — задняя половина пути рисуется здесь (за подарком)
    if (rarity == 'epic') {
      _orbit(canvas, size, back: true);
    }
  }

  void _orbit(Canvas canvas, Size size, {required bool back}) => _paintOrbit(canvas, size, t, back);

  @override
  bool shouldRepaint(covariant _GiftFx old) => old.t != t || old.rarity != rarity;
}

/// Три искры летают по эллипсу вокруг подарка (один оборот за круг).
void _paintOrbit(Canvas canvas, Size size, double t, bool back) {
  final c = size.center(Offset.zero);
  final w = size.width;
  for (var i = 0; i < 3; i++) {
    final ang = (t + i / 3) * 2 * math.pi;
    final depth = math.sin(ang); // <0 — сзади (сверху эллипса), >0 — спереди
    if ((depth < 0) != back) continue;
    final p = c + Offset(math.cos(ang) * w * 0.38, depth * w * 0.12 - w * 0.02);
    final k = 0.65 + 0.35 * (depth + 1) / 2;
    _sparkle(canvas, p, w * 0.022 * k,
        Paint()..color = Colors.white.withValues(alpha: 0.55 + 0.4 * (depth + 1) / 2));
    canvas.drawCircle(
        p,
        w * 0.05 * k,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.18)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
  }
}

/// Блеск ПОВЕРХ предмета: искры, передняя половина орбиты и блик у легендарных.
class _GiftFront extends CustomPainter {
  final double t;
  final String rarity;
  final int seed;
  _GiftFront({required this.t, required this.rarity, required this.seed});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    if (rarity == 'rare' || rarity == 'common') return;
    if (rarity == 'epic') _paintOrbit(canvas, size, t, false);
    if (rarity == 'legendary') {
      // блик проходит в первой половине круга, потом пауза — начало и конец совпадают
      final k = t < 0.5 ? t / 0.5 : 1.0;
      final x = (-0.6 + 2.2 * Curves.easeInOut.transform(k)) * w;
      final shine = Paint()
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(colors: [
          Colors.white.withValues(alpha: 0),
          Colors.white.withValues(alpha: 0.3),
          Colors.white.withValues(alpha: 0),
        ]).createShader(Rect.fromLTWH(x, 0, w * 0.3, size.height));
      canvas.save();
      canvas.translate(x + w * 0.15, size.height / 2);
      canvas.rotate(0.5);
      canvas.translate(-(x + w * 0.15), -size.height / 2);
      canvas.drawRect(Rect.fromLTWH(x, -size.height, w * 0.3, size.height * 3), shine);
      canvas.restore();
    }
    final rnd = math.Random(seed ^ 0x5f3759df);
    final n = rarity == 'legendary' ? 7 : 5;
    for (var i = 0; i < n; i++) {
      final px = size.width * (0.12 + rnd.nextDouble() * 0.76);
      final py = size.height * (0.1 + rnd.nextDouble() * 0.7);
      final phase = rnd.nextDouble();
      final freq = 1 + rnd.nextInt(3); // 1..3 вспышки за круг
      final tw = _twinkle(t, freq, phase);
      final r = w * 0.028 * tw;
      if (r <= 0.3) continue;
      _sparkle(
          canvas,
          Offset(px, py),
          r,
          Paint()
            ..color = (rarity == 'legendary' ? const Color(0xFFFFF7D1) : Colors.white)
                .withValues(alpha: 0.95 * tw));
    }
  }

  @override
  bool shouldRepaint(covariant _GiftFront old) => old.t != t;
}

/// Узор уникального подарка: два кольца символов, вращаются навстречу и мерцают.
class _PatternRings extends CustomPainter {
  final double t;
  final String symbol;
  final double size;
  _PatternRings({required this.t, required this.symbol, required this.size});

  static final Map<String, TextPainter> _cache = {};

  /// Кэш по размеру и уровню прозрачности (6 ступеней) — без saveLayer на каждый символ.
  TextPainter _tp(double fs, int level) {
    final key = '$symbol|${fs.round()}|$level';
    return _cache.putIfAbsent(key, () {
      final tp = TextPainter(
        text: TextSpan(
            text: symbol,
            style: TextStyle(fontSize: fs, color: Colors.white.withValues(alpha: 0.12 + level * 0.12))),
        textDirection: TextDirection.ltr,
      )..layout();
      return tp;
    });
  }

  @override
  void paint(Canvas canvas, Size sz) {
    final c = sz.center(Offset.zero);
    for (final ring in const [
      [8, 0.30, 1.0, 0.085],
      [12, 0.44, -2 / 3, 0.07], // поворот кратен шагу символов — без рывка
    ]) {
      final n = ring[0].toInt();
      final rad = ring[1] * size;
      final dir = ring[2].toDouble();
      final fs = (ring[3] * size).clamp(6.0, 40.0).toDouble();
      for (var i = 0; i < n; i++) {
        final a = i * 2 * math.pi / n + t * 2 * math.pi * 0.25 * dir;
        final tw = 0.5 + 0.5 * math.sin(t * 2 * math.pi * 2 + i);
        final tp = _tp(fs, (tw * 5).round());
        final o = Offset(c.dx + math.cos(a) * rad - tp.width / 2,
            c.dy + math.sin(a) * rad - tp.height / 2);
        tp.paint(canvas, o);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PatternRings old) => old.t != t || old.symbol != symbol;
}

/// Плашка-подарок для сетки (в профиле и в магазине).
class GiftTile extends StatelessWidget {
  final Map<String, dynamic> gift;
  final Widget? footer;
  final String? corner;
  final VoidCallback? onTap;
  final bool dim;
  const GiftTile(
      {super.key, required this.gift, this.footer, this.corner, this.onTap, this.dim = false});

  @override
  Widget build(BuildContext context) {
    final rarity = gift['rarity'] as String? ?? 'common';
    final rc = rarityColor(rarity);
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Opacity(
        opacity: dim ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
          decoration: BoxDecoration(
            color: cardColor(context),
            borderRadius: BorderRadius.circular(18),
            border: rarity == 'common'
                ? null
                : Border.all(color: rc.withValues(alpha: 0.45), width: 1.2),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.topCenter,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // клетка сетки ограничена по высоте — картинка ужимается, чтобы не было overflow
                  Flexible(
                    child: LayoutBuilder(
                      builder: (context, c) => GiftArt(
                          gift: gift,
                          size: math.max(
                              24.0, math.min(math.min(c.maxWidth - 8, c.maxHeight), 76.0))),
                    ),
                  ),
                  const SizedBox(height: 7),
                  Text(gift['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
                  if (footer != null) ...[const SizedBox(height: 4), footer!],
                ],
              ),
              if (corner != null)
                Positioned(
                  right: -2,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: rc,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(corner!,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Магазин подарков
// ─────────────────────────────────────────────────────────────

/// Выбрать и подарить подарок. true — подарок отправлен.
Future<bool> showGiftShop(BuildContext context,
    {required String toUserId, required String toName}) async {
  final r = await showAppSheet<Map<String, dynamic>>(context,
      scrollable: true, builder: (ctx) => _GiftShop(toUserId: toUserId, toName: toName));
  if (r == null) return false;
  if (context.mounted) {
    final self = toUserId == appState.myUserId;
    // красивое подтверждение на весь экран
    await showGiftReveal(context, r,
        title: self ? 'Подарок себе!' : 'Подарок отправлен!',
        subtitle: self ? 'Он уже в твоём профиле' : 'для $toName');
  }
  return true;
}

class _GiftShop extends StatefulWidget {
  final String toUserId;
  final String toName;
  const _GiftShop({required this.toUserId, required this.toName});
  @override
  State<_GiftShop> createState() => _GiftShopState();
}

class _GiftShopState extends State<_GiftShop> {
  List<Map<String, dynamic>>? _gifts;
  int _balance = appState.coins;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.giftCatalog();
      if (!mounted) return;
      setState(() {
        _gifts = ((d['gifts'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _balance = (d['balance'] as num?)?.toInt() ?? _balance;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _pick(Map<String, dynamic> g) async {
    final sent = await showAppSheet<Map<String, dynamic>>(context,
        scrollable: true,
        builder: (ctx) => _GiftConfirm(
            gift: g, balance: _balance, toUserId: widget.toUserId, toName: widget.toName));
    if (sent != null && mounted) Navigator.pop(context, sent);
  }

  @override
  Widget build(BuildContext context) {
    final gifts = _gifts;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.82),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.toUserId == appState.myUserId ? 'Подарок себе' : 'Подарок',
                          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                      Text(
                          widget.toUserId == appState.myUserId
                              ? 'с Connecto Premium'
                              : 'для ${widget.toName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtleText(context), fontSize: 13)),
                    ],
                  ),
                ),
                Pressable(
                  onTap: () async {
                    await Navigator.push(
                        context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                    _load();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: kPremium.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CoinAmount(_balance, size: 14),
                        const SizedBox(width: 6),
                        const Icon(AppIcons.plus, size: 16, color: kPremium),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error != null)
            Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center))
          else if (gifts == null)
            const Padding(
                padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else
            Flexible(
              child: GridView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 0.74),
                itemCount: gifts.length,
                itemBuilder: (context, i) {
                  final g = gifts[i];
                  final left = (g['left'] as num?)?.toInt();
                  final soldOut = left != null && left <= 0;
                  return FadeSlideIn(
                    delayMs: 25 * math.min(i, 15),
                    child: GiftTile(
                      gift: g,
                      dim: soldOut,
                      corner: g['supply'] != null
                          ? (soldOut ? 'нет' : 'осталось $left')
                          : giftSaleCorner(g),
                      onTap: soldOut ? null : () => _pick(g),
                      footer: CoinAmount((g['price'] as num).toInt(), size: 12.5),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _GiftConfirm extends StatefulWidget {
  final Map<String, dynamic> gift;
  final int balance;
  final String toUserId;
  final String toName;
  const _GiftConfirm(
      {required this.gift, required this.balance, required this.toUserId, required this.toName});
  @override
  State<_GiftConfirm> createState() => _GiftConfirmState();
}

class _GiftConfirmState extends State<_GiftConfirm> {
  final _text = TextEditingController();
  bool _anon = false;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  int get _price => (widget.gift['price'] as num).toInt();
  bool get _self => widget.toUserId == appState.myUserId;

  Future<void> _send() async {
    if (_busy) return;
    if (widget.balance < _price) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
      return;
    }
    setState(() => _busy = true);
    try {
      final r = await Api.sendGift(widget.toUserId, widget.gift['id'] as String,
          text: _text.text.trim(), anonymous: _anon);
      appState.coins = (r['balance'] as num?)?.toInt() ?? appState.coins;
      appState.refreshMe();
      if (!mounted) return;
      final sent = (r['gift'] as Map?)?.cast<String, dynamic>() ?? {'gift': widget.gift};
      Navigator.pop(context, sent);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.gift;
    final rarity = g['rarity'] as String? ?? 'common';
    final enough = widget.balance >= _price;
    // с открытой клавиатурой (подпись) содержимое не влезает — прокрутка вместо overflow
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GiftArt(gift: g, size: 132),
          const SizedBox(height: 14),
          Text(g['title'] as String? ?? '',
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(rarityName(rarity),
                  style: TextStyle(color: rarityColor(rarity), fontWeight: FontWeight.w800)),
              if (g['supply'] != null)
                Text('  ·  лимит ${g['supply']} шт.',
                    style: TextStyle(color: subtleText(context), fontSize: 13)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
              _self
                  ? 'Можно обменять на ${g['convert_value']} кристаллов или сделать уникальным'
                  : 'Получатель сможет обменять его на ${g['convert_value']} кристаллов',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(context), fontSize: 12.5)),
          const SizedBox(height: 16),
          AppTextField(
              controller: _text, hint: 'Подпись к подарку (необязательно)', maxLength: 200),
          const SizedBox(height: 6),
          if (!_self)
          SwitchListTile(
            value: _anon,
            onChanged: (v) => setState(() => _anon = v),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('Анонимно', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text('Только ${widget.toName} узнает, от кого подарок',
                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
          ),
          const SizedBox(height: 8),
          PrimaryButton(
            label: enough
                ? '${_self ? 'Купить' : 'Подарить'} за ${fmtCoins(_price)}'
                : 'Не хватает ${fmtCoins(_price - widget.balance)} · пополнить',
            icon: enough ? AppIcons.gift : AppIcons.coin,
            loading: _busy,
            gradient: rarity == 'legendary' ? kPremiumGradient : null,
            onTap: _send,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Подарок в профиле: подробности, скрыть, обменять
// ─────────────────────────────────────────────────────────────

String _date(String? iso) {
  final d = parseServerTime(iso ?? '');
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
}

Map<String, dynamic>? _uniqueOf(Map<String, dynamic> ug) =>
    (ug['unique'] as Map?)?.cast<String, dynamic>();

/// Показать подарок. После закрытия список лучше обновить (могли скрыть, обменять, улучшить).
Future<bool> showGiftDetails(BuildContext context, Map<String, dynamic> ug) async {
  await showAppSheet<bool>(context, scrollable: true, builder: (ctx) => _GiftDetails(ug: ug));
  return true;
}

class _GiftDetails extends StatefulWidget {
  final Map<String, dynamic> ug;
  const _GiftDetails({required this.ug});
  @override
  State<_GiftDetails> createState() => _GiftDetailsState();
}

class _GiftDetailsState extends State<_GiftDetails> {
  bool _busy = false;
  late Map<String, dynamic> _ug = widget.ug;
  bool _changed = false;

  Future<void> _run(Future<void> Function() f) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _hide() => _run(() async {
        final r = await Api.hideGift(_ug['id'] as String, _ug['hidden'] != true);
        _changed = true;
        if (mounted) setState(() => _ug = {..._ug, ...r});
      });

  Future<void> _pin() => _run(() async {
        final r = await Api.pinGift(_ug['id'] as String, _ug['pinned'] != true);
        _changed = true;
        HapticFeedback.selectionClick();
        if (mounted) setState(() => _ug = {..._ug, ...r});
      });

  Future<void> _convert() async {
    final value = _ug['convert_value'];
    final ok = await confirm(context,
        title: 'Обменять на $value кристаллов?',
        body: 'Подарок исчезнет из профиля, а кристаллы придут на баланс.',
        action: 'Обменять');
    if (!ok || !mounted) return;
    await _run(() async {
      final r = await Api.convertGift(_ug['id'] as String);
      appState.coins = (r['balance'] as num?)?.toInt() ?? appState.coins;
      appState.refreshMe();
      if (!mounted) return;
      Navigator.pop(context, true);
      toast(context, '+${r['coins']} кристаллов на балансе', icon: AppIcons.coin);
    });
  }

  Future<void> _upgrade() async {
    final cost = (_ug['upgrade_cost'] as num?)?.toInt() ?? 0;
    final ok = await showAppSheet<bool>(context, scrollable: true, builder: (ctx) => _UpgradePreview(ug: _ug, cost: cost));
    if (ok != true || !mounted) return;
    await _run(() async {
      final r = await Api.upgradeGift(_ug['id'] as String);
      appState.coins = (r['balance'] as num?)?.toInt() ?? appState.coins;
      appState.refreshMe();
      final g = (r['gift'] as Map).cast<String, dynamic>();
      _changed = true;
      if (!mounted) return;
      setState(() => _ug = g);
      await showGiftReveal(context, g, title: 'Подарок стал уникальным!', subtitle: '', button: 'Вау!');
    });
  }

  @override
  Widget build(BuildContext context) {
    final ug = _ug;
    final g = (ug['gift'] as Map).cast<String, dynamic>();
    final from = (ug['from'] as Map?)?.cast<String, dynamic>();
    final rarity = g['rarity'] as String? ?? 'common';
    final mine = ug['mine'] == true;
    final serial = ug['serial'];
    final u = _uniqueOf(ug);
    final value = (ug['value'] as num?)?.toInt() ?? (g['price'] as num?)?.toInt() ?? 0;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => showGiftReveal(context, ug, title: u != null ? 'Уникальный подарок' : 'Подарок'),
              child: GiftArt(gift: g, unique: u, size: 150),
            ),
            const SizedBox(height: 14),
            Text('${g['title'] ?? ''}${u != null ? ' #${u['no']}' : ''}',
                style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
                '${u != null ? 'Уникальный · ' : ''}${rarityName(rarity)}${serial != null ? ' · №$serial из ${ug['supply']}' : ''}',
                style: TextStyle(color: rarityColor(rarity), fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            // характеристики
            Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _row(context, 'Ценность', CoinAmount(value, size: 14)),
                  if (u != null) ...[
                    _row(context, 'Фон', _attr(u['backdrop']?['name'], u['backdrop']?['pct'],
                        color: hexColor((u['backdrop']?['colors'] as List?)?.first as String? ?? '#6366F1'))),
                    _row(context, 'Узор', _attr('${u['pattern']?['symbol']} ${u['pattern']?['name']}', u['pattern']?['pct'])),
                  ],
                  if (g['supply'] != null)
                    _row(context, 'Выпуск', Text('лимит ${g['supply']} шт.',
                        style: const TextStyle(fontWeight: FontWeight.w700))),
                  _row(
                    context,
                    'От кого',
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (from != null)
                          Avatar(
                              name: from['display_name'] as String? ?? '?',
                              url: from['avatar_url'] as String?,
                              size: 22)
                        else
                          const Icon(AppIcons.incognito, size: 18),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                              from != null
                                  ? '${from['display_name']}${ug['anonymous'] == true ? ' · анонимно' : ''}'
                                  : (ug['anonymous'] == true ? 'Аноним' : 'Connecto'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                  _row(context, 'Дата', Text(_date(ug['created_at'] as String?),
                      style: const TextStyle(fontWeight: FontWeight.w700))),
                  if ((ug['text'] as String? ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text('«${ug['text']}»',
                            style: const TextStyle(fontSize: 15, fontStyle: FontStyle.italic)),
                      ),
                    ),
                ],
              ),
            ),
            if (mine) ...[
              const SizedBox(height: 14),
              if (u == null && ug['upgrade_cost'] != null)
                PrimaryButton(
                  label: 'Сделать уникальным · ${fmtCoins((ug['upgrade_cost'] as num).toInt())}',
                  icon: AppIcons.sparkles,
                  gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]),
                  loading: _busy,
                  onTap: _upgrade,
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _SmallBtn(
                      icon: ug['pinned'] == true ? AppIcons.pinOff : AppIcons.pin,
                      label: ug['pinned'] == true ? 'Открепить' : 'Закрепить',
                      onTap: _busy ? null : _pin,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SmallBtn(
                      icon: ug['hidden'] == true ? AppIcons.eye : AppIcons.eyeOff,
                      label: ug['hidden'] == true ? 'Показать' : 'Скрыть',
                      onTap: _busy ? null : _hide,
                    ),
                  ),
                  if (u == null && ((ug['convert_value'] as num?) ?? 0) > 0) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _SmallBtn(
                        icon: AppIcons.coin,
                        label: '+${ug['convert_value']}',
                        color: kPremium,
                        onTap: _busy ? null : _convert,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, _changed),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _attr(Object? name, Object? pct, {Color? color}) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (color != null) ...[
            Container(width: 14, height: 14, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
          ],
          Text('${name ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(8)),
            child: Text('$pct%',
                style: const TextStyle(
                    color: Color(0xFF8B5CF6), fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ],
      );

  Widget _row(BuildContext context, String k, Widget v) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            SizedBox(
                width: 86,
                child: Text(k, style: TextStyle(color: subtleText(context), fontSize: 13.5))),
            Expanded(child: Align(alignment: Alignment.centerLeft, child: v)),
          ],
        ),
      );
}

class _SmallBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;
  const _SmallBtn({required this.icon, required this.label, this.onTap, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? appState.accent;
    return Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: c.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Icon(icon, color: c, size: 20),
            const SizedBox(height: 4),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c, fontWeight: FontWeight.w800, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }
}

/// Перед улучшением: какие фоны и узоры могут выпасть и с каким шансом.
class _UpgradePreview extends StatefulWidget {
  final Map<String, dynamic> ug;
  final int cost;
  const _UpgradePreview({required this.ug, required this.cost});
  @override
  State<_UpgradePreview> createState() => _UpgradePreviewState();
}

class _UpgradePreviewState extends State<_UpgradePreview> {
  Map<String, dynamic>? _info;
  int _shown = 0;

  @override
  void initState() {
    super.initState();
    Api.giftUpgradeInfo().then((d) {
      if (mounted) setState(() => _info = d);
    }).catchError((_) {});
    // перебор вариантов «как в слот-машине»
    Future.doWhile(() async {
      await Future.delayed(const Duration(milliseconds: 900));
      if (!mounted) return false;
      setState(() => _shown++);
      return true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = (widget.ug['gift'] as Map).cast<String, dynamic>();
    final info = _info;
    final bds = ((info?['backdrops'] as List?) ?? const []).cast<Map>();
    final pts = ((info?['patterns'] as List?) ?? const []).cast<Map>();
    Map<String, dynamic>? preview;
    if (bds.isNotEmpty && pts.isNotEmpty) {
      preview = {
        'backdrop': bds[_shown % bds.length],
        'pattern': pts[(_shown * 3) % pts.length],
      };
    }
    final enough = appState.coins >= widget.cost;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (c, a) => FadeTransition(
                opacity: a, child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(a), child: c)),
            child: KeyedSubtree(
              key: ValueKey(_shown),
              child: GiftArt(gift: g, unique: preview, size: 140),
            ),
          ),
          const SizedBox(height: 14),
          const Text('Сделать уникальным',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text(
              'Подарок получит случайный фон, узор и свой номер. Чем реже выпадет — '
              'тем выше ценность. Обменять уникальный подарок на кристаллы уже нельзя.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(context), height: 1.4)),
          const SizedBox(height: 14),
          if (bds.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final b in bds)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        hexColor((b['colors'] as List)[0] as String),
                        hexColor((b['colors'] as List)[1] as String),
                      ]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${b['name']} · ${b['pct']}%',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w800)),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          if (pts.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                for (final p in pts)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${p['symbol']} ${p['name']} · ${p['pct']}%',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: enough
                ? 'Улучшить за ${fmtCoins(widget.cost)}'
                : 'Не хватает ${fmtCoins(widget.cost - appState.coins)} · пополнить',
            icon: enough ? AppIcons.sparkles : AppIcons.coin,
            gradient: const LinearGradient(colors: [Color(0xFF8B5CF6), Color(0xFFEC4899)]),
            onTap: () {
              if (!enough) {
                Navigator.pop(context, false);
                Navigator.push(context, MaterialPageRoute(builder: (_) => const WalletScreen()));
                return;
              }
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );
  }
}

/// Пришёл подарок — показываем его на весь экран.
Future<void> showGiftReceived(BuildContext context, Map<String, dynamic> ug) =>
    showGiftReveal(context, ug);

// ─────────────────────────────────────────────────────────────
// Стена подарков в профиле: легендарные — на всю ширину (3 слота)
// ─────────────────────────────────────────────────────────────

class GiftWall extends StatelessWidget {
  final List<Map<String, dynamic>> gifts;
  final ValueChanged<Map<String, dynamic>> onTap;
  const GiftWall({super.key, required this.gifts, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    var buf = <Map<String, dynamic>>[];
    var n = 0;
    void flush() {
      if (buf.isEmpty) return;
      final row = buf;
      rows.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(
                child: i < row.length
                    ? FadeSlideIn(
                        delayMs: 30 * math.min(n++, 12),
                        child: GiftCard(ug: row[i], onTap: () => onTap(row[i])))
                    : const SizedBox(),
              ),
            ],
          ],
        ),
      ));
      buf = [];
    }

    for (final ug in gifts) {
      final g = (ug['gift'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (g['rarity'] == 'legendary') {
        flush();
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: FadeSlideIn(
            delayMs: 30 * math.min(n++, 12),
            child: LegendaryGiftCard(ug: ug, onTap: () => onTap(ug)),
          ),
        ));
      } else {
        buf.add(ug);
        if (buf.length == 3) flush();
      }
    }
    flush();
    return Column(children: rows);
  }
}

/// Обычная клетка (1 слот).
class GiftCard extends StatelessWidget {
  final Map<String, dynamic> ug;
  final VoidCallback onTap;
  const GiftCard({super.key, required this.ug, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final g = (ug['gift'] as Map).cast<String, dynamic>();
    final rarity = g['rarity'] as String? ?? 'common';
    final u = _uniqueOf(ug);
    final from = (ug['from'] as Map?)?.cast<String, dynamic>();
    final rc = rarityColor(rarity);
    final dark = Theme.of(context).brightness == Brightness.dark;
    Decoration deco;
    if (u != null) {
      final cs = ((u['backdrop'] as Map?)?['colors'] as List?)?.map((e) => hexColor(e as String)).toList() ??
          [appState.accent, Colors.black];
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
            colors: [cs[0].withValues(alpha: 0.35), cs[1].withValues(alpha: 0.25)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        border: Border.all(color: cs[0].withValues(alpha: 0.8), width: 1.4),
      );
    } else if (rarity == 'common') {
      deco = BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(18));
    } else {
      deco = BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: cardColor(context),
        gradient: LinearGradient(
          colors: [rc.withValues(alpha: dark ? 0.22 : 0.14), cardColor(context)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: rc.withValues(alpha: 0.4), width: 1.1),
      );
    }
    return Pressable(
      onTap: onTap,
      scale: 0.94,
      child: Opacity(
        opacity: ug['hidden'] == true ? 0.45 : 1,
        child: AspectRatio(
          aspectRatio: 0.78,
          child: Container(
            decoration: deco,
            padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
            child: LayoutBuilder(builder: (context, c) {
              final art = math.max(30.0, math.min(c.maxWidth * 0.78, c.maxHeight - 40));
              return Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      SizedBox(
                          width: c.maxWidth,
                          child: Center(child: GiftArt(gift: g, unique: u, size: art))),
                      const Spacer(),
                      Text(u != null ? '${g['title']} #${u['no']}' : (g['title'] as String? ?? ''),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
                      Text(
                          from != null
                              ? (from['display_name'] as String? ?? '')
                              : (ug['anonymous'] == true ? 'Аноним' : 'Connecto'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: subtleText(context), fontSize: 11)),
                    ],
                  ),
                  if (ug['pinned'] == true)
                    const Positioned(
                        left: 0, top: 0, child: Icon(AppIcons.pin, size: 14, color: kPremium)),
                  if (ug['serial'] != null)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(color: rc, borderRadius: BorderRadius.circular(7)),
                        child: Text('№${ug['serial']}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w900)),
                      ),
                    ),
                ],
              );
            }),
          ),
        ),
      ),
    );
  }
}

/// Легендарный подарок — карточка на всю ширину: золото, блик, светящаяся рамка.
class LegendaryGiftCard extends StatefulWidget {
  final Map<String, dynamic> ug;
  final VoidCallback onTap;
  const LegendaryGiftCard({super.key, required this.ug, required this.onTap});
  @override
  State<LegendaryGiftCard> createState() => _LegendaryGiftCardState();
}

class _LegendaryGiftCardState extends State<LegendaryGiftCard> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (appState.motion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ug = widget.ug;
    final g = (ug['gift'] as Map).cast<String, dynamic>();
    final u = _uniqueOf(ug);
    final from = (ug['from'] as Map?)?.cast<String, dynamic>();
    final value = (ug['value'] as num?)?.toInt() ?? (g['price'] as num?)?.toInt() ?? 0;
    final cs = u != null
        ? (((u['backdrop'] as Map?)?['colors'] as List?)?.map((e) => hexColor(e as String)).toList() ??
            [const Color(0xFFFFC928), const Color(0xFF7A4A00)])
        : [const Color(0xFFFFC928), const Color(0xFF6B3F00)];
    return Pressable(
      onTap: widget.onTap,
      scale: 0.97,
      child: Opacity(
        opacity: ug['hidden'] == true ? 0.5 : 1,
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              return Container(
                height: 168,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  // бегущая золотая рамка
                  gradient: SweepGradient(
                    transform: GradientRotation(t * 2 * math.pi),
                    colors: const [
                      Color(0xFFFFF4C2),
                      Color(0xFFFFB020),
                      Color(0xFF8A5A00),
                      Color(0xFFFFE08A),
                      Color(0xFFFFF4C2),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                        color: cs[0].withValues(alpha: 0.35 + 0.15 * math.sin(t * 2 * math.pi).abs()),
                        blurRadius: 24,
                        offset: const Offset(0, 8)),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(-0.6, 0),
                            radius: 1.3,
                            colors: [cs[0].withValues(alpha: 0.95), cs[1], const Color(0xFF120A00)],
                            stops: const [0, 0.55, 1],
                          ),
                        ),
                      ),
                      // блик по карточке
                      Positioned(
                        left: -120 + (t * 2.4 % 1.2) * 600,
                        top: -40,
                        bottom: -40,
                        child: Transform.rotate(
                          angle: 0.35,
                          child: Container(
                            width: 70,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Colors.white.withValues(alpha: 0),
                                Colors.white.withValues(alpha: 0.22),
                                Colors.white.withValues(alpha: 0),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                        child: Row(
                          children: [
                            GiftArt(gift: g, unique: u, size: 128),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.28),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(u != null ? 'УНИКАЛЬНЫЙ · ЛЕГЕНДА' : 'ЛЕГЕНДАРНЫЙ',
                                        style: const TextStyle(
                                            color: Color(0xFFFFE08A),
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 1.1)),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('${g['title']}${u != null ? ' #${u['no']}' : ''}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          shadows: [Shadow(blurRadius: 12, color: Color(0x99000000))])),
                                  if (ug['serial'] != null)
                                    Text('№${ug['serial']} из ${ug['supply'] ?? g['supply'] ?? '—'}',
                                        style: const TextStyle(
                                            color: Color(0xFFFFE9A6), fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 6),
                                  Text(
                                      from != null
                                          ? 'от ${from['display_name']}'
                                          : (ug['anonymous'] == true ? 'от анонима' : 'от Connecto'),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: Colors.white70, fontSize: 12.5)),
                                  const SizedBox(height: 6),
                                  CoinAmount(value, size: 13.5, color: Colors.white),
                                ],
                              ),
                            ),
                            if (ug['pinned'] == true)
                              const Icon(AppIcons.pin, color: Color(0xFFFFE08A), size: 18),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
