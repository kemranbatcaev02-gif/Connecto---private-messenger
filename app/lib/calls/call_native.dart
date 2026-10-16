import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';

import '../platform.dart';

/// Мост к Android (MainActivity.kt, канал connecto/call): рингтон, гудки,
/// экран поверх блокировки, датчик приближения, сервис звонка, картинка в картинке.
class CallNative {
  CallNative._();
  static const _ch = MethodChannel('connecto/call');

  /// Android просит: «завершить» из уведомления / включился режим PiP.
  static void Function()? onEndFromNotification;
  static void Function(bool on)? onPip;

  static bool _bound = false;
  static void bind() {
    if (_bound) return;
    _bound = true;
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'endCall':
          onEndFromNotification?.call();
          break;
        case 'pip':
          final on = (call.arguments as Map?)?['on'] == true;
          onPip?.call(on);
          break;
      }
      return null;
    });
  }

  static Future<void> _invoke(String method, [Map<String, Object?>? args]) async {
    if (!isAndroid) return; // на компьютере этих системных штук нет
    try {
      await _ch.invokeMethod(method, args);
    } catch (_) {}
  }

  // ── звуки на компьютере (на Android — системный рингтон и гудки) ──
  static AudioPlayer? _ringer;
  static AudioPlayer? _toner;
  // команды одному плееру выполняем строго по очереди: stop/play вперемешку
  // (например, «гудки» и сразу «конец звонка») на Windows могут уронить плеер
  static Future<void> _ringQ = Future.value();
  static Future<void> _toneQ = Future.value();

  static Future<void> _serial(bool ring, Future<void> Function() job) {
    Future<void> run(Future<void> prev) =>
        prev.then((_) => job()).catchError((_) {}).timeout(const Duration(seconds: 4),
            onTimeout: () {});
    if (ring) {
      return _ringQ = run(_ringQ);
    }
    return _toneQ = run(_toneQ);
  }

  static Future<void> _play(AudioPlayer p, String file, {bool loop = false}) async {
    try {
      await p.stop();
      await p.setReleaseMode(loop ? ReleaseMode.loop : ReleaseMode.stop);
      await p.play(AssetSource('sounds/$file'), volume: 0.9);
    } catch (_) {}
  }

  static Future<void> _stop(AudioPlayer p) async {
    try {
      await p.stop();
    } catch (_) {}
  }

  static Future<void> ring(bool on, {bool sound = true, bool vibrate = true}) async {
    if (isAndroid) {
      return _invoke('ring', {'on': on, 'sound': sound, 'vibrate': vibrate});
    }
    if (diagFlag('NO_SOUNDS')) return;
    final p = _ringer ??= AudioPlayer(playerId: 'connecto_ring');
    return _serial(true, () => (on && sound) ? _play(p, 'ring.wav', loop: true) : _stop(p));
  }

  /// ringback — «длинные гудки», busy — «занято», end/connect — короткий сигнал, none — тишина.
  static Future<void> tone(String kind) async {
    if (isAndroid) return _invoke('tone', {'kind': kind});
    if (diagFlag('NO_SOUNDS')) return;
    final p = _toner ??= AudioPlayer(playerId: 'connecto_tone');
    return _serial(false, () {
      switch (kind) {
        case 'ringback':
          return _play(p, 'ringback.wav', loop: true);
        case 'busy':
          return _play(p, 'busy.wav');
        case 'connect':
          return _play(p, 'connect.wav');
        case 'end':
          return _play(p, 'end.wav');
        default:
          return _stop(p);
      }
    });
  }

  static Future<void> keepScreenOn(bool on) => _invoke('keepOn', {'on': on});
  static Future<void> showOverLockScreen(bool on) => _invoke('lockScreen', {'on': on});
  static Future<void> proximity(bool on) => _invoke('proximity', {'on': on});

  static Future<void> service(bool on,
          {String title = 'Connecto',
          String text = 'Идёт звонок',
          int? since,
          bool mic = true,
          bool camera = false,
          bool screen = false}) =>
      _invoke('service', {
        'on': on,
        'title': title,
        'text': text,
        'since': since ?? DateTime.now().millisecondsSinceEpoch,
        'mic': mic,
        'camera': camera,
        'screen': screen,
      });

  static Future<void> allowPip(bool on, {int w = 9, int h = 16}) =>
      _invoke('pip', {'on': on, 'w': w, 'h': h});

  /// Увести приложение в фон (вместо закрытия, чтобы не оборвать звонок).
  static Future<void> moveToBack() => _invoke('moveToBack');

  /// Попросить разблокировать телефон (звонок приняли на экране блокировки).
  static Future<void> dismissKeyguard() => _invoke('dismissKeyguard');

  /// Отключить оптимизацию батареи для надёжной работы звонков в фоне
  static Future<void> requestBatteryOptimizations() =>
      _invoke('requestBatteryOptimizations');
}
