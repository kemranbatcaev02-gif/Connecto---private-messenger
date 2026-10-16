import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../desktop_pane.dart';
import '../platform.dart';
import '../e2e.dart';
import '../io/web_notify.dart';
import '../app_state.dart';
import '../notifications.dart';
import '../realtime.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/glass_nav_bar.dart';
import '../widgets/ui.dart';
import 'chats_screen.dart';
import 'onboarding_screen.dart';
import 'settings_screen.dart';
import 'store_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  var _controller = PageController();
  late final GlobalKey<NavigatorState> _paneKey;
  late final NavigatorObserver _paneObserver;
  bool? _wasWide;
  int _index = 0;

  static const _destinations = [
    NavDestination(NavIconKind.chats, 'Чаты'),
    NavDestination(NavIconKind.store, 'Магазин'),
    NavDestination(NavIconKind.settings, 'Настройки'),
    NavDestination(NavIconKind.profile, 'Профиль'),
  ];

  final _pages = const [ChatsScreen(), StoreScreen(), SettingsScreen(), ProfileScreen()];

  @override
  void initState() {
    super.initState();
    final pane = DesktopPane.attach();
    _paneKey = pane.$1;
    _paneObserver = pane.$2;
    Realtime.addListener(_onMsg);
    E2E.ensure().catchError((_) {}); // ключ устройства для сквозного шифрования
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // первый вход на устройстве — знакомство с приложением, потом проверка обновлений
      await maybeShowOnboarding(context);
      if (mounted && !isWeb) _checkUpdate();
      if (mounted && isWeb) _offerWebNotify();
    });
  }

  /// Браузер: один раз предложить уведомления (запрос разрешения браузер
  /// показывает только после нажатия, поэтому — кнопкой в плашке).
  Future<void> _offerWebNotify() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    // на телефоне браузер не покажет уведомления, пока сайт в фоне, — не обещаем
    if (WebNotify.canAsk && isWebDesktop) {
      if (prefs.getBool('web_notify_offered') == true) return;
      await prefs.setBool('web_notify_offered', true);
      messenger.showSnackBar(SnackBar(
        duration: const Duration(seconds: 12),
        content: const Text('Включить уведомления о новых сообщениях?'),
        action: SnackBarAction(
          label: 'Включить',
          onPressed: () async {
            final ok = await WebNotify.ask();
            if (ok && mounted) toast(context, 'Уведомления включены', icon: AppIcons.bell);
          },
        ),
      ));
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      // iPhone: с экрана «Домой» сайт открывается на весь экран, как приложение
      if (prefs.getBool('web_ios_home_tip') == true) return;
      await prefs.setBool('web_ios_home_tip', true);
      messenger.showSnackBar(const SnackBar(
        duration: Duration(seconds: 10),
        content: Text('Совет: «Поделиться» → «На экран Домой» — Connecto будет '
            'открываться на весь экран, как приложение'),
      ));
    }
  }

  Future<void> _checkUpdate() async {
    if (isWeb || !mounted) return;
    final upd = await Api.checkUpdate();
    if (upd == null || !mounted) return;
    final build = (upd['build'] as num?)?.toInt() ?? 0;
    final must = upd['mandatory'] == true;
    if (!must) {
      final prefs = await SharedPreferences.getInstance();
      if ((prefs.getInt('dismissed_update_build') ?? 0) >= build) return;
    }
    final direct = (upd['url_direct'] as String?) ?? '';
    final tg = (upd['url_telegram'] as String?) ?? '';
    final notes = (upd['notes'] as String?) ?? '';
    final ver = (upd['version'] as String?) ?? '';
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: !must,
      builder: (_) => PopScope(
        canPop: !must,
        child: AlertDialog(
        title: Text('Доступно обновление${ver.isNotEmpty ? ' $ver' : ''}'),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
          child: SingleChildScrollView(
            child: Text(notes.isEmpty ? 'Вышла новая версия Connecto.' : notes),
          ),
        ),
        actions: [
          if (!must)
            TextButton(
                onPressed: () async {
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setInt('dismissed_update_build', build);
                  if (mounted) Navigator.pop(context);
                },
                child: const Text('Позже')),
          if (tg.isNotEmpty)
            TextButton(
              onPressed: () {
                if (!must) Navigator.pop(context); // обязательное — окно не закрываем
                launchUrl(Uri.parse(tg), mode: LaunchMode.externalApplication);
              },
              child: const Text('Telegram'),
            ),
          if (direct.isNotEmpty)
            TextButton(
              onPressed: () {
                if (!must) Navigator.pop(context); // обязательное — окно не закрываем
                launchUrl(Uri.parse(direct),
                    mode: LaunchMode.externalApplication);
              },
              child: Text(desktopUx ? 'Скачать' : 'Скачать APK'),
            ),
        ],
      ),
      ),
    );
  }

  @override
  void dispose() {
    Realtime.removeListener(_onMsg);
    _controller.dispose();
    super.dispose();
  }

  void _onMsg(Map<String, dynamic> m) {
    final type = m['type'];
    if (type == 'me_updated') {
      appState.refreshMe(); // админ выдал Premium / галочку
      return;
    }
    if (type == 'sessions_changed') {
      // сеансы изменились (выход на другом устройстве / бан) — проверим свой
      appState.refreshMe();
      return;
    }
    if (type == 'reactions') {
      _onReaction(m);
      return;
    }
    if (type == 'gift_received') {
      // подарок покажем красиво, когда человек откроет чат с дарителем
      return;
    }
    if (type == 'story_reaction') {
      if (mounted) {
        toast(context, '${m['name'] ?? 'Кто-то'} отреагировал(а) ${m['emoji'] ?? ''} на вашу историю',
            icon: AppIcons.stories);
      }
      return;
    }
    if (type != 'message') return;
    if (appState.muteAll) return; // уведомления отключены в настройках
    if (m['sender_id'] == appState.myUserId) return; // моё же сообщение
    if (m['kind'] == 'service') return;
    if (m['kind'] == 'call') {
      // история звонка: уведомляем только о пропущенном
      final info = ((m['extra'] as Map?)?['call'] as Map?) ?? const {};
      if (info['status'] != 'missed' && info['status'] != 'busy') return;
    }
    if (m['silent'] == true) return; // тихая отправка — без уведомления
    final cid = m['chat_id'] as String?;
    if (cid != null && appState.isMuted(cid)) return; // чат заглушён
    if (cid == appState.currentOpenChatId && !appState.notifyInChat) return;
    // зашифрованное сообщение: расшифруем на телефоне и только потом покажем
    final env = m['enc'] as String?;
    if (env != null && (m['kind'] ?? 'text') == 'text') {
      E2E.open(env, id: m['id'] as String?).then((t) {
        _notifyMessage(m, t ?? '🔒 Новое сообщение');
      });
      return;
    }
    _notifyMessage(m, null);
  }

  void _notifyMessage(Map<String, dynamic> m, String? plain) {
    final cid = m['chat_id'] as String?;
    final chatType = m['chat_type'] as String? ?? 'direct';
    final key = switch (chatType) {
      'group' => 'groups',
      'channel' => 'channels',
      _ => 'private',
    };
    if (appState.notify[key] == false) return;
    final kind = m['kind'] as String? ?? 'text';
    final sender = (m['sender_name'] as String?)?.isNotEmpty == true
        ? m['sender_name'] as String
        : 'Новое сообщение';
    var body = switch (kind) {
      'image' => '📷 Фото',
      'video' => '🎬 Видео',
      'file' => '📎 Файл',
      'voice' => '🎤 Голосовое',
      'round' => '📹 Видеосообщение',
      'call' => (((m['extra'] as Map?)?['call'] as Map?)?['video'] == true)
          ? '📹 Пропущенный видеозвонок'
          : '📞 Пропущенный звонок',
      'location' => '📍 Геолокация',
      'contact' => '👤 Контакт',
      'gift' => '🎁 Подарок',
      _ => plain ?? (m['text'] as String? ?? ''),
    };
    if (m['sealed'] == true) body = '📦 Капсула времени';
    if (appState.notify['preview'] == false) body = 'Новое сообщение';
    final chatTitle = (m['chat_title'] as String?) ?? '';
    final title = switch (chatType) {
      'group' => chatTitle.isEmpty ? sender : chatTitle,
      'channel' => chatTitle.isEmpty ? sender : chatTitle,
      _ => sender,
    };
    if (chatType == 'group' && appState.notify['preview'] != false) {
      body = '$sender: $body';
    }
    Notif.show(title, body,
        avatarUrl: m['sender_avatar'] as String?, groupKey: cid);
  }

  void _onReaction(Map<String, dynamic> m) {
    if (m['added'] != true) return;
    if (m['author_id'] != appState.myUserId) return;
    if (m['actor_id'] == appState.myUserId) return;
    if (appState.muteAll || appState.notify['reactions'] == false) return;
    final cid = m['chat_id'] as String?;
    if (cid != null && (appState.isMuted(cid) || cid == appState.currentOpenChatId)) {
      return;
    }
    Notif.show((m['actor_name'] as String?) ?? 'Реакция',
        '${m['emoji'] ?? '❤️'} на ваше сообщение');
  }

  bool _animating = false;

  /// Переключение по нижнему меню: всегда анимируем ровно одну страницу,
  /// чтобы движение было таким же плавным, как при свайпе пальцем.
  Future<void> _onTap(int i) async {
    if (i == _index && !_animating) return;
    HapticFeedback.selectionClick();
    final from = _controller.hasClients ? (_controller.page ?? _index.toDouble()).round() : _index;
    setState(() => _index = i); // иконка реагирует сразу, а не на середине анимации
    if (!appState.motion) {
      _controller.jumpToPage(i);
      return;
    }
    _animating = true;
    if ((i - from).abs() > 1) {
      _controller.jumpToPage(i > from ? i - 1 : i + 1);
    }
    await _controller.animateToPage(i,
        duration: const Duration(milliseconds: 360), curve: Curves.easeInOutCubic);
    _animating = false;
  }

  /// Ширина, начиная с которой — две колонки (компьютер, планшет, развёрнутое окно).
  static const double _kWide = 860;

  // у каждой вкладки слева свой стек экранов (настройки открываются в колонке)
  final _tabNavs = List.generate(4, (_) => GlobalKey<NavigatorState>());

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= _kWide;
      DesktopPane.active = wide;
      if (_wasWide == true && !wide) {
        // окно сузили: правая колонка пропала — сбрасываем подсветку, а нижние
        // вкладки начинаем с той, что выбрана в боковой панели
        final old = _controller;
        _controller = PageController(initialPage: _index);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          old.dispose();
          DesktopPane.reset();
        });
      }
      _wasWide = wide;
      return wide ? _wide(box.maxWidth) : _narrow();
    });
  }

  void _onRail(int i) {
    if (i == _index) {
      // повторное нажатие — к началу вкладки
      _tabNavs[i].currentState?.popUntil((r) => r.isFirst);
      return;
    }
    // справа был раздел другой вкладки (настройки/профиль) — закрываем его
    if (DesktopPane.sectionMode.value) DesktopPane.close();
    setState(() => _index = i);
    if (_controller.hasClients) _controller.jumpToPage(i);
  }

  /// Esc: сначала закрыть меню/шторку/окно, если они открыты, и только потом чат справа.
  void _onEsc() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    final route = ctx != null ? ModalRoute.of(ctx) : null;
    if (route != null && (route is PopupRoute || !route.opaque)) {
      route.navigator?.maybePop();
      return;
    }
    DesktopPane.close();
  }

  Widget _wide(double width) {
    final listW = (width * 0.3).clamp(320.0, 420.0);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _onEsc,
      },
      child: Scaffold(
        body: Row(
          children: [
            ValueListenableBuilder<int>(
              valueListenable: appState.unreadTotal,
              builder: (_, unread, _) =>
                  _SideRail(index: _index, unread: unread, onTap: _onRail),
            ),
            VerticalDivider(width: 1, thickness: 1, color: hairline(context)),
            SizedBox(
              width: listW,
              child: IndexedStack(
                index: _index,
                children: [
                  for (var i = 0; i < _pages.length; i++)
                    HeroMode(
                      enabled: false,
                      child: Navigator(
                        key: _tabNavs[i],
                        onGenerateRoute: (_) =>
                            MaterialPageRoute(builder: (_) => _pages[i]),
                      ),
                    ),
                ],
              ),
            ),
            VerticalDivider(width: 1, thickness: 1, color: hairline(context)),
            Expanded(
              child: ClipRect(
                child: ValueListenableBuilder<bool>(
                  valueListenable: DesktopPane.sectionMode,
                  // раздел настроек — по центру и не шире 820, чат — на всю колонку
                  builder: (context, section, nav) => ColoredBox(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(maxWidth: section ? 820 : double.infinity),
                        child: nav,
                      ),
                    ),
                  ),
                  child: HeroMode(
                    enabled: false,
                    child: Navigator(
                      key: _paneKey,
                      observers: [_paneObserver],
                      onGenerateRoute: (_) =>
                          PageRouteBuilder(pageBuilder: (_, _, _) => const _EmptyPane()),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _narrow() {
    return Scaffold(
      // не даём нижней панели подниматься над клавиатурой
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            allowImplicitScrolling: true, // соседние вкладки готовы заранее — без рывков
            physics: const ClampingScrollPhysics(),
            onPageChanged: (i) {
              if (!_animating && i != _index) setState(() => _index = i);
            },
            itemCount: _pages.length,
            itemBuilder: (context, i) =>
                _KeepAlive(child: RepaintBoundary(child: _pages[i])),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: RepaintBoundary(
              child: ValueListenableBuilder<int>(
                valueListenable: appState.unreadTotal,
                builder: (_, unread, __) => GlassNavBar(
                    currentIndex: _index,
                    onTap: _onTap,
                    items: _destinations,
                    chatsBadge: unread),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Узкая панель слева (широкий режим): логотип, вкладки, тема.
class _SideRail extends StatelessWidget {
  final int index;
  final int unread;
  final ValueChanged<int> onTap;
  const _SideRail({required this.index, required this.unread, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label) {
      final sel = i == index;
      return Tooltip(
        message: label,
        waitDuration: const Duration(milliseconds: 500),
        child: Pressable(
          onTap: () => onTap(i),
          child: Container(
            width: 72,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 50,
                      height: 38,
                      decoration: BoxDecoration(
                        color: sel ? appState.accent.withValues(alpha: 0.16) : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(icon,
                          color: sel ? appState.accent : subtleText(context), size: 24),
                    ),
                    if (i == 0 && unread > 0)
                      Positioned(right: -2, top: -4, child: CountBadge(unread)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        color: sel ? appState.accent : subtleText(context))),
              ],
            ),
          ),
        ),
      );
    }

    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 72,
      color: cardColor(context),
      child: SafeArea(
        right: false,
        child: Column(
          children: [
            const SizedBox(height: 14),
            const AppLogo(size: 40, shadow: false),
            const SizedBox(height: 18),
            item(0, AppIcons.messagesSquare, 'Чаты'),
            item(1, AppIcons.shoppingBag, 'Магазин'),
            item(2, AppIcons.tune, 'Настройки'),
            item(3, AppIcons.userRound, 'Профиль'),
            const Spacer(),
            Tooltip(
              message: dark ? 'Светлая тема' : 'Тёмная тема',
              child: IconButton(
                icon: Icon(dark ? AppIcons.sun : AppIcons.moon, color: subtleText(context)),
                onPressed: () =>
                    appState.setThemeMode(dark ? ThemeMode.light : ThemeMode.dark),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// Правая колонка, пока чат не выбран.
class _EmptyPane extends StatelessWidget {
  const _EmptyPane();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ChatBackground(
        child: Center(
          child: Container(
            padding: const EdgeInsets.fromLTRB(26, 22, 26, 22),
            margin: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: cardColor(context).withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(kRadiusL),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const MascotArt('empty_chat', size: 150),
                const SizedBox(height: 12),
                const Text('Выбери чат, чтобы начать общение',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Text(
                    'Enter — отправить, Shift+Enter — новая строка, Esc — закрыть чат.\n'
                    'Файлы можно просто перетащить в окно чата.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: subtleText(context), fontSize: 13)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepAlive extends StatefulWidget {
  final Widget child;
  const _KeepAlive({required this.child});
  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
