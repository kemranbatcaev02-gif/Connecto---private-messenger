part of 'chat_screen.dart';

// ─────────────────────────────────────────────────────────────
// Волна голосового: хранится в тексте сообщения «wave:<мс>:<48 символов>»
// ─────────────────────────────────────────────────────────────

const String _kWaveAlphabet = '0123456789abcdefghijklmnopqrstuv';
const int _kWaveBars = 48;

class VoiceMeta {
  final int durationMs;
  final List<double> bars; // 0..1
  const VoiceMeta(this.durationMs, this.bars);
}

/// Сжать громкость записи в 48 столбиков и упаковать в строку.
String encodeWave(List<double> samples, int durationMs) {
  if (samples.isEmpty) return 'wave:$durationMs:';
  final out = <double>[];
  for (var i = 0; i < _kWaveBars; i++) {
    final a = (i * samples.length / _kWaveBars).floor();
    var b = ((i + 1) * samples.length / _kWaveBars).floor();
    if (b <= a) b = a + 1;
    var peak = 0.0;
    for (var j = a; j < b && j < samples.length; j++) {
      if (samples[j] > peak) peak = samples[j];
    }
    out.add(peak);
  }
  final maxV = out.fold<double>(0.05, (m, v) => v > m ? v : m);
  final sb = StringBuffer('wave:$durationMs:');
  for (final v in out) {
    final q = ((v / maxV) * 31).round();
    sb.write(_kWaveAlphabet[q < 0 ? 0 : (q > 31 ? 31 : q)]);
  }
  return sb.toString();
}

VoiceMeta? parseWave(String text) {
  if (!text.startsWith('wave:')) return null;
  final parts = text.split(':');
  if (parts.length < 3) return null;
  final ms = int.tryParse(parts[1]) ?? 0;
  final bars = <double>[];
  for (final ch in parts[2].split('')) {
    final i = _kWaveAlphabet.indexOf(ch);
    if (i >= 0) bars.add(i / 31);
  }
  return VoiceMeta(ms, bars);
}

/// Стабильная «псевдоволна» для старых голосовых без сохранённой волны.
List<double> _fallbackBars(String seed) {
  final rnd = math.Random(seed.hashCode);
  return List.generate(_kWaveBars, (i) {
    final base = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(i * 0.45 + rnd.nextDouble()));
    return (base * (0.6 + rnd.nextDouble() * 0.5)).clamp(0.12, 1.0);
  });
}

String _fmtDur(int ms) {
  final s = (ms / 1000).round();
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

// ─────────────────────────────────────────────────────────────
// Единый плеер: играет одно голосовое, не останавливается при прокрутке,
// после окончания включает следующее непрослушанное.
// ─────────────────────────────────────────────────────────────

class VoiceItem {
  final String id;
  final String chatId;
  final String url;
  final String? localPath;
  final String title;
  final int durationMs;
  final bool mine;
  const VoiceItem(
      {required this.id,
      required this.chatId,
      required this.url,
      this.localPath,
      required this.title,
      this.durationMs = 0,
      this.mine = false});
}

class VoiceNow {
  final VoiceItem item;
  final bool playing;
  final bool loading;
  final int posMs;
  final int durMs;
  final DateTime stamp;
  const VoiceNow(this.item, this.playing, this.loading, this.posMs, this.durMs, this.stamp);

  VoiceNow copy({bool? playing, bool? loading, int? posMs, int? durMs}) => VoiceNow(
      item,
      playing ?? this.playing,
      loading ?? this.loading,
      posMs ?? livePos(), // сохраняем плавность при смене состояния
      durMs ?? this.durMs,
      DateTime.now());

  /// Плавная позиция «сейчас» (между редкими событиями плеера).
  int livePos() {
    if (!playing || loading) return posMs;
    final add = DateTime.now().difference(stamp).inMilliseconds * appState.voiceSpeed;
    final p = posMs + add.round();
    return durMs > 0 && p > durMs ? durMs : p;
  }

  double fraction() => durMs <= 0 ? 0 : (livePos() / durMs).clamp(0.0, 1.0);
}

class VoiceHub {
  VoiceHub._();
  static AudioPlayer? _player;
  static final ValueNotifier<VoiceNow?> now = ValueNotifier(null);

  /// Очередь голосовых текущего чата (задаёт экран чата).
  static List<VoiceItem> Function()? queue;

  static AudioPlayer get _p {
    final existing = _player;
    if (existing != null) return existing;
    final p = AudioPlayer();
    _player = p;
    p.onPositionChanged.listen((d) {
      final n = now.value;
      if (n != null) now.value = n.copy(posMs: d.inMilliseconds, loading: false);
    });
    p.onDurationChanged.listen((d) {
      final n = now.value;
      if (n != null && d.inMilliseconds > 0) now.value = n.copy(durMs: d.inMilliseconds);
    });
    p.onPlayerStateChanged.listen((s) {
      final n = now.value;
      if (n == null) return;
      if (s == PlayerState.playing) {
        now.value = n.copy(playing: true);
      } else if (s == PlayerState.paused || s == PlayerState.stopped) {
        now.value = n.copy(playing: false, loading: false);
      }
    });
    p.onPlayerComplete.listen((_) => _next());
    return p;
  }

  static bool isCurrent(String id) => now.value?.item.id == id;

  // ── кэш голосовых: скачиваем один раз, дальше играем с диска (без подлагиваний) ──
  static final Map<String, Future<String?>> _dl = {};
  static int _token = 0;

  static Future<String?> cached(String url) async {
    if (kIsWeb) return null; // в браузере играем прямо по ссылке
    final p = await _fetch(url);
    // кэш почистили в «Данные и память» — файла уже нет, скачаем заново
    if (p != null && !File(p).existsSync()) {
      _dl.remove(url);
      return _fetch(url);
    }
    return p;
  }

  static Future<String?> _fetch(String url) {
    return _dl[url] ??= () async {
      try {
        final dir = await getTemporaryDirectory();
        final d = Directory('${dir.path}/voice_cache');
        if (!d.existsSync()) d.createSync(recursive: true);
        final dot = url.lastIndexOf('.');
        final ext = dot > url.lastIndexOf('/') && url.length - dot <= 6 ? url.substring(dot) : '.m4a';
        final f = File('${d.path}/${url.hashCode.toUnsigned(32).toRadixString(16)}$ext');
        if (f.existsSync() && f.lengthSync() > 0) return f.path;
        final r = await Api.client.get(Uri.parse(url)).timeout(const Duration(seconds: 25));
        if (r.statusCode != 200 || r.bodyBytes.isEmpty) {
          _dl.remove(url);
          return null;
        }
        await f.writeAsBytes(r.bodyBytes, flush: true);
        return f.path;
      } catch (_) {
        _dl.remove(url);
        return null;
      }
    }();
  }

  /// Заранее скачать следующее голосовое из очереди.
  static void _prefetchAfter(VoiceItem it) {
    final list = queue?.call() ?? const <VoiceItem>[];
    final i = list.indexWhere((x) => x.id == it.id);
    if (i < 0) return;
    for (var j = i + 1; j < list.length && j <= i + 2; j++) {
      final n = list[j];
      if (n.localPath == null) cached(n.url);
    }
  }

  static Future<void> toggle(VoiceItem it, {double startFrac = 0}) async {
    final n = now.value;
    if (n != null && n.item.id == it.id) {
      if (n.playing) {
        await _p.pause();
      } else {
        await _p.resume();
        await _p.setPlaybackRate(appState.voiceSpeed);
      }
      return;
    }
    await play(it, startFrac: startFrac);
  }

  static Future<void> play(VoiceItem it, {double startFrac = 0}) async {
    final p = _p;
    final token = ++_token;
    now.value = VoiceNow(it, false, true, 0, it.durationMs, DateTime.now());
    appState.markVoicePlayed(it.id);
    try {
      await p.stop();
      var lp = it.localPath;
      if (!localExists(lp)) lp = await cached(it.url);
      if (token != _token) return; // пока качали, нажали другое
      final Source src = (lp != null && localExists(lp)) ? localAudio(lp) : UrlSource(it.url);
      await p.play(src);
      _prefetchAfter(it);
      await p.setPlaybackRate(appState.voiceSpeed);
      if (startFrac > 0.01 && it.durationMs > 0) {
        await p.seek(Duration(milliseconds: (it.durationMs * startFrac).round()));
      }
    } catch (_) {
      now.value = null;
    }
  }

  static Future<void> seekFrac(double f) async {
    final n = now.value;
    if (n == null) return;
    final dur = n.durMs > 0 ? n.durMs : n.item.durationMs;
    if (dur <= 0) return;
    final ms = (dur * f.clamp(0.0, 1.0)).round();
    now.value = n.copy(posMs: ms);
    await _p.seek(Duration(milliseconds: ms));
  }

  static Future<void> setSpeed(double s) async {
    appState.setVoiceSpeed(s);
    final n = now.value;
    if (n != null) {
      now.value = n.copy(posMs: n.livePos());
      if (n.playing) await _p.setPlaybackRate(s);
    }
  }

  static Future<void> stop() async {
    _token++;
    now.value = null;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  static Future<void> _next() async {
    final cur = now.value;
    now.value = null;
    if (cur == null) return;
    final list = queue?.call() ?? const <VoiceItem>[];
    final i = list.indexWhere((x) => x.id == cur.item.id);
    if (i < 0) return;
    for (var j = i + 1; j < list.length; j++) {
      final it = list[j];
      if (it.mine) continue;
      if (!appState.isVoicePlayed(it.id)) {
        await play(it);
      }
      return;
    }
  }
}

double _nextSpeed(double s) => s < 1.25 ? 1.5 : (s < 1.75 ? 2.0 : 1.0);
String _speedLabel(double s) => s == 1.5 ? '1.5×' : '${s.round()}×';

// ─────────────────────────────────────────────────────────────
// Пузырь голосового
// ─────────────────────────────────────────────────────────────

class _VoicePlayer extends StatefulWidget {
  final VoiceItem item;
  final List<double> bars;
  final bool mine;
  const _VoicePlayer({required this.item, required this.bars, required this.mine});
  @override
  State<_VoicePlayer> createState() => _VoicePlayerState();
}

class _VoicePlayerState extends State<_VoicePlayer> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker((_) => _tick());
  final ValueNotifier<double> _progress = ValueNotifier(0);
  double? _scrub;
  String _sig = '';

  bool get _current => VoiceHub.isCurrent(widget.item.id);

  @override
  void initState() {
    super.initState();
    VoiceHub.now.addListener(_onHub);
    _onHub();
  }

  @override
  void dispose() {
    VoiceHub.now.removeListener(_onHub);
    _ticker.dispose();
    _progress.dispose();
    super.dispose();
  }

  void _onHub() {
    final n = VoiceHub.now.value;
    final cur = n != null && n.item.id == widget.item.id;
    if (n != null && cur && n.playing && !n.loading && appState.motion) {
      if (!_ticker.isActive) _ticker.start();
    } else if (_ticker.isActive) {
      _ticker.stop();
    }
    _progress.value = (n != null && cur) ? n.fraction() : 0;
    // перестраиваем пузырь только при смене состояния, а не на каждый тик позиции —
    // иначе все голосовые в чате перерисовываются по 5 раз в секунду
    final sig = (n != null && cur)
        ? '${n.playing}|${n.loading}|${n.durMs}|${appState.voiceSpeed}|${appState.isVoicePlayed(widget.item.id)}'
        : 'off|${appState.isVoicePlayed(widget.item.id)}';
    if (sig != _sig) {
      _sig = sig;
      if (mounted) setState(() {});
    }
  }

  void _tick() {
    final n = VoiceHub.now.value;
    if (n == null || n.item.id != widget.item.id) return;
    final f = n.fraction();
    // 172 px волны: меньше полупикселя — не перерисовываем
    if ((f - _progress.value).abs() * 172 >= 0.5 || f == 0 || f >= 1) _progress.value = f;
  }

  void _tap() {
    HapticFeedback.selectionClick();
    VoiceHub.toggle(widget.item);
  }

  void _seekTo(double f) {
    if (_current) {
      VoiceHub.seekFrac(f);
    } else {
      VoiceHub.play(widget.item, startFrac: f);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = widget.mine;
    final n = VoiceHub.now.value;
    final cur = n != null && n.item.id == widget.item.id;
    final playing = n != null && cur && n.playing;
    final loading = n != null && cur && n.loading;
    final fg = mine ? Colors.white : appState.accent;
    final dim = mine ? Colors.white.withValues(alpha: 0.35) : appState.accent.withValues(alpha: 0.28);
    final durMs = (n != null && cur && n.durMs > 0) ? n.durMs : widget.item.durationMs;
    final unplayed = !mine && !appState.isVoicePlayed(widget.item.id);
    final metaColor = mine ? Colors.white70 : subtleText(context);
    return SizedBox(
      width: 240,
      child: Row(
        children: [
          Pressable(
            onTap: _tap,
            scale: 0.88,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: mine ? Colors.white.withValues(alpha: 0.22) : appState.accent,
                shape: BoxShape.circle,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (loading)
                    const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (c, a) => ScaleTransition(
                        scale: a, child: FadeTransition(opacity: a, child: c)),
                    child: Icon(playing ? AppIcons.pause : AppIcons.play,
                        key: ValueKey(playing), color: Colors.white, size: 24),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _seekTo((d.localPosition.dx / 172).clamp(0.0, 1.0)),
                  onHorizontalDragStart: (d) =>
                      setState(() => _scrub = (d.localPosition.dx / 172).clamp(0.0, 1.0)),
                  onHorizontalDragUpdate: (d) =>
                      setState(() => _scrub = (d.localPosition.dx / 172).clamp(0.0, 1.0)),
                  onHorizontalDragEnd: (_) {
                    final f = _scrub;
                    setState(() => _scrub = null);
                    if (f != null) _seekTo(f);
                  },
                  child: RepaintBoundary(
                    child: SizedBox(
                      width: 172,
                      height: 30,
                      child: ValueListenableBuilder<double>(
                        valueListenable: _progress,
                        builder: (_, p, __) => CustomPaint(
                          painter: _WavePainter(
                              bars: widget.bars,
                              progress: _scrub ?? p,
                              fg: fg,
                              dim: dim),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    RepaintBoundary(
                      child: ValueListenableBuilder<double>(
                      valueListenable: _progress,
                      builder: (_, p, __) => Text(
                        cur && (playing || p > 0)
                            ? _fmtDur(((_scrub ?? p) * durMs).round())
                            : (durMs > 0 ? _fmtDur(durMs) : '0:00'),
                        style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: metaColor,
                            fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                    ),
                    if (unplayed) ...[
                      const SizedBox(width: 5),
                      Container(
                        width: 6,
                        height: 6,
                        decoration:
                            BoxDecoration(color: appState.accent, shape: BoxShape.circle),
                      ),
                    ],
                    const Spacer(),
                    if (cur)
                      GestureDetector(
                        onTap: () {
                          VoiceHub.setSpeed(_nextSpeed(appState.voiceSpeed));
                          setState(() {});
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1.5),
                          decoration: BoxDecoration(
                              color: fg.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text(_speedLabel(appState.voiceSpeed),
                              style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w800, color: fg)),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color fg;
  final Color dim;
  _WavePainter({required this.bars, required this.progress, required this.fg, required this.dim});

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;
    final n = bars.length;
    final gap = 1.6;
    final w = (size.width - gap * (n - 1)) / n;
    final playedX = size.width * progress;
    final pDim = Paint()..color = dim;
    final pFg = Paint()..color = fg;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final h = math.max(3.0, bars[i] * size.height);
      final r = RRect.fromLTRBR(
          x, (size.height - h) / 2, x + w, (size.height + h) / 2, Radius.circular(w / 2));
      if (x + w <= playedX) {
        canvas.drawRRect(r, pFg);
      } else if (x >= playedX) {
        canvas.drawRRect(r, pDim);
      } else {
        canvas.drawRRect(r, pDim);
        canvas.save();
        canvas.clipRect(Rect.fromLTRB(x, 0, playedX, size.height));
        canvas.drawRRect(r, pFg);
        canvas.restore();
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.progress != progress || old.fg != fg || old.bars != bars || old.dim != dim;
}

/// Полоска «сейчас играет» под шапкой чата.
class _NowPlayingBar extends StatefulWidget {
  final String chatId;
  final ValueChanged<String> onTap;
  const _NowPlayingBar({required this.chatId, required this.onTap});
  @override
  State<_NowPlayingBar> createState() => _NowPlayingBarState();
}

class _NowPlayingBarState extends State<_NowPlayingBar> with SingleTickerProviderStateMixin {
  late final Ticker _t = createTicker((_) {
    final f = VoiceHub.now.value?.fraction() ?? 0;
    if ((f - _p.value).abs() > 0.002 || f == 0) _p.value = f;
  });
  final ValueNotifier<double> _p = ValueNotifier(0);
  String _sig = '';

  @override
  void initState() {
    super.initState();
    VoiceHub.now.addListener(_on);
    _on();
  }

  @override
  void dispose() {
    VoiceHub.now.removeListener(_on);
    _t.dispose();
    _p.dispose();
    super.dispose();
  }

  void _on() {
    final n = VoiceHub.now.value;
    if (n != null && n.playing && appState.motion) {
      if (!_t.isActive) _t.start();
    } else if (_t.isActive) {
      _t.stop();
    }
    _p.value = n?.fraction() ?? 0;
    final sig = n == null
        ? 'none'
        : '${n.item.id}|${n.playing}|${n.loading}|${n.durMs}|${appState.voiceSpeed}';
    if (sig != _sig) {
      _sig = sig;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = VoiceHub.now.value;
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      child: (n == null || n.item.chatId != widget.chatId)
          ? const SizedBox(width: double.infinity)
          : Material(
              color: cardColor(context),
              child: InkWell(
                onTap: () => widget.onTap(n.item.id),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 2, 4, 2),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(n.playing ? AppIcons.pause : AppIcons.play,
                                color: appState.accent),
                            onPressed: () => VoiceHub.toggle(n.item),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(n.item.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800, fontSize: 13.5)),
                                ValueListenableBuilder<double>(
                                  valueListenable: _p,
                                  builder: (_, __, ___) => Text(
                                      'Голосовое · ${_fmtDur(n.livePos())}'
                                      '${n.durMs > 0 ? ' / ${_fmtDur(n.durMs)}' : ''}',
                                      style: TextStyle(
                                          color: subtleText(context), fontSize: 12)),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              VoiceHub.setSpeed(_nextSpeed(appState.voiceSpeed));
                              setState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                  color: appState.accent.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(9)),
                              child: Text(_speedLabel(appState.voiceSpeed),
                                  style: TextStyle(
                                      color: appState.accent,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12)),
                            ),
                          ),
                          IconButton(
                            icon: Icon(AppIcons.x, color: subtleText(context), size: 20),
                            onPressed: VoiceHub.stop,
                          ),
                        ],
                      ),
                    ),
                    ValueListenableBuilder<double>(
                      valueListenable: _p,
                      builder: (_, p, __) => LinearProgressIndicator(
                        value: p,
                        minHeight: 2.2,
                        backgroundColor: Colors.transparent,
                        color: appState.accent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Запись
// ─────────────────────────────────────────────────────────────

/// Живая волна записи: новые столбики появляются справа.
class _LiveWave extends StatelessWidget {
  final List<double> samples;
  final Listenable listenable;
  final Color color;
  const _LiveWave({required this.samples, required this.listenable, required this.color});
  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _LiveWavePainter(samples, color, listenable),
          size: const Size(double.infinity, 30),
        ),
      );
}

class _LiveWavePainter extends CustomPainter {
  final List<double> samples;
  final Color color;
  _LiveWavePainter(this.samples, this.color, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    const w = 3.0, gap = 2.0;
    final count = (size.width / (w + gap)).floor();
    final p = Paint()..color = color;
    final start = samples.length > count ? samples.length - count : 0;
    final visible = samples.length - start;
    final offsetX = size.width - visible * (w + gap);
    for (var i = 0; i < visible; i++) {
      final v = samples[start + i];
      final h = math.max(3.0, v * size.height);
      final x = offsetX + i * (w + gap);
      canvas.drawRRect(
          RRect.fromLTRBR(x, (size.height - h) / 2, x + w, (size.height + h) / 2,
              const Radius.circular(1.5)),
          p);
    }
    // пунктир там, где ещё пусто
    final dot = Paint()..color = color.withValues(alpha: 0.25);
    for (var x = offsetX - (w + gap); x > 0; x -= (w + gap)) {
      canvas.drawCircle(Offset(x + w / 2, size.height / 2), 1.2, dot);
    }
  }

  @override
  bool shouldRepaint(covariant _LiveWavePainter old) => true;
}

/// Большая «капля» под пальцем: дышит в такт голосу, уезжает влево при отмене.
class _RecordBlob extends StatelessWidget {
  final ValueListenable<double> amp;
  final ValueListenable<Offset> drag;
  final bool locked;
  final bool round;
  final VoidCallback? onSend;
  const _RecordBlob(
      {required this.amp,
      required this.drag,
      required this.locked,
      this.round = false,
      this.onSend});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(child: AnimatedBuilder(
      animation: Listenable.merge([amp, drag]),
      builder: (_, __) {
        final dx = locked ? 0.0 : drag.value.dx.clamp(-150.0, 0.0);
        final cancel = (-dx / 150).clamp(0.0, 1.0);
        final base = Color.lerp(appState.accent, kDanger, cancel)!;
        final halo = 66 + amp.value * 28;
        return Transform.translate(
          offset: Offset(dx, 0),
          child: SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 110),
                  width: locked ? 0 : halo,
                  height: locked ? 0 : halo,
                  decoration: BoxDecoration(
                      color: base.withValues(alpha: 0.22), shape: BoxShape.circle),
                ),
                GestureDetector(
                  onTap: onSend,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: accentGradient(base),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: base.withValues(alpha: 0.45), blurRadius: 14),
                      ],
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                      child: Icon(
                        locked
                            ? AppIcons.send
                            : (cancel > 0.7
                                ? AppIcons.trash2
                                : (round ? AppIcons.video : AppIcons.mic)),
                        key: ValueKey(locked ? 's' : (cancel > 0.7 ? 't' : 'm')),
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ));
  }
}

/// Замочек над кнопкой: тянешь вверх — запись без рук.
class _LockPill extends StatelessWidget {
  final ValueListenable<Offset> drag;
  const _LockPill({required this.drag});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Offset>(
      valueListenable: drag,
      builder: (_, d, __) {
        final up = (-d.dy / 100).clamp(0.0, 1.0);
        return Transform.translate(
          offset: Offset(0, -up * 30),
          child: Container(
            width: 42,
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: cardColor(context),
              borderRadius: BorderRadius.circular(21),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 12),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(up > 0.9 ? AppIcons.lock : AppIcons.lockOpen,
                    size: 20, color: Color.lerp(subtleText(context), appState.accent, up)),
                const SizedBox(height: 4),
                const _BounceChevron(),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BounceChevron extends StatefulWidget {
  const _BounceChevron();
  @override
  State<_BounceChevron> createState() => _BounceChevronState();
}

class _BounceChevronState extends State<_BounceChevron> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, child) =>
            Transform.translate(offset: Offset(0, -4 * _c.value), child: child),
        child: Icon(AppIcons.chevronUp, size: 18, color: subtleText(context)),
      );
}

/// «‹ Влево — отмена» с бегущей стрелкой.
class _SlideHint extends StatefulWidget {
  final ValueListenable<Offset> drag;
  const _SlideHint({required this.drag});
  @override
  State<_SlideHint> createState() => _SlideHintState();
}

class _SlideHintState extends State<_SlideHint> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_c, widget.drag]),
      builder: (_, __) {
        final dx = widget.drag.value.dx.clamp(-150.0, 0.0);
        final fade = 1 - (-dx / 120).clamp(0.0, 1.0);
        return Opacity(
          opacity: fade,
          child: Transform.translate(
            offset: Offset(dx * 0.5, 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.translate(
                  offset: Offset(-6 * math.sin(_c.value * math.pi), 0),
                  child: Icon(AppIcons.chevronLeft, size: 20, color: subtleText(context)),
                ),
                Text('Влево — отмена',
                    style: TextStyle(
                        color: subtleText(context),
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      },
    );
  }
}
