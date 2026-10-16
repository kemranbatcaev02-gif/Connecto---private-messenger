import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'app_state.dart';
import 'customization.dart';

/// Иконка приложения на рабочем столе (только Android).
/// Меняется через activity-alias в AndroidManifest; применяется, когда приложение уходит в фон.
class LauncherIcon {
  static const _ch = MethodChannel('connecto/app_icon');

  /// Смена иконки поддерживается только на Android.
  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Какая иконка выбрана сейчас ('classic', 'neon' …).
  static final ValueNotifier<String> current = ValueNotifier('classic');

  static Future<void> load() async {
    if (!supported) return;
    try {
      final id = await _ch.invokeMethod<String>('get');
      if (id != null) current.value = id;
    } catch (_) {}
  }

  static Future<bool> set(String id) async {
    if (!supported) return false;
    try {
      final ok = await _ch.invokeMethod<bool>('set', {'id': id});
      if (ok == true) current.value = id;
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Premium закончился — премиум-иконку возвращаем на обычную.
  static Future<void> enforcePremium() async {
    if (!supported) return;
    await load();
    final o = optOf(kLauncherIcons, current.value);
    if (o.premium && !appState.isPremium) await set('classic');
  }
}
