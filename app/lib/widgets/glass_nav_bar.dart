import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../theme.dart';

enum NavIconKind { chats, store, settings, profile }

class NavDestination {
  final NavIconKind kind;
  final String label;
  const NavDestination(this.kind, this.label);
}

/// Нижнее меню. Стиль берётся из настроек (Стекло, Классика, Капсула, Неон).
class GlassNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<NavDestination> items;
  final int chatsBadge;

  const GlassNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
    this.chatsBadge = 0,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        switch (appState.navStyleEff) {
          case 'solid':
            return _solid(context);
          case 'floating':
            return _floating(context);
          case 'neon':
            return _neon(context);
          default:
            return _glass(context);
        }
      },
    );
  }

  Color _muted(BuildContext c) => Theme.of(c).brightness == Brightness.dark
      ? const Color(0xFF7B8090)
      : const Color(0xFF9AA0AC);

  Widget _items(BuildContext context, Widget Function(int i, bool sel) build,
      {MainAxisAlignment align = MainAxisAlignment.spaceAround}) {
    return Row(
      mainAxisAlignment: align,
      mainAxisSize: align == MainAxisAlignment.center ? MainAxisSize.min : MainAxisSize.max,
      children: [
        for (var i = 0; i < items.length; i++)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTap(i),
            child: build(i, i == currentIndex),
          ),
      ],
    );
  }

  Widget _glass(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = appState.accent;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              height: 68,
              decoration: BoxDecoration(
                color: cardColor(context).withValues(alpha: dark ? 0.62 : 0.76),
                borderRadius: BorderRadius.circular(30),
                border: Border.all(color: hairline(context)),
              ),
              child: _items(context, (i, sel) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? accent.withValues(alpha: 0.16) : Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: _badge(i, NavIcon(kind: items[i].kind, selected: sel,
                      color: sel ? accent : _muted(context))),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _solid(BuildContext context) {
    final accent = appState.accent;
    return Container(
      decoration: BoxDecoration(
        color: cardColor(context),
        border: Border(top: BorderSide(color: hairline(context))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: _items(context, (i, sel) {
            return SizedBox(
              width: 64,
              child: Center(
                child: _badge(i, NavIcon(kind: items[i].kind, selected: sel,
                    color: sel ? accent : _muted(context))),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _floating(BuildContext context) {
    final accent = appState.accent;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 18),
        child: Center(
          heightFactor: 1,
          child: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: cardColor(context),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 10)),
              ],
            ),
            child: _items(context, (i, sel) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: sel ? accentGradient(accent) : null,
                  boxShadow: sel
                      ? [BoxShadow(color: accent.withValues(alpha: 0.45), blurRadius: 14)]
                      : null,
                ),
                child: Center(
                  child: _badge(i, NavIcon(
                      kind: items[i].kind,
                      selected: sel,
                      color: sel ? Colors.white : _muted(context),
                      cutout: sel ? accent : null)),
                ),
              );
            }, align: MainAxisAlignment.center),
          ),
        ),
      ),
    );
  }

  Widget _neon(BuildContext context) {
    final accent = appState.accent;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            color: const Color(0xFF07070D).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: accent.withValues(alpha: 0.7), width: 1.3),
            boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.35), blurRadius: 22)],
          ),
          child: _items(context, (i, sel) {
            return SizedBox(
              width: 64,
              child: Center(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: sel
                        ? [BoxShadow(color: accent.withValues(alpha: 0.8), blurRadius: 16)]
                        : null,
                  ),
                  child: _badge(i, NavIcon(
                      kind: items[i].kind,
                      selected: sel,
                      color: sel ? accent : Colors.white54,
                      cutout: const Color(0xFF07070D))),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _badge(int i, Widget icon) {
    if (items[i].kind != NavIconKind.chats || chatsBadge <= 0) return icon;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -8,
          top: -6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 18),
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: kDanger, borderRadius: BorderRadius.circular(9)),
            child: Text(chatsBadge > 99 ? '99+' : '$chatsBadge',
                style: const TextStyle(
                    color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }
}

/// Иконка нижнего меню, нарисованная вручную: плавно «заливается» при выборе
/// и слегка подпрыгивает.
class NavIcon extends StatelessWidget {
  final NavIconKind kind;
  final bool selected;
  final Color color;
  final Color? cutout; // цвет «вырезов» (точки, ручки) на залитой иконке
  final double size;
  const NavIcon(
      {super.key,
      required this.kind,
      required this.selected,
      required this.color,
      this.cutout,
      this.size = 25});

  @override
  Widget build(BuildContext context) {
    final bg = cutout ?? Theme.of(context).colorScheme.surface;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: selected ? 1 : 0),
      duration: Duration(milliseconds: appState.motion ? 380 : 0),
      curve: Curves.easeOutCubic,
      builder: (_, t, __) {
        final bounce = selected ? 1 + 0.14 * math.sin(t * math.pi) : 1.0;
        return Transform.scale(
          scale: bounce,
          child: CustomPaint(
            size: Size.square(size),
            painter: _NavPainter(kind, t, color, bg),
          ),
        );
      },
    );
  }
}

class _NavPainter extends CustomPainter {
  final NavIconKind kind;
  final double t;
  final Color color;
  final Color bg;
  _NavPainter(this.kind, this.t, this.color, this.bg);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color.withValues(alpha: t);
    switch (kind) {
      case NavIconKind.chats:
        // Современный плавный диалоговый пузырь
        final bubble = Path()
          ..moveTo(6.5, 4)
          ..lineTo(17.5, 4)
          ..quadraticBezierTo(21, 4, 21, 7.5)
          ..lineTo(21, 14.5)
          ..quadraticBezierTo(21, 18, 17.5, 18)
          ..lineTo(11, 18)
          ..lineTo(6.5, 21.2)
          ..quadraticBezierTo(5.5, 21.8, 5.5, 20.5)
          ..lineTo(5.5, 18)
          ..lineTo(6.5, 18)
          ..quadraticBezierTo(3, 18, 3, 14.5)
          ..lineTo(3, 7.5)
          ..quadraticBezierTo(3, 4, 6.5, 4)
          ..close();
        if (t > 0) canvas.drawPath(bubble, fill);
        canvas.drawPath(bubble, stroke);
        final dotColor = Color.lerp(color, bg, t)!;
        final dotPaint = Paint()..color = dotColor;
        for (final x in const [8.0, 12.0, 16.0]) {
          canvas.drawCircle(Offset(x, 11.0), 1.35, dotPaint);
        }
        break;
      case NavIconKind.store:
        // Премиальная сумка бутика с кристальной эмблемой
        final bag = Path()
          ..moveTo(5.5, 8.5)
          ..lineTo(18.5, 8.5)
          ..quadraticBezierTo(20.5, 8.5, 20.2, 11)
          ..lineTo(19.2, 19.2)
          ..quadraticBezierTo(19, 21, 17, 21)
          ..lineTo(7, 21)
          ..quadraticBezierTo(5, 21, 4.8, 19.2)
          ..lineTo(3.8, 11)
          ..quadraticBezierTo(3.5, 8.5, 5.5, 8.5)
          ..close();
        if (t > 0) canvas.drawPath(bag, fill);
        canvas.drawPath(bag, stroke);
        final handle = Path()
          ..moveTo(8.5, 9.5)
          ..lineTo(8.5, 6.5)
          ..quadraticBezierTo(8.5, 4, 12, 4)
          ..quadraticBezierTo(15.5, 4, 15.5, 6.5)
          ..lineTo(15.5, 9.5);
        canvas.drawPath(handle, stroke);
        final emblem = Path()
          ..moveTo(12, 12.5)
          ..lineTo(13.6, 14.5)
          ..lineTo(12, 16.5)
          ..lineTo(10.4, 14.5)
          ..close();
        canvas.drawPath(emblem, Paint()..color = Color.lerp(color.withValues(alpha: 0.6), bg, t)!);
        break;
      case NavIconKind.settings:
        // Современные ползунки настроек (Apple / Telegram)
        const ys = [6.8, 12.0, 17.2];
        const off = [8.5, 15.5, 10.0];
        const on = [15.5, 8.5, 14.5];
        for (var i = 0; i < 3; i++) {
          final linePath = Path()
            ..moveTo(4, ys[i])
            ..lineTo(20, ys[i]);
          canvas.drawPath(linePath, stroke);
        }
        for (var i = 0; i < 3; i++) {
          final x = off[i] + (on[i] - off[i]) * t;
          final c = Offset(x, ys[i]);
          canvas.drawCircle(c, 3.0, Paint()..color = bg);
          if (t > 0) canvas.drawCircle(c, 3.0, fill);
          canvas.drawCircle(c, 3.0, stroke);
        }
        break;
      case NavIconKind.profile:
        // Аккуратный профиль с гладкими контурами
        final head = Path()..addOval(Rect.fromCircle(center: const Offset(12, 7.8), radius: 4.2));
        final body = Path()
          ..moveTo(4.6, 20.2)
          ..cubicTo(4.6, 15.8, 8, 13.8, 12, 13.8)
          ..cubicTo(16, 13.8, 19.4, 15.8, 19.4, 20.2)
          ..quadraticBezierTo(19.4, 21, 18.2, 21)
          ..lineTo(5.8, 21)
          ..quadraticBezierTo(4.6, 21, 4.6, 20.2)
          ..close();
        if (t > 0) {
          canvas.drawPath(head, fill);
          canvas.drawPath(body, fill);
        }
        canvas.drawPath(head, stroke);
        canvas.drawPath(body, stroke);
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _NavPainter old) =>
      old.t != t || old.color != color || old.bg != bg || old.kind != kind;
}
