import 'dart:math' as math;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../customization.dart';
import '../icons.dart';
import '../push_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'appearance_screen.dart';

/// Показать знакомство с приложением, если его ещё не видели на этом устройстве.
/// Для уже существующих аккаунтов (вход с другого устройства) экран пропускается.
Future<void> maybeShowOnboarding(BuildContext context) async {
  if (appState.onboardingDone) return;
  if (appState.token != null) {
    // Пользователь уже зашёл в существующий аккаунт — он уже знает Connecto
    await appState.setOnboardingDone();
    return;
  }
  await Navigator.of(context).push(PageRouteBuilder(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 380),
    pageBuilder: (_, __, ___) => const OnboardingScreen(),
    transitionsBuilder: (_, a, __, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child),
  ));
}

class _Slide {
  final String image;
  final String title;
  final String text;
  final Color tint;
  const _Slide(this.image, this.title, this.text, this.tint);
}

const _slides = [
  _Slide('onboarding_1_hello', 'Привет! Я Конни 👋',
      'Добро пожаловать в Connecto. Пара шагов — и можно общаться с друзьями.', Color(0xFF7C6CFF)),
  _Slide('onboarding_2_style', 'Сделай Connecto своим',
      'Выбери тему и цвет прямо сейчас. Шрифты, обои, рамки и иконку можно поменять в «Оформлении».',
      Color(0xFFEC4899)),
  _Slide('onboarding_3_gifts', 'Истории, подарки и кристаллы',
      'Выкладывай истории, дари друзьям подарки и каждый день забирай бонус кристаллов.', Color(0xFF0EA5E9)),
  _Slide('onboarding_4_friends', 'Будь на связи',
      'Включи уведомления, чтобы не пропускать сообщения. Остальные разрешения спросим, когда понадобятся.',
      Color(0xFF10B981)),
];

/// Знакомство с приложением: 4 экрана с маскотом, быстрая настройка оформления
/// и разрешение на уведомления. Показывается один раз.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  double _page = 0;
  bool? _notif; // null — ещё не спрашивали
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _pc.addListener(() => setState(() => _page = _pc.page ?? 0));
    _checkNotif();
  }

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<void> _checkNotif() async {
    try {
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      final ok = s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
      if (mounted && ok) setState(() => _notif = true);
    } catch (_) {}
  }

  Future<void> _askNotif() async {
    if (_asking) return;
    setState(() => _asking = true);
    var ok = false;
    try {
      await Push.register(); // запросит разрешение и отправит токен на сервер
      final s = await FirebaseMessaging.instance.getNotificationSettings();
      ok = s.authorizationStatus == AuthorizationStatus.authorized ||
          s.authorizationStatus == AuthorizationStatus.provisional;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _asking = false;
      _notif = ok;
    });
    if (!ok) {
      toast(context, 'Уведомления можно включить позже в настройках телефона',
          icon: AppIcons.bellOff);
    } else {
      HapticFeedback.lightImpact();
    }
  }

  int get _index => _page.round().clamp(0, _slides.length - 1);
  bool get _last => _index == _slides.length - 1;

  bool _closing = false;

  Future<void> _finish() async {
    if (_closing) return;
    _closing = true;
    await appState.setOnboardingDone();
    if (mounted) Navigator.of(context).pop();
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_last) {
      _finish();
      return;
    }
    if (appState.motion) {
      _pc.nextPage(duration: const Duration(milliseconds: 420), curve: Curves.easeOutCubic);
    } else {
      _pc.jumpToPage(_index + 1);
    }
  }

  Color get _tint {
    final i = _page.floor().clamp(0, _slides.length - 1);
    final j = math.min(i + 1, _slides.length - 1);
    return Color.lerp(_slides[i].tint, _slides[j].tint, _page - i)!;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final art = math.min(mq.size.width * 0.72, mq.size.height * 0.34);
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: bg,
          body: Stack(
            children: [
              // мягкое цветное свечение за маскотом — меняет цвет вместе со слайдом
              Positioned(
                left: -mq.size.width * 0.3,
                right: -mq.size.width * 0.3,
                top: -mq.size.width * 0.15,
                height: mq.size.width * 1.25,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: RadialGradient(colors: [
                        _tint.withValues(alpha: dark ? 0.32 : 0.22),
                        _tint.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    // «Пропустить»
                    SizedBox(
                      height: 48,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 200),
                          opacity: _last ? 0 : 1,
                          child: TextButton(
                            onPressed: _last ? null : _finish,
                            child: Text('Пропустить',
                                style: TextStyle(
                                    color: subtleText(context), fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: PageView.builder(
                        controller: _pc,
                        itemCount: _slides.length,
                        itemBuilder: (context, i) {
                          final d = (_page - i).clamp(-1.0, 1.0);
                          return _slidePage(context, i, d, art);
                        },
                      ),
                    ),
                    // точки + кнопка
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < _slides.length; i++)
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 250),
                                  margin: const EdgeInsets.symmetric(horizontal: 4),
                                  width: i == _index ? 24 : 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: i == _index
                                        ? appState.accent
                                        : subtleText(context).withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          PrimaryButton(
                            label: _last ? 'Начать общение' : 'Далее',
                            icon: _last ? AppIcons.send : AppIcons.arrowRight,
                            onTap: _next,
                          ),
                        ],
                      ),
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

  Widget _slidePage(BuildContext context, int i, double d, double art) {
    final s = _slides[i];
    final k = 1 - d.abs();
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 26),
      child: Column(
        children: [
          const SizedBox(height: 4),
          // маскот плывёт чуть медленнее страницы (параллакс) и уменьшается при уходе
          Transform.translate(
            offset: Offset(d * 70, 0),
            child: Opacity(
              opacity: (0.3 + 0.7 * k).clamp(0.0, 1.0),
              child: Transform.scale(scale: 0.85 + 0.15 * k, child: MascotArt(s.image, size: art)),
            ),
          ),
          const SizedBox(height: 18),
          Transform.translate(
            offset: Offset(d * 30, 0),
            child: Column(
              children: [
                Text(s.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                const SizedBox(height: 10),
                Text(s.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtleText(context), fontSize: 15.5, height: 1.45)),
                const SizedBox(height: 18),
                if (i == 1) _stylePicker(context),
                if (i == 2) _features(context),
                if (i == 3) _permissions(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── слайд 2: быстрое оформление ──

  Widget _stylePicker(BuildContext context) {
    Widget mode(ThemeMode m, IconData icon, String label) {
      final sel = appState.themeMode == m;
      return Expanded(
        child: Pressable(
          onTap: () => appState.setThemeMode(m),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: sel ? appState.accent.withValues(alpha: 0.14) : cardColor(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? appState.accent : hairline(context), width: sel ? 1.6 : 1),
            ),
            child: Column(
              children: [
                Icon(icon, size: 20, color: sel ? appState.accent : subtleText(context)),
                const SizedBox(height: 4),
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

    return Column(
      children: [
        Row(
          children: [
            mode(ThemeMode.dark, AppIcons.moon, 'Тёмная'),
            const SizedBox(width: 8),
            mode(ThemeMode.light, AppIcons.sun, 'Светлая'),
            const SizedBox(width: 8),
            mode(ThemeMode.system, AppIcons.monitorSmartphone, 'Как в системе'),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in kAccentPresets)
              Pressable(
                onTap: () {
                  HapticFeedback.selectionClick();
                  appState.setAccent(c);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: appState.accent.toARGB32() == c.toARGB32()
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.transparent,
                        width: 3),
                    boxShadow: [BoxShadow(color: c.withValues(alpha: 0.4), blurRadius: 8)],
                  ),
                  child: appState.accent.toARGB32() == c.toARGB32()
                      ? const Icon(AppIcons.check, color: Colors.white, size: 18)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        // мини-превью сообщений в выбранном стиле
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            for (final o in kBubbleStyles.where((o) => !o.premium))
              ChoiceChip(
                label: Text(o.title),
                selected: appState.bubbleStyleEff == o.id,
                onSelected: (_) => appState.setCustom(bubble: o.id),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextButton.icon(
          onPressed: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => const AppearanceScreen())),
          icon: const Icon(AppIcons.palette, size: 18),
          label: const Text('Все настройки оформления'),
        ),
      ],
    );
  }

  // ── слайд 3: что умеет приложение ──

  Widget _features(BuildContext context) {
    Widget row(IconData icon, Color c, String title, String sub) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: c, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                    Text(sub, style: TextStyle(color: subtleText(context), fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
          color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
      child: Column(
        children: [
          row(AppIcons.stories, const Color(0xFFEC4899), 'Истории',
              'Текст, стикеры, музыка и погода'),
          row(AppIcons.gift, const Color(0xFFF59E0B), 'Подарки',
              'От роз до легендарных драконов'),
          row(AppIcons.coin, const Color(0xFF0EA5E9), 'Кристаллы',
              'Ежедневный бонус — заходи каждый день'),
          row(AppIcons.sparkles, const Color(0xFF7C6CFF), 'Эффекты и капсулы',
              'Салют на весь экран и письма в будущее'),
        ],
      ),
    );
  }

  // ── слайд 4: разрешения ──

  Widget _permissions(BuildContext context) {
    final on = _notif == true;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
          color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
      child: Column(
        children: [
          Row(
            children: [
              IconTile(AppIcons.bell, size: 40),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Уведомления', style: TextStyle(fontWeight: FontWeight.w800)),
                    Text('Сообщения, подарки и реакции', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: on
                    ? const Icon(AppIcons.circleCheck, key: ValueKey('on'), color: kSuccess, size: 28)
                    : FilledButton(
                        key: const ValueKey('off'),
                        onPressed: _asking ? null : _askNotif,
                        style: FilledButton.styleFrom(backgroundColor: appState.accent),
                        child: _asking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Включить'),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(AppIcons.mic, size: 18, color: subtleText(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Микрофон, камеру и геолокацию спросим только когда понадобятся',
                    style: TextStyle(color: subtleText(context), fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
