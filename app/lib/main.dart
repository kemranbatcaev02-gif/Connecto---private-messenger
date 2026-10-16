import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_state.dart';
import 'calls/call_manager.dart';
import 'calls/call_ui.dart';
import 'notifications.dart';
import 'platform.dart';
import 'push_service.dart';
import 'realtime.dart';
import 'theme.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/passcode_screen.dart';
import 'screens/chat_screen.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> messengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ── Оптимизация графики и памяти: быстрый кэш декодированных картинок в RAM ──
  PaintingBinding.instance.imageCache.maximumSizeBytes = 350 << 20; // 350 МБ быстрый кэш
  PaintingBinding.instance.imageCache.maximumSize = 3000;            // до 3000 изображений горячими
  await initDesktopWindow(); // компьютер: заголовок и минимальный размер окна
  await appState.loadPrefs();
  // шрифт пользователя — заранее, чтобы первый кадр был уже с ним
  try {
    GoogleFonts.getFont(appState.fontEff);
    await GoogleFonts.pendingFonts().timeout(const Duration(milliseconds: 1500));
  } catch (_) {}
  Notif.init(); // локальные каналы уведомлений
  Notif.onOpenChat = (chatId) {
    navKey.currentState?.push(MaterialPageRoute(
      builder: (_) => ChatScreen(chatId: chatId, name: 'Чат'),
    ));
  };
  CallManager.instance
    ..navigatorKey = navKey
    ..attach(); // звонки: слушаем сигналинг с первого подключения
  // Firebase-пуши — только в приложении на телефоне; на компьютере и в браузере
  // сообщения приходят, пока окно/вкладка открыты
  if (isNativeMobile) await Push.init();
  appState.onSessionEndedUi = _onSessionEnded;
  runApp(const ConnectoApp());
}

/// Сервер завершил сеанс (вышли с другого устройства, аккаунт заблокирован…).
void _onSessionEnded() {
  final nav = navKey.currentState;
  if (nav == null) return;
  if (appState.token != null) return; // уже переключились на другой аккаунт
  nav.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  messengerKey.currentState?.showSnackBar(const SnackBar(
      content: Text('Сеанс завершён. Войди снова.')));
}

class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }
}

class ConnectoApp extends StatefulWidget {
  const ConnectoApp({super.key});

  @override
  State<ConnectoApp> createState() => _ConnectoAppState();
}

class _ConnectoAppState extends State<ConnectoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // в браузере свёрнутая вкладка — «hidden», до «paused» дело не доходит
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      appState.onPaused();
    } else if (state == AppLifecycleState.resumed) {
      appState.onResumed();
      Realtime.kick();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // в браузере число непрочитанных видно в заголовке вкладки: «(3) Connecto»
      listenable: isWeb ? Listenable.merge([appState, appState.unreadTotal]) : appState,
      builder: (context, _) => MaterialApp(
        title: isWeb && appState.unreadTotal.value > 0
            ? '(${appState.unreadTotal.value}) Connecto'
            : 'Connecto',
        debugShowCheckedModeBanner: false,
        navigatorKey: navKey,
        scaffoldMessengerKey: messengerKey,
        scrollBehavior: AppScrollBehavior(),
        theme: buildTheme(appState.accent, Brightness.light),
        darkTheme: buildTheme(appState.accent, Brightness.dark),
        themeMode: appState.themeMode,
        themeAnimationDuration:
            appState.motion ? const Duration(milliseconds: 280) : Duration.zero,
        builder: (context, child) {
          // Код-пароль — поверх всего приложения
          return Stack(
            children: [
              if (child != null) child,
              if (appState.locked) const Positioned.fill(child: LockOverlay()),
              // звонок — поверх всего, в том числе код-пароля
              const Positioned.fill(child: CallLayer()),
            ],
          );
        },
        home: const SplashScreen(),
      ),
    );
  }
}
