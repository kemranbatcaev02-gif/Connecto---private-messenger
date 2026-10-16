import 'package:flutter/material.dart';

import '../app_state.dart';
import '../customization.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/frames.dart';
import '../widgets/ui.dart';
import 'appearance_screen.dart' show ColorPickerSheet, premiumGate;

/// Своя рамка (Premium): цвета, градиент, толщина, свечение, скругление, анимация.
/// Отдельно для плиток в списке чатов и для пузырей сообщений.
class FrameEditorScreen extends StatefulWidget {
  /// true — сразу открыть вкладку «Сообщения».
  final bool bubbles;
  const FrameEditorScreen({super.key, this.bubbles = false});

  @override
  State<FrameEditorScreen> createState() => _FrameEditorScreenState();
}

/// Готовые пары цветов для быстрого старта.
const List<List<Color>> _kPairs = [
  [Color(0xFF7C6CFF), Color(0xFF22D3EE)],
  [Color(0xFFFF3B8D), Color(0xFFFFB23B)],
  [Color(0xFF00E5A0), Color(0xFF00B4FF)],
  [Color(0xFFFFE08A), Color(0xFFB8860B)],
  [Color(0xFFFF4D4D), Color(0xFF8A2BE2)],
  [Color(0xFFB9FBC0), Color(0xFF98F5E1)],
  [Color(0xFFFFFFFF), Color(0xFF9CA3AF)],
  [Color(0xFF39FF14), Color(0xFF00FFFF)],
];

class _FrameEditorScreenState extends State<FrameEditorScreen> {
  late bool _bubbles = widget.bubbles;
  late FrameCustom _chat = appState.chatFrameCustom;
  late FrameCustom _bubble = appState.bubbleFrameCustom;

  FrameCustom get _c => _bubbles ? _bubble : _chat;
  set _c(FrameCustom v) => setState(() {
        if (_bubbles) {
          _bubble = v;
        } else {
          _chat = v;
        }
      });

  Future<void> _pickColor(bool second) async {
    final c = await showAppSheet<Color>(context,
        builder: (ctx) => ColorPickerSheet(
            initial: second ? _c.c2 : _c.c1, title: second ? 'Второй цвет' : 'Основной цвет'));
    if (c == null || !mounted) return;
    _c = second ? _c.copyWith(c2: c) : _c.copyWith(c1: c);
  }

  void _apply() {
    if (!appState.isPremium) {
      premiumGate(context, 'Своя рамка');
      return;
    }
    if (_bubbles) {
      appState.setFrames(bubble: 'custom', bubbleCustom: _bubble);
    } else {
      appState.setFrames(chat: 'custom', chatCustom: _chat);
    }
    toast(context, _bubbles ? 'Обводка сообщений сохранена' : 'Рамка чатов сохранена',
        icon: AppIcons.check);
  }

  // ── предпросмотр ──

  Widget _previewList() {
    final look = chatFrameLook(context, id: 'custom', custom: _chat)!;
    Widget tile(String name, String text, String time, int unread) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: FramedBox(
          look: look,
          radius: BorderRadius.circular(look.radius),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
            child: Row(
              children: [
                Avatar(name: name, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          Text(time, style: TextStyle(color: subtleText(context), fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Expanded(
                            child: Text(text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: subtleText(context), fontSize: 13.5)),
                          ),
                          if (unread > 0) CountBadge(unread),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(children: [
      tile('Алина', 'Смотри, какая рамка 😍', '12:41', 2),
      tile('Команда', 'Макс: вечером в зал?', '11:05', 0),
    ]);
  }

  Widget _previewBubbles() {
    final r = BorderRadius.circular(18);
    Widget bubble(String text, bool mine) {
      final look = bubbleFrameLook(context, mine, id: 'custom', custom: _bubble)!;
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: FramedBox(
            look: look,
            radius: r,
            clip: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 9, 13, 9),
              decoration: mine ? myBubbleDecoration(r) : otherBubbleDecoration(context, r),
              child: Text(text,
                  style: TextStyle(
                      fontSize: 15,
                      color: mine ? Colors.white : Theme.of(context).colorScheme.onSurface)),
            ),
          ),
        ),
      );
    }

    return Column(children: [
      bubble('Привет! Как тебе обводка?', false),
      bubble('Огонь, сама настроила 🔥', true),
    ]);
  }

  // ── элементы управления ──

  Widget _slider(String label, double v, double min, double max, String value,
      ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700))),
              Text(value, style: TextStyle(color: subtleText(context), fontSize: 13)),
            ],
          ),
          Slider(
            value: v.clamp(min, max),
            min: min,
            max: max,
            activeColor: appState.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _swatch(Color c, String label, VoidCallback onTap, {bool enabled = true}) {
    return Expanded(
      child: Opacity(
        opacity: enabled ? 1 : 0.4,
        child: Pressable(
          onTap: enabled ? onTap : null,
          child: Container(
            height: 54,
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hairline(context)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8)],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                Icon(AppIcons.colorize, size: 17, color: subtleText(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: const Text('Своя рамка')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Список чатов'), icon: Icon(AppIcons.frame)),
              ButtonSegment(value: true, label: Text('Сообщения'), icon: Icon(AppIcons.messageCircle)),
            ],
            selected: {_bubbles},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _bubbles = v.first),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Container(
              key: ValueKey(_bubbles),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              decoration: BoxDecoration(
                color: cardColor(context),
                borderRadius: BorderRadius.circular(kRadiusL),
              ),
              child: _bubbles ? _previewBubbles() : _previewList(),
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Цвета'),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _kPairs.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final pair = i == 0
                    ? [appState.accent, HSLColor.fromColor(appState.accent)
                        .withHue((HSLColor.fromColor(appState.accent).hue + 70) % 360)
                        .toColor()]
                    : _kPairs[i - 1];
                final sel = c.c1.toARGB32() == pair[0].toARGB32() &&
                    c.c2.toARGB32() == pair[1].toARGB32();
                return Pressable(
                  onTap: () => _c = c.copyWith(c1: pair[0], c2: pair[1]),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(colors: pair),
                      border: Border.all(
                          color: sel ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
                          width: 2.5),
                    ),
                    child: i == 0
                        ? const Icon(AppIcons.palette, color: Colors.white, size: 18)
                        : null,
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _swatch(c.c1, 'Основной', () => _pickColor(false)),
              const SizedBox(width: 10),
              _swatch(c.c2, 'Второй', () => _pickColor(true), enabled: c.twoColors),
            ],
          ),
          const SizedBox(height: 14),
          SectionCard(children: [
            SwitchTile(
              icon: AppIcons.gradient,
              title: 'Градиент из двух цветов',
              value: c.twoColors,
              onChanged: (v) => _c = c.copyWith(twoColors: v),
            ),
            SwitchTile(
              icon: AppIcons.sparkles,
              title: 'Анимация',
              subtitle: c.twoColors ? 'Цвета переливаются по кругу' : 'По рамке бежит блик',
              value: c.animated,
              onChanged: (v) => _c = c.copyWith(animated: v),
            ),
            _slider('Толщина', c.width, 0.5, 4, c.width.toStringAsFixed(1),
                (v) => _c = c.copyWith(width: v)),
            _slider('Свечение', c.glow, 0, 1, '${(c.glow * 100).round()}%',
                (v) => _c = c.copyWith(glow: v)),
            if (!_bubbles) ...[
              _slider('Скругление', c.radius, 6, 32, c.radius.round().toString(),
                  (v) => _c = c.copyWith(radius: v)),
              _slider('Заливка плитки', c.fill, 0, 1, '${(c.fill * 100).round()}%',
                  (v) => _c = c.copyWith(fill: v)),
            ],
            const SizedBox(height: 8),
          ]),
          if (_bubbles)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 6, 0),
              child: Text('Скругление пузырей — в «Размер текста и скругление».',
                  style: TextStyle(color: subtleText(context), fontSize: 12.5)),
            ),
          const SizedBox(height: 18),
          PrimaryButton(
            label: appState.isPremium ? 'Применить' : 'Применить · Premium',
            icon: appState.isPremium ? AppIcons.check : AppIcons.star,
            gradient: appState.isPremium ? accentGradient(appState.accent) : kPremiumGradient,
            onTap: _apply,
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () => setState(() {
                if (_bubbles) {
                  _bubble = const FrameCustom(width: 1.6, glow: 0.3);
                } else {
                  _chat = const FrameCustom();
                }
              }),
              child: const Text('Сбросить настройки'),
            ),
          ),
        ],
      ),
    );
  }
}
