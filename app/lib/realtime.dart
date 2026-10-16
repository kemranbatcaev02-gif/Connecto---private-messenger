import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api.dart';
import 'app_state.dart';

/// Живое соединение с сервером: авто-переподключение с паузой,
/// пинг каждые 25 с и признак «подключено» для интерфейса.
class Realtime {
  static WebSocketChannel? _ch;
  static StreamSubscription? _sub;
  static Timer? _retry;
  static Timer? _ping;
  static bool _want = false;
  static int _attempt = 0;
  static final List<void Function(Map<String, dynamic>)> _listeners = [];

  /// Сообщения, которые не успели уйти, пока соединение переподключалось
  /// (сигналинг звонков не должен теряться при смене Wi-Fi ↔ мобильная сеть).
  static final List<(DateTime, String)> _outbox = [];

  /// Кто хочет знать, что соединение (пере)установлено — например, звонок.
  static final List<void Function()> _readyListeners = [];
  static void addReadyListener(void Function() l) => _readyListeners.add(l);

  /// Когда последний раз что-то пришло от сервера (для сторожа «мёртвого» сокета).
  static DateTime _lastRx = DateTime.now();

  /// true — соединение установлено (для надписи «Соединение…»).
  static final ValueNotifier<bool> connected = ValueNotifier(false);

  static void connect() {
    _want = true;
    if (_ch == null) _open();
  }

  static void _open() {
    if (!_want || Api.token == null) return;
    _retry?.cancel();
    try {
      final ch = WebSocketChannel.connect(Uri.parse('$kWsUrl?token=${Api.token}'));
      _ch = ch;
      _whenReady(ch);
      _sub = ch.stream.listen(
        (data) {
          _lastRx = DateTime.now();
          try {
            final msg = (jsonDecode(data as String) as Map).cast<String, dynamic>();
            if (msg['type'] == 'pong') return;
            for (final l in List.of(_listeners)) {
              l(msg);
            }
          } catch (_) {}
        },
        onError: (_) {
          if (_ch == ch) _scheduleReconnect();
        },
        onDone: () {
          if (_ch == ch) _scheduleReconnect();
        },
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  static Future<void> _whenReady(WebSocketChannel ch) async {
    try {
      await ch.ready;
    } catch (_) {
      if (_ch == ch) _scheduleReconnect();
      return;
    }
    if (_ch != ch) return;
    _attempt = 0;
    _lastRx = DateTime.now();
    connected.value = true;
    _flush();
    _ping?.cancel();
    _ping = Timer.periodic(const Duration(seconds: 20), (_) {
      // сервер отвечает pong на каждый ping; долгая тишина — сокет «повис» (сменилась сеть)
      if (DateTime.now().difference(_lastRx).inSeconds > 50) {
        final dead = _ch;
        _scheduleReconnect();
        try {
          dead?.sink.close();
        } catch (_) {}
        return;
      }
      try {
        _ch?.sink.add(jsonEncode({'type': 'ping'}));
      } catch (_) {}
    });
    for (final l in List.of(_readyListeners)) {
      try {
        l();
      } catch (_) {}
    }
  }

  static void _scheduleReconnect() {
    connected.value = false;
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    _ch = null;
    if (!_want) return;
    _retry?.cancel();
    _attempt = (_attempt + 1).clamp(1, 6);
    // 1, 2, 4, 8, 15, 15 секунд
    final secs = [1, 2, 4, 8, 15, 15][_attempt - 1];
    _retry = Timer(Duration(seconds: secs), _open);
  }

  static void disconnect() {
    _want = false;
    _retry?.cancel();
    _ping?.cancel();
    _sub?.cancel();
    _sub = null;
    try {
      _ch?.sink.close();
    } catch (_) {}
    _ch = null;
    connected.value = false;
  }

  /// Переподключиться сразу (например, при возврате в приложение).
  static void kick() {
    if (!_want) return;
    if (_ch == null) {
      _attempt = 0;
      _open();
    }
  }

  static void typing(String chatId, String state) {
    // «Невидимка» (Premium): собеседник не видит «печатает…» и «записывает…»
    if (appState.ghostTyping && appState.isPremium) return;
    try {
      _ch?.sink.add(jsonEncode({'type': 'typing', 'chat_id': chatId, 'state': state}));
    } catch (_) {}
  }

  /// Отправить событие на сервер. queue — если соединения нет, отправим
  /// после переподключения (но не позже чем через 20 секунд). true — ушло сразу.
  static bool send(Map<String, dynamic> data, {bool queue = true}) {
    final raw = jsonEncode(data);
    final ch = _ch;
    if (ch != null && connected.value) {
      try {
        ch.sink.add(raw);
        return true;
      } catch (_) {}
    }
    if (queue) {
      _outbox.add((DateTime.now(), raw));
      if (_outbox.length > 120) _outbox.removeAt(0);
      kick();
    }
    return false;
  }

  static void _flush() {
    if (_outbox.isEmpty) return;
    final now = DateTime.now();
    final items = List.of(_outbox);
    _outbox.clear();
    for (final (at, raw) in items) {
      if (now.difference(at).inSeconds > 20) continue;
      try {
        _ch?.sink.add(raw);
      } catch (_) {}
    }
  }

  static void addListener(void Function(Map<String, dynamic>) l) => _listeners.add(l);
  static void removeListener(void Function(Map<String, dynamic>) l) =>
      _listeners.remove(l);
}
