import 'package:flutter/material.dart';
import '../icons.dart';
import '../io/local_files.dart';

/// Полноэкранный просмотр фото с зумом.
void openImageViewer(BuildContext context,
    {String? url, String? localPath}) {
  Navigator.push(
    context,
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      pageBuilder: (_, __, ___) =>
          _ImageViewer(url: url, localPath: localPath),
    ),
  );
}

class _ImageViewer extends StatelessWidget {
  final String? url;
  final String? localPath;
  const _ImageViewer({this.url, this.localPath});

  @override
  Widget build(BuildContext context) {
    final ImageProvider provider = localExists(localPath)
        ? localImageProvider(localPath!)
        : NetworkImage(url ?? '') as ImageProvider;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image(
                  image: provider,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(AppIcons.imageOff,
                      color: Colors.white54, size: 60),
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 8,
            child: IconButton(
              icon: const Icon(AppIcons.x, color: Colors.white, size: 28),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
