part of 'chat_screen.dart';

// ─────────────────────────────────────────────────────────────
// Видеосообщения («кружочки») и история звонков в чате
// ─────────────────────────────────────────────────────────────

/// Лимит видеосообщения — как в Telegram.
const Duration kRoundMax = Duration(seconds: 60);

/// Длительность из текста сообщения «round:<мс>».
int _roundMs(String text) {
  if (!text.startsWith('round:')) return 0;
  return int.tryParse(text.substring(6)) ?? 0;
}

/// Кто сейчас играет со звуком (только один кружочек за раз).
class RoundHub {
  RoundHub._();
  static final ValueNotifier<String?> playing = ValueNotifier(null);
  static int autoplaying = 0;
  static void stop() => playing.value = null;
}

/// Кольцо прогресса вокруг кружочка.
class _RingPainter extends CustomPainter {
  final double progress; // 0..1
  final Color color;
  final double width;
  final bool track;
  _RingPainter({required this.progress, required this.color, this.width = 4, this.track = true});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(width / 2, width / 2, size.width - width, size.height - width);
    if (track) {
      canvas.drawArc(
          r,
          0,
          math.pi * 2,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..color = Colors.white.withValues(alpha: 0.18));
    }
    if (progress <= 0) return;
    canvas.drawArc(
        r,
        -math.pi / 2,
        math.pi * 2 * progress.clamp(0.0, 1.0),
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = StrokeCap.round
          ..color = color);
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.color != color || old.width != width;
}

// ── пузырь видеосообщения ──

class _RoundNote extends StatefulWidget {
  final Message msg;
  final bool mine;
  const _RoundNote({required this.msg, required this.mine});
  @override
  State<_RoundNote> createState() => _RoundNoteState();
}

class _RoundNoteState extends State<_RoundNote> {
  VideoPlayerController? _vc;
  bool _error = false;
  bool _sound = false; // играет со звуком (по нажатию)
  bool _auto = false; // крутится без звука
  bool _disposed = false;

  Message get m => widget.msg;

  @override
  void initState() {
    super.initState();
    RoundHub.playing.addListener(_onHub);
    VoiceHub.now.addListener(_onVoice);
    _load();
  }

  @override
  void didUpdateWidget(covariant _RoundNote old) {
    super.didUpdateWidget(old);
    // загрузился на сервер — ничего не пересоздаём, файл тот же
    if (_vc == null && !_error && old.msg.localPath != m.localPath) _load();
  }

  Future<void> _load() async {
    String? path;
    final lp = m.localPath;
    if (localExists(lp)) {
      path = lp;
    } else if (m.mediaUrl != null) {
      // в браузере — прямо по ссылке (кэширует сам браузер)
      path = kIsWeb ? mediaUrl(m.mediaUrl) : await MediaCache.file(mediaUrl(m.mediaUrl));
    }
    if (_disposed) return;
    if (path == null) {
      if (m.mediaUrl != null && mounted) setState(() => _error = true);
      return;
    }
    final vc = localVideo(path, options: VideoPlayerOptions(mixWithOthers: true));
    try {
      await vc.initialize();
    } catch (_) {
      await vc.dispose();
      if (mounted) setState(() => _error = true);
      return;
    }
    if (_disposed) {
      await vc.dispose();
      return;
    }
    // сразу запоминаем — если пузырь уйдёт с экрана, dispose() закроет плеер
    _vc = vc;
    vc.addListener(_onVideo);
    if (mounted) setState(() {});
    try {
      await vc.setLooping(true);
      await vc.setVolume(0);
      if (_disposed) return;
      if (appState.callPref('roundAutoplay') &&
          !appState.energySaving &&
          RoundHub.autoplaying < 3) {
        _auto = true;
        RoundHub.autoplaying++;
        await vc.play();
      }
    } catch (_) {}
  }

  void _onVideo() {
    final vc = _vc;
    if (vc == null || !_sound) return;
    final v = vc.value;
    if (v.duration > Duration.zero &&
        !v.isPlaying &&
        v.position >= v.duration - const Duration(milliseconds: 120)) {
      _stopSound(); // досмотрели до конца
    }
  }

  void _onHub() {
    if (_sound && RoundHub.playing.value != m.id) _stopSound();
  }

  void _onVoice() {
    if (_sound && (VoiceHub.now.value?.playing ?? false)) _stopSound();
  }

  Future<void> _stopSound() async {
    final vc = _vc;
    if (!_sound) return;
    _sound = false;
    if (RoundHub.playing.value == m.id) RoundHub.playing.value = null;
    if (vc != null) {
      await vc.setVolume(0);
      await vc.setLooping(true);
      if (_auto) {
        await vc.play();
      } else {
        await vc.pause();
        await vc.seekTo(Duration.zero);
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _tap() async {
    final vc = _vc;
    if (vc == null) return;
    HapticFeedback.selectionClick();
    if (!_sound) {
      await VoiceHub.stop();
      RoundHub.playing.value = m.id;
      _sound = true;
      appState.markVoicePlayed(m.id);
      await vc.setLooping(false);
      await vc.seekTo(Duration.zero);
      await vc.setVolume(1);
      await vc.play();
    } else if (vc.value.isPlaying) {
      await vc.pause();
    } else {
      await vc.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    RoundHub.playing.removeListener(_onHub);
    VoiceHub.now.removeListener(_onVoice);
    if (RoundHub.playing.value == m.id) RoundHub.playing.value = null;
    if (_auto) RoundHub.autoplaying = math.max(0, RoundHub.autoplaying - 1);
    _vc?.removeListener(_onVideo);
    _vc?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final d = _sound ? math.min(w * 0.72, 290.0) : math.min(w * 0.56, 220.0);
    final vc = _vc;
    final ms = _roundMs(m.text);
    final unplayed = !widget.mine && !appState.isVoicePlayed(m.id);
    return GestureDetector(
      onTap: _tap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        width: d,
        height: d,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: accentGradient(appState.accent),
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 14),
                ],
              ),
            ),
            if (vc != null && vc.value.isInitialized)
              ClipOval(
                child: FittedBox(
                  fit: BoxFit.cover,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(
                    width: vc.value.size.width,
                    height: vc.value.size.height,
                    child: VideoPlayer(vc),
                  ),
                ),
              )
            else
              Center(
                child: _error
                    ? const Icon(AppIcons.circleAlert, color: Colors.white, size: 34)
                    : const SizedBox(
                        width: 34,
                        height: 34,
                        child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white)),
              ),
            if (m.uploading)
              Container(
                decoration: BoxDecoration(
                    shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.35)),
                child: const Center(
                  child: SizedBox(
                      width: 46,
                      height: 46,
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                ),
              ),
            if (vc != null && _sound)
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: vc,
                builder: (_, v, _) {
                  final dur = v.duration.inMilliseconds;
                  final p = dur <= 0 ? 0.0 : v.position.inMilliseconds / dur;
                  return CustomPaint(
                      painter: _RingPainter(
                          progress: p, color: Colors.white, width: 4, track: true));
                },
              ),
            if (vc != null && _sound && !vc.value.isPlaying)
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                  child: const Icon(AppIcons.play, color: Colors.white, size: 32),
                ),
              ),
            // длительность и значок звука
            Positioned(
              left: d * 0.14,
              bottom: d * 0.07,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(10)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (vc != null && _sound)
                      ValueListenableBuilder<VideoPlayerValue>(
                        valueListenable: vc,
                        builder: (_, v, _) => Text(
                            _fmtDur((v.duration - v.position).inMilliseconds.clamp(0, 1 << 30)),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()])),
                      )
                    else
                      Text(_fmtDur(ms > 0 ? ms : (vc?.value.duration.inMilliseconds ?? 0)),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    Icon(_sound ? AppIcons.volume2 : AppIcons.volumeOff,
                        color: Colors.white, size: 13),
                    if (unplayed) ...[
                      const SizedBox(width: 4),
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: appState.accent, shape: BoxShape.circle),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── экран записи кружочка ──

/// Круг с камерой, кольцо-таймер, вспышка/зум/смена камеры.
class _RoundRecorderView extends StatelessWidget {
  final CameraController? cam;
  final bool ready;
  final bool locked;
  final bool paused;
  final bool front;
  final bool torch;
  final double zoom;
  final double zoomMax;
  final ValueListenable<Duration> time;
  final VoidCallback onFlip;
  final int flipTick;
  final VoidCallback onTorch;
  final VoidCallback onZoomStep;
  final ValueChanged<double> onZoom;
  final VoidCallback onZoomStart;
  const _RoundRecorderView({
    required this.cam,
    required this.ready,
    required this.locked,
    required this.paused,
    required this.front,
    required this.torch,
    required this.zoom,
    required this.zoomMax,
    required this.time,
    required this.onFlip,
    this.flipTick = 0,
    required this.onTorch,
    required this.onZoomStep,
    required this.onZoom,
    required this.onZoomStart,
  });

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final d = math.min(w * 0.8, 320.0);
    final screenFlash = torch && front;
    final c = cam;
    return Stack(
      fit: StackFit.expand,
      children: [
        // фон: размытый чат, а при «вспышке» фронтальной камеры — белый свет
        _RoundShade(flash: screenFlash),
        Align(
          alignment: const Alignment(0, -0.35),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.6, end: 1),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutBack,
                builder: (_, s, child) => Transform.scale(scale: s, child: child),
                child: SizedBox(
                  width: d + 16,
                  height: d + 16,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // кольцо-таймер
                      ValueListenableBuilder<Duration>(
                        valueListenable: time,
                        builder: (_, t, _) => CustomPaint(
                          size: Size(d + 16, d + 16),
                          painter: _RingPainter(
                              progress: t.inMilliseconds / kRoundMax.inMilliseconds,
                              color: paused ? Colors.white70 : kDanger,
                              width: 5),
                        ),
                      ),
                      GestureDetector(
                        onDoubleTap: ready ? onFlip : null,
                        onScaleStart: (_) => onZoomStart(),
                        onScaleUpdate: (s) {
                          if (s.pointerCount >= 2) onZoom(s.scale);
                        },
                        child: _FlipCam(
                          tick: flipTick,
                          child: Container(
                          width: d,
                          height: d,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black,
                              // при «вспышке» — мягкое свечение вокруг кружка
                              boxShadow: screenFlash
                                  ? const [BoxShadow(color: Color(0x33000000), blurRadius: 24)]
                                  : null),
                          child: ClipOval(
                            child: (c != null && c.value.isInitialized)
                                ? FittedBox(
                                    fit: BoxFit.cover,
                                    clipBehavior: Clip.hardEdge,
                                    child: SizedBox(
                                      width: d,
                                      height: d * c.value.aspectRatio,
                                      child: CameraPreview(c),
                                    ),
                                  )
                                : const Center(
                                    child: SizedBox(
                                        width: 36,
                                        height: 36,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.6, color: Colors.white))),
                          ),
                        ),
                        ),
                      ),
                      if (paused)
                        Container(
                          width: d,
                          height: d,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.45)),
                          child: const Icon(AppIcons.pause, color: Colors.white, size: 54),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: ready ? 1 : 0.4,
                child: IgnorePointer(
                  ignoring: !ready,
                  child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _roundCtl(front ? AppIcons.flash : AppIcons.flashlight,
                        torch, onTorch, screenFlash),
                    const SizedBox(width: 14),
                    _roundCtl(AppIcons.cameraSwitch, false, onFlip, screenFlash),
                    if (zoomMax > 1.01) ...[
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: onZoomStep,
                        child: Container(
                          height: 46,
                          constraints: const BoxConstraints(minWidth: 46),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: (screenFlash ? Colors.black : Colors.white)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(23),
                          ),
                          child: Text('${zoom.toStringAsFixed(zoom < 10 ? 1 : 0)}×',
                              style: TextStyle(
                                  color: screenFlash ? Colors.black87 : Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14)),
                        ),
                      ),
                    ],
                  ],
                ),
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: (screenFlash ? Colors.black12 : Colors.black45),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: (screenFlash ? Colors.black26 : Colors.white24),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      locked ? AppIcons.cameraSwitch : AppIcons.lock,
                      size: 13,
                      color: screenFlash ? Colors.black87 : Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      locked
                          ? 'Двойной тап — камера  •  Щипок — зум'
                          : 'Смахни вверх для фиксации записи',
                      style: TextStyle(
                        color: screenFlash ? Colors.black87 : Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundCtl(IconData icon, bool active, VoidCallback onTap, bool light) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? const Color(0xFFFFD54F)
                : (light ? Colors.black.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.45)),
            border: Border.all(
              color: active
                  ? const Color(0xFFFFD54F)
                  : (light ? Colors.black26 : Colors.white24),
              width: 1,
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: const Color(0xFFFFD54F).withValues(alpha: 0.4),
                      blurRadius: 10,
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(icon,
                color: active ? Colors.black87 : (light ? Colors.black87 : Colors.white),
                size: 21),
          ),
        ),
      );
}

/// Фон под кружочком: размытый и затемнённый чат или, при «вспышке», чистый белый.
class _RoundShade extends StatelessWidget {
  final bool flash;
  const _RoundShade({required this.flash});
  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      child: flash
          ? const SizedBox.expand(
              key: ValueKey('flash'), child: ColoredBox(color: Colors.white))
          : ClipRect(
              key: const ValueKey('blur'),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
                child: ColoredBox(color: Colors.black.withValues(alpha: 0.5)),
              ),
            ),
    );
  }
}

/// Смена камеры: кружок «переворачивается» вокруг вертикальной оси.
class _FlipCam extends StatefulWidget {
  final int tick;
  final Widget child;
  const _FlipCam({required this.tick, required this.child});
  @override
  State<_FlipCam> createState() => _FlipCamState();
}

class _FlipCamState extends State<_FlipCam> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 560));

  @override
  void didUpdateWidget(covariant _FlipCam old) {
    super.didUpdateWidget(old);
    if (old.tick != widget.tick && appState.motion) _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (_, child) {
        // всегда один и тот же Transform — превью камеры не пересоздаётся
        final t = Curves.easeInOutCubic.transform(_c.value);
        // первая половина — уходит «ребром», вторая — выходит уже другая сторона
        final angle = t < 0.5 ? t * math.pi : (t - 1) * math.pi;
        final scale = 1 - 0.08 * math.sin(t * math.pi);
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0014)
            ..rotateY(angle),
          child: Transform.scale(scale: scale, child: child),
        );
      },
    );
  }
}

// ── история звонка в чате ──

String _callTitle(Message m) {
  final info = (m.extra?['call'] as Map?) ?? const {};
  final video = info['video'] == true;
  final status = info['status'];
  final out = m.mine;
  final what = video ? 'видеозвонок' : 'звонок';
  if (status == 'busy' && out) return 'Линия занята';
  if (status == 'missed' || status == 'busy') {
    return out ? 'Отменённый $what' : 'Пропущенный $what';
  }
  if (status == 'declined') return 'Отклонённый $what';
  if (status == 'failed') return 'Неудачный $what';
  final t = out ? 'Исходящий $what' : 'Входящий $what';
  return t[0].toUpperCase() + t.substring(1);
}

class _CallContent extends StatelessWidget {
  final Message msg;
  final bool mine;
  final ValueChanged<bool>? onCall;
  const _CallContent({required this.msg, required this.mine, this.onCall});

  @override
  Widget build(BuildContext context) {
    final info = (msg.extra?['call'] as Map?) ?? const {};
    final video = info['video'] == true;
    final status = info['status'] as String?;
    final dur = (info['duration'] as num?)?.toInt() ?? 0;
    final bad = status == 'missed' || status == 'busy' || status == 'declined' || status == 'failed';
    final fg = mine ? Colors.white : Theme.of(context).colorScheme.onSurface;
    final sub = mine ? Colors.white70 : subtleText(context);
    final arrow = bad && !mine
        ? AppIcons.phoneMissed
        : (mine ? AppIcons.phoneOutgoing : AppIcons.phoneIncoming);
    final arrowColor = bad ? (mine ? const Color(0xFFFFC2C2) : kDanger) : (mine ? Colors.white : kSuccess);
    return SizedBox(
      width: 232,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_callTitle(msg),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(arrow, size: 15, color: arrowColor),
                    const SizedBox(width: 4),
                    Text(
                      dur > 0 ? _fmtDur(dur * 1000) : (bad ? 'Нажми, чтобы перезвонить' : msg.time),
                      style: TextStyle(color: sub, fontSize: 12.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onCall != null)
            Pressable(
              onTap: () => onCall!(video),
              scale: 0.88,
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: mine ? Colors.white.withValues(alpha: 0.22) : appState.accent.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(video ? AppIcons.video : AppIcons.phone,
                    color: mine ? Colors.white : appState.accent, size: 21),
              ),
            ),
        ],
      ),
    );
  }
}
