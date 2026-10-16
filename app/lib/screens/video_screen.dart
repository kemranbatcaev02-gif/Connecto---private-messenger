import 'dart:async';

import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../app_state.dart';
import '../io/local_files.dart';

/// Открыть видео во встроенном плеере.
void openVideo(BuildContext context, {String? url, String? localPath}) {
  Navigator.push(
    context,
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => VideoScreen(url: url, localPath: localPath),
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ),
  );
}

class VideoScreen extends StatefulWidget {
  final String? url;
  final String? localPath;
  const VideoScreen({super.key, this.url, this.localPath});
  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  VideoPlayerController? _c;
  bool _error = false;
  bool _controls = true;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final c = localExists(widget.localPath)
          ? localVideo(widget.localPath!)
          : VideoPlayerController.networkUrl(Uri.parse(widget.url ?? ''));
      _c = c;
      await c.initialize();
      c.addListener(_tick);
      if (appState.autoplayVideo) {
        await c.play();
        _scheduleHide();
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  void _tick() {
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && (_c?.value.isPlaying ?? false)) {
        setState(() => _controls = false);
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  void _toggle() {
    final c = _c;
    if (c == null || !c.value.isInitialized) return;
    if (c.value.isPlaying) {
      c.pause();
      _hide?.cancel();
      setState(() => _controls = true);
    } else {
      if (c.value.position >= c.value.duration) c.seekTo(Duration.zero);
      c.play();
      _scheduleHide();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    final h = d.inHours;
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final ready = c != null && c.value.isInitialized;
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          setState(() => _controls = !_controls);
          if (_controls) _scheduleHide();
        },
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0).abs() > 600) Navigator.pop(context);
        },
        child: Stack(
          children: [
            Center(
              child: _error
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(AppIcons.videoOff, color: Colors.white70, size: 48),
                        const SizedBox(height: 12),
                        const Text('Не удалось воспроизвести видео',
                            style: TextStyle(color: Colors.white70)),
                        if (widget.url != null)
                          TextButton(
                            onPressed: () => launchUrl(Uri.parse(widget.url!),
                                mode: LaunchMode.externalApplication),
                            child: const Text('Открыть в другом приложении'),
                          ),
                      ],
                    )
                  : !ready
                      ? const CircularProgressIndicator(color: Colors.white)
                      : AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
            ),
            // верх: закрыть
            AnimatedOpacity(
              opacity: _controls ? 1 : 0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: IconButton(
                    icon: const Icon(AppIcons.x, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
            if (ready)
              Center(
                child: AnimatedOpacity(
                  opacity: _controls || !c.value.isPlaying ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: GestureDetector(
                    onTap: _toggle,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                          color: Colors.black45, shape: BoxShape.circle),
                      child: Icon(
                          c.value.isPlaying ? AppIcons.pause : AppIcons.play,
                          color: Colors.white,
                          size: 34),
                    ),
                  ),
                ),
              ),
            if (ready)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedOpacity(
                  opacity: _controls ? 1 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: Row(
                        children: [
                          Text(_fmt(c.value.position),
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                          Expanded(
                            child: Slider(
                              value: c.value.position.inMilliseconds
                                  .clamp(0, c.value.duration.inMilliseconds)
                                  .toDouble(),
                              max: c.value.duration.inMilliseconds
                                  .clamp(1, 1 << 31)
                                  .toDouble(),
                              activeColor: Colors.white,
                              inactiveColor: Colors.white24,
                              onChanged: (v) =>
                                  c.seekTo(Duration(milliseconds: v.round())),
                            ),
                          ),
                          Text(_fmt(c.value.duration),
                              style: const TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
