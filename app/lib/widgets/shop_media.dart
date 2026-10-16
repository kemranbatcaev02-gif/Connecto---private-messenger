import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../media_cache.dart';
import 'effects.dart';

/// Полный адрес медиа магазина (сервер отдаёт относительные /media/...).
String shopUrl(String? u) =>
    (u == null || u.isEmpty) ? '' : (u.startsWith('http') ? u : '$kBaseUrl$u');

/// Быстрое отображение картинки с двухуровневым кэшем (память + локальный диск на телефоне/ПК,
/// и встроенный браузерный кэш в веб-версии).
class CachedShopImage extends StatefulWidget {
  final String url;
  final BoxFit fit;
  final int? targetW;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  const CachedShopImage({
    super.key,
    required this.url,
    required this.fit,
    this.targetW,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<CachedShopImage> createState() => _CachedShopImageState();
}

class _CachedShopImageState extends State<CachedShopImage> {
  String? _localPath;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && widget.url.isNotEmpty) {
      _localPath = MediaCache.peek(widget.url);
      if (_localPath == null) {
        MediaCache.file(widget.url);
      }
    }
  }

  @override
  void didUpdateWidget(covariant CachedShopImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url && !kIsWeb && widget.url.isNotEmpty) {
      _localPath = MediaCache.peek(widget.url);
      if (_localPath == null) {
        MediaCache.file(widget.url);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.url.isEmpty) return const _Placeholder();
    final isAnimated = widget.url.endsWith('.webp') ||
        widget.url.endsWith('.gif') ||
        widget.url.contains('.webp?') ||
        widget.url.contains('.gif?');
    final effectiveW = (isAnimated || kIsWeb) ? null : widget.targetW;

    final lp = _localPath;
    if (lp != null && File(lp).existsSync()) {
      return Image.file(
        File(lp),
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: effectiveW,
        filterQuality: FilterQuality.medium,
        errorBuilder: widget.errorBuilder ?? (_, __, ___) => const _Placeholder(),
      );
    }

    return Image.network(
      widget.url,
      fit: widget.fit,
      gaplessPlayback: true,
      cacheWidth: effectiveW,
      filterQuality: FilterQuality.medium,
      loadingBuilder: widget.loadingBuilder ??
          (_, child, p) => p == null ? child : const _Placeholder(),
      errorBuilder: widget.errorBuilder ?? (_, __, ___) => const _Placeholder(),
    );
  }
}

Widget buildCachedShopImage({
  Key? key,
  required String url,
  required BoxFit fit,
  int? targetW,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
  Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
}) =>
    CachedShopImage(
      key: key,
      url: url,
      fit: fit,
      targetW: targetW,
      errorBuilder: errorBuilder,
      loadingBuilder: loadingBuilder,
    );

/// Медиа товара: картинка (в т.ч. анимированный webp/gif) или видео (по кругу, без звука).
/// [still] — в списках вместо видео показываем кадр-превью, чтобы не грузить десятки роликов.
class ShopMedia extends StatelessWidget {
  final String? url;
  final String? kind;
  final String? preview;
  final bool still;
  final BoxFit fit;
  const ShopMedia(
      {super.key, this.url, this.kind, this.preview, this.still = false, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final isVideo = kind == 'video';
    if (isVideo && !still && (url ?? '').isNotEmpty) {
      return CoverView(url: url!, kind: 'video', previewUrl: preview);
    }
    final src = (preview != null && preview!.isNotEmpty)
        ? preview
        : ((url != null && url!.isNotEmpty) ? url : null);
    if (src == null || src.isEmpty) return const _Placeholder();

    if (isVideo && (preview == null || preview!.isEmpty) && (url ?? '').isNotEmpty) {
      return CoverView(url: url!, kind: 'video');
    }

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final targetW = still
        ? (260 * dpr).round().clamp(128, 720).toInt()
        : (600 * dpr).round().clamp(200, 1440).toInt();

    return buildCachedShopImage(
      url: shopUrl(src),
      fit: fit,
      targetW: targetW,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();
  @override
  Widget build(BuildContext context) {
    final a = appState.accent;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(a, Colors.black, 0.6)!, Color.lerp(a, Colors.black, 0.85)!],
        ),
      ),
    );
  }
}

/// Аватар с рамкой из магазина. Картинка рамки квадратная, отверстие под аватар —
/// ~71% её ширины (рамка на 40% больше аватара), поэтому рисуем её поверх с запасом.
class FramedAvatar extends StatelessWidget {
  final Widget child;
  final double size;
  final Map<String, dynamic>? frame;
  const FramedAvatar({super.key, required this.child, required this.size, this.frame});

  @override
  Widget build(BuildContext context) {
    final url = frame?['url'] as String?;
    if (url == null || url.isEmpty) return child;
    final preview = frame?['preview_url'] as String?;
    final pad = size * 0.20;
    final fullUrl = shopUrl(url);
    final fullPrev = (preview != null && preview.isNotEmpty) ? shopUrl(preview) : null;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(child: child),
          Positioned(
            left: -pad,
            top: -pad,
            width: size + pad * 2,
            height: size + pad * 2,
            child: IgnorePointer(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (fullPrev != null && fullPrev != fullUrl)
                    buildCachedShopImage(
                      url: fullPrev,
                      fit: BoxFit.contain,
                      loadingBuilder: (_, c, p) => p == null ? c : const SizedBox.shrink(),
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  buildCachedShopImage(
                    key: ValueKey('frame_$fullUrl'),
                    url: fullUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (_, c, p) => p == null ? c : const SizedBox.shrink(),
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Анимация профиля (снег, искры, лепестки…) — прозрачный анимированный webp поверх шапки.
class ProfileFxOverlay extends StatelessWidget {
  final Map<String, dynamic>? fx;
  final BoxFit fit;
  const ProfileFxOverlay({super.key, this.fx, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    final url = fx?['url'] as String?;
    if (url == null || url.isEmpty || !appState.motion) return const SizedBox.shrink();
    return IgnorePointer(
      child: buildCachedShopImage(
        url: shopUrl(url),
        fit: fit,
        loadingBuilder: (_, child, p) => p == null ? child : const SizedBox.shrink(),
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      ),
    );
  }
}
