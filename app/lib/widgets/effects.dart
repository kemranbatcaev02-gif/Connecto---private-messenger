import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:video_player/video_player.dart';

import '../io/local_files.dart';

import '../api.dart';
import '../app_state.dart';
import '../customization.dart';
import '../media_cache.dart';
import '../theme.dart';

// ─────────────────────────────────────────────────────────────
// Рамка аватара (в т.ч. анимированные — Premium)
// ─────────────────────────────────────────────────────────────

class AvatarRing extends StatefulWidget {
  final Widget child;
  final String? style; // null — из настроек
  final double width;
  const AvatarRing({super.key, required this.child, this.style, this.width = 4});
  @override
  State<AvatarRing> createState() => _AvatarRingState();
}

class _AvatarRingState extends State<AvatarRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));

  String get _style => widget.style ?? appState.avatarRingEff;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant AvatarRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animated = ['rainbow', 'gold', 'aurora'].contains(_style) && appState.motion;
    if (animated && !_c.isAnimating) {
      _c.repeat();
    } else if (!animated && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  List<Color> _colors() {
    final a = appState.accent;
    switch (_style) {
      case 'rainbow':
        return const [
          Color(0xFFFF3B6B), Color(0xFFFFA43B), Color(0xFFFFE53B), Color(0xFF3BFF8A),
          Color(0xFF3BC4FF), Color(0xFF8A3BFF), Color(0xFFFF3B6B),
        ];
      case 'gold':
        return const [
          Color(0xFFB8860B), Color(0xFFFFE08A), Color(0xFFD4AF37), Color(0xFFFFF4C2),
          Color(0xFFB8860B),
        ];
      case 'aurora':
        final h = HSLColor.fromColor(a);
        return [
          a,
          h.withHue((h.hue + 60) % 360).toColor(),
          h.withHue((h.hue + 140) % 360).toColor(),
          h.withHue((h.hue + 220) % 360).toColor(),
          a,
        ];
      default:
        final g = accentGradient(a);
        return [g.colors.first, g.colors.last, g.colors.first];
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_style == 'none') return widget.child;
    final colors = _colors();
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Container(
        padding: EdgeInsets.all(widget.width),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: colors,
            transform: GradientRotation(_c.value * 2 * math.pi),
          ),
          boxShadow: _style == 'gold' || _style == 'aurora' || _style == 'rainbow'
              ? [BoxShadow(color: colors[1].withValues(alpha: 0.45), blurRadius: 18)]
              : null,
        ),
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Фон чата: статичные обои или «живые» (Premium)
// ─────────────────────────────────────────────────────────────

class ChatBackground extends StatelessWidget {
  final Widget child;
  final int? live;       // переопределение для предпросмотра
  final int? wallpaper;
  const ChatBackground({super.key, required this.child, this.live, this.wallpaper});

  @override
  Widget build(BuildContext context) {
    // обои из магазина (если не идёт предпросмотр других)
    final shop = appState.shopWallpaperUrl;
    if (live == null && wallpaper == null && shop != null && shop.isNotEmpty) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
              child: RepaintBoundary(
                  child: CoverView(url: shop, kind: appState.shopWallpaperKind))),
          child,
        ],
      );
    }
    final l = live ?? appState.liveWallpaperEff;
    if (l >= 0 && l < kLiveWallpapers.length) {
      return Stack(
        fit: StackFit.passthrough,
        children: [
          // свой слой: переливающийся фон не заставляет перерисовываться весь чат
          Positioned.fill(
              child: RepaintBoundary(child: LiveGradient(colors: kLiveWallpapers[l].colors))),
          child,
        ],
      );
    }
    final wp = wallpaper ?? appState.chatWallpaperEff;
    final img = imageWallpaperOf(wp);
    if (img != null) {
      final size = MediaQuery.of(context).size;
      final dpr = MediaQuery.of(context).devicePixelRatio;
      return Stack(
        fit: StackFit.passthrough,
        children: [
          Positioned.fill(
            child: Image.asset(
              img.asset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              cacheWidth: (size.width * dpr).round().clamp(360, 1080).toInt(),
              gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          child,
        ],
      );
    }
    if (wp >= 0 && wp < kWallpapers.length) {
      return Container(
        decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: kWallpapers[wp],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter)),
        child: child,
      );
    }
    return child;
  }
}

/// Плавно «переливающийся» градиент.
class LiveGradient extends StatefulWidget {
  final List<Color> colors;
  final Duration period;
  const LiveGradient(
      {super.key, required this.colors, this.period = const Duration(seconds: 14)});
  @override
  State<LiveGradient> createState() => _LiveGradientState();
}

class _LiveGradientState extends State<LiveGradient> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void initState() {
    super.initState();
    if (appState.motion) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          final t = _c.value * 2 * math.pi;
          final begin = Alignment(math.cos(t), math.sin(t));
          final end = Alignment(-math.cos(t), -math.sin(t));
          return DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: widget.colors, begin: begin, end: end),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(math.sin(t * 2) * 0.6, math.cos(t) * 0.6),
                  radius: 1.1,
                  colors: [
                    widget.colors[widget.colors.length ~/ 2].withValues(alpha: 0.45),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Обложка профиля 1:1 (фото или видео до 15 с)
// ─────────────────────────────────────────────────────────────

/// Обложка профиля (фото или видео). Файл скачивается один раз в кэш на диске —
/// дальше открывается мгновенно. Если сеть подвела — повторяем, а по тапу можно
/// попробовать ещё раз.
class CoverView extends StatelessWidget {
  final String url;
  final String? kind;
  final String? localPath;
  final String? previewUrl;
  const CoverView({super.key, required this.url, this.kind, this.localPath, this.previewUrl});

  @override
  Widget build(BuildContext context) {
    final full = url.startsWith('http') ? url : '$kBaseUrl$url';
    if (kind == 'video') {
      final prev = (previewUrl != null && previewUrl!.isNotEmpty)
          ? (previewUrl!.startsWith('http') ? previewUrl! : '$kBaseUrl$previewUrl')
          : null;
      return _VideoCover(url: full, localPath: localPath, previewUrl: prev, key: ValueKey(localPath ?? full));
    }
    if (localExists(localPath)) {
      return localImage(localPath!, fit: BoxFit.cover);
    }
    return _ImageCover(url: full, key: ValueKey(full));
  }
}

/// Заглушка, пока обложка грузится: мягкий переливающийся градиент.
class _CoverPlaceholder extends StatelessWidget {
  final bool failed;
  final VoidCallback? onRetry;
  const _CoverPlaceholder({this.failed = false, this.onRetry});

  @override
  Widget build(BuildContext context) {
    final a = appState.accent;
    return GestureDetector(
      onTap: failed ? onRetry : null,
      child: Stack(
        fit: StackFit.expand,
        children: [
          LiveGradient(
            colors: [
              Color.lerp(a, Colors.black, 0.55)!,
              Color.lerp(a, Colors.black, 0.25)!,
              Color.lerp(a, Colors.black, 0.6)!,
            ],
            period: const Duration(seconds: 5),
          ),
          if (failed)
            const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(AppIcons.refreshCw, color: Colors.white, size: 30),
                  SizedBox(height: 6),
                  Text('Не загрузилось — нажми, чтобы повторить',
                      style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ImageCover extends StatefulWidget {
  final String url;
  const _ImageCover({super.key, required this.url});
  @override
  State<_ImageCover> createState() => _ImageCoverState();
}

class _ImageCoverState extends State<_ImageCover> {
  String? _path;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _path = kIsWeb ? widget.url : MediaCache.peek(widget.url);
    if (!kIsWeb && _path == null) _load();
  }

  @override
  void didUpdateWidget(_ImageCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _path = kIsWeb ? widget.url : MediaCache.peek(widget.url);
      if (!kIsWeb && _path == null) _load();
    }
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    final p = await MediaCache.file(widget.url);
    if (!mounted) return;
    setState(() {
      _path = p;
      _failed = p == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = _path;
    final w = MediaQuery.of(context).size.width * MediaQuery.of(context).devicePixelRatio;
    final cw = w.round().clamp(480, 1440).toInt();

    Widget fade(BuildContext c, Widget child, int? frame, bool sync) => AnimatedOpacity(
          opacity: frame == null && !sync ? 0 : 1,
          duration: const Duration(milliseconds: 250),
          child: child,
        );
    Widget failed(BuildContext _, Object _, StackTrace? _) =>
        _CoverPlaceholder(failed: true, onRetry: _load);

    if (p != null) {
      return Image(
        image: ResizeImage(localImageProvider(p), width: cw),
        fit: BoxFit.cover,
        gaplessPlayback: true,
        frameBuilder: fade,
        errorBuilder: failed,
      );
    }

    // Пока файл скачивается на диск — сразу показываем по сети (быстрый стриминг + кэш в памяти)
    return Image.network(
      widget.url,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      cacheWidth: cw,
      frameBuilder: (c, child, frame, sync) {
        if (frame != null || sync) return child;
        return const _CoverPlaceholder();
      },
      errorBuilder: failed,
    );
  }
}

class _VideoCover extends StatefulWidget {
  final String url;
  final String? localPath;
  final String? previewUrl;
  const _VideoCover({super.key, required this.url, this.localPath, this.previewUrl});
  @override
  State<_VideoCover> createState() => _VideoCoverState();
}

class _VideoCoverState extends State<_VideoCover> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _ready = false;
  bool _failed = false;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    if (_failed && mounted) setState(() => _failed = false);
    final old = _c;
    _c = null;
    old?.removeListener(_loopGuard);
    await old?.dispose();
    try {
      final opts = VideoPlayerOptions(mixWithOthers: true); // не глушит музыку
      var lp = widget.localPath;
      if (!localExists(lp)) lp = MediaCache.peek(widget.url);
      final c = lp != null
          ? localVideo(lp, options: opts)
          : VideoPlayerController.networkUrl(Uri.parse(widget.url), videoPlayerOptions: opts);
      _c = c;
      await c.initialize().timeout(const Duration(seconds: 15));
      await c.setVolume(0);
      await c.setLooping(true);
      c.addListener(_loopGuard);
      if (appState.motion) await c.play();
      if (mounted) {
        setState(() => _ready = true);
      }
      // Фоново сохраняем видео в кэш на диске, если играли по сети
      if (lp == null && !kIsWeb) {
        MediaCache.file(widget.url).catchError((_) => null);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _ready = false;
          _failed = true;
        });
      }
    }
  }

  /// Страховка: на части Android setLooping не срабатывает —
  /// ролик доигрывает и замирает. Перезапускаем вручную, как гифку.
  void _loopGuard() {
    final c = _c;
    if (c == null || _restarting || !appState.motion) return;
    final v = c.value;
    if (!v.isInitialized || v.duration == Duration.zero) return;
    final atEnd = v.isCompleted ||
        (!v.isPlaying &&
            !v.isBuffering &&
            v.position >= v.duration - const Duration(milliseconds: 250));
    if (!atEnd) return;
    _restarting = true;
    c.seekTo(Duration.zero).then((_) => c.play()).whenComplete(() => _restarting = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _c;
    if (c == null || !_ready) return;
    if (state == AppLifecycleState.resumed && appState.motion) {
      c.play(); // после сворачивания видео снова крутится
    } else if (state == AppLifecycleState.paused) {
      c.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _c?.removeListener(_loopGuard);
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (!_ready || c == null) {
      return Stack(
        fit: StackFit.expand,
        children: [
          if (widget.previewUrl != null)
            Image.network(
              widget.previewUrl!,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _CoverPlaceholder(failed: _failed, onRetry: _init),
            )
          else
            _CoverPlaceholder(failed: _failed, onRetry: _init),
          if (!_failed)
            const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white70))),
        ],
      );
    }
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: c.value.size.width,
        height: c.value.size.height,
        child: VideoPlayer(c),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Утилиты медиа
// ─────────────────────────────────────────────────────────────

/// Обрезать фото по центру в квадрат 1:1 (до [size] px). Возвращает путь к PNG.
Future<String> cropSquare(String path, {int size = 1080}) async {
  final bytes = await readLocalBytes(path);
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final img = frame.image;
  final side = math.min(img.width, img.height);
  final src = Rect.fromLTWH((img.width - side) / 2, (img.height - side) / 2,
      side.toDouble(), side.toDouble());
  final out = math.min(size, side);
  final rec = ui.PictureRecorder();
  final canvas = Canvas(rec);
  canvas.drawImageRect(img, src, Rect.fromLTWH(0, 0, out.toDouble(), out.toDouble()),
      Paint()..filterQuality = FilterQuality.high);
  final pic = rec.endRecording();
  final res = await pic.toImage(out, out);
  final data = await res.toByteData(format: ui.ImageByteFormat.png);
  return writeTempBytes(data!.buffer.asUint8List(), 'cover.png');
}

/// Длительность локального видео (null — не удалось прочитать).
Future<Duration?> videoDuration(String path) async {
  final c = localVideo(path);
  try {
    await c.initialize().timeout(const Duration(seconds: 20));
    return c.value.duration;
  } catch (_) {
    return null;
  } finally {
    await c.dispose();
  }
}
