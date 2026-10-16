import 'dart:js_interop';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';
import 'package:video_player/video_player.dart';
import 'package:web/web.dart' as web;

bool localExists(String? path) => path != null && path.isNotEmpty;

Image localImage(String path,
        {double? width,
        double? height,
        BoxFit? fit,
        int? cacheWidth,
        bool gaplessPlayback = false}) =>
    Image.network(path,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        gaplessPlayback: gaplessPlayback);

ImageProvider localImageProvider(String path) => NetworkImage(path);

VideoPlayerController localVideo(String path, {VideoPlayerOptions? options}) =>
    VideoPlayerController.networkUrl(Uri.parse(path), videoPlayerOptions: options);

Source localAudio(String path) => UrlSource(path);

Future<Uint8List> readLocalBytes(String path) => XFile(path).readAsBytes();

void deleteLocal(String? path) {
  if (path == null || !path.startsWith('blob:')) return;
  try {
    web.URL.revokeObjectURL(path);
  } catch (_) {}
}

Future<String?> tempDirPath() async => null;

/// В браузере «временный файл» — blob:-ссылка на байты в памяти.
Future<String> writeTempBytes(Uint8List bytes, String name) async {
  final blob = web.Blob(<web.BlobPart>[bytes.toJS].toJS, web.BlobPropertyBag(type: _mime(name)));
  return web.URL.createObjectURL(blob);
}

String _mime(String name) {
  final n = name.toLowerCase();
  if (n.endsWith('.png')) return 'image/png';
  if (n.endsWith('.jpg') || n.endsWith('.jpeg')) return 'image/jpeg';
  if (n.endsWith('.gif')) return 'image/gif';
  if (n.endsWith('.webp')) return 'image/webp';
  if (n.endsWith('.mp4')) return 'video/mp4';
  if (n.endsWith('.webm')) return 'video/webm';
  if (n.endsWith('.mp3')) return 'audio/mpeg';
  if (n.endsWith('.m4a')) return 'audio/mp4';
  if (n.endsWith('.wav')) return 'audio/wav';
  if (n.endsWith('.pdf')) return 'application/pdf';
  return 'application/octet-stream';
}
