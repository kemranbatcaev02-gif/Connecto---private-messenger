import 'dart:typed_data';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api.dart';
import 'app_state.dart';
import 'calls/call_native.dart';
import 'io/web_notify.dart';
import 'platform.dart';

/// Системные уведомления (в шторке, с именем и аватаром отправителя).
/// Когда приложение закрыто — приходят пуши FCM в канал «messages».
class Notif {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static int _id = 100;

  /// Открыть чат при нажатии на уведомление
  static void Function(String chatId)? onOpenChat;

  // Настройки канала на Android менять после создания нельзя,
  // поэтому для каждой комбинации «звук/вибрация» — свой канал.
  static const _channels = [
    AndroidNotificationChannel('messages', 'Сообщения',
        description: 'Со звуком и вибрацией', importance: Importance.high),
    AndroidNotificationChannel('messages_sound', 'Сообщения (без вибрации)',
        description: 'Только звук',
        importance: Importance.high,
        enableVibration: false),
    AndroidNotificationChannel('messages_vibrate', 'Сообщения (без звука)',
        description: 'Только вибрация',
        importance: Importance.high,
        playSound: false),
    AndroidNotificationChannel('messages_silent', 'Сообщения (тихо)',
        description: 'Без звука и вибрации',
        importance: Importance.defaultImportance,
        playSound: false,
        enableVibration: false),
  ];

  /// Звонки: полноэкранный вызов со звуком системного рингтона и вибрацией,
  /// чтобы звонок не пропускался, когда приложение свёрнуто или заблокировано.
  static final _callChannels = [
    AndroidNotificationChannel('calls_v2', 'Входящие звонки',
        description: 'Входящие аудио- и видеозвонки',
        importance: Importance.max,
        sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 1000, 800, 1000, 800]),
        audioAttributesUsage: AudioAttributesUsage.notificationRingtone),
    const AndroidNotificationChannel('calls', 'Входящие звонки (архив)',
        description: 'Когда приложение закрыто',
        importance: Importance.max,
        sound: UriAndroidNotificationSound('content://settings/system/ringtone')),
    const AndroidNotificationChannel('calls_incoming', 'Звонок на экране (архив)',
        description: 'Входящий звонок поверх других приложений',
        importance: Importance.max,
        playSound: false,
        enableVibration: false),
  ];
  static const int _callNotifId = 77;

  /// Нажали «Ответить» / «Отклонить» / само уведомление о звонке.
  static void Function(String? action, String? payload)? onCallAction;

  static Future<void> init() async {
    if (_ready) return;
    if (isWeb) return; // в браузере — свои уведомления (WebNotify)
    try {
      const androidInit = AndroidInitializationSettings('@drawable/ic_stat_notify');
      const settings = InitializationSettings(
        android: androidInit,
        // уведомления Windows (всплывают справа внизу)
        windows: WindowsInitializationSettings(
          appName: 'Connecto',
          appUserModelId: 'Connecto.Messenger.Desktop',
          guid: 'a7c3e3a2-5d1b-4c7e-9f0a-3b2d6e8f1c45',
        ),
      );
      await _plugin.initialize(settings, onDidReceiveNotificationResponse: (r) {
        final p = r.payload ?? '';
        if (p.startsWith('call:')) {
          // Windows кладёт аргументы кнопки в payload: «call:ID|answer»
          final b = p.substring(5);
          final i = b.indexOf('|');
          if (i >= 0) {
            onCallAction?.call(b.substring(i + 1), b.substring(0, i));
          } else {
            onCallAction?.call(r.actionId, b);
          }
          if (isDesktop) bringAppToFront();
        } else if (p.startsWith('chat:')) {
          final chatId = p.substring(5);
          cancelChat(chatId);
          onOpenChat?.call(chatId);
          if (isDesktop) bringAppToFront();
        } else if (isDesktop) {
          bringAppToFront(); // нажали на уведомление — показываем окно
        }
      });
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      for (final ch in _channels) {
        await android?.createNotificationChannel(ch);
      }
      for (final ch in _callChannels) {
        await android?.createNotificationChannel(ch);
      }
      await android?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {}
  }

  /// Стабильный ID уведомления для чата, чтобы они не копились бесконечно
  static int notifIdForChat(String chatId) => (chatId.hashCode.abs() % 100000) + 1000;

  /// Удалить уведомления конкретного чата из шторки (когда чат прочитан)
  static Future<void> cancelChat(String chatId) async {
    if (isWeb) {
      WebNotify.close(chatId);
      return;
    }
    try {
      await init();
      final id = notifIdForChat(chatId);
      await _plugin.cancel(id, tag: 'chat_$chatId');
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// Снять все уведомления (например, при «Прочитать все»)
  static Future<void> cancelAll() async {
    if (isWeb) return;
    try {
      await init();
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Входящий звонок, пока приложение свёрнуто: на весь экран (поверх
  /// блокировки) с рингтоном, вибрацией и кнопками «Отклонить» и «Ответить».
  static Future<void> showIncomingCall(
      {required String callId,
      required String name,
      required bool video,
      String? avatarUrl}) async {
    if (isWeb) {
      WebNotify.show(name, video ? '📹 Входящий видеозвонок' : '📞 Входящий звонок',
          icon: _fullUrl(avatarUrl), tag: 'call'); // клик — вкладка выходит вперёд
      return;
    }
    try {
      await init();
      AndroidBitmap<Object>? largeIcon;
      if (isAndroid && avatarUrl != null && avatarUrl.isNotEmpty) {
        final bytes = await _avatarBytes(avatarUrl);
        if (bytes != null) largeIcon = ByteArrayAndroidBitmap(bytes);
      }
      final details = NotificationDetails(
        windows: WindowsNotificationDetails(
          actions: [
            WindowsAction(content: 'Отклонить', arguments: 'call:$callId|decline'),
            WindowsAction(content: 'Ответить', arguments: 'call:$callId|answer'),
          ],
        ),
        android: AndroidNotificationDetails(
          'calls_v2',
          'Входящие звонки',
          channelDescription: 'Входящие аудио- и видеозвонки',
          importance: Importance.max,
          priority: Priority.max,
          sound: const UriAndroidNotificationSound('content://settings/system/ringtone'),
          playSound: true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 1000, 800, 1000, 800]),
          audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
          icon: '@drawable/ic_stat_notify',
          largeIcon: largeIcon,
          category: AndroidNotificationCategory.call,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          visibility: NotificationVisibility.public,
          timeoutAfter: 60000,
          actions: const [
            AndroidNotificationAction('decline', 'Отклонить', showsUserInterface: true),
            AndroidNotificationAction('answer', 'Ответить', showsUserInterface: true),
          ],
        ),
      );
      await _plugin.show(_callNotifId, name,
          video ? '📹 Входящий видеозвонок' : '📞 Входящий звонок', details,
          payload: 'call:$callId');
    } catch (_) {}
  }

  static Future<void> cancelCall() async {
    if (isWeb) {
      WebNotify.close('call');
      return;
    }
    try {
      await _plugin.cancel(_callNotifId);
      await CallNative.ring(false);
    } catch (_) {}
  }

  static final Map<String, Uint8List> _avatarCache = {};

  static String? _fullUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    return url.startsWith('http') ? url : '$kBaseUrl$url';
  }

  static Future<Uint8List?> _avatarBytes(String url) async {
    if (_avatarCache.containsKey(url)) return _avatarCache[url];
    try {
      final full = url.startsWith('http') ? url : '$kBaseUrl$url';
      final r =
          await Api.client.get(Uri.parse(full)).timeout(const Duration(seconds: 5));
      if (r.statusCode == 200) {
        if (_avatarCache.length >= 50) {
          _avatarCache.remove(_avatarCache.keys.first);
        }
        _avatarCache[url] = r.bodyBytes;
        return r.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  static AndroidNotificationChannel _pick() {
    final s = appState.notifySound, v = appState.notifyVibrate;
    if (s && v) return _channels[0];
    if (s) return _channels[1];
    if (v) return _channels[2];
    return _channels[3];
  }

  static Future<void> show(String title, String body,
      {String? avatarUrl, String? groupKey, String? payload}) async {
    if (isWeb) {
      // вкладка открыта и в фокусе — человек и так видит сообщение
      if (WebNotify.pageActive) return;
      WebNotify.show(title, body, icon: _fullUrl(avatarUrl), tag: groupKey);
      return;
    }
    try {
      // на компьютере не мешаем, если человек и так смотрит в окно Connecto
      if (isDesktop && await appWindowFocused()) return;
      await init();
      AndroidBitmap<Object>? largeIcon;
      if (isAndroid && avatarUrl != null && avatarUrl.isNotEmpty) {
        final bytes = await _avatarBytes(avatarUrl);
        if (bytes != null) largeIcon = ByteArrayAndroidBitmap(bytes);
      }
      final ch = _pick();
      final notifId = groupKey != null ? notifIdForChat(groupKey) : _id++;
      final details = NotificationDetails(
        windows: const WindowsNotificationDetails(),
        android: AndroidNotificationDetails(
          ch.id,
          ch.name,
          channelDescription: ch.description,
          importance: ch.importance,
          priority: Priority.high,
          playSound: ch.playSound,
          enableVibration: ch.enableVibration,
          icon: '@drawable/ic_stat_notify',
          largeIcon: largeIcon,
          tag: groupKey != null ? 'chat_$groupKey' : null,
          groupKey: groupKey,
          styleInformation: BigTextStyleInformation(body),
        ),
      );
      await _plugin.show(
        notifId,
        title,
        body,
        details,
        payload: payload ?? (groupKey != null ? 'chat:$groupKey' : null),
      );
    } catch (_) {}
  }
}
