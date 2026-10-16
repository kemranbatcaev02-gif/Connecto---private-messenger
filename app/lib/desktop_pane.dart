import 'package:flutter/material.dart';

/// Правая колонка на компьютере (и планшете, и в браузере): там открывается чат
/// или раздел настроек, а список слева остаётся — как в Telegram Desktop.
class DesktopPane {
  DesktopPane._();

  /// Ключ и наблюдатель правой колонки. У каждого HomeShell свои (см. attach):
  /// при смене аккаунта старый и новый экран какое-то время живут вместе.
  static GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

  /// Широкий режим сейчас на экране (ставит HomeShell).
  static bool active = false;

  /// Какой чат открыт справа (для подсветки в списке).
  static final ValueNotifier<String?> currentChatId = ValueNotifier(null);

  /// Справа открыт раздел (настройки, профиль…) — он ограничен по ширине и
  /// выровнен по центру, чтобы не растягиваться на весь монитор.
  static final ValueNotifier<bool> sectionMode = ValueNotifier(false);

  static bool get ready => active && navKey.currentState != null;

  /// Следит, когда справа снова пусто, — сбрасывает подсветку и режим раздела.
  static NavigatorObserver observer = _PaneObserver();

  /// Новый HomeShell: свой ключ и наблюдатель для правой колонки.
  static (GlobalKey<NavigatorState>, NavigatorObserver) attach() {
    navKey = GlobalKey<NavigatorState>();
    observer = _PaneObserver();
    WidgetsBinding.instance.addPostFrameCallback((_) => reset());
    return (navKey, observer);
  }

  /// Справа пусто: снять подсветку чата и режим раздела.
  static void reset() {
    currentChatId.value = null;
    sectionMode.value = false;
  }

  static PageRouteBuilder<T> _route<T>(Widget screen, {String? name}) => PageRouteBuilder<T>(
        settings: RouteSettings(name: name),
        pageBuilder: (_, _, _) => screen,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        transitionsBuilder: (_, a, _, child) => FadeTransition(
          opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(begin: const Offset(0.02, 0), end: Offset.zero)
                .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      );

  /// Открыть экран справа вместо текущего (чат — на всю ширину колонки).
  static Future<T?> open<T>(Widget screen, {String? chatId}) {
    final nav = navKey.currentState;
    if (nav == null) return Future.value(null);
    if (chatId != null && chatId == currentChatId.value && nav.canPop()) {
      // этот чат уже открыт — убираем то, что открыли поверх него (профиль и т.п.)
      nav.popUntil((r) => r.isFirst || r.settings.name == 'chat:$chatId');
      return Future.value(null);
    }
    currentChatId.value = chatId;
    sectionMode.value = false;
    return nav.pushAndRemoveUntil<T>(
        _route<T>(screen, name: chatId != null ? 'chat:$chatId' : null), (r) => r.isFirst);
  }

  /// Открыть раздел (настройки, кошелёк, профиль…) справа — по центру, не шире 820.
  static Future<T?> openSection<T>(Widget screen) {
    final nav = navKey.currentState;
    if (nav == null) return Future.value(null);
    currentChatId.value = null;
    sectionMode.value = true;
    return nav.pushAndRemoveUntil<T>(_route<T>(screen), (r) => r.isFirst);
  }

  /// Закрыть то, что открыто справа (Esc).
  static void close() {
    final nav = navKey.currentState;
    if (nav == null) return;
    nav.popUntil((r) => r.isFirst);
    currentChatId.value = null;
    sectionMode.value = false;
  }

  /// Чат закрылся сам (кнопка «назад» в шапке).
  static void chatClosed(String chatId) {
    if (currentChatId.value == chatId) currentChatId.value = null;
  }
}

/// Открыть раздел: в широком окне — в правой колонке, на телефоне — обычным переходом.
Future<T?> openSection<T>(BuildContext context, Widget screen) {
  if (DesktopPane.ready) return DesktopPane.openSection<T>(screen);
  return Navigator.push<T>(context, MaterialPageRoute(builder: (_) => screen));
}

class _PaneObserver extends NavigatorObserver {
  void _check() {
    final nav = navigator;
    if (nav == null) return;
    // остался только пустой экран «Выбери чат»
    if (!nav.canPop()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!(navigator?.canPop() ?? true)) {
          DesktopPane.sectionMode.value = false;
          DesktopPane.currentChatId.value = null;
        }
      });
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _check();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _check();
}
