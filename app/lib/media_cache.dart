import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'api.dart';

/// Кэш файлов на диске: скачиваем один раз, дальше открываем мгновенно.
/// Для обложек профиля (фото и видео) и других больших картинок.
class MediaCache {
  MediaCache._();

  static final Map<String, Future<String?>> _inflight = {};
  static final Map<String, String> _ready = {}; // url → путь (уже скачано)
  static Directory? _dir;

  static Future<Directory> _folder() async {
    final d = _dir;
    if (d != null && d.existsSync()) return d; // папку могли удалить при очистке кэша
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/media_cache');
    if (!dir.existsSync()) dir.createSync(recursive: true);
    return _dir = dir;
  }

  static String _name(String url) {
    final clean = url.split('?').first;
    final dot = clean.lastIndexOf('.');
    final ext = dot > clean.lastIndexOf('/') && clean.length - dot <= 6 ? clean.substring(dot) : '';
    // два разных хэша — чтобы случайные совпадения были практически невозможны
    final h1 = url.hashCode.toUnsigned(32).toRadixString(16);
    final h2 = url.codeUnits.fold<int>(7, (a, b) => (a * 31 + b) & 0x7fffffff).toRadixString(16);
    return '$h1$h2$ext';
  }

  /// Путь к уже скачанному файлу (без ожидания) или null.
  static String? peek(String url) {
    final p = _ready[url];
    if (p == null || kIsWeb) return p;
    if (File(p).existsSync()) return p;
    _ready.remove(url); // файл удалили при очистке кэша
    return null;
  }

  /// Скачать (или взять с диска). null — не получилось даже после повтора.
  static Future<String?> file(String url, {Duration timeout = const Duration(seconds: 40)}) {
    if (kIsWeb) return Future.value(null); // в браузере кэширует сам браузер
    final done = peek(url);
    if (done != null) return Future.value(done);
    return _inflight[url] ??= _download(url, timeout).whenComplete(() => _inflight.remove(url));
  }

  static Future<String?> _download(String url, Duration timeout) async {
    try {
      final dir = await _folder();
      final f = File('${dir.path}/${_name(url)}');
      if (f.existsSync() && f.lengthSync() > 0) {
        _ready[url] = f.path;
        return f.path;
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        final tmp = File('${f.path}.part');
        try {
          final res = await Api.client.send(http.Request('GET', Uri.parse(url))).timeout(timeout);
          if (res.statusCode != 200) continue;
          final sink = tmp.openWrite();
          await res.stream.pipe(sink).timeout(timeout * 3);
          if (tmp.existsSync() && tmp.lengthSync() > 0) {
            await tmp.rename(f.path);
            _ready[url] = f.path;
            return f.path;
          }
        } catch (_) {
          try {
            if (tmp.existsSync()) tmp.deleteSync();
          } catch (_) {}
        }
        await Future.delayed(const Duration(milliseconds: 600));
      }
    } catch (_) {}
    return null;
  }
}
