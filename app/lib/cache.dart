import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// Локальный кэш чатов и сообщений — чтобы офлайн показывать загруженное.
/// Кэш свой у каждого аккаунта (scope = id пользователя).
class Cache {
  static String scope = '';

  static String _key(String name) => 'c_${scope}_$name';

  static Future<void> saveChats(List<dynamic> list) async {
    try {
      // кодируем сразу: потом в списке могут появиться расшифрованные превью — их на диск не пишем
      final s = jsonEncode(list);
      final p = await SharedPreferences.getInstance();
      await p.setString(_key('chats'), s);
    } catch (_) {}
  }

  static Future<List<dynamic>?> loadChats() async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_key('chats'));
      if (s != null) return jsonDecode(s) as List<dynamic>;
    } catch (_) {}
    return null;
  }

  static Future<void> saveMessages(String chatId, List<dynamic> list) async {
    // храним последние 100 (в браузере — 30: там всего ~5 МБ на всё, и в том же
    // месте лежит вход в аккаунт — его нельзя вытеснить кэшем)
    final keep = kIsWeb ? 30 : 100;
    final trimmed = list.length > keep ? list.sublist(list.length - keep) : list;
    final key = _key('msg_$chatId');
    String data;
    try {
      data = jsonEncode(trimmed);
    } catch (_) {
      return;
    }
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, data);
    } catch (_) {
      if (!kIsWeb) return;
      // место кончилось: чистим кэш других чатов и пробуем ещё раз
      try {
        final p = await SharedPreferences.getInstance();
        for (final k in p.getKeys().where((k) => k.startsWith('c_') && k.contains('_msg_') && k != key).toList()) {
          await p.remove(k);
        }
        await p.setString(key, data);
      } catch (_) {
        try {
          final p = await SharedPreferences.getInstance();
          await p.remove(key);
        } catch (_) {}
      }
    }
  }

  static Future<List<dynamic>?> loadMessages(String chatId) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString(_key('msg_$chatId'));
      if (s != null) return jsonDecode(s) as List<dynamic>;
    } catch (_) {}
    return null;
  }

  /// Размер кэша сообщений в байтах (примерно) — для «Данные и память».
  static Future<int> sizeBytes() async {
    try {
      final p = await SharedPreferences.getInstance();
      var n = 0;
      for (final k in p.getKeys()) {
        if (k.startsWith('c_') || k.startsWith('cache_')) {
          final v = p.get(k);
          if (v is String) n += v.length;
        }
      }
      return n;
    } catch (_) {
      return 0;
    }
  }

  /// Очистить кэш сообщений всех аккаунтов.
  static Future<void> clearAll() async {
    try {
      final p = await SharedPreferences.getInstance();
      final keys = p.getKeys()
          .where((k) => k.startsWith('c_') || k.startsWith('cache_'))
          .toList();
      for (final k in keys) {
        await p.remove(k);
      }
    } catch (_) {}
  }
}
