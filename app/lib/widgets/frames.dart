import 'dart:math' as math;
import 'dart:ui' show MaskFilter, BlurStyle;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../app_state.dart';
import '../customization.dart';
import '../theme.dart';

/// Рамки чатов в списке и обводка сообщений.
/// Все рамки рисуются одним CustomPainter; анимированные слушают общие «часы»,
/// поэтому перерисовывается только сама рамка, а не весь чат.

// ─────────────────────────────── общие часы ───────────────────────────────

class _FrameClock extends ChangeNotifier {
  Ticker? _ticker;
  int _users = 0;
  double value = 0; // 0..1, полный круг за 4 секунды

  void attach() {
    _users++;
    if (_ticker != null) return;
    _ticker = Ticker((d) {
      value = (d.inMilliseconds % 4000) / 4000.0;
      notifyListeners();
    })
      ..start();
  }

  void detach() {
    _users = math.max(0, _users - 1);
    if (_users == 0) {
      _ticker?.stop();
      _ticker?.dispose();
      _ticker = null;
    }
  }
}

final _clock = _FrameClock();

// ─────────────────────────────── описание рамки ───────────────────────────────

class FrameLook {
  final List<Color> colors;  // 1 цвет — сплошная, больше — градиент
  final double width;
  final double glow;         // 0..1
  final Color? glowColor;
  final bool spin;           // градиент вращается по кругу
  final bool shine;          // по рамке бежит блик
  final Color? fill;         // заливка (плитки в списке)
  final bool shadow;         // мягкая тень под плиткой
  final double radius;       // скругление плиток в списке

  const FrameLook({
    required this.colors,
    this.width = 1.2,
    this.glow = 0,
    this.glowColor,
    this.spin = false,
    this.shine = false,
    this.fill,
    this.shadow = false,
    this.radius = 20,
  });

  bool get animated => (spin || shine) && appState.motion;
}

Color _hue(Color c, double deg, {double? light, double? sat}) {
  final h = HSLColor.fromColor(c);
  var r = h.withHue((h.hue + deg) % 360);
  if (light != null) r = r.withLightness(light);
  if (sat != null) r = r.withSaturation(sat);
  return r.toColor();
}

const _gold = [Color(0xFFFFE9A8), Color(0xFFD4A017), Color(0xFFFFD36B), Color(0xFF9C7412)];

List<Color> _aurora(Color a) => [a, const Color(0xFF22D3EE), const Color(0xFFF472B6), a];

/// Рамка плиток в списке чатов. null — классический список без рамок.
FrameLook? chatFrameLook(BuildContext context, {String? id, FrameCustom? custom}) {
  final style = id ?? appState.chatFrameEff;
  final a = appState.accent;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final card = cardColor(context);
  final line = Theme.of(context).colorScheme.onSurface.withValues(alpha: dark ? 0.07 : 0.06);
  switch (style) {
    case 'card':
      return FrameLook(colors: [line], width: 1, fill: card, shadow: true, radius: 20);
    case 'outline':
      return FrameLook(colors: [a.withValues(alpha: 0.5)], width: 1.3,
          fill: a.withValues(alpha: dark ? 0.035 : 0.025), radius: 18);
    case 'pill':
      return FrameLook(colors: [a.withValues(alpha: 0.18)], width: 1, fill: card,
          shadow: true, radius: 32);
    case 'gradient':
      return FrameLook(colors: [a, _hue(a, 70, light: 0.62)], width: 1.8, fill: card, radius: 20);
    case 'neon':
      final n = _hue(a, 0, light: 0.66, sat: 1);
      return FrameLook(colors: [n], width: 1.5, glow: 0.8, glowColor: a,
          fill: Color.alphaBlend(a.withValues(alpha: 0.05), card), radius: 18);
    case 'aurora':
      return FrameLook(colors: _aurora(a), width: 2, glow: 0.3, spin: true, fill: card, radius: 22);
    case 'glass':
      return FrameLook(
          colors: [
            Colors.white.withValues(alpha: dark ? 0.35 : 0.9),
            Colors.white.withValues(alpha: dark ? 0.05 : 0.3),
            Colors.white.withValues(alpha: dark ? 0.22 : 0.7),
          ],
          width: 1.2,
          shine: true,
          fill: dark ? Colors.white.withValues(alpha: 0.06) : Colors.white.withValues(alpha: 0.72),
          shadow: !dark,
          radius: 22);
    case 'gold':
      return FrameLook(colors: _gold, width: 1.8, glow: 0.25, glowColor: const Color(0xFFFFC53D),
          shine: true, fill: card, radius: 20);
    case 'custom':
      final c = custom ?? appState.chatFrameCustom;
      return FrameLook(
          colors: c.twoColors ? [c.c1, c.c2] : [c.c1],
          width: c.width,
          glow: c.glow,
          glowColor: c.c1,
          spin: c.animated && c.twoColors,
          shine: c.animated && !c.twoColors,
          fill: card.withValues(alpha: c.fill),
          radius: c.radius);
    default:
      return null;
  }
}

/// Обводка пузырей сообщений. null — без обводки.
FrameLook? bubbleFrameLook(BuildContext context, bool mine, {String? id, FrameCustom? custom}) {
  final style = id ?? appState.bubbleFrameEff;
  final a = appState.accent;
  final dark = Theme.of(context).brightness == Brightness.dark;
  switch (style) {
    case 'thin':
      return FrameLook(
          colors: [
            mine
                ? Colors.white.withValues(alpha: 0.38)
                : Theme.of(context).colorScheme.onSurface.withValues(alpha: dark ? 0.16 : 0.12)
          ],
          width: 1);
    case 'accent':
      return FrameLook(
          colors: [mine ? _hue(a, 0, light: 0.8) : a.withValues(alpha: 0.75)], width: 1.4);
    case 'gradient':
      return FrameLook(
          colors: mine
              ? [Colors.white.withValues(alpha: 0.9), _hue(a, 70, light: 0.78)]
              : [a, _hue(a, 70, light: 0.62)],
          width: 1.7);
    case 'neon':
      final n = _hue(a, 0, light: mine ? 0.82 : 0.66, sat: 1);
      return FrameLook(colors: [n], width: 1.3, glow: 0.85, glowColor: a);
    case 'aurora':
      return FrameLook(colors: _aurora(mine ? _hue(a, 0, light: 0.8) : a), width: 1.8,
          glow: 0.25, spin: true);
    case 'gold':
      return const FrameLook(colors: _gold, width: 1.6, glow: 0.2,
          glowColor: Color(0xFFFFC53D), shine: true);
    case 'custom':
      final c = custom ?? appState.bubbleFrameCustom;
      return FrameLook(
          colors: c.twoColors ? [c.c1, c.c2] : [c.c1],
          width: c.width,
          glow: c.glow,
          glowColor: c.c1,
          spin: c.animated && c.twoColors,
          shine: c.animated && !c.twoColors);
    default:
      return null;
  }
}

// ─────────────────────────────── отрисовка ───────────────────────────────

class _FramePainter extends CustomPainter {
  final FrameLook look;
  final BorderRadius radius;
  final bool back; // true — тень, свечение и заливка; false — сама рамка поверх
  final bool anim;
  _FramePainter(this.look, this.radius, {required this.back, required this.anim})
      : super(repaint: anim ? _clock : null);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rr = radius.toRRect(rect);
    final t = anim ? _clock.value : 0.12;
    if (back) {
      if (look.shadow) {
        canvas.drawRRect(
            rr.shift(const Offset(0, 3)),
            Paint()
              ..color = Colors.black.withValues(alpha: 0.10)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
      }
      if (look.glow > 0) {
        final gc = look.glowColor ?? look.colors.first;
        final pulse = anim ? (0.85 + 0.15 * math.sin(t * 2 * math.pi)) : 1.0;
        canvas.drawRRect(
            rr,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = look.width + 3
              ..color = gc.withValues(alpha: (0.6 * look.glow * pulse).clamp(0.0, 1.0))
              ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + 9 * look.glow));
      }
      if (look.fill != null) canvas.drawRRect(rr, Paint()..color = look.fill!);
      return;
    }
    if (look.width <= 0) return;
    final inner = rr.deflate(look.width / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = look.width
      ..isAntiAlias = true;
    if (look.colors.length == 1) {
      p.color = look.colors.first;
    } else if (look.spin) {
      final cs = [...look.colors, look.colors.first];
      p.shader = SweepGradient(colors: cs, transform: GradientRotation(2 * math.pi * t))
          .createShader(rect);
    } else {
      p.shader = LinearGradient(
              colors: look.colors, begin: Alignment.topLeft, end: Alignment.bottomRight)
          .createShader(rect);
    }
    canvas.drawRRect(inner, p);
    if (look.shine) {
      // блик: светлая полоса скользит по диагонали
      final x = -1.6 + 3.2 * t;
      final sh = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = look.width + 0.4
        ..blendMode = BlendMode.plus
        ..shader = LinearGradient(
          begin: Alignment(x - 0.6, -1),
          end: Alignment(x + 0.6, 1),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.35, 0.5, 0.65],
        ).createShader(rect);
      canvas.drawRRect(inner, sh);
    }
  }

  @override
  bool shouldRepaint(covariant _FramePainter old) =>
      old.look != look || old.radius != radius || old.anim != anim;
}

/// Контейнер с рамкой: сзади — тень/свечение/заливка, спереди — кант.
class FramedBox extends StatefulWidget {
  final FrameLook look;
  final BorderRadius radius;
  final Widget child;
  final bool clip;
  const FramedBox(
      {super.key, required this.look, required this.radius, required this.child, this.clip = true});

  @override
  State<FramedBox> createState() => _FramedBoxState();
}

class _FramedBoxState extends State<FramedBox> {
  bool _attached = false;
  bool _visible = true; // экран под другим экраном — анимацию не крутим

  void _sync() {
    final want = widget.look.animated && _visible;
    if (want && !_attached) {
      _clock.attach();
      _attached = true;
    } else if (!want && _attached) {
      _clock.detach();
      _attached = false;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _visible = TickerMode.of(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant FramedBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    if (_attached) _clock.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anim = _attached;
    Widget child = widget.child;
    if (widget.clip) child = ClipRRect(borderRadius: widget.radius, child: child);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _FramePainter(widget.look, widget.radius, back: true, anim: anim),
        foregroundPainter: _FramePainter(widget.look, widget.radius, back: false, anim: anim),
        child: child,
      ),
    );
  }
}
