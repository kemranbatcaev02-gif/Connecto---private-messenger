import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:app/icons.dart';
import 'package:app/widgets/ui.dart';

class FileOpener {
  FileOpener._();

  static Directory? _cachedFilesDir;
  static final Map<String, String> _knownPaths = {};
  static final Set<String> _activeDownloads = {};

  static String sanitizeName(String name) {
    var clean = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
    if (clean.isEmpty) clean = 'file';
    return clean;
  }

  static Future<Directory> _filesDirectory() async {
    if (_cachedFilesDir != null && _cachedFilesDir!.existsSync()) {
      return _cachedFilesDir!;
    }
    Directory base;
    if (Platform.isAndroid) {
      base = (await getExternalStorageDirectory()) ??
          (await getApplicationDocumentsDirectory());
    } else if (Platform.isWindows) {
      base = (await getDownloadsDirectory()) ??
          (await getApplicationDocumentsDirectory());
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final d = Directory('${base.path}/ConnectoFiles');
    if (!d.existsSync()) {
      d.createSync(recursive: true);
    }
    return _cachedFilesDir = d;
  }

  /// Проверяет, сохранён ли уже файл локально.
  static Future<String?> findLocalPath(String fileName, {String? localPath}) async {
    if (kIsWeb) return null;
    if (localPath != null && localPath.isNotEmpty) {
      final f = File(localPath);
      if (f.existsSync() && f.lengthSync() > 0) return localPath;
    }
    final clean = sanitizeName(fileName);
    final mem = _knownPaths[clean];
    if (mem != null && File(mem).existsSync() && File(mem).lengthSync() > 0) {
      return mem;
    }
    try {
      final dir = await _filesDirectory();
      final target = File('${dir.path}/$clean');
      if (target.existsSync() && target.lengthSync() > 0) {
        _knownPaths[clean] = target.path;
        return target.path;
      }
    } catch (_) {}
    return null;
  }

  /// Скачивает файл во внутреннее хранилище и сразу же открывает его через системный просмотрщик.
  static Future<void> openOrDownload(
    BuildContext context, {
    required String url,
    required String fileName,
    String? localPath,
    void Function(double progress)? onProgress,
    void Function(bool downloading)? onStateChanged,
  }) async {
    if (kIsWeb) {
      // В браузере открываем / скачиваем файл напрямую
      final targetUrl = Uri.parse(url);
      try {
        await launchUrl(targetUrl, mode: LaunchMode.platformDefault);
      } catch (_) {
        await launchUrl(targetUrl, mode: LaunchMode.externalApplication);
      }
      return;
    }

    final clean = sanitizeName(fileName);

    // 1. Если файл уже скачан — мгновенно открываем
    final existing = await findLocalPath(fileName, localPath: localPath);
    if (existing != null) {
      await _launchFile(context, existing, fileName);
      return;
    }

    // 2. Если уже идёт скачивание этого файла — не дублируем
    if (_activeDownloads.contains(clean)) {
      if (context.mounted) {
        toast(context, 'Файл уже скачивается…', icon: AppIcons.download);
      }
      return;
    }

    _activeDownloads.add(clean);
    onStateChanged?.call(true);

    try {
      final dir = await _filesDirectory();
      final targetFile = File('${dir.path}/$clean');
      final tempFile = File('${dir.path}/$clean.part');

      if (context.mounted) {
        toast(context, 'Скачиваю «$fileName»…', icon: AppIcons.download);
      }

      final req = http.Request('GET', Uri.parse(url));
      final client = http.Client();
      try {
        final res = await client.send(req).timeout(const Duration(seconds: 90));
        if (res.statusCode != 200) {
          throw Exception('Сервер вернул статус ${res.statusCode}');
        }

        final total = res.contentLength ?? 0;
        var received = 0;
        final sink = tempFile.openWrite();
        try {
          await for (final chunk in res.stream) {
            sink.add(chunk);
            received += chunk.length;
            if (total > 0 && onProgress != null) {
              onProgress(received / total);
            }
          }
          await sink.flush();
        } finally {
          await sink.close();
        }

        if (tempFile.existsSync() && tempFile.lengthSync() > 0) {
          if (targetFile.existsSync()) targetFile.deleteSync();
          await tempFile.rename(targetFile.path);
          _knownPaths[clean] = targetFile.path;

          if (context.mounted) {
            await _launchFile(context, targetFile.path, fileName);
          }
        } else {
          throw Exception('Файл пустой');
        }
      } finally {
        client.close();
      }
    } catch (e) {
      if (context.mounted) {
        toast(context, 'Не удалось открыть файл: $e', icon: AppIcons.fileText, error: true);
      }
    } finally {
      _activeDownloads.remove(clean);
      onStateChanged?.call(false);
    }
  }

  static Future<void> _launchFile(BuildContext context, String filePath, String fileName) async {
    try {
      final res = await OpenFilex.open(filePath);
      if (res.type == ResultType.done) {
        return;
      }
      if (res.type == ResultType.noAppToOpen) {
        final ext = fileName.contains('.') ? fileName.split('.').last.toUpperCase() : '';
        if (context.mounted) {
          toast(
            context,
            'Нет приложения для открытия ${ext.isNotEmpty ? ext : 'файла'}',
            icon: AppIcons.fileText,
            error: true,
          );
        }
        return;
      }
      // Резервная попытка через url_launcher file://
      final fileUri = Uri.file(filePath);
      if (!await launchUrl(fileUri)) {
        if (context.mounted) {
          toast(context, 'Не удалось открыть файл: ${res.message}', error: true);
        }
      }
    } catch (e) {
      if (context.mounted) {
        toast(context, 'Ошибка открытия файла: $e', error: true);
      }
    }
  }

  /// Цвет подложки и иконки по расширению файла.
  static (Color, IconData) getFileStyle(String name) {
    final ext = (name.contains('.') ? name.split('.').last : '').toLowerCase();
    switch (ext) {
      case 'pdf':
        return (const Color(0xFFEF4444), AppIcons.fileText);
      case 'doc':
      case 'docx':
        return (const Color(0xFF3B82F6), AppIcons.fileText);
      case 'ppt':
      case 'pptx':
        return (const Color(0xFFF97316), AppIcons.fileText);
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (const Color(0xFF10B981), AppIcons.fileText);
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return (const Color(0xFF8B5CF6), AppIcons.file);
      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'ogg':
      case 'flac':
        return (const Color(0xFFA855F7), AppIcons.music);
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return (const Color(0xFF06B6D4), AppIcons.video);
      case 'py':
      case 'js':
      case 'ts':
      case 'dart':
      case 'html':
      case 'json':
      case 'css':
        return (const Color(0xFF14B8A6), AppIcons.fileText);
      default:
        return (const Color(0xFF6C5CE7), AppIcons.fileText);
    }
  }
}
