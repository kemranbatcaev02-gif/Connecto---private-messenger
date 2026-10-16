import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../app_state.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'call_manager.dart';

/// Слой звонка поверх всего приложения (выше навигатора): полноэкранный
/// звонок, мини-окно при сворачивании и картинка-в-картинке.
/// Стоит в MaterialApp.builder, поэтому звонок не пропадает при переходах.
class CallLayer extends StatefulWidget {
  const CallLayer({super.key});
  @override
  State<CallLayer> createState() => _CallLayerState();
}

class _CallLayerState extends State<CallLayer> with WidgetsBindingObserver {
  CallPhase _lastPhase = CallPhase.idle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    calls.addListener(_on);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    calls.removeListener(_on);
    super.dispose();
  }

  void _on() {
    final c = calls;
    if (_lastPhase == CallPhase.idle && c.phase != CallPhase.idle) {
      // звонок начался — клавиатуру из чата убираем
      FocusManager.instance.primaryFocus?.unfocus();
    }
    _lastPhase = c.phase;
    if (mounted) setState(() {});
  }

  /// Кнопка «назад»: звонок сворачивается, а не закрывает экран под ним.
  /// Такой же наблюдатель зарегистрирован в CallManager.attach() — какой бы порядок
  /// ни выбрал Flutter, один из них сработает раньше навигатора.
  @override
  Future<bool> didPopRoute() => calls.handleBack();

  @override
  Widget build(BuildContext context) {
    final c = calls;
    Widget child;
    String key;
    if (c.phase == CallPhase.idle) {
      child = const SizedBox.shrink();
      key = 'none';
    } else if (c.pip) {
      child = const _PipView();
      key = 'pip';
    } else if (c.minimized) {
      child = const _MiniCall();
      key = 'mini';
    } else {
      child = const CallScreen();
      key = 'full';
    }
    return Material(
      type: MaterialType.transparency,
      child: AnimatedSwitcher(
        duration: Duration(milliseconds: appState.motion ? 320 : 0),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        layoutBuilder: (cur, prev) => Stack(
          fit: StackFit.expand,
          children: [...prev, ?cur],
        ),
        transitionBuilder: (w, a) {
          if (w.key == const ValueKey('full')) {
            return FadeTransition(
              opacity: a,
              child: ScaleTransition(
                  scale: Tween(begin: 0.94, end: 1.0).animate(a), child: w),
            );
          }
          return FadeTransition(opacity: a, child: w);
        },
        child: KeyedSubtree(key: ValueKey(key), child: child),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Вспомогательное
// ─────────────────────────────────────────────────────────────

String fmtCallTime(Duration d) {
  final h = d.inHours, m = d.inMinutes % 60, s = d.inSeconds % 60;
  final ss = s.toString().padLeft(2, '0');
  if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
  return '${m.toString().padLeft(2, '0')}:$ss';
}

String _statusText(CallManager c) {
  switch (c.phase) {
    case CallPhase.outgoing:
      if (c.ringing) return 'Звонок…';
      if (c.peerOffline) return 'Ожидание ответа…';
      return c.video ? 'Видеовызов…' : 'Вызов…';
    case CallPhase.incoming:
      return c.video ? 'Входящий видеозвонок' : 'Входящий звонок';
    case CallPhase.connecting:
      return 'Соединение…';
    case CallPhase.active:
      return c.reconnecting ? 'Переподключение…' : fmtCallTime(c.elapsed.value);
    case CallPhase.ended:
      return _endText(c);
    case CallPhase.idle:
      return '';
  }
}

String _endText(CallManager c) {
  final dur = c.lastDuration.inSeconds > 0 ? ' · ${fmtCallTime(c.lastDuration)}' : '';
  switch (c.endReason) {
    case 'busy':
      return 'Линия занята';
    case 'declined':
      return 'Собеседник отклонил звонок';
    case 'declined_me':
      return 'Звонок отклонён';
    case 'missed':
      return c.outgoing ? 'Не отвечает' : 'Пропущенный звонок';
    case 'cancelled':
      return 'Звонок отменён';
    case 'failed':
      return 'Не удалось соединиться';
    case 'taken':
      return 'Отвечено на другом устройстве';
    case 'privacy':
    case 'error':
      return c.endMessage ?? 'Звонок не удался';
    default:
      return 'Звонок завершён$dur';
  }
}

/// Круглая «стеклянная» кнопка с подписью.
class _RoundBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final Color? color;
  final double size;
  const _RoundBtn(
      {required this.icon,
      required this.label,
      this.active = false,
      this.onTap,
      this.color,
      this.size = 58});
  @override
  State<_RoundBtn> createState() => _RoundBtnState();
}

class _RoundBtnState extends State<_RoundBtn> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final bg = widget.color ??
        (widget.active ? Colors.white : Colors.white.withValues(alpha: 0.16));
    final fg = widget.color != null
        ? Colors.white
        : (widget.active ? const Color(0xFF111318) : Colors.white);
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: SizedBox(
          width: widget.size + 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: _down ? 0.88 : 1,
                duration: const Duration(milliseconds: 120),
                child: ClipOval(
                  child: _Glass(sigma: 14, child: AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        transitionBuilder: (c, a) => ScaleTransition(
                            scale: a, child: FadeTransition(opacity: a, child: c)),
                        child: Icon(widget.icon,
                            key: ValueKey('${widget.icon.codePoint}${widget.active}'),
                            color: fg,
                            size: widget.size * 0.44),
                      ),
                    ),
                  ),
                ),
              ),
              if (widget.label.isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Маленькая круглая стеклянная кнопка без подписи (верхняя панель).
class _GlassIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _GlassIcon({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ClipOval(
          child: _Glass(sigma: 12, child: Container(
              width: 42,
              height: 42,
              color: Colors.white.withValues(alpha: 0.14),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
          ),
        ),
      );
}

/// Живой фон звонка: мягкие цветные пятна плавно плывут (цикл без рывков).
class _Backdrop extends StatefulWidget {
  final Color a;
  final Color b;
  const _Backdrop({required this.a, required this.b});
  @override
  State<_Backdrop> createState() => _BackdropState();
}

class _BackdropState extends State<_Backdrop> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 22));

  @override
  void initState() {
    super.initState();
    if (appState.motion && !diagFlag('NO_ANIM')) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(
          painter: _BlobPainter(_c, widget.a, widget.b),
          child: const SizedBox.expand(),
        ),
      );
}

class _BlobPainter extends CustomPainter {
  final Animation<double> t;
  final Color a;
  final Color b;
  _BlobPainter(this.t, this.a, this.b) : super(repaint: t);

  // градиенты создаём один раз на размер окна, а каждый кадр только сдвигаем —
  // меньше работы и никакого мусора на 144 Гц
  Size? _size;
  final List<Paint> _blobs = [];
  final List<double> _radii = [];
  Paint? _shade;
  static final Paint _bg = Paint()..color = const Color(0xFF090B12);

  void _prepare(Size size) {
    if (_size == size && _shade != null) return;
    _size = size;
    _blobs.clear();
    _radii.clear();
    final colors = [a, b, Color.lerp(a, b, 0.5)!];
    const rs = [0.75, 0.8, 0.7];
    for (var i = 0; i < 3; i++) {
      final radius = size.longestSide * rs[i] * 0.62;
      _radii.add(radius);
      _blobs.add(Paint()
        ..shader = RadialGradient(colors: [
          colors[i].withValues(alpha: 0.55),
          colors[i].withValues(alpha: 0.0),
        ]).createShader(Rect.fromCircle(center: Offset.zero, radius: radius)));
    }
    // лёгкое затемнение сверху и снизу — чтобы текст и кнопки читались
    _shade = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0x66000000), Color(0x00000000), Color(0x00000000), Color(0x88000000)],
        stops: [0, 0.25, 0.6, 1],
      ).createShader(Offset.zero & size);
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, _bg);
    _prepare(size);
    final p = t.value * 2 * math.pi;
    final centers = [
      (0.30 + 0.18 * math.sin(p), 0.28 + 0.12 * math.cos(p)),
      (0.72 + 0.16 * math.cos(p * 2), 0.62 + 0.14 * math.sin(p)),
      (0.5 + 0.22 * math.sin(p * 3 + 1), 0.95 + 0.06 * math.cos(p * 2)),
    ];
    for (var i = 0; i < 3; i++) {
      final (x, y) = centers[i];
      canvas.save();
      canvas.translate(size.width * x, size.height * y);
      canvas.drawCircle(Offset.zero, _radii[i], _blobs[i]);
      canvas.restore();
    }
    canvas.drawRect(Offset.zero & size, _shade!);
  }

  @override
  bool shouldRepaint(covariant _BlobPainter old) => old.a != a || old.b != b;
}

/// Аватар с волнами: пока звоним — расходящиеся круги, в разговоре — «дышит» от голоса.
class _PulseAvatar extends StatefulWidget {
  final double size;
  final bool waiting;
  const _PulseAvatar({this.size = 136, required this.waiting});
  @override
  State<_PulseAvatar> createState() => _PulseAvatarState();
}

class _PulseAvatarState extends State<_PulseAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (appState.motion && !diagFlag('NO_ANIM')) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = calls;
    final s = widget.size;
    final avatar = Avatar(name: c.peerName, url: c.peerAvatar, size: s);
    return SizedBox(
      width: s * 1.9,
      height: s * 1.9,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (widget.waiting)
            AnimatedBuilder(
              animation: _c,
              builder: (_, _) => Stack(
                alignment: Alignment.center,
                children: [
                  for (var i = 0; i < 3; i++)
                    Builder(builder: (_) {
                      final v = (_c.value + i / 3) % 1.0;
                      return Container(
                        width: s * (1 + v * 0.85),
                        height: s * (1 + v * 0.85),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.22 * (1 - v)), width: 2),
                          color: Colors.white.withValues(alpha: 0.05 * (1 - v)),
                        ),
                      );
                    }),
                ],
              ),
            )
          else
            Positioned.fill(
              child: _Smoothed(
                level: c.peerLevel,
                painter: (v) => _GlowPainter(v,
                    size: s, base: 1.06, spread: 0.42, glow: appState.accent),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 24),
              ],
            ),
            child: avatar,
          ),
        ],
      ),
    );
  }
}

/// Полоски качества связи.
class _QualityBars extends StatelessWidget {
  final int q;
  final bool relayed;
  const _QualityBars({required this.q, required this.relayed});
  @override
  Widget build(BuildContext context) {
    final color = q >= 3 ? const Color(0xFF4ADE80) : (q == 2 ? kWarning : kDanger);
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var i = 1; i <= 3; i++)
            Container(
              width: 4,
              height: 5.0 + i * 4,
              margin: const EdgeInsets.only(right: 2.5, top: 2),
              decoration: BoxDecoration(
                color: i <= q ? color : Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          if (relayed) ...[
            const SizedBox(width: 4),
            const Icon(AppIcons.database, size: 14, color: Colors.white60),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Экран звонка
// ─────────────────────────────────────────────────────────────

const List<String> _kCallReactions = ['❤️', '😂', '👍', '🔥', '😮', '👏', '🎉', '😢'];
const List<String> _kQuickReplies = [
  'Не могу говорить, напишу позже',
  'Перезвоню через пару минут',
  'Я в дороге, позже наберу 🚗',
  'Что-то срочное? Напиши',
];

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  bool _controls = true;
  bool _swap = false;
  bool _reactionsOpen = false;
  bool _keyOpen = false;
  bool _repliesOpen = false;
  List<MediaDeviceInfo>? _outputs;
  // компьютер: устройства и выбор экрана для демонстрации
  bool _devicesOpen = false;
  List<MediaDeviceInfo> _mics = const [], _outs = const [], _cams = const [];
  List<DesktopCapturerSource>? _sources;
  Offset? _previewPos; // левый верхний угол своего видео
  bool _dragging = false;
  Timer? _hideTimer;
  Timer? _hintTimer;
  // фокус для горячих клавиш: забираем его у поля ввода чата
  final FocusNode _keys = FocusNode(debugLabel: 'call-keys');

  CallManager get c => calls;

  @override
  void initState() {
    super.initState();
    c.lastHint.addListener(_onHint);
    c.addListener(_onCall);
    _armHide();
    if (desktopUx) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keys.requestFocus();
      });
    }
  }

  void _onCall() {
    if (!mounted) return;
    // видео пропало — панель управления снова видна
    if (!c.showsVideo && !_controls) _controls = true;
    setState(() {});
  }

  @override
  void dispose() {
    c.removeListener(_onCall);
    c.lastHint.removeListener(_onHint);
    _hideTimer?.cancel();
    _hintTimer?.cancel();
    _keys.dispose();
    super.dispose();
  }

  void _onHint() {
    _hintTimer?.cancel();
    if (c.lastHint.value != null) {
      _hintTimer = Timer(const Duration(milliseconds: 2600), () => c.lastHint.value = null);
    }
  }

  void _armHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      if (c.phase == CallPhase.active && c.showsVideo && !_anyPanel) {
        setState(() => _controls = false);
      }
    });
  }

  bool get _anyPanel =>
      _reactionsOpen ||
      _keyOpen ||
      _repliesOpen ||
      _outputs != null ||
      _devicesOpen ||
      _sources != null;

  void _touch() {
    if (!_controls) setState(() => _controls = true);
    _armHide();
  }

  void _closePanels() {
    setState(() {
      _reactionsOpen = false;
      _keyOpen = false;
      _repliesOpen = false;
      _outputs = null;
      _devicesOpen = false;
      _sources = null;
    });
  }

  Future<void> _openDevices() async {
    _touch();
    if (_devicesOpen) {
      setState(() => _devicesOpen = false);
      return;
    }
    final r = await Future.wait(
        [c.devices('audioinput'), c.devices('audiooutput'), c.devices('videoinput')]);
    if (!mounted) return;
    setState(() {
      _mics = r[0];
      _outs = r[1];
      _cams = r[2];
      _devicesOpen = true;
      _sources = null;
      _reactionsOpen = false;
    });
  }

  Future<void> _openSources() async {
    _touch();
    if (c.screenOn) {
      c.toggleScreenShare();
      return;
    }
    if (_sources != null) {
      setState(() => _sources = null);
      return;
    }
    final list = await c.screenSources();
    if (!mounted) return;
    if (list.isEmpty) {
      c.lastHint.value = 'Не удалось получить список экранов';
      return;
    }
    setState(() {
      _sources = list;
      _devicesOpen = false;
      _reactionsOpen = false;
    });
  }

  /// Горячие клавиши на компьютере: M — микрофон, V — камера, Esc — свернуть.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (!desktopUx || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.physicalKey;
    if (c.phase == CallPhase.active || c.phase == CallPhase.connecting ||
        c.phase == CallPhase.outgoing) {
      if (k == PhysicalKeyboardKey.keyM) {
        c.toggleMic();
        return KeyEventResult.handled;
      }
      if (k == PhysicalKeyboardKey.keyV && c.canVideo) {
        c.toggleCamera();
        return KeyEventResult.handled;
      }
      if (k == PhysicalKeyboardKey.escape) {
        if (_anyPanel) {
          _closePanels();
        } else {
          c.minimize();
        }
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  Future<void> _speaker() async {
    _touch();
    final outs = await c.audioOutputs();
    if (!mounted) return;
    if (outs.length > 2) {
      setState(() {
        _outputs = outs;
        _reactionsOpen = false;
      });
    } else {
      c.toggleSpeaker();
    }
  }

  IconData _outputIcon(MediaDeviceInfo d) {
    final id = '${d.deviceId} ${d.label}'.toLowerCase();
    if (id.contains('bluetooth')) return AppIcons.bluetooth;
    if (id.contains('headset') || id.contains('wired') || id.contains('headphone')) {
      return AppIcons.headphones;
    }
    if (id.contains('speaker')) return AppIcons.speakerOn;
    return AppIcons.phoneInTalk;
  }

  String _outputName(MediaDeviceInfo d) {
    final id = '${d.deviceId} ${d.label}'.toLowerCase();
    if (id.contains('bluetooth')) return d.label.isNotEmpty ? d.label : 'Bluetooth';
    if (id.contains('headset') || id.contains('wired') || id.contains('headphone')) {
      return 'Наушники';
    }
    if (id.contains('speaker')) return 'Динамик';
    if (id.contains('earpiece')) return 'Телефон';
    return d.label.isNotEmpty ? d.label : 'Устройство';
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final remoteOn =
        (c.peerCam || c.peerScreen) && c.remoteVideoReady && c.remoteRenderer != null;
    final localOn = c.camOn && c.localRenderer != null && c.phase != CallPhase.ended;
    final bigLocal = (_swap && remoteOn && localOn) || (!remoteOn && localOn);
    final bigVideo = bigLocal || remoteOn;
    final smallOn = remoteOn && localOn;
    final base = avatarColor(c.peerName.isEmpty ? '?' : c.peerName);
    final waiting = c.phase == CallPhase.outgoing ||
        c.phase == CallPhase.incoming ||
        c.phase == CallPhase.connecting;
    final showControls = _controls || !bigVideo || c.phase != CallPhase.active;
    final mirrorLocal = c.frontCam && appState.callPref('mirror');

    final big = bigVideo && c.phase != CallPhase.ended
        ? (bigLocal
            ? RTCVideoView(c.localRenderer!,
                mirror: mirrorLocal,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
            : RTCVideoView(c.remoteRenderer!,
                objectFit: c.peerScreen
                    ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                    : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover))
        : null;

    // своё видео в уголке
    const pw = 112.0, ph = 168.0;
    final safeTop = mq.padding.top + 64;
    final safeBottom = size.height - mq.padding.bottom - 230;
    final defPos = Offset(size.width - pw - 14, safeTop);
    final pos = _previewPos ?? defPos;

    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (desktopUx) _keys.requestFocus();
            if (_anyPanel) {
              _closePanels();
              return;
            }
            if (c.phase == CallPhase.active && bigVideo) {
              setState(() => _controls = !_controls);
              if (_controls) _armHide();
            }
          },
          onVerticalDragEnd: (d) {
            if ((d.primaryVelocity ?? 0) > 700 &&
                c.phase != CallPhase.incoming &&
                c.phase != CallPhase.ended) {
              c.minimize();
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              // фон или видео
              _Backdrop(a: base, b: appState.accent),
              if (big != null)
                Positioned.fill(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: KeyedSubtree(key: ValueKey(bigLocal), child: big),
                  ),
                ),
              if (big != null)
                const Positioned.fill(
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0x88000000),
                            Color(0x00000000),
                            Color(0x00000000),
                            Color(0xAA000000)
                          ],
                          stops: [0, 0.22, 0.62, 1],
                        ),
                      ),
                    ),
                  ),
                ),

              // аватар и имя по центру (когда нет большого видео)
              if (big == null)
                Align(
                  alignment: const Alignment(0, -0.28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PulseAvatar(
                          waiting: waiting, size: math.min(136, size.width * 0.34)),
                      const SizedBox(height: 4),
                      _nameBlock(center: true),
                      if (c.phase == CallPhase.active && c.screenOn) ...[
                        const SizedBox(height: 18),
                        _screenBanner(),
                      ],
                    ],
                  ),
                ),

              // верхняя панель
              Positioned(
                left: 12,
                right: 12,
                top: mq.padding.top + 8,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 220),
                  opacity: showControls ? 1 : 0,
                  child: IgnorePointer(
                    ignoring: !showControls,
                    child: _topBar(),
                  ),
                ),
              ),

              // имя поверх видео
              if (big != null)
                Positioned(
                  left: 20,
                  right: 20,
                  top: mq.padding.top + 62,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: showControls ? 1 : 0,
                    child: _nameBlock(center: true, small: true),
                  ),
                ),

              // собеседник выключил микрофон
              if (c.phase == CallPhase.active && !c.peerMic)
                Positioned(
                  left: 0,
                  right: 0,
                  top: mq.padding.top + (big != null ? 122 : 70),
                  child: Center(
                    child: _chip(AppIcons.micOff,
                        '${c.peerName.split(' ').first} выключил(а) микрофон'),
                  ),
                ),

              // своё видео в уголке (тап — поменять местами, можно перетаскивать)
              if (smallOn && c.phase != CallPhase.ended)
                AnimatedPositioned(
                  duration: Duration(milliseconds: _dragging ? 0 : 260),
                  curve: Curves.easeOutCubic,
                  left: pos.dx,
                  top: pos.dy,
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _swap = !_swap);
                    },
                    onPanStart: (_) => setState(() => _dragging = true),
                    onPanUpdate: (d) => setState(() {
                      final p = (_previewPos ?? defPos) + d.delta;
                      final minY = mq.padding.top + 6;
                      _previewPos = Offset(p.dx.clamp(6.0, math.max(6.0, size.width - pw - 6)),
                          p.dy.clamp(minY, math.max(minY, size.height - ph - 6)));
                    }),
                    onPanEnd: (_) => setState(() {
                      _dragging = false;
                      final p = _previewPos ?? defPos;
                      final left = p.dx + pw / 2 < size.width / 2;
                      final top = p.dy + ph / 2 < size.height / 2;
                      _previewPos = Offset(left ? 14 : size.width - pw - 14,
                          top ? safeTop : math.max(safeTop, safeBottom - ph));
                    }),
                    child: Container(
                      width: pw,
                      height: ph,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.white24, width: 1.2),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4), blurRadius: 18),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(17),
                        child: bigLocal
                            ? RTCVideoView(c.remoteRenderer!,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                            : RTCVideoView(c.localRenderer!,
                                mirror: mirrorLocal,
                                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                      ),
                    ),
                  ),
                ),

              // «Вы показываете экран» (когда поверх — видео собеседника)
              if (big != null && c.screenOn)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: mq.padding.bottom + 250,
                  child: Center(child: _screenBanner()),
                ),

              // летающие реакции
              const Positioned.fill(child: IgnorePointer(child: _FlyingReactions())),

              // подсказка
              Positioned(
                left: 24,
                right: 24,
                bottom: mq.padding.bottom + 240,
                child: IgnorePointer(
                  child: ValueListenableBuilder<String?>(
                    valueListenable: c.lastHint,
                    builder: (_, h, _) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: h == null
                          ? const SizedBox.shrink()
                          : Center(key: ValueKey(h), child: _chip(AppIcons.info, h)),
                    ),
                  ),
                ),
              ),

              // ключ шифрования
              if (_keyOpen) _keyCard(mq),

              // нижняя панель
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: AnimatedSlide(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  offset: showControls ? Offset.zero : const Offset(0, 0.6),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: showControls ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !showControls,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(12, 0, 12, mq.padding.bottom + 22),
                        child: Center(
                          heightFactor: 1,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 640),
                            child: _bottom(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _chip(IconData icon, String text) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: _Glass(sigma: 14, child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            color: Colors.black.withValues(alpha: 0.35),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 16),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(text,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _screenBanner() => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _Glass(sigma: 16, child: Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            color: Colors.white.withValues(alpha: 0.14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.screenShare, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                const Text('Вы показываете экран',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: c.toggleScreenShare,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: kDanger, borderRadius: BorderRadius.circular(14)),
                    child: const Text('Остановить',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _nameBlock({required bool center, bool small = false}) {
    final status = c.phase == CallPhase.active && !c.reconnecting
        ? ValueListenableBuilder<Duration>(
            valueListenable: c.elapsed,
            builder: (_, d, _) => Text(fmtCallTime(d),
                style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: small ? 14 : 16,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [ui.FontFeature.tabularFigures()])),
          )
        : AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: Text(_statusText(c),
                key: ValueKey(_statusText(c)),
                textAlign: TextAlign.center,
                style: TextStyle(
                    color: c.phase == CallPhase.ended && c.endReason != 'ended'
                        ? const Color(0xFFFFB4B4)
                        : Colors.white.withValues(alpha: 0.85),
                    fontSize: small ? 14 : 16,
                    fontWeight: FontWeight.w600)),
          );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: center ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(c.peerName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
                fontSize: small ? 20 : 28,
                fontWeight: FontWeight.w800,
                shadows: const [Shadow(color: Colors.black38, blurRadius: 12)])),
        const SizedBox(height: 4),
        status,
      ],
    );
  }

  Widget _topBar() {
    final canMin = c.phase != CallPhase.incoming && c.phase != CallPhase.ended;
    return Row(
      children: [
        if (canMin)
          _GlassIcon(icon: AppIcons.chevronDown, onTap: c.minimize)
        else
          const SizedBox(width: 42),
        Expanded(
          child: Center(
            child: c.emojiKey.isNotEmpty && c.phase == CallPhase.active
                ? GestureDetector(
                    onTap: () => setState(() {
                      _keyOpen = !_keyOpen;
                      _reactionsOpen = false;
                      _outputs = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(AppIcons.lock, size: 14, color: Colors.white70),
                          const SizedBox(width: 6),
                          Text(c.emojiKey.join(' '), style: const TextStyle(fontSize: 17)),
                        ],
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(AppIcons.lock, size: 13, color: Colors.white54),
                      const SizedBox(width: 5),
                      Text('Сквозное шифрование',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.white.withValues(alpha: 0.6),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
          ),
        ),
        if (c.phase == CallPhase.active)
          _QualityBars(q: c.quality, relayed: c.relayed)
        else if (c.camOn && c.phase != CallPhase.ended)
          _GlassIcon(icon: AppIcons.cameraSwitch, onTap: c.switchCamera)
        else
          const SizedBox(width: 42),
      ],
    );
  }

  Widget _keyCard(MediaQueryData mq) => Positioned(
        left: 24,
        right: 24,
        top: mq.padding.top + 64,
        child: FadeSlideIn(
          dy: -8,
          child: GestureDetector(
            onTap: () => setState(() => _keyOpen = false),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: _Glass(sigma: 20, child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(c.emojiKey.join('  '), style: const TextStyle(fontSize: 40)),
                      const SizedBox(height: 12),
                      const Text('Звонок защищён сквозным шифрованием',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text(
                          'Если у ${c.peerName} на экране такие же эмодзи — никто, даже сервер Connecto, не может подслушать разговор.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13.5, color: Colors.white.withValues(alpha: 0.75))),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  // ── нижняя панель ──

  Widget _bottom() {
    switch (c.phase) {
      case CallPhase.incoming:
        return _incomingControls();
      case CallPhase.ended:
        return _endedControls();
      default:
        return _activeControls();
    }
  }

  Widget _incomingControls() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _repliesOpen
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: _glassPanel(Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final r in _kQuickReplies)
                        InkWell(
                          onTap: () => c.decline(reply: r),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                            child: Row(
                              children: [
                                const Icon(AppIcons.messageCircle,
                                    size: 18, color: Colors.white70),
                                const SizedBox(width: 12),
                                Expanded(
                                    child: Text(r,
                                        style: const TextStyle(
                                            fontSize: 14.5, fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )),
                )
              : const SizedBox(width: double.infinity),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _RoundBtn(
              icon: AppIcons.phoneEnd,
              label: 'Отклонить',
              color: kDanger,
              size: 70,
              onTap: () => c.decline(),
            ),
            _RoundBtn(
              icon: AppIcons.messageCircle,
              label: 'Ответить текстом',
              active: _repliesOpen,
              size: 50,
              onTap: () => setState(() => _repliesOpen = !_repliesOpen),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _AcceptButton(video: c.video, onTap: () => c.accept()),
                if (c.video)
                  GestureDetector(
                    onTap: () => c.accept(withVideo: false),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Без видео',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white.withValues(alpha: 0.8),
                              decoration: TextDecoration.underline,
                              decorationColor: Colors.white54)),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _endedControls() {
    final sticky = c.outgoing && kStickyEndReasons.contains(c.endReason);
    if (!sticky) return const SizedBox(height: 96);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundBtn(
            icon: AppIcons.x, label: 'Закрыть', size: 64, onTap: c.dismissEnded),
        if (c.endReason != 'privacy')
          _RoundBtn(
          icon: c.video ? AppIcons.video : AppIcons.phone,
          label: 'Перезвонить',
          color: const Color(0xFF22C55E),
          size: 64,
          onTap: () {
            c.dismissEnded();
            c.callBack();
          },
        ),
      ],
    );
  }

  Widget _glassPanel(Widget child) => ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: _Glass(sigma: 20, child: Container(
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.38),
            child: child,
          ),
        ),
      );

  Widget _deviceRow(IconData icon, String name, bool selected, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white70, size: 20),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w800 : FontWeight.w500))),
              if (selected) const Icon(AppIcons.check, color: Colors.white, size: 20),
            ],
          ),
        ),
      );

  Widget _devicesPanel() {
    Widget section(String title) => Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 2),
          child: Text(title,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.white.withValues(alpha: 0.6))),
        );
    String label(MediaDeviceInfo d, String fallback) => d.label.isNotEmpty ? d.label : fallback;
    return _glassPanel(ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 340),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            section('МИКРОФОН'),
            if (c.phase == CallPhase.active)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: 6,
                      child: _Smoothed(
                        level: c.myLevel,
                        painter: (v) => _BarPainter(v),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                        c.micOn
                            ? 'Скажи что-нибудь — полоска должна двигаться'
                            : 'Микрофон выключен',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55))),
                  ],
                ),
              ),
            if (_mics.isEmpty) _deviceRow(AppIcons.micOff, 'Не найден', false, () {}),
            for (var i = 0; i < _mics.length; i++)
              _deviceRow(AppIcons.mic, label(_mics[i], 'Микрофон ${i + 1}'),
                  c.micId == null ? i == 0 : c.micId == _mics[i].deviceId, () {
                c.selectMic(_mics[i].deviceId);
                setState(() {});
              }),
            section('ЗВУК'),
            for (var i = 0; i < _outs.length; i++)
              _deviceRow(AppIcons.speakerOn, label(_outs[i], 'Динамики ${i + 1}'),
                  c.outId == null ? i == 0 : c.outId == _outs[i].deviceId, () {
                c.selectSpeakerDevice(_outs[i].deviceId);
                setState(() {});
              }),
            section('КАМЕРА'),
            if (_cams.isEmpty) _deviceRow(AppIcons.videoOff, 'Не найдена', false, () {}),
            for (var i = 0; i < _cams.length; i++)
              _deviceRow(AppIcons.video, label(_cams[i], 'Камера ${i + 1}'),
                  c.camId == null ? i == 0 : c.camId == _cams[i].deviceId, () {
                c.selectCamera(_cams[i].deviceId);
                setState(() {});
              }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ));
  }

  Widget _sourcesPanel() {
    final list = _sources ?? const <DesktopCapturerSource>[];
    return _glassPanel(Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Text('Что показать собеседнику?',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 300),
            child: GridView.builder(
              shrinkWrap: true,
              itemCount: list.length,
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200, mainAxisSpacing: 10, crossAxisSpacing: 10,
                  childAspectRatio: 1.35),
              itemBuilder: (_, i) {
                final src = list[i];
                final thumb = src.thumbnail;
                return GestureDetector(
                  onTap: () {
                    setState(() => _sources = null);
                    c.toggleScreenShare(source: src);
                  },
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            color: Colors.black38,
                            child: thumb != null && thumb.isNotEmpty
                                ? Image.memory(thumb, fit: BoxFit.contain, gaplessPlayback: true)
                                : Icon(
                                    src.type == SourceType.Screen
                                        ? AppIcons.monitor
                                        : AppIcons.monitor,
                                    color: Colors.white54,
                                    size: 36),
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                          src.type == SourceType.Screen
                              ? 'Весь экран${list.where((x) => x.type == SourceType.Screen).length > 1 ? ' ${i + 1}' : ''}'
                              : src.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    ));
  }

  Widget _activeControls() {
    final active = c.phase == CallPhase.active;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: (_devicesOpen || _sources != null)
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _devicesOpen ? _devicesPanel() : _sourcesPanel(),
                )
              : const SizedBox(width: double.infinity),
        ),
        // выбор, куда выводить звук
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _outputs != null
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _glassPanel(Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final d in _outputs!)
                        InkWell(
                          onTap: () {
                            c.selectOutput(d);
                            setState(() => _outputs = null);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                            child: Row(
                              children: [
                                Icon(_outputIcon(d), color: Colors.white, size: 22),
                                const SizedBox(width: 14),
                                Expanded(
                                    child: Text(_outputName(d),
                                        style: const TextStyle(
                                            fontSize: 15, fontWeight: FontWeight.w600))),
                              ],
                            ),
                          ),
                        ),
                    ],
                  )),
                )
              : const SizedBox(width: double.infinity),
        ),
        // реакции
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _reactionsOpen && active
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: _Glass(sigma: 18, child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        color: Colors.black.withValues(alpha: 0.35),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            for (final e in _kCallReactions)
                              _ReactionKey(emoji: e, onTap: () {
                                c.sendReaction(e);
                                _armHide();
                              }),
                          ],
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            if (isDesktop)
              _RoundBtn(
                icon: AppIcons.tune,
                label: 'Устройства',
                active: _devicesOpen,
                onTap: _openDevices,
              )
            else if (isNativeMobile)
              _RoundBtn(
                icon: c.speakerOn ? AppIcons.speakerOn : AppIcons.phoneInTalk,
                label: c.speakerOn ? 'Динамик' : 'Телефон',
                active: c.speakerOn,
                onTap: _speaker,
              ),
            _RoundBtn(
              icon: c.camOn ? AppIcons.video : AppIcons.videoOff,
              label: 'Камера',
              active: c.camOn,
              onTap: c.canVideo
                  ? () {
                      _touch();
                      c.toggleCamera();
                    }
                  : null,
            ),
            Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                // кольцо вокруг кнопки «дышит», когда ты говоришь — видно, что микрофон работает
                if (active && c.micOn)
                  Positioned(
                    top: -10,
                    width: 78,
                    height: 78,
                    child: IgnorePointer(
                      child: _Smoothed(
                        level: c.myLevel,
                        painter: (v) => _RingPainter(v, radius: 29),
                      ),
                    ),
                  ),
                _RoundBtn(
                  icon: c.micOn ? AppIcons.mic : AppIcons.micOff,
                  label: c.micOn ? 'Микрофон' : 'Без звука',
                  active: !c.micOn,
                  onTap: () {
                    _touch();
                    c.toggleMic();
                  },
                ),
              ],
            ),
            _RoundBtn(
              icon: c.screenOn ? AppIcons.stopScreenShare : AppIcons.screenShare,
              label: 'Экран',
              active: c.screenOn || _sources != null,
              // в браузере на телефоне показывать экран нельзя (Safari не умеет)
              onTap: active && c.canVideo && !isWebMobile
                  ? () {
                      _touch();
                      if (isDesktop) {
                        _openSources();
                      } else {
                        c.toggleScreenShare();
                      }
                    }
                  : null,
            ),
            _RoundBtn(
              icon: AppIcons.smile,
              label: 'Реакция',
              active: _reactionsOpen,
              onTap: active
                  ? () {
                      _touch();
                      setState(() {
                        _reactionsOpen = !_reactionsOpen;
                        _outputs = null;
                        _keyOpen = false;
                      });
                    }
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 22),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (c.camOn && active) ...[
              _RoundBtn(
                  icon: AppIcons.cameraSwitch,
                  label: '',
                  size: 50,
                  onTap: () {
                    _touch();
                    c.switchCamera();
                  }),
              const SizedBox(width: 18),
            ],
            _EndButton(onTap: c.hangup),
            if (c.camOn && active) ...[
              const SizedBox(width: 18),
              _RoundBtn(
                  icon: AppIcons.pip,
                  label: '',
                  size: 50,
                  onTap: c.minimize),
            ],
          ],
        ),
      ],
    );
  }
}

class _ReactionKey extends StatefulWidget {
  final String emoji;
  final VoidCallback onTap;
  const _ReactionKey({required this.emoji, required this.onTap});
  @override
  State<_ReactionKey> createState() => _ReactionKeyState();
}

class _ReactionKeyState extends State<_ReactionKey> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 1.35 : 1,
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutBack,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text(widget.emoji, style: const TextStyle(fontSize: 28)),
          ),
        ),
      );
}

/// Красная кнопка «положить трубку»: при нажатии трубка поворачивается.
class _EndButton extends StatefulWidget {
  final VoidCallback onTap;
  const _EndButton({required this.onTap});
  @override
  State<_EndButton> createState() => _EndButtonState();
}

class _EndButtonState extends State<_EndButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => setState(() => _down = true),
        onTapUp: (_) => setState(() => _down = false),
        onTapCancel: () => setState(() => _down = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _down ? 0.9 : 1,
          duration: const Duration(milliseconds: 120),
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: kDanger,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: kDanger.withValues(alpha: 0.45), blurRadius: 22)],
            ),
            child: AnimatedRotation(
              turns: _down ? -0.1 : 0,
              duration: const Duration(milliseconds: 160),
              child: const Icon(AppIcons.phoneEnd, color: Colors.white, size: 34),
            ),
          ),
        ),
      );
}

/// Зелёная кнопка «ответить»: покачивается и пускает волны.
class _AcceptButton extends StatefulWidget {
  final bool video;
  final VoidCallback onTap;
  const _AcceptButton({required this.video, required this.onTap});
  @override
  State<_AcceptButton> createState() => _AcceptButtonState();
}

class _AcceptButtonState extends State<_AcceptButton> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _down = false;

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
    const green = Color(0xFF22C55E);
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: SizedBox(
        width: 88,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 88,
              height: 88,
              child: AnimatedBuilder(
                animation: _c,
                builder: (_, _) {
                  final v = _c.value;
                  // первые 40% цикла — покачивание трубки, дальше пауза
                  final shake = v < 0.4 ? math.sin(v / 0.4 * math.pi * 6) * 0.07 : 0.0;
                  return Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 70 + 18 * v,
                        height: 70 + 18 * v,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: green.withValues(alpha: 0.35 * (1 - v)),
                        ),
                      ),
                      AnimatedScale(
                        scale: _down ? 0.9 : 1,
                        duration: const Duration(milliseconds: 120),
                        child: Container(
                          width: 70,
                          height: 70,
                          decoration: BoxDecoration(
                            color: green,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(color: green.withValues(alpha: 0.5), blurRadius: 22),
                            ],
                          ),
                          child: Transform.rotate(
                            angle: shake * math.pi,
                            child: Icon(
                                widget.video ? AppIcons.video : AppIcons.phone,
                                color: Colors.white,
                                size: 32),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 0),
            const Text('Ответить',
                style: TextStyle(
                    color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Летящие реакции
// ─────────────────────────────────────────────────────────────

class _Flying {
  final String emoji;
  final bool mine;
  final Duration start;
  final double x; // 0..1
  final double wobble;
  final double scale;
  _Flying(this.emoji, this.mine, this.start, this.x, this.wobble, this.scale);
}

class _FlyingReactions extends StatefulWidget {
  const _FlyingReactions();
  @override
  State<_FlyingReactions> createState() => _FlyingReactionsState();
}

class _FlyingReactionsState extends State<_FlyingReactions> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final List<_Flying> _items = [];
  Duration _now = Duration.zero;
  StreamSubscription<CallReaction>? _sub;
  final _rnd = math.Random();
  static const _life = Duration(milliseconds: 2800);

  @override
  void initState() {
    super.initState();
    _sub = calls.reactions.stream.listen(_add);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  void _add(CallReaction r) {
    // «салют»: одна реакция — несколько эмодзи
    for (var i = 0; i < 5; i++) {
      final base = r.mine ? 0.72 : 0.28;
      _items.add(_Flying(
        r.emoji,
        r.mine,
        _now + Duration(milliseconds: i * 110),
        (base + (_rnd.nextDouble() - 0.5) * 0.3).clamp(0.08, 0.92),
        (_rnd.nextDouble() - 0.5) * 60,
        0.8 + _rnd.nextDouble() * 0.7,
      ));
    }
    if (!_ticker.isActive) _ticker.start();
  }

  void _tick(Duration d) {
    _now = d;
    _items.removeWhere((e) => d - e.start > _life);
    if (_items.isEmpty) {
      _ticker.stop();
      _now = Duration.zero;
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(builder: (_, box) {
      return Stack(
        children: [
          for (final e in _items)
            Builder(builder: (_) {
              final t = ((_now - e.start).inMilliseconds / _life.inMilliseconds)
                  .clamp(0.0, 1.0);
              if (_now < e.start) return const SizedBox.shrink();
              final y = box.maxHeight * (0.82 - 0.7 * Curves.easeOut.transform(t));
              final x = box.maxWidth * e.x + math.sin(t * math.pi * 2) * e.wobble;
              final s = e.scale * (t < 0.15 ? Curves.easeOutBack.transform(t / 0.15) : 1.0);
              final o = t > 0.7 ? (1 - (t - 0.7) / 0.3) : 1.0;
              return Positioned(
                left: x - 22,
                top: y - 22,
                child: Opacity(
                  opacity: o.clamp(0.0, 1.0),
                  child: Transform.scale(
                    scale: s,
                    child: Text(e.emoji, style: const TextStyle(fontSize: 40)),
                  ),
                ),
              );
            }),
        ],
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────
// Свёрнутый звонок
// ─────────────────────────────────────────────────────────────

class _MiniCall extends StatefulWidget {
  const _MiniCall();
  @override
  State<_MiniCall> createState() => _MiniCallState();
}

class _MiniCallState extends State<_MiniCall> {
  static Offset? _pos; // запоминаем, куда человек перетащил окошко
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    calls.addListener(_onCall);
  }

  @override
  void dispose() {
    calls.removeListener(_onCall);
    super.dispose();
  }

  void _onCall() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = calls;
    final mq = MediaQuery.of(context);
    final size = mq.size;
    final remoteOn =
        (c.peerCam || c.peerScreen) && c.remoteVideoReady && c.remoteRenderer != null;
    final localOn = c.camOn && c.localRenderer != null;
    final videoMode = remoteOn || localOn;
    final w = videoMode ? 112.0 : 82.0;
    final h = videoMode ? 168.0 : 104.0;
    final def = Offset(size.width - w - 12, mq.padding.top + 70);
    var pos = _pos ?? def;
    final minY = mq.padding.top + 6;
    pos = Offset(pos.dx.clamp(6.0, math.max(6.0, size.width - w - 6)),
        pos.dy.clamp(minY, math.max(minY, size.height - h - mq.padding.bottom - 6)));

    final Widget body = videoMode
        ? ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Colors.black),
                remoteOn
                    ? RTCVideoView(c.remoteRenderer!,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                    : RTCVideoView(c.localRenderer!,
                        mirror: c.frontCam && appState.callPref('mirror'),
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black54],
                      ),
                    ),
                    child: _miniStatus(c, 12),
                  ),
                ),
                if (!c.micOn)
                  const Positioned(
                    right: 6,
                    top: 6,
                    child: Icon(AppIcons.micOff, color: Colors.white, size: 16),
                  ),
              ],
            ),
          )
        : Column(
            children: [
              SizedBox(
                width: 70,
                height: 70,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned.fill(
                      child: _Smoothed(
                        level: c.peerLevel,
                        painter: (v) => _GlowPainter(v,
                            size: 60,
                            base: 1.0,
                            spread: 1 / 6,
                            fill: const Color(0xFF22C55E),
                            fillAlpha: 0.35,
                            fillAlphaK: 0),
                      ),
                    ),
                    Avatar(name: c.peerName, url: c.peerAvatar, size: 56),
                    if (!c.micOn)
                      Positioned(
                        right: 2,
                        bottom: 2,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration:
                              const BoxDecoration(color: kDanger, shape: BoxShape.circle),
                          child: const Icon(AppIcons.micOff, color: Colors.white, size: 12),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF22C55E),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _miniStatus(c, 11.5),
              ),
            ],
          );

    return Stack(
      children: [
        AnimatedPositioned(
          duration: Duration(milliseconds: _dragging ? 0 : 280),
          curve: Curves.easeOutCubic,
          left: pos.dx,
          top: pos.dy,
          child: GestureDetector(
            onTap: c.expand,
            onPanStart: (_) => setState(() => _dragging = true),
            onPanUpdate: (d) => setState(() => _pos = (_pos ?? def) + d.delta),
            onPanEnd: (_) => setState(() {
              _dragging = false;
              final p = _pos ?? def;
              final left = p.dx + w / 2 < size.width / 2;
              _pos = Offset(left ? 12 : size.width - w - 12, p.dy);
            }),
            child: Container(
              width: w,
              height: h,
              decoration: videoMode
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 18),
                      ],
                    )
                  : null,
              child: body,
            ),
          ),
        ),
      ],
    );
  }

  Widget _miniStatus(CallManager c, double fs) {
    final style = TextStyle(
        color: Colors.white,
        fontSize: fs,
        fontWeight: FontWeight.w700,
        fontFeatures: const [ui.FontFeature.tabularFigures()]);
    if (c.phase == CallPhase.active && !c.reconnecting) {
      return ValueListenableBuilder<Duration>(
        valueListenable: c.elapsed,
        builder: (_, d, _) =>
            Text(fmtCallTime(d), textAlign: TextAlign.center, maxLines: 1, style: style),
      );
    }
    return Text(
      c.phase == CallPhase.active ? 'Связь…' : (c.phase == CallPhase.outgoing ? 'Вызов…' : '…'),
      textAlign: TextAlign.center,
      maxLines: 1,
      style: style,
    );
  }
}

/// Картинка в картинке (Android свернул приложение в маленькое окошко).
class _PipView extends StatelessWidget {
  const _PipView();
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: calls,
        builder: (context, _) => _build(),
      );

  Widget _build() {
    final c = calls;
    final remoteOn =
        (c.peerCam || c.peerScreen) && c.remoteVideoReady && c.remoteRenderer != null;
    final localOn = c.camOn && c.localRenderer != null;
    return ColoredBox(
      color: Colors.black,
      child: remoteOn
          ? RTCVideoView(c.remoteRenderer!,
              objectFit: c.peerScreen
                  ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                  : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          : localOn
              ? RTCVideoView(c.localRenderer!,
                  mirror: c.frontCam && appState.callPref('mirror'),
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
              : Center(child: Avatar(name: c.peerName, url: c.peerAvatar, size: 72)),
    );
  }
}

/// Стекло: на телефоне — с размытием фона, на компьютере — без него.
/// Размытие поверх живого фона пересчитывается каждый кадр, и на мониторах
/// 144 Гц это съедает всю плавность, а на тёмном фоне разницы почти не видно.
class _Glass extends StatelessWidget {
  final double sigma;
  final Widget child;
  const _Glass({required this.sigma, required this.child});
  @override
  Widget build(BuildContext context) => isDesktop || isWeb
      ? child
      : BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma), child: child);
}

/// Плавный уровень громкости. Новые значения приходят ~10 раз в секунду, а рисуем
/// каждый кадр экрана (на 144 Гц — 144 раза в секунду): быстро «вверх» на звук,
/// мягко «вниз» в тишине. Когда всё стихло — таймер кадров останавливается.
class _Smoothed extends StatefulWidget {
  final ValueListenable<double> level;
  final CustomPainter Function(ValueListenable<double> v) painter;
  const _Smoothed({required this.level, required this.painter});
  @override
  State<_Smoothed> createState() => _SmoothedState();
}

class _SmoothedState extends State<_Smoothed> with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_frame);
  final ValueNotifier<double> _v = ValueNotifier(0);
  Duration _last = Duration.zero;
  final bool _noAnim = diagFlag('NO_ANIM');

  @override
  void initState() {
    super.initState();
    widget.level.addListener(_wake);
    _wake();
  }

  @override
  void didUpdateWidget(covariant _Smoothed old) {
    super.didUpdateWidget(old);
    if (old.level != widget.level) {
      old.level.removeListener(_wake);
      widget.level.addListener(_wake);
      _wake();
    }
  }

  @override
  void dispose() {
    widget.level.removeListener(_wake);
    _ticker.dispose();
    _v.dispose();
    super.dispose();
  }

  void _wake() {
    if (_noAnim) {
      _v.value = widget.level.value.clamp(0.0, 1.0);
      return;
    }
    if (!_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  void _frame(Duration t) {
    final dt = _last == Duration.zero ? 1 / 60 : (t - _last).inMicroseconds / 1e6;
    _last = t;
    final target = widget.level.value.clamp(0.0, 1.0);
    final cur = _v.value;
    final speed = target > cur ? 20.0 : 5.5;
    final next = cur + (target - cur) * (1 - math.exp(-speed * dt.clamp(0.0, 0.1)));
    if ((target - next).abs() < 0.002) {
      _v.value = target;
      _ticker.stop();
    } else {
      _v.value = next;
    }
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: CustomPaint(painter: widget.painter(_v), child: const SizedBox.expand()),
      );
}

/// Круг вокруг аватара собеседника: растёт и светится от его голоса.
class _GlowPainter extends CustomPainter {
  final ValueListenable<double> v;
  final double size;
  final double base;
  final double spread;
  final Color fill;
  final double fillAlpha;
  final double fillAlphaK;
  final Color? glow;
  _GlowPainter(this.v,
      {required this.size,
      required this.base,
      required this.spread,
      this.fill = Colors.white,
      this.fillAlpha = 0.06,
      this.fillAlphaK = 0.10,
      this.glow})
      : super(repaint: v);

  @override
  void paint(Canvas canvas, Size box) {
    final k = (v.value * 1.4).clamp(0.0, 1.0);
    final c = box.center(Offset.zero);
    final r = size * (base + k * spread) / 2;
    final g = glow;
    if (g != null) {
      // мягкое свечение градиентом — дешевле размытой тени
      final gr = math.min(box.shortestSide / 2, r + 18 + k * 26);
      if (gr > r + 1) {
        canvas.drawCircle(
          c,
          gr,
          Paint()
            ..shader = RadialGradient(
              colors: [g.withValues(alpha: 0.22 + k * 0.38), g.withValues(alpha: 0)],
              stops: [r / gr, 1],
            ).createShader(Rect.fromCircle(center: c, radius: gr)),
        );
      }
    }
    canvas.drawCircle(
        c, r, Paint()..color = fill.withValues(alpha: fillAlpha + k * fillAlphaK));
  }

  @override
  bool shouldRepaint(covariant _GlowPainter old) =>
      old.v != v || old.size != size || old.glow != glow || old.fill != fill;
}

/// Кольцо вокруг кнопки микрофона: видно, что тебя слышно.
class _RingPainter extends CustomPainter {
  final ValueListenable<double> v;
  final double radius;
  _RingPainter(this.v, {required this.radius}) : super(repaint: v);

  @override
  void paint(Canvas canvas, Size box) {
    final k = (v.value * 1.3).clamp(0.0, 1.0);
    if (k < 0.02) return;
    final c = box.center(Offset.zero);
    canvas.drawCircle(
      c,
      radius + 3 + k * 7,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0xFF22C55E).withValues(alpha: 0.35 + k * 0.6),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) => old.v != v || old.radius != radius;
}

/// Полоска громкости микрофона (проверка в «Устройствах»).
class _BarPainter extends CustomPainter {
  final ValueListenable<double> v;
  _BarPainter(this.v) : super(repaint: v);

  @override
  void paint(Canvas canvas, Size box) {
    final rr = Radius.circular(box.height / 2);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & box, rr),
        Paint()..color = Colors.white.withValues(alpha: 0.14));
    final w = box.width * v.value.clamp(0.0, 1.0);
    if (w <= 0.5) return;
    canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, box.height), rr),
        Paint()..color = const Color(0xFF22C55E));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.v != v;
}
