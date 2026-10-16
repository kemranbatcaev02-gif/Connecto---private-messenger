import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// Уведомления браузера: всплывают, когда вкладка Connecto не на экране.
class WebNotify {
  WebNotify._();

  static final Map<String, web.Notification> _open = {};

  static bool get supported {
    try {
      return web.window.has('Notification');
    } catch (_) {
      return false;
    }
  }

  static bool get granted => supported && web.Notification.permission == 'granted';

  /// Разрешение ещё не спрашивали (не «разрешено» и не «запрещено»).
  static bool get canAsk => supported && web.Notification.permission == 'default';

  /// Вкладка открыта и в фокусе — уведомление не нужно.
  static bool get pageActive {
    try {
      return web.document.visibilityState == 'visible' && web.document.hasFocus();
    } catch (_) {
      return true;
    }
  }

  /// Спросить разрешение (браузер покажет запрос только после нажатия человека).
  static Future<bool> ask() async {
    if (!supported) return false;
    if (granted) return true;
    try {
      final r = await web.Notification.requestPermission().toDart;
      return r.toDart == 'granted';
    } catch (_) {
      return false;
    }
  }

  static void show(String title, String body,
      {String? icon, String? tag, void Function()? onClick}) {
    if (!granted) return;
    try {
      final opts = web.NotificationOptions(body: body, icon: icon ?? 'icons/Icon-192.png');
      if (tag != null) opts.tag = tag;
      final n = web.Notification(title, opts);
      n.onclick = ((web.Event _) {
        try {
          web.window.focus();
        } catch (_) {}
        onClick?.call();
        n.close();
      }).toJS;
      if (tag != null) {
        _open[tag]?.close();
        _open[tag] = n;
      }
    } catch (_) {}
  }

  static void close(String tag) {
    try {
      _open.remove(tag)?.close();
    } catch (_) {}
  }

  /// Число непрочитанных в заголовке вкладки: «(3) Connecto».
  static void setTitleBadge(int unread) {
    try {
      web.document.title = unread > 0 ? '($unread) Connecto' : 'Connecto';
    } catch (_) {}
  }
}
