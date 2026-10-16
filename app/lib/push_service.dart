import 'package:flutter/widgets.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'api.dart';
import 'notifications.dart';
import 'platform.dart';

/// Фоновый обработчик сообщений FCM, когда приложение свёрнуто или закрыто.
@pragma('vm:entry-point')
Future<void> _bgHandler(RemoteMessage message) async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final d = message.data;
    final type = d['type'];
    if (type == 'call') {
      final callId = (d['call_id'] as String?) ?? '';
      final name = (d['name'] as String?) ??
          message.notification?.title ??
          'Входящий звонок';
      final video = d['video'] == 'true' || d['video'] == '1';
      final avatarUrl = d['avatar_url'] as String?;
      await Notif.showIncomingCall(
        callId: callId,
        name: name,
        video: video,
        avatarUrl: avatarUrl,
      );
    } else if (type == 'call_ended' || type == 'call_cancel' || type == 'call_declined') {
      await Notif.cancelCall();
    } else if (type == 'message') {
      final title = (d['title'] as String?) ?? message.notification?.title;
      final body = (d['body'] as String?) ?? message.notification?.body;
      final cid = (d['chat_id'] as String?) ?? '';
      final avatarUrl = d['avatar_url'] as String?;
      if (title != null && body != null && title.isNotEmpty && body.isNotEmpty) {
        await Notif.show(
          title,
          body,
          avatarUrl: avatarUrl,
          groupKey: cid.isNotEmpty ? cid : null,
        );
      }
    }
  } catch (_) {}
}

/// Push-уведомления через Firebase Cloud Messaging (работают при закрытом
/// приложении). Бесплатно, без лимитов.
class Push {
  static bool _inited = false;

  static Future<void> init() async {
    if (_inited) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_bgHandler);
      await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.instance.onTokenRefresh.listen(_send);

      void handlePushOpen(RemoteMessage message) {
        final d = message.data;
        final cid = d['chat_id'] as String?;
        if (cid != null && cid.isNotEmpty) {
          Notif.cancelChat(cid);
          Notif.onOpenChat?.call(cid);
        }
      }

      // Обработка нажатия на пуш-уведомление, когда приложение в фоне
      FirebaseMessaging.onMessageOpenedApp.listen(handlePushOpen);

      // Если приложение было полностью закрыто и открыто нажатием на пуш
      FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
        if (message != null) {
          handlePushOpen(message);
        }
      });

      _inited = true;
    } catch (_) {}
  }

  /// Получить токен устройства и отправить на сервер (после входа).
  static Future<void> register() async {
    if (!isNativeMobile) return;
    try {
      await init();
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await _send(t);
    } catch (_) {}
  }

  /// Перестать получать пуши этого аккаунта на этом устройстве (при выходе).
  static Future<void> unregister() async {
    try {
      if (!_inited) return;
      final t = await FirebaseMessaging.instance.getToken();
      if (t != null) await Api.dropPushToken(t);
    } catch (_) {}
  }

  static Future<void> _send(String token) async {
    try {
      await Api.registerPushToken(token);
    } catch (_) {}
  }
}
