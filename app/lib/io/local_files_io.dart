import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

/// Файл существует (в браузере — ссылка не пустая).
bool localExists(String? path) {
  if (path == null || path.isEmpty) return false;
  try {
    return File(path).existsSync();
  } catch (_) {
    return false;
  }
}

Image localImage(String path,
        {double? width,
        double? height,
        BoxFit? fit,
        int? cacheWidth,
        bool gaplessPlayback = false}) =>
    Image.file(File(path),
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: gaplessPlayback);

ImageProvider localImageProvider(String path) => FileImage(File(path));

VideoPlayerController localVideo(String path, {VideoPlayerOptions? options}) =>
    VideoPlayerController.file(File(path), videoPlayerOptions: options);

Source localAudio(String path) => DeviceFileSource(path);

Future<Uint8List> readLocalBytes(String path) => File(path).readAsBytes();

void deleteLocal(String? path) {
  if (path == null) return;
  try {
    File(path).deleteSync();
  } catch (_) {}
}

/// Папка для временных файлов (в браузере — null: файлы живут в памяти).
Future<String?> tempDirPath() async => (await getTemporaryDirectory()).path;

/// Сохранить байты во временный файл и вернуть путь.
Future<String> writeTempBytes(Uint8List bytes, String name) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/${DateTime.now().microsecondsSinceEpoch}_$name');
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}
