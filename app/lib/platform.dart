import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Где запущено приложение.
bool get isDesktop =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
bool get isAndroid => !kIsWeb && Platform.isAndroid;
bool get isWindows => !kIsWeb && Platform.isWindows;

/// Веб-версия в браузере.
bool get isWeb => kIsWeb;

/// Браузер на телефоне (iPhone/Android) — управление пальцами.
bool get isWebMobile =>
    kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android);

/// Браузер на компьютере — мышь и клавиатура.
bool get isWebDesktop => kIsWeb && !isWebMobile;

/// «Компьютерный» интерфейс: мышь, клавиатура, Enter — отправить, перетаскивание файлов.
bool get desktopUx => isDesktop || isWebDesktop;

/// Приложение на телефоне (Android/iOS), не в браузере.
bool get isNativeMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

/// Флажки для проверки на компьютере (переменные окружения CONNECTO_...):
/// NO_STATS — без статистики звонка, NO_ANIM — без анимаций звонка, NO_SOUNDS — без звуков.
bool diagFlag(String name) {
  if (!isDesktop) return false;
  try {
    final v = Platform.environment['CONNECTO_$name'];
    return v != null && v.isNotEmpty && v != '0';
  } catch (_) {
    return false;
  }
}

/// Окно на компьютере: заголовок и минимальный размер (размер и центр задаёт runner).
Future<void> initDesktopWindow() async {
  if (!isDesktop) return;
  try {
    await windowManager.ensureInitialized();
    await windowManager.setTitle('Connecto');
    await windowManager.setMinimumSize(const Size(400, 600));
  } catch (_) {}
}

/// Входящий звонок: развернуть окно и вывести его наверх.
Future<void> bringAppToFront() async {
  if (!isDesktop) return;
  try {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  } catch (_) {}
}

/// Окно сейчас в фокусе (на телефоне — всегда true, там это решает жизненный цикл).
Future<bool> appWindowFocused() async {
  if (!isDesktop) return true;
  try {
    return await windowManager.isFocused() && !await windowManager.isMinimized();
  } catch (_) {
    return true;
  }
}
