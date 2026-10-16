import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../api.dart';
import '../app_state.dart';
import '../customization.dart';
import '../icons.dart';
import '../launcher_icon.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/frames.dart';
import '../widgets/glass_nav_bar.dart';
import '../widgets/ui.dart';
import 'chat_settings_screen.dart';
import 'frame_editor_screen.dart';
import 'name_color_screen.dart';
import 'premium_screen.dart';
import 'wallpaper_screen.dart';

/// Показать предложение Premium для закрытого варианта оформления.
void premiumGate(BuildContext context, String what) {
  showAppSheet(context, builder: (ctx) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: const BoxDecoration(gradient: kPremiumGradient, shape: BoxShape.circle),
            child: const Icon(AppIcons.star, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 14),
          Text('$what — в Premium',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
              'Премиум-темы, стили сообщений, шрифты, анимации, живые обои, '
              'эмодзи-статус и видео-обложка профиля.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(ctx), height: 1.4)),
          const SizedBox(height: 18),
          PrimaryButton(
            label: 'Узнать о Premium',
            gradient: kPremiumGradient,
            icon: AppIcons.star,
            onTap: () {
              Navigator.pop(ctx);
              Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
            },
          ),
        ],
      ),
    );
  });
}

/// «Оформление»: темы, цвета, стили сообщений, шрифты, анимации, меню, эффекты.
class AppearanceScreen extends StatelessWidget {
  const AppearanceScreen({super.key});

  bool _locked(Opt o) => o.premium && !appState.isPremium;

  void _pick(BuildContext context, Opt o, VoidCallback apply) {
    if (_locked(o)) {
      premiumGate(context, '«${o.title}»');
      return;
    }
    apply();
  }

  /// Выбор рамки: «Своя» открывает редактор, остальные применяются сразу.
  void _pickFrame(BuildContext context, Opt o, {required bool bubbles}) {
    if (_locked(o)) {
      premiumGate(context, '«${o.title}»');
      return;
    }
    if (o.id == 'custom') {
      Navigator.push(
          context, MaterialPageRoute(builder: (_) => FrameEditorScreen(bubbles: bubbles)));
      return;
    }
    if (bubbles) {
      appState.setFrames(bubble: o.id);
    } else {
      appState.setFrames(chat: o.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: const Text('Оформление'),
          actions: [
            IconButton(
              tooltip: 'Сбросить',
              icon: const Icon(AppIcons.refreshCw),
              onPressed: () async {
                final ok = await confirm(context,
                    title: 'Сбросить оформление?',
                    body: 'Тема, цвета, шрифт, стили и обои вернутся к стандартным.',
                    action: 'Сбросить');
                if (ok) appState.resetCustom();
              },
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            const FadeSlideIn(child: _LivePreview()),
            const SizedBox(height: 20),

            // ── режим ──
            const SectionLabel('Режим'),
            Row(children: [
              _mode(context, ThemeMode.light, AppIcons.sun, 'Светлый'),
              const SizedBox(width: 10),
              _mode(context, ThemeMode.dark, AppIcons.moon, 'Тёмный'),
              const SizedBox(width: 10),
              _mode(context, ThemeMode.system,
                  desktopUx ? AppIcons.monitor : AppIcons.smartphone, 'Системный'),
            ]),
            const SizedBox(height: 20),

            // ── темы ──
            const SectionLabel('Тема'),
            ChoiceStrip(
              height: 128,
              itemCount: kThemeStyles.length,
                itemBuilder: (context, i) {
                  final o = kThemeStyles[i];
                  final pal = kPalettes[o.id]!;
                  final dark = Theme.of(context).brightness == Brightness.dark;
                  return _Choice(
                    selected: appState.themeStyleEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 96,
                    onTap: () => _pick(context, o, () => appState.setCustom(theme: o.id)),
                    child: Container(
                      decoration: BoxDecoration(
                        color: dark ? pal.darkBg : pal.lightBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                              height: 14,
                              decoration: BoxDecoration(
                                  color: dark ? pal.darkCard : pal.lightCard,
                                  borderRadius: BorderRadius.circular(6))),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                                width: 40,
                                height: 12,
                                decoration: BoxDecoration(
                                    gradient: accentGradient(appState.accent),
                                    borderRadius: BorderRadius.circular(6))),
                          ),
                          const SizedBox(height: 5),
                          Container(
                              width: 34,
                              height: 12,
                              decoration: BoxDecoration(
                                  color: dark ? pal.darkCard : pal.lightCard,
                                  borderRadius: BorderRadius.circular(6))),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),

            // ── акцент ──
            const SectionLabel('Цвет акцента'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final c in kAccentPresets) _dot(context, c, false),
                  for (final c in kPremiumAccents) _dot(context, c, true),
                  _customDot(context),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── пузыри ──
            const SectionLabel('Стиль сообщений'),
            ChoiceStrip(
              height: 118,
              itemCount: kBubbleStyles.length,
                itemBuilder: (context, i) {
                  final o = kBubbleStyles[i];
                  final r = BorderRadius.circular(o.id == 'round' ? 14 : 10);
                  return _Choice(
                    selected: appState.bubbleStyleEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 104,
                    onTap: () => _pick(context, o, () => appState.setCustom(bubble: o.id)),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              width: 52,
                              height: 18,
                              decoration: otherBubbleDecoration(context, r, style: o.id),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Container(
                              width: 62,
                              height: 18,
                              decoration: myBubbleDecoration(r, style: o.id),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),

            // ── иконка приложения (Android) ──
            if (LauncherIcon.supported) ...[
              const SectionLabel('Иконка приложения'),
              const _LauncherIconPicker(),
              const SizedBox(height: 20),
            ],

            // ── рамки чатов ──
            const SectionLabel('Рамки чатов в списке'),
            ChoiceStrip(
              height: 124,
              itemCount: kChatFrames.length,
                itemBuilder: (context, i) {
                  final o = kChatFrames[i];
                  return _Choice(
                    selected: appState.chatFrameEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 104,
                    onTap: () => _pickFrame(context, o, bubbles: false),
                    child: _ChatFramePreview(id: o.id),
                  );
                },
              ),
            const SizedBox(height: 16),
            const SectionLabel('Обводка сообщений'),
            ChoiceStrip(
              height: 118,
              itemCount: kBubbleFrames.length,
                itemBuilder: (context, i) {
                  final o = kBubbleFrames[i];
                  return _Choice(
                    selected: appState.bubbleFrameEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 104,
                    onTap: () => _pickFrame(context, o, bubbles: true),
                    child: _BubbleFramePreview(id: o.id),
                  );
                },
              ),
            const SizedBox(height: 10),
            SectionCard(children: [
              SettingsTile(
                icon: AppIcons.tune,
                title: 'Своя рамка',
                subtitle: appState.isPremium
                    ? 'Цвета, градиент, толщина, свечение и анимация'
                    : 'Ручная настройка — в Premium',
                trailing: appState.isPremium
                    ? null
                    : const Icon(AppIcons.star, color: kPremium, size: 20),
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const FrameEditorScreen())),
              ),
            ]),
            const SizedBox(height: 20),

            // ── шрифт ──
            const SectionLabel('Шрифт'),
            ChoiceStrip(
              height: 96,
              itemCount: kFonts.length,
                itemBuilder: (context, i) {
                  final o = kFonts[i];
                  TextStyle st;
                  try {
                    st = GoogleFonts.getFont(o.id, fontSize: 24, fontWeight: FontWeight.w700);
                  } catch (_) {
                    st = const TextStyle(fontSize: 24, fontWeight: FontWeight.w700);
                  }
                  return _Choice(
                    selected: appState.fontEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 110,
                    onTap: () => _pick(context, o, () => appState.setCustom(font: o.id)),
                    child: Center(child: Text('Аа Bb', style: st)),
                  );
                },
              ),
            const SizedBox(height: 20),

            // ── анимации ──
            const SectionLabel('Анимация переходов'),
            SectionCard(children: [
              for (final o in kTransitions)
                _optTile(context, o, appState.transitionEff == o.id,
                    () => appState.setCustom(trans: o.id)),
              SettingsTile(
                icon: AppIcons.play,
                title: 'Посмотреть в деле',
                chevron: false,
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const _TransitionDemo())),
              ),
            ]),
            if (!appState.motion)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                child: Text('Анимации сейчас выключены (энергосбережение или настройки чатов).',
                    style: TextStyle(color: kWarning, fontSize: 12.5)),
              ),
            const SizedBox(height: 20),

            // ── меню ── (на компьютере меню слева, а не снизу)
            if (!desktopUx) ...[
            const SectionLabel('Нижнее меню'),
            ChoiceStrip(
              height: 112,
              itemCount: kNavStyles.length,
                itemBuilder: (context, i) {
                  final o = kNavStyles[i];
                  return _Choice(
                    selected: appState.navStyleEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 124,
                    onTap: () => _pick(context, o, () => appState.setCustom(nav: o.id)),
                    child: _NavPreview(style: o.id),
                  );
                },
              ),
            const SizedBox(height: 20),
            ],

            // ── иконки ──
            const SectionLabel('Иконки'),
            ChoiceStrip(
              height: 112,
              itemCount: kIconStyles.length,
                itemBuilder: (context, i) {
                  final o = kIconStyles[i];
                  return _Choice(
                    selected: appState.iconStyleEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 118,
                    onTap: () => _pick(context, o, () => appState.setCustom(icons: o.id)),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconTile(AppIcons.bell, size: 26, style: o.id),
                          const SizedBox(width: 5),
                          IconTile(AppIcons.lock, size: 26, style: o.id),
                          const SizedBox(width: 5),
                          IconTile(AppIcons.palette, size: 26, style: o.id),
                        ],
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),

            // ── рамка аватара ──
            const SectionLabel('Рамка аватара в профиле'),
            ChoiceStrip(
              height: 112,
              itemCount: kAvatarRings.length,
                itemBuilder: (context, i) {
                  final o = kAvatarRings[i];
                  return _Choice(
                    selected: appState.avatarRingEff == o.id,
                    locked: _locked(o),
                    label: o.title,
                    width: 92,
                    onTap: () => _pick(context, o, () => appState.setCustom(ring: o.id)),
                    child: Center(
                      child: AvatarRing(
                        style: o.id,
                        width: 3,
                        child: Avatar(
                            name: appState.displayName,
                            url: appState.avatarUrl,
                            size: 40,
                            useAccent: true),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),

            // ── живые обои ──
            Row(
              children: [
                const Expanded(child: SectionLabel('Живые обои чатов')),
                _premiumTag(),
              ],
            ),
            ChoiceStrip(
              height: 128,
              itemCount: kLiveWallpapers.length + 1,
                itemBuilder: (context, i) {
                  if (i == 0) {
                    return _Choice(
                      selected: appState.liveWallpaperEff < 0,
                      locked: false,
                      label: 'Выкл',
                      width: 80,
                      onTap: () => appState.setCustom(live: -1),
                      child: Center(child: Icon(AppIcons.ban, color: subtleText(context))),
                    );
                  }
                  final w = kLiveWallpapers[i - 1];
                  final locked = !appState.isPremium;
                  return _Choice(
                    selected: appState.liveWallpaperEff == i - 1,
                    locked: locked,
                    label: w.title,
                    width: 80,
                    onTap: () => locked
                        ? premiumGate(context, 'Живые обои')
                        : appState.setCustom(live: i - 1),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: LiveGradient(
                          colors: w.colors, period: const Duration(seconds: 6)),
                    ),
                  );
                },
              ),
            const SizedBox(height: 20),

            // ── эмодзи-статус ──
            Row(
              children: [
                const Expanded(child: SectionLabel('Эмодзи-статус')),
                _premiumTag(),
              ],
            ),
            const _EmojiStatusPicker(),
            const SizedBox(height: 20),

            SectionCard(children: [
              SettingsTile(
                icon: AppIcons.wallpaper,
                title: 'Обои чатов',
                subtitle: 'Градиентные фоны',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const WallpaperScreen())),
              ),
              SettingsTile(
                icon: AppIcons.brush,
                title: 'Цвет имени',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const NameColorScreen())),
              ),
              SettingsTile(
                icon: AppIcons.messageCircle,
                title: 'Размер текста и скругление',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ChatSettingsScreen())),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _premiumTag() => const Padding(
        padding: EdgeInsets.only(right: 14, bottom: 8),
        child: Row(
          children: [
            Icon(AppIcons.star, color: kPremium, size: 16),
            SizedBox(width: 3),
            Text('Premium',
                style: TextStyle(color: kPremium, fontWeight: FontWeight.w800, fontSize: 12)),
          ],
        ),
      );

  Widget _optTile(BuildContext context, Opt o, bool sel, VoidCallback apply) {
    final locked = _locked(o);
    return ListTile(
      onTap: () => _pick(context, o, apply),
      leading: Icon(o.icon, color: sel ? appState.accent : subtleText(context)),
      title: Row(
        children: [
          Text(o.title, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (o.premium) ...[
            const SizedBox(width: 6),
            const Icon(AppIcons.star, color: kPremium, size: 16),
          ],
        ],
      ),
      subtitle: Text(o.subtitle, style: TextStyle(color: subtleText(context), fontSize: 13)),
      trailing: locked
          ? Icon(AppIcons.lock, color: subtleText(context), size: 18)
          : _Radio(selected: sel),
    );
  }

  Widget _mode(BuildContext context, ThemeMode mode, IconData icon, String label) {
    final sel = appState.themeMode == mode;
    return Expanded(
      child: Pressable(
        onTap: () => appState.setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: sel ? appState.accent.withValues(alpha: 0.14) : cardColor(context),
            borderRadius: BorderRadius.circular(kRadius),
            border: Border.all(color: sel ? appState.accent : Colors.transparent, width: 2),
          ),
          child: Column(
            children: [
              Icon(icon, color: sel ? appState.accent : subtleText(context)),
              const SizedBox(height: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: sel ? appState.accent : null)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dot(BuildContext context, Color c, bool premium) {
    final sel = appState.accent.toARGB32() == c.toARGB32();
    final locked = premium && !appState.isPremium;
    return Pressable(
      onTap: () => locked ? premiumGate(context, 'Этот цвет') : appState.setAccent(c),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          gradient: accentGradient(c),
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
              width: 3),
          boxShadow: sel ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 12)] : null,
        ),
        child: sel
            ? const Icon(AppIcons.check, color: Colors.white, size: 20)
            : (locked ? const Icon(AppIcons.lock, color: Colors.white, size: 16) : null),
      ),
    );
  }

  Widget _customDot(BuildContext context) {
    final isCustom = ![...kAccentPresets, ...kPremiumAccents]
        .any((c) => c.toARGB32() == appState.accent.toARGB32());
    return Pressable(
      onTap: () async {
        if (!appState.isPremium) {
          premiumGate(context, 'Свой цвет');
          return;
        }
        final c = await showAppSheet<Color>(context,
            builder: (ctx) => ColorPickerSheet(initial: appState.accent));
        if (c != null) appState.setAccent(c);
      },
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const SweepGradient(colors: [
            Color(0xFFFF3B6B), Color(0xFFFFE53B), Color(0xFF3BFF8A),
            Color(0xFF3BC4FF), Color(0xFF8A3BFF), Color(0xFFFF3B6B),
          ]),
          border: Border.all(
              color: isCustom ? Theme.of(context).colorScheme.onSurface : Colors.transparent,
              width: 3),
        ),
        child: const Icon(AppIcons.colorize, color: Colors.white, size: 18),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────

/// Выбор иконки приложения на рабочем столе: 3 бесплатные, 7 — Premium.
class _LauncherIconPicker extends StatefulWidget {
  const _LauncherIconPicker();
  @override
  State<_LauncherIconPicker> createState() => _LauncherIconPickerState();
}

class _LauncherIconPickerState extends State<_LauncherIconPicker> {
  @override
  void initState() {
    super.initState();
    LauncherIcon.load();
  }

  Future<void> _pick(Opt o) async {
    if (o.premium && !appState.isPremium) {
      premiumGate(context, 'Иконка «${o.title}»');
      return;
    }
    if (LauncherIcon.current.value == o.id) return;
    final ok = await LauncherIcon.set(o.id);
    if (!mounted) return;
    toast(
        context,
        ok
            ? 'Иконка «${o.title}» появится, когда свернёшь приложение'
            : 'Не получилось сменить иконку',
        icon: ok ? AppIcons.check : null,
        error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: LauncherIcon.current,
      builder: (context, cur, _) => ChoiceStrip(
              height: 112,
              itemCount: kLauncherIcons.length,
          itemBuilder: (context, i) {
            final o = kLauncherIcons[i];
            return _Choice(
              selected: cur == o.id,
              locked: o.premium && !appState.isPremium,
              label: o.title,
              width: 84,
              onTap: () => _pick(o),
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(15),
                  child: Image.asset('assets/app_icons/${o.id}.webp',
                      width: 58, height: 58, fit: BoxFit.cover, cacheWidth: 180),
                ),
              ),
            );
          },
        ),
    );
  }
}

/// Мини-список чатов с выбранной рамкой.
class _ChatFramePreview extends StatelessWidget {
  final String id;
  const _ChatFramePreview({required this.id});

  @override
  Widget build(BuildContext context) {
    final look = chatFrameLook(context, id: id);
    Widget row(double w) {
      final inner = Padding(
        padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
        child: Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                  gradient: accentGradient(appState.accent), shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                      width: w,
                      height: 4,
                      decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(height: 3),
                  Container(
                      width: w * 0.7,
                      height: 3.5,
                      decoration: BoxDecoration(
                          color: subtleText(context).withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(2))),
                ],
              ),
            ),
          ],
        ),
      );
      if (look == null) {
        return Column(children: [
          inner,
          Divider(height: 0.6, thickness: 0.6, indent: 28, color: hairline(context)),
        ]);
      }
      final r = BorderRadius.circular(look.radius * 0.45);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: FramedBox(look: look, radius: r, child: inner),
      );
    }

    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [row(44), row(34)],
      ),
    );
  }
}

/// Два мини-пузыря с выбранной обводкой.
class _BubbleFramePreview extends StatelessWidget {
  final String id;
  const _BubbleFramePreview({required this.id});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(9);
    Widget b(bool mine, double w) {
      final look = bubbleFrameLook(context, mine, id: id);
      final box = Container(
        width: w,
        height: 18,
        decoration: mine ? myBubbleDecoration(r) : otherBubbleDecoration(context, r),
      );
      return Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: look == null ? box : FramedBox(look: look, radius: r, clip: false, child: box),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [b(false, 54), const SizedBox(height: 8), b(true, 62)],
      ),
    );
  }
}

class _Radio extends StatelessWidget {
  final bool selected;
  const _Radio({required this.selected});
  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: selected ? appState.accent : subtleText(context),
              width: selected ? 7 : 2),
        ),
      );
}

/// Карточка выбора с подписью, галочкой и замком Premium.
class _Choice extends StatelessWidget {
  final bool selected;
  final bool locked;
  final String label;
  final double width;
  final Widget child;
  final VoidCallback onTap;
  const _Choice(
      {required this.selected,
      required this.locked,
      required this.label,
      required this.width,
      required this.child,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                decoration: BoxDecoration(
                  color: cardColor(context),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                      color: selected ? appState.accent : hairline(context),
                      width: selected ? 2.5 : 1),
                  boxShadow: selected
                      ? [BoxShadow(color: appState.accent.withValues(alpha: 0.3), blurRadius: 12)]
                      : null,
                ),
                padding: const EdgeInsets.all(3),
                child: Stack(
                  children: [
                    Positioned.fill(child: ClipRRect(
                        borderRadius: BorderRadius.circular(14), child: child)),
                    if (locked)
                      Positioned(
                        right: 5,
                        top: 5,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(
                              color: Colors.black45, shape: BoxShape.circle),
                          child: const Icon(AppIcons.star, color: kPremium, size: 13),
                        ),
                      ),
                    if (selected)
                      Positioned(
                        right: 5,
                        bottom: 5,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                              color: appState.accent, shape: BoxShape.circle),
                          child: const Icon(AppIcons.check, color: Colors.white, size: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? appState.accent : null)),
          ],
        ),
      ),
    );
  }
}

/// Живой предпросмотр: обои, пузыри, шрифт, эмодзи-статус.
class _LivePreview extends StatelessWidget {
  const _LivePreview();

  @override
  Widget build(BuildContext context) {
    final r = bubbleRadiusEff();
    BorderRadius rad(bool mine) => BorderRadius.only(
          topLeft: Radius.circular(r),
          topRight: Radius.circular(r),
          bottomLeft: Radius.circular(mine || appState.bubbleStyleEff == 'round' ? r : 5),
          bottomRight: Radius.circular(!mine || appState.bubbleStyleEff == 'round' ? r : 5),
        );
    Widget bubble(String text, bool mine) => Align(
          alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            margin: const EdgeInsets.symmetric(vertical: 3),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: mine
                ? myBubbleDecoration(rad(true))
                : otherBubbleDecoration(context, rad(false)),
            child: Text(text,
                style: TextStyle(
                    color: mine ? Colors.white : null,
                    fontSize: 15 * appState.messageTextScale)),
          ),
        );
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadiusL),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border.all(color: hairline(context)),
          borderRadius: BorderRadius.circular(kRadiusL),
        ),
        child: ChatBackground(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AvatarRing(
                      width: 2.5,
                      child: Avatar(
                          name: appState.displayName,
                          url: appState.avatarUrl,
                          size: 34,
                          useAccent: true),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: NameBadges(
                        appState.displayName.isEmpty ? 'Ты' : appState.displayName,
                        premium: appState.isPremium,
                        emoji: appState.emojiStatus,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: appState.nameColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                bubble('Привет! Как тебе новое оформление? 🙂', false),
                bubble('Огонь, всё настроил под себя 🔥', true),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavPreview extends StatelessWidget {
  final String style;
  const _NavPreview({required this.style});
  @override
  Widget build(BuildContext context) {
    final accent = appState.accent;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final muted = dark ? Colors.white38 : Colors.black38;
    Widget icons(Color sel, Color other, {Color? cut}) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            NavIcon(kind: NavIconKind.chats, selected: true, color: sel, size: 18, cutout: cut),
            NavIcon(kind: NavIconKind.store, selected: false, color: other, size: 18, cutout: cut),
            NavIcon(kind: NavIconKind.settings, selected: false, color: other, size: 18, cutout: cut),
            NavIcon(kind: NavIconKind.profile, selected: false, color: other, size: 18, cutout: cut),
          ],
        );
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      alignment: Alignment.bottomCenter,
      padding: const EdgeInsets.all(6),
      child: switch (style) {
        'solid' => Container(
            height: 34,
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(6)),
            child: icons(accent, muted),
          ),
        'floating' => Container(
            height: 34,
            width: 84,
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(20)),
            child: icons(accent, muted),
          ),
        'neon' => Container(
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF07070D),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: accent),
              boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.5), blurRadius: 8)],
            ),
            child: icons(accent, Colors.white54, cut: const Color(0xFF07070D)),
          ),
        _ => Container(
            height: 34,
            decoration: BoxDecoration(
                color: cardColor(context).withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: hairline(context))),
            child: icons(accent, muted),
          ),
      },
    );
  }
}

/// Выбор своего цвета: оттенок, насыщенность, яркость.
class ColorPickerSheet extends StatefulWidget {
  final Color initial;
  final String title;
  const ColorPickerSheet({super.key, required this.initial, this.title = 'Свой цвет'});
  @override
  State<ColorPickerSheet> createState() => ColorPickerSheetState();
}

class ColorPickerSheetState extends State<ColorPickerSheet> {
  late HSLColor _c = HSLColor.fromColor(widget.initial);

  Widget _slider(String label, double v, double max, List<Color> track,
      ValueChanged<double> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: subtleText(context), fontSize: 12.5)),
        const SizedBox(height: 6),
        Container(
          height: 26,
          decoration: BoxDecoration(
              gradient: LinearGradient(colors: track),
              borderRadius: BorderRadius.circular(13)),
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 0,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              overlayColor: Colors.white24,
            ),
            child: Slider(value: v, max: max, onChanged: onChanged),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _c.toColor();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: 56,
            decoration: BoxDecoration(
                gradient: accentGradient(color), borderRadius: BorderRadius.circular(18)),
            alignment: Alignment.center,
            child: const Text('Так будут выглядеть кнопки и пузыри',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 16),
          _slider(
              'Оттенок',
              _c.hue,
              359.9,
              [for (var h = 0; h <= 360; h += 60) HSLColor.fromAHSL(1, h % 360.0, 0.8, 0.55).toColor()],
              (v) => setState(() => _c = _c.withHue(v))),
          _slider('Насыщенность', _c.saturation, 1,
              [_c.withSaturation(0).toColor(), _c.withSaturation(1).toColor()],
              (v) => setState(() => _c = _c.withSaturation(v))),
          _slider('Яркость', _c.lightness.clamp(0.2, 0.75), 0.75,
              [_c.withLightness(0.2).toColor(), _c.withLightness(0.75).toColor()],
              (v) => setState(() => _c = _c.withLightness(v < 0.2 ? 0.2 : v))),
          PrimaryButton(label: 'Готово', onTap: () => Navigator.pop(context, color)),
        ],
      ),
    );
  }
}

/// Эмодзи-статус: синхронизируется с сервером, его видят все.
class _EmojiStatusPicker extends StatefulWidget {
  const _EmojiStatusPicker();
  @override
  State<_EmojiStatusPicker> createState() => _EmojiStatusPickerState();
}

class _EmojiStatusPickerState extends State<_EmojiStatusPicker> {
  bool _saving = false;

  Future<void> _set(String e) async {
    if (!appState.isPremium) {
      premiumGate(context, 'Эмодзи-статус');
      return;
    }
    setState(() => _saving = true);
    try {
      appState.applyServerUser(await Api.updateMe({'emoji_status': e}));
    } catch (err) {
      if (mounted) toast(context, friendlyError(err), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cur = appState.emojiStatus ?? '';
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: _saving ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
            color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            _cell(context, '', cur.isEmpty,
                child: Icon(AppIcons.ban, size: 20, color: subtleText(context))),
            for (final e in kStatusEmojis)
              _cell(context, e, cur == e,
                  child: Text(e, style: const TextStyle(fontSize: 24))),
          ],
        ),
      ),
    );
  }

  Widget _cell(BuildContext context, String e, bool sel, {required Widget child}) {
    return Pressable(
      scale: 0.85,
      onTap: _saving ? null : () => _set(e),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: sel ? appState.accent.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: sel ? appState.accent : Colors.transparent, width: 2),
        ),
        child: child,
      ),
    );
  }
}

/// Экран для проверки анимации перехода.
class _TransitionDemo extends StatelessWidget {
  const _TransitionDemo();
  @override
  Widget build(BuildContext context) {
    final o = optOf(kTransitions, appState.transitionEff);
    return Scaffold(
      appBar: AppBar(title: Text('Анимация «${o.title}»')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(o.icon, size: 64, color: appState.accent),
              const SizedBox(height: 16),
              Text(o.subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 24),
              PrimaryButton(
                  label: 'Открыть ещё раз',
                  icon: AppIcons.refreshCw,
                  onTap: () => Navigator.pushReplacement(
                      context, MaterialPageRoute(builder: (_) => const _TransitionDemo()))),
            ],
          ),
        ),
      ),
    );
  }
}
