import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────
// Аватар с градиентом, фото, значками и индикатором «в сети»
// ─────────────────────────────────────────────────────────────

class Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double size;
  final double? radius;      // null — круг
  final IconData? icon;      // вместо буквы (группы/каналы)
  final bool online;
  final bool useAccent;
  const Avatar({
    super.key,
    required this.name,
    this.url,
    this.size = 48,
    this.radius,
    this.icon,
    this.online = false,
    this.useAccent = false,
  });

  @override
  Widget build(BuildContext context) {
    final has = url != null && url!.isNotEmpty;
    final full = has ? (url!.startsWith('http') ? url! : '$kBaseUrl$url') : null;
    final base = avatarColor(name.isEmpty ? '?' : name);
    final gradient = useAccent
        ? accentGradient(appState.accent)
        : LinearGradient(colors: [
            base,
            HSLColor.fromColor(base).withLightness(0.66).toColor(),
          ], begin: Alignment.topLeft, end: Alignment.bottomRight);
    final shape = radius == null
        ? const BoxDecoration(shape: BoxShape.circle)
        : BoxDecoration(borderRadius: BorderRadius.circular(radius!));
    final letter = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final core = Container(
      width: size,
      height: size,
      decoration: shape.copyWith(gradient: gradient),
      clipBehavior: Clip.antiAlias,
      child: has
          ? Image.network(full!,
              fit: BoxFit.cover,
              width: size,
              height: size,
              gaplessPlayback: true,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 512).toInt(),
              cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(48, 512).toInt(),
              errorBuilder: (_, _, _) => _fallback(letter))
          : _fallback(letter),
    );
    if (!online) return RepaintBoundary(child: core);
    final dot = (size * 0.27).clamp(10.0, 16.0);
    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          core,
          Positioned(
            right: radius == null ? 0 : -1,
            bottom: radius == null ? 0 : -1,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: kSuccess,
                shape: BoxShape.circle,
                border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor, width: 2.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(String letter) => Center(
        child: icon != null
            ? Icon(icon, color: Colors.white, size: size * 0.44)
            : Text(letter,
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: size * 0.4)),
      );
}

/// Имя со значками: ✓ (официальный), ⭐ (Premium), «бот».
class NameBadges extends StatelessWidget {
  final String name;
  final bool verified;
  final bool premium;
  final bool bot;
  final TextStyle? style;
  final int maxLines;
  final String? emoji;
  const NameBadges(this.name,
      {super.key,
      this.verified = false,
      this.premium = false,
      this.bot = false,
      this.style,
      this.maxLines = 1,
      this.emoji});

  @override
  Widget build(BuildContext context) {
    final st = style ?? const TextStyle(fontWeight: FontWeight.w700, fontSize: 16);
    final sz = (st.fontSize ?? 16) * 0.95;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(name,
              maxLines: maxLines, overflow: TextOverflow.ellipsis, style: st),
        ),
        if (verified) ...[
          const SizedBox(width: 4),
          Icon(AppIcons.verified, size: sz, color: appState.accent),
        ],
        if (emoji != null && emoji!.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(emoji!, style: TextStyle(fontSize: sz * 0.92, height: 1.1)),
        ] else if (premium) ...[
          const SizedBox(width: 4),
          Icon(AppIcons.star, size: sz, color: kPremium),
        ],
        if (bot) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
                color: appState.accent.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6)),
            child: Text('бот',
                style: TextStyle(
                    color: appState.accent,
                    fontSize: sz * 0.7,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Карточки и строки настроек
// ─────────────────────────────────────────────────────────────

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                color: subtleText(context),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5)),
      );
}

class SectionCard extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsets margin;
  const SectionCard(
      {super.key, required this.children, this.margin = EdgeInsets.zero});
  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (i < children.length - 1) {
        items.add(Padding(
          padding: const EdgeInsets.only(left: 64),
          child: Divider(height: 1, thickness: 1, color: hairline(context)),
        ));
      }
    }
    return Container(
      margin: margin,
      decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(kRadiusL)),
      clipBehavior: Clip.antiAlias,
      child: Column(children: items),
    );
  }
}

class SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final Color? iconColor;
  final bool chevron;
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.iconColor,
    this.chevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      leading: IconTile(icon, color: iconColor, danger: danger),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: danger ? kDanger : null)),
      subtitle: subtitle != null && subtitle!.isNotEmpty
          ? Text(subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subtleText(context), fontSize: 13))
          : null,
      trailing: trailing ??
          (onTap != null && chevron
              ? Icon(AppIcons.chevronRight, color: subtleText(context), size: 20)
              : null),
    );
  }
}

class SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  const SwitchTile(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      required this.value,
      required this.onChanged});
  @override
  Widget build(BuildContext context) => SettingsTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        onTap: () => onChanged(!value),
        trailing: Switch(value: value, onChanged: onChanged),
      );
}

// ─────────────────────────────────────────────────────────────
// Кнопки
// ─────────────────────────────────────────────────────────────

/// Нажатие с лёгким «вдавливанием».
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final double scale;
  const Pressable(
      {super.key,
      required this.child,
      this.onTap,
      this.onLongPress,
      this.scale = 0.96});
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.onTap == null ? null : (_) => setState(() => _down = true),
      onTapUp: widget.onTap == null ? null : (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: AnimatedScale(
        scale: _down && appState.motion ? widget.scale : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// Главная кнопка с градиентом и состоянием загрузки.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool loading;
  final IconData? icon;
  final bool danger;
  final Gradient? gradient;
  const PrimaryButton(
      {super.key,
      required this.label,
      this.onTap,
      this.loading = false,
      this.icon,
      this.danger = false,
      this.gradient});

  @override
  Widget build(BuildContext context) {
    final g = gradient ??
        (danger
            ? const LinearGradient(colors: [Color(0xFFF43F5E), Color(0xFFFB7185)])
            : accentGradient(appState.accent));
    final shadow = danger ? kDanger : appState.accent;
    final disabled = onTap == null || loading;
    return Pressable(
      onTap: disabled ? null : onTap,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 180),
        opacity: onTap == null ? 0.5 : 1,
        child: Container(
          height: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: g,
            borderRadius: BorderRadius.circular(kRadius),
            boxShadow: [
              BoxShadow(
                  color: shadow.withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 8)),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: loading
                ? const SizedBox(
                    key: ValueKey('l'),
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.6, color: Colors.white))
                : Row(
                    key: const ValueKey('t'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(label,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 16)),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

/// Поле ввода в фирменном стиле.
class AppTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final int maxLines;
  final int? maxLength;
  final bool obscure;
  final Widget? suffix;
  final TextInputType? keyboard;
  final bool autofocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final String? prefixText;
  const AppTextField({
    super.key,
    required this.controller,
    required this.hint,
    this.icon,
    this.maxLines = 1,
    this.maxLength,
    this.obscure = false,
    this.suffix,
    this.keyboard,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.prefixText,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: obscure ? 1 : maxLines,
      maxLength: maxLength,
      obscureText: obscure,
      keyboardType: keyboard,
      autofocus: autofocus,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
        counterText: '',
        prefixText: prefixText,
        prefixIcon:
            icon != null ? Icon(icon, color: subtleText(context), size: 20) : null,
        suffixIcon: suffix,
        fillColor: cardColor(context),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Листы, диалоги, тосты
// ─────────────────────────────────────────────────────────────

/// Красивый нижний лист: ручка сверху, скругления, отступ от краёв.
/// Красивый нижний лист: ручка сверху, скругления, 120 FPS свайп сверху вниз для закрытия.
Future<T?> showAppSheet<T>(BuildContext context,
    {required Widget Function(BuildContext) builder,
    bool scrollable = false}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: scrollable,
    backgroundColor: Colors.transparent,
    enableDrag: false,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: cardColor(ctx),
          borderRadius: BorderRadius.circular(kRadiusL),
        ),
        clipBehavior: Clip.antiAlias,
        child: SafeArea(
          top: false,
          child: SwipeDismissibleSheet(
            scrollable: scrollable,
            onDismiss: () => Navigator.of(ctx).pop(),
            child: builder(ctx),
          ),
        ),
      ),
    ),
  );
}

/// Обертка модального листа с поддержкой плавного свайпа вниз для закрытия (120 FPS, пружинная физика).
class SwipeDismissibleSheet extends StatefulWidget {
  final Widget child;
  final VoidCallback onDismiss;
  final bool scrollable;

  const SwipeDismissibleSheet({
    super.key,
    required this.child,
    required this.onDismiss,
    this.scrollable = false,
  });

  @override
  State<SwipeDismissibleSheet> createState() => _SwipeDismissibleSheetState();
}

class _SwipeDismissibleSheetState extends State<SwipeDismissibleSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final ValueNotifier<double> _offsetNotifier = ValueNotifier<double>(0.0);
  double _currentY = 0.0;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _anim.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  void _onDragStart() {
    if (_dismissing) return;
    _anim.stop();
  }

  void _onDragUpdate(double delta) {
    if (_dismissing) return;
    _currentY = (_currentY + delta).clamp(0.0, 1200.0);
    _offsetNotifier.value = _currentY;
  }

  void _onDragEnd(double velocity) {
    if (_dismissing) return;
    final h = MediaQuery.of(context).size.height;
    final shouldDismiss = _currentY > 85 || velocity > 650;

    if (shouldDismiss) {
      _dismissing = true;
      final start = _currentY;
      final target = h;
      final durationMs = ((target - start) / (velocity.abs().clamp(1000.0, 3200.0)) * 1000)
          .clamp(100, 220)
          .toInt();

      _anim.duration = Duration(milliseconds: durationMs);
      final curveAnim = CurvedAnimation(parent: _anim, curve: Curves.easeInQuad);
      final tween = Tween<double>(begin: start, end: target).animate(curveAnim);

      void listener() {
        _offsetNotifier.value = tween.value;
      }

      tween.addListener(listener);
      _anim.forward(from: 0).then((_) {
        tween.removeListener(listener);
        widget.onDismiss();
      });
    } else {
      final start = _currentY;
      _anim.duration = const Duration(milliseconds: 220);
      final curveAnim = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);
      final tween = Tween<double>(begin: start, end: 0.0).animate(curveAnim);

      void listener() {
        _currentY = tween.value;
        _offsetNotifier.value = tween.value;
      }

      tween.addListener(listener);
      _anim.forward(from: 0).then((_) {
        tween.removeListener(listener);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = widget.child;

    if (widget.scrollable) {
      content = NotificationListener<ScrollNotification>(
        onNotification: (notif) {
          if (_dismissing) return false;
          if (notif is OverscrollNotification) {
            if (notif.overscroll < 0) {
              _onDragUpdate(-notif.overscroll);
            }
          } else if (notif is ScrollUpdateNotification) {
            if (_currentY > 0 && notif.scrollDelta != null) {
              _onDragUpdate(-notif.scrollDelta!);
            }
          } else if (notif is ScrollEndNotification) {
            if (_currentY > 0) {
              _onDragEnd(notif.dragDetails?.primaryVelocity ?? 0);
            }
          }
          return false;
        },
        child: content,
      );
    } else {
      content = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragStart: (_) => _onDragStart(),
        onVerticalDragUpdate: (d) => _onDragUpdate(d.primaryDelta ?? 0),
        onVerticalDragEnd: (d) => _onDragEnd(d.primaryVelocity ?? 0),
        child: content,
      );
    }

    return ValueListenableBuilder<double>(
      valueListenable: _offsetNotifier,
      builder: (context, offset, child) {
        return Transform.translate(
          offset: Offset(0, offset),
          child: child,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Ручка-ползунок сверху с широкой областью нажатия для удобного свайпа вниз
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => _onDragStart(),
            onVerticalDragUpdate: (d) => _onDragUpdate(d.primaryDelta ?? 0),
            onVerticalDragEnd: (d) => _onDragEnd(d.primaryVelocity ?? 0),
            child: Container(
              height: 36,
              width: double.infinity,
              alignment: Alignment.center,
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: subtleText(context).withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Flexible(child: content),
        ],
      ),
    );
  }
}

/// Пункт меню в листе.
class SheetItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  final bool danger;
  final String? subtitle;
  const SheetItem(
      {super.key,
      required this.icon,
      required this.title,
      required this.onTap,
      this.danger = false,
      this.subtitle});
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: IconTile(icon, size: 34, danger: danger),
        title: Text(title,
            style: TextStyle(
                fontWeight: FontWeight.w600, color: danger ? kDanger : null)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!, style: TextStyle(color: subtleText(context))),
      );
}

/// Подтверждение. true — пользователь согласился.
Future<bool> confirm(BuildContext context,
    {required String title,
    String? body,
    String action = 'Да',
    bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: body == null ? null : Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action,
                style: TextStyle(
                    color: danger ? kDanger : appState.accent,
                    fontWeight: FontWeight.w800))),
      ],
    ),
  );
  return r == true;
}

/// Спросить строку (название, код и т.п.).
Future<String?> askText(BuildContext context,
    {required String title,
    String hint = '',
    String initial = '',
    String action = 'Готово',
    int maxLength = 128,
    TextInputType? keyboard}) {
  final c = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLength: maxLength,
        keyboardType: keyboard,
        decoration: InputDecoration(
            hintText: hint,
            counterText: '',
            fillColor: Theme.of(ctx).scaffoldBackgroundColor),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: Text(action,
                style: const TextStyle(fontWeight: FontWeight.w800))),
      ],
    ),
  );
}

/// Короткое всплывающее уведомление.
void toast(BuildContext context, String text, {IconData? icon, bool error = false}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m.hideCurrentSnackBar();
  m.showSnackBar(SnackBar(
    duration: const Duration(milliseconds: 2400),
    content: Row(
      children: [
        Icon(icon ?? (error ? AppIcons.circleAlert : AppIcons.circleCheck),
            color: error ? const Color(0xFFFB7185) : const Color(0xFF86EFAC),
            size: 20),
        const SizedBox(width: 12),
        Expanded(child: Text(text)),
      ],
    ),
  ));
}

// ─────────────────────────────────────────────────────────────
// Пустые состояния и анимации
// ─────────────────────────────────────────────────────────────

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  /// Картинка маскота из assets/mascot (без расширения) вместо иконки.
  final String? mascot;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      this.subtitle,
      this.action,
      this.mascot});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: FadeSlideIn(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (mascot != null)
                MascotArt(mascot!, size: 176)
              else
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    color: appState.accent.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 38, color: appState.accent),
                ),
              const SizedBox(height: 18),
              Text(title,
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              if (subtitle != null) ...[
                const SizedBox(height: 6),
                Text(subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtleText(context), height: 1.4)),
              ],
              if (action != null) ...[const SizedBox(height: 18), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Маскот Конни: картинка из assets/mascot, мягко «дышит» и покачивается.
class MascotArt extends StatefulWidget {
  final String name;
  final double size;
  const MascotArt(this.name, {super.key, this.size = 170});
  @override
  State<MascotArt> createState() => _MascotArtState();
}

class _MascotArtState extends State<MascotArt> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 3200));

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
    final s = widget.size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final img = Image.asset('assets/mascot/${widget.name}.webp',
        width: s,
        height: s,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        cacheWidth: (s * dpr).round().clamp(64, 560).toInt(),
        errorBuilder: (_, _, _) => SizedBox(width: s, height: s));
    return SizedBox(
      width: s,
      height: s + 10,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, child) {
          // один полный цикл синуса — начало и конец совпадают, без рывков
          final t = _c.value * 2 * math.pi;
          final dy = math.sin(t) * 5;
          final sc = 1 + math.sin(t) * 0.012;
          final shadowW = 0.55 - math.sin(t) * 0.05;
          return Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned(
                bottom: 0,
                child: Container(
                  width: s * shadowW,
                  height: 10,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: RadialGradient(colors: [
                      Colors.black.withValues(alpha: 0.16),
                      Colors.black.withValues(alpha: 0),
                    ]),
                  ),
                ),
              ),
              Transform.translate(
                offset: Offset(0, dy),
                child: Transform.scale(scale: sc, child: child),
              ),
            ],
          );
        },
        child: img,
      ),
    );
  }
}

/// Плавное появление (снизу + прозрачность). delay — для «лесенки» в списках.
class FadeSlideIn extends StatefulWidget {
  final Widget child;
  final int delayMs;
  final double dy;
  const FadeSlideIn({super.key, required this.child, this.delayMs = 0, this.dy = 12});
  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  // коротко и почти без задержек: экран должен «появляться», а не «загружаться»
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 240));
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide =
      Tween(begin: Offset(0, widget.dy / 250), end: Offset.zero).animate(_a);

  @override
  void initState() {
    super.initState();
    if (!appState.motion) {
      _c.value = 1;
    } else if (widget.delayMs <= 0) {
      _c.forward();
    } else {
      Future.delayed(Duration(milliseconds: widget.delayMs ~/ 2), () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // FadeTransition/SlideTransition не перестраивают виджеты каждый кадр
    return FadeTransition(
      opacity: _a,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

/// «Скелетон» — мерцающая заглушка на время загрузки.
class Shimmer extends StatefulWidget {
  final double width;
  final double height;
  final double radius;
  const Shimmer({super.key, this.width = double.infinity, this.height = 14, this.radius = 8});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = subtleText(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withValues(alpha: 0.10 + 0.10 * _c.value),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// Список-скелетон для загрузки чатов/участников.
class ListSkeleton extends StatelessWidget {
  final int count;
  const ListSkeleton({super.key, this.count = 7});
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            child: Row(
              children: [
                const Shimmer(width: 52, height: 52, radius: 18),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Shimmer(width: 120 + (i % 3) * 30.0, height: 14),
                      const SizedBox(height: 8),
                      Shimmer(width: 180 + (i % 2) * 40.0, height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Бейдж-счётчик непрочитанных.
class CountBadge extends StatelessWidget {
  final int count;
  final bool muted;
  const CountBadge(this.count, {super.key, this.muted = false});
  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: count > 0 ? 1 : 0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      child: Container(
        constraints: const BoxConstraints(minWidth: 22),
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: muted ? subtleText(context).withValues(alpha: 0.6) : appState.accent,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(count > 999 ? '999+' : '$count',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );
  }
}

/// Текст «был(а) …» по времени последнего захода.
String lastSeenText(DateTime? d, {bool online = false}) {
  if (online) return 'в сети';
  if (d == null) return 'был(а) недавно';
  final local = d.toLocal();
  final now = DateTime.now();
  final diff = now.difference(local);
  if (diff.inMinutes < 1) return 'был(а) только что';
  if (diff.inMinutes < 60) return 'был(а) ${diff.inMinutes} мин назад';
  final hhmm =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(local.year, local.month, local.day);
  final dd = today.difference(that).inDays;
  if (dd == 0) return 'был(а) в $hhmm';
  if (dd == 1) return 'был(а) вчера в $hhmm';
  return 'был(а) ${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')} в $hhmm';
}

/// Склонение: 1 участник, 2 участника, 5 участников.
String plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return '$n $one';
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return '$n $few';
  return '$n $many';
}

// ─────────────────────────────────────────────────────────────
// Иконки-плашки: единый стиль для меню, профилей и листов.
// Вид выбирается в «Оформление → Иконки».
// ─────────────────────────────────────────────────────────────

const Color _cRed = Color(0xFFEF4444);
const Color _cOrange = Color(0xFFF97316);
const Color _cAmber = Color(0xFFF5A60B);
const Color _cGreen = Color(0xFF22C55E);
const Color _cTeal = Color(0xFF14B8A6);
const Color _cSky = Color(0xFF0EA5E9);
const Color _cBlue = Color(0xFF3B82F6);
const Color _cIndigo = Color(0xFF6366F1);
const Color _cPurple = Color(0xFFA855F7);
const Color _cPink = Color(0xFFEC4899);
const Color _cSlate = Color(0xFF64748B);

Map<int, Color>? _tintCache;

/// «родной» цвет иконки (для цветных стилей). null — берём акцент.
Color? iconTint(IconData icon) {
  final m = _tintCache ??= () {
    final r = <int, Color>{};
    void put(Color c, List<IconData> list) {
      for (final i in list) {
        r.putIfAbsent(i.codePoint, () => c);
      }
    }

    put(_cRed, [
      AppIcons.trash2, AppIcons.ban, AppIcons.logOut, AppIcons.flag, AppIcons.userX,
      AppIcons.eraser, AppIcons.messageCircleOff, AppIcons.shieldOff, AppIcons.userMinus,
      AppIcons.searchX, AppIcons.x,
    ]);
    put(_cOrange, [
      AppIcons.bell, AppIcons.bellDot, AppIcons.bellOff, AppIcons.partyPopper,
      AppIcons.cake, AppIcons.megaphone, AppIcons.pin,
    ]);
    put(_cAmber, [
      AppIcons.crown, AppIcons.star, AppIcons.sparkles, AppIcons.lightbulb,
      AppIcons.ticket, AppIcons.hand, AppIcons.trophy, AppIcons.flame,
    ]);
    put(_cGreen, [
      AppIcons.phone, AppIcons.circleCheck, AppIcons.checkCheck, AppIcons.userCheck,
      AppIcons.shieldCheck, AppIcons.userPlus, AppIcons.batteryCharging,
      AppIcons.messageCirclePlus, AppIcons.plus, AppIcons.refreshCw, AppIcons.lockOpen,
      AppIcons.chart, AppIcons.messageCircle, AppIcons.wallet, AppIcons.store,
    ]);
    put(_cTeal, [
      AppIcons.mapPin, AppIcons.wifiOff, AppIcons.monitorSmartphone, AppIcons.timer,
      AppIcons.clock, AppIcons.circleHelp, AppIcons.smartphone,
    ]);
    put(_cSky, [
      AppIcons.atSign, AppIcons.link, AppIcons.globe, AppIcons.languages, AppIcons.mail,
      AppIcons.mailCheck, AppIcons.send, AppIcons.forward, AppIcons.reply,
      AppIcons.download, AppIcons.verified, AppIcons.bot, AppIcons.user, AppIcons.userRound,
      AppIcons.share2, AppIcons.coin,
    ]);
    put(_cBlue, [
      AppIcons.users, AppIcons.messageSquare, AppIcons.messageSquareDot, AppIcons.info,
      AppIcons.userSearch, AppIcons.search,
    ]);
    put(_cIndigo, [
      AppIcons.lock, AppIcons.lockKeyhole, AppIcons.keyRound, AppIcons.fingerprint,
      AppIcons.shield, AppIcons.shieldPlus, AppIcons.shieldMinus, AppIcons.eye,
      AppIcons.eyeOff, AppIcons.database,
    ]);
    put(_cPurple, [
      AppIcons.palette, AppIcons.brush, AppIcons.wallpaper, AppIcons.image, AppIcons.images,
      AppIcons.camera, AppIcons.type, AppIcons.circlePlay, AppIcons.play, AppIcons.pencil,
      AppIcons.brushSpark, AppIcons.cover,
    ]);
    put(_cPink, [
      AppIcons.heart, AppIcons.messageCircleHeart, AppIcons.mic, AppIcons.volume2,
      AppIcons.vibrate, AppIcons.headset, AppIcons.smile, AppIcons.gift, AppIcons.stories,
    ]);
    put(_cSlate, [
      AppIcons.archive, AppIcons.archiveRestore, AppIcons.copy, AppIcons.fileText,
      AppIcons.squareSlash, AppIcons.webhook, AppIcons.listChecks,
    ]);
    return r;
  }();
  return m[icon.codePoint];
}

class IconTile extends StatelessWidget {
  final IconData icon;
  final Color? color;
  final double size;
  final bool danger;
  final String? style; // null — из настроек
  const IconTile(this.icon,
      {super.key, this.color, this.size = 38, this.danger = false, this.style});

  @override
  Widget build(BuildContext context) {
    final st = style ?? appState.iconStyleEff;
    final colorful = st == 'color' || st == 'pastel' || st == 'glow';
    final tint = danger
        ? kDanger
        : (color ?? (colorful ? (iconTint(icon) ?? appState.accent) : appState.accent));
    final r = BorderRadius.circular(size * 0.31);
    final isz = size * 0.53;
    final dark = Theme.of(context).brightness == Brightness.dark;

    switch (st) {
      case 'color':
        final hsl = HSLColor.fromColor(tint);
        final light = hsl.withLightness((hsl.lightness + 0.12).clamp(0.0, 0.85)).toColor();
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
                colors: [light, tint], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(
                  color: tint.withValues(alpha: dark ? 0.28 : 0.32),
                  blurRadius: 8,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: isz),
        );
      case 'glow':
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: r,
            color: tint.withValues(alpha: dark ? 0.10 : 0.08),
            border: Border.all(color: tint.withValues(alpha: 0.75), width: 1.3),
            boxShadow: [BoxShadow(color: tint.withValues(alpha: 0.45), blurRadius: 12)],
          ),
          child: Icon(icon, color: tint, size: isz, shadows: [
            Shadow(color: tint.withValues(alpha: 0.9), blurRadius: 10),
          ]),
        );
      case 'aurora':
        final h = HSLColor.fromColor(tint);
        final shift = (icon.codePoint % 7) * 18.0;
        final a = h.withHue((h.hue + shift) % 360).toColor();
        final b = h.withHue((h.hue + shift + 70) % 360).toColor();
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: r,
            gradient: LinearGradient(
                colors: [a, b], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [
              BoxShadow(color: b.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 3)),
            ],
          ),
          child: Icon(icon, color: Colors.white, size: isz),
        );
      case 'mono':
        final fg = danger ? kDanger : Theme.of(context).colorScheme.onSurface;
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: r,
            color: fg.withValues(alpha: 0.07),
          ),
          child: Icon(icon, color: fg.withValues(alpha: 0.85), size: isz),
        );
      default: // pastel, soft
        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            borderRadius: r,
            color: tint.withValues(alpha: dark ? 0.18 : 0.14),
          ),
          child: Icon(icon, color: tint, size: isz),
        );
    }
  }
}

/// Кнопка быстрого действия в шапке профиля (кладётся в Row).
class ProfileAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final bool danger;
  /// Подпись под кнопкой. По умолчанию — только иконка (подпись — во всплывающей подсказке).
  final bool showLabel;
  /// Главная кнопка — залита цветом акцента.
  final bool primary;
  const ProfileAction(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap,
      this.color,
      this.danger = false,
      this.showLabel = false,
      this.primary = false});

  @override
  Widget build(BuildContext context) {
    final tint = danger ? kDanger : (color ?? appState.accent);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final circle = Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: primary
            ? accentGradient(tint)
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  tint.withValues(alpha: dark ? 0.24 : 0.16),
                  tint.withValues(alpha: dark ? 0.12 : 0.08),
                ],
              ),
        boxShadow: primary
            ? [BoxShadow(color: tint.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 5))]
            : null,
      ),
      child: Icon(icon, size: 26, color: primary ? Colors.white : tint),
    );
    return Expanded(
      child: Tooltip(
        message: label,
        child: Pressable(
          onTap: onTap,
          scale: 0.9,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              circle,
              if (showLabel) ...[
                const SizedBox(height: 6),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: danger ? kDanger : subtleText(context))),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Строка с данными (юзернейм, телефон…) с плашкой-иконкой.
class InfoTile extends StatelessWidget {
  final IconData icon;
  final Widget title;
  final String? label;
  final VoidCallback? onTap;
  final Widget? trailing;
  const InfoTile(
      {super.key, required this.icon, required this.title, this.label, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: IconTile(icon),
        title: DefaultTextStyle.merge(
            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600), child: title),
        subtitle: label == null
            ? null
            : Text(label!, style: TextStyle(color: subtleText(context), fontSize: 12.5)),
        trailing: trailing,
      );
}

// ─────────────────────────────────────────────────────────────
// Логотип Connecto: градиентная плашка и «C» дугой (без шрифта —
// поэтому выглядит одинаково с первого кадра и совпадает с иконкой).
// ─────────────────────────────────────────────────────────────

class AppLogo extends StatelessWidget {
  final double size;
  final Color? accent;
  final bool shadow;
  const AppLogo({super.key, this.size = 92, this.accent, this.shadow = true});

  @override
  Widget build(BuildContext context) {
    final a = accent ?? appState.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: accentGradient(a),
        borderRadius: BorderRadius.circular(size * 0.31),
        boxShadow: shadow
            ? [
                BoxShadow(
                    color: a.withValues(alpha: 0.45),
                    blurRadius: size * 0.4,
                    offset: Offset(0, size * 0.13)),
              ]
            : null,
      ),
      child: CustomPaint(painter: LogoCPainter()),
    );
  }
}

/// Белая «C» дугой со скруглёнными концами.
class LogoCPainter extends CustomPainter {
  final Color color;
  LogoCPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size s) {
    final r = s.width * 0.20;
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * 0.10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: s.center(Offset.zero), radius: r), math.pi / 4,
        math.pi * 1.5, false, p);
  }

  @override
  bool shouldRepaint(covariant LogoCPainter old) => old.color != color;
}


/// Ряд вариантов (темы, шрифты, рамки…): на телефоне — прокрутка вбок,
/// в широком окне — все варианты сразу, с переносом строк.
class ChoiceStrip extends StatelessWidget {
  final double height;
  final int itemCount;
  final double spacing;
  final IndexedWidgetBuilder itemBuilder;
  const ChoiceStrip(
      {super.key,
      required this.height,
      required this.itemCount,
      required this.itemBuilder,
      this.spacing = 10});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      if (box.maxWidth >= 560) {
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < itemCount; i++)
              SizedBox(height: height, child: itemBuilder(context, i)),
          ],
        );
      }
      return SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: itemCount,
          separatorBuilder: (_, _) => SizedBox(width: spacing),
          itemBuilder: itemBuilder,
        ),
      );
    });
  }
}
