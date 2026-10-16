import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../app_state.dart';
import '../notifications.dart';
import '../platform.dart';
import '../realtime.dart';
import 'call_diag.dart';
import 'call_native.dart';
import 'win_audio.dart';

/// Этапы звонка.
/// outgoing — звоним (ждём ответа), incoming — звонят нам,
/// connecting — ответили, устанавливаем соединение, active — разговор,
/// ended — экран «звонок завершён» (пара секунд или с кнопкой «Перезвонить»).
enum CallPhase { idle, outgoing, incoming, connecting, active, ended }

/// Реакция, летящая по экрану звонка.
class CallReaction {
  final String emoji;
  final bool mine;
  final int id;
  const CallReaction(this.emoji, this.mine, this.id);
}

/// Эмодзи для «ключа шифрования»: у обоих собеседников должны совпасть.
const List<String> kCallKeyEmojis = [
  '🐶', '🐱', '🦊', '🐻', '🐼', '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔', '🐧', '🦉', '🐺',
  '🦄', '🐝', '🦋', '🐞', '🐢', '🐙', '🦀', '🐬', '🐳', '🦈', '🐘', '🦒', '🌵', '🌲', '🍀', '🍁',
  '🍄', '🌸', '🌻', '🌈', '⭐', '🔥', '❄️', '⚡', '🍎', '🍋', '🍉', '🍇', '🍓', '🍒', '🥑', '🌽',
  '🍕', '🍩', '🎈', '🎁', '🎸', '🎧', '🚀', '⚓', '🏀', '⚽', '🎲', '💎', '🔑', '🔔', '🎯', '🪐',
];

/// Звонки 1-на-1 поверх WebRTC. Одна штука на всё приложение.
///
/// * сигналинг — через наш WebSocket (call.invite / accept / ice …);
/// * звук и видео — напрямую между телефонами или через TURN, всегда
///   зашифрованы DTLS-SRTP; «ключ» из 4 эмодзи сверяется голосом;
/// * управление (микрофон, камера, экран, реакции) — по data channel.
class CallManager extends ChangeNotifier {
  CallManager._();
  static final CallManager instance = CallManager._();

  // ── состояние для интерфейса ──
  CallPhase phase = CallPhase.idle;
  String? callId;
  String? chatId;
  String peerId = '';
  String peerName = '';
  String? peerAvatar;
  bool video = false; // звонок начат как видеозвонок
  bool outgoing = false;
  bool ringing = false; // у собеседника звонит телефон
  bool peerOffline = false; // собеседник не в сети — ему ушёл пуш
  bool reconnecting = false;
  DateTime? connectedAt;
  String? endReason; // ended/cancelled/declined/busy/missed/failed/error/taken
  String? endMessage;
  Duration lastDuration = Duration.zero;

  bool micOn = true;
  bool camOn = false;
  bool screenOn = false;
  bool frontCam = true;
  bool speakerOn = false;
  bool canVideo = true; // есть видеоканал (можно включить камеру)

  bool peerMic = true;
  bool peerCam = false;
  bool peerScreen = false;
  bool remoteVideoReady = false;

  bool minimized = false;
  bool pip = false;
  List<String> emojiKey = const [];
  int quality = 3; // 1..3 — полоски связи
  bool relayed = false; // идём через сервер (TURN), а не напрямую
  int rttMs = 0;
  final ValueNotifier<double> peerLevel = ValueNotifier(0);
  /// Громкость моего микрофона 0..1 (анимация «я говорю» и проверка микрофона).
  final ValueNotifier<double> myLevel = ValueNotifier(0);
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);
  final StreamController<CallReaction> reactions = StreamController.broadcast();

  RTCVideoRenderer? localRenderer;
  RTCVideoRenderer? remoteRenderer;

  /// Браузер: звук собеседника играет только через <audio> на странице —
  /// отдельный невидимый рендер только для голоса (на телефоне/ПК звук идёт сам).
  RTCVideoRenderer? _webAudio;
  MediaStream? _remoteAudioWrap;

  bool get busy => phase != CallPhase.idle && phase != CallPhase.ended;
  bool get inCall => busy;
  bool get showsVideo =>
      camOn || screenOn || ((peerCam || peerScreen) && remoteVideoReady);

  // ── внутреннее ──
  RTCPeerConnection? _pc;
  MediaStream? _mic;
  MediaStream? _cam;
  MediaStream? _screen;
  MediaStream? _remoteWrap;
  RTCRtpSender? _videoSender;
  MediaStream? _remoteStream;
  MediaStreamTrack? _remoteVideoTrack;
  MediaStreamTrack? _remoteAudioTrack;
  Timer? _rebindTimer;
  int _rebinds = 0;
  RTCDataChannel? _dc;
  String? _remoteOffer;
  final List<Map<String, dynamic>> _pendingIce = [];
  // свои кандидаты, найденные до отправки приглашения (сервер ещё не знает звонок)
  final List<Map<String, dynamic>> _localIce = [];
  bool _signalReady = false;
  bool _remoteSet = false;
  List<Map<String, dynamic>> _iceServers = const [];
  bool _relay = false;
  Timer? _tick;
  Timer? _stats;
  Timer? _disconnectTimer;
  Timer? _endTimer;
  Timer? _connectTimer;
  int _restarts = 0;
  bool _camBeforeScreen = false;
  bool _bound = false;
  bool _foreground = true;
  int _seq = 0;
  num _lastLost = 0;
  num _lastRecv = 0;
  Future<void>? _statsRun; // запрос статистики «в полёте» — дождёмся перед закрытием
  Future<void>? _teardown; // прошлый звонок ещё закрывается — новый ждёт его
  int _statsTick = 0;
  (String chatId, String peerId, String name, String? avatar, bool video)? _last;
  AppLifecycleListener? _life;
  Timer? _reconnectTimer;
  DateTime _lastRestart = DateTime(2000);
  String? _lastOffer; // последнее предложение перезапуска (чтобы повторить, если потерялось)
  Map<String, dynamic>? _inviteMsg; // приглашение — повторим после переподключения сокета
  final List<Map<String, dynamic>> _myIce = [];
  String? _answerSdp; // наш ответ — повторим, если call.accept потерялся

  /// Навигатор приложения: чтобы «назад» при свёрнутом звонке не закрывало приложение.
  GlobalKey<NavigatorState>? navigatorKey;

  bool _alive(String? id) => id != null && callId == id && busy;

  bool _sig(Map<String, dynamic> m, {bool queue = true}) {
    m['device'] = appState.deviceId;
    return Realtime.send(m, queue: queue);
  }

  // ─────────────────────────────── подключение ───────────────────────────────

  /// Вызывается один раз при старте приложения.
  void attach() {
    if (_bound) return;
    _bound = true;
    Realtime.addListener(_onWs);
    Realtime.addReadyListener(_onWsReady);
    WidgetsBinding.instance.addObserver(_BackObserver());
    CallNative.bind();
    CallNative.onEndFromNotification = () {
      if (callId == null) {
        CallNative.service(false); // звонка уже нет, а уведомление осталось
      } else {
        hangup();
      }
    };
    CallNative.onPip = (on) {
      pip = on;
      notifyListeners();
    };
    Notif.onCallAction = _onNotifAction;
    if (isDesktop) {
      // журнал памяти и вне звонка: чтобы понять, где она растёт
      CallDiag.log('app start rss=${CallDiag.rssMb()}MB flags: '
          'NO_STATS=${diagFlag('NO_STATS')} NO_ANIM=${diagFlag('NO_ANIM')} '
          'NO_SOUNDS=${diagFlag('NO_SOUNDS')} IMPELLER=${Platform.environment['CONNECTO_IMPELLER'] ?? '-'}');
      var n = 0;
      Timer.periodic(const Duration(seconds: 1), (_) {
        // в звонке — каждую секунду, вне звонка — раз в 15 с
        if (busy || n++ % 15 == 0) {
          CallDiag.log('${busy ? 'call ${phase.name}' : 'idle'} rss=${CallDiag.rssMb()}MB');
        }
      });
    }
    _foreground = WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden;
    _life = AppLifecycleListener(onStateChange: (s) {
      // на компьютере «inactive» = окно не в фокусе: тогда нужно уведомление
      _foreground = s == AppLifecycleState.resumed ||
          (!isDesktop && !isWeb && s == AppLifecycleState.inactive);
      if (s == AppLifecycleState.resumed) {
        if (_servicePending && busy) _updateService();
        if (pip) {
          pip = false;
          notifyListeners();
        }
      }
    });
  }

  @override
  void dispose() {
    _life?.dispose();
    super.dispose();
  }

  // ─────────────────────────────── медиа ───────────────────────────────

  Map<String, dynamic> _audioConstraints() {
    if (isWeb) {
      // браузер понимает только стандартные ключи (старые mandatory/goog* Safari и Firefox молча игнорируют)
      return {
        'echoCancellation': appState.callPref('echo'),
        'noiseSuppression': appState.callPref('noise'),
        'autoGainControl': appState.callPref('agc'),
      };
    }
    String b(String k) => appState.callPref(k) ? 'true' : 'false';
    final mic = micId, out = outId;
    return {
      'mandatory': {
        'googEchoCancellation': b('echo'),
        'googNoiseSuppression': b('noise'),
        'googAutoGainControl': b('agc'),
        'googHighpassFilter': 'true',
      },
      // Windows: какой микрофон слушать (sourceId) и куда выводить звук (deviceId)
      'optional': [
        if (isWindows && mic != null) {'sourceId': mic},
      ],
      if (isWindows && out != null) 'deviceId': out,
    };
  }

  Map<String, dynamic> _videoConstraints() {
    final saver = appState.callPref('saver');
    final hd = appState.callPref('hd') && !saver;
    final camId = this.camId;
    return {
      // на компьютере камеру выбирают по sourceId (так читает нативная часть)
      if (camId != null) ...{
        'deviceId': camId,
        'optional': [
          {'sourceId': camId}
        ],
      } else
        'facingMode': frontCam ? 'user' : 'environment',
      'width': saver ? 480 : (hd ? 1280 : 640),
      'height': saver ? 360 : (hd ? 720 : 480),
      'frameRate': saver ? 15 : (hd ? 30 : 24),
    };
  }

  Future<void> _ensureRenderers() async {
    if (localRenderer == null) {
      final r = RTCVideoRenderer();
      await r.initialize();
      localRenderer = r;
    }
    if (remoteRenderer == null) {
      final r = RTCVideoRenderer();
      await r.initialize();
      r.onFirstFrameRendered = () {
        remoteVideoReady = true;
        // канал управления ещё не открылся, а видео уже идёт — показываем его
        if (!peerCam && !peerScreen && _dc?.state != RTCDataChannelState.RTCDataChannelOpen) {
          peerCam = true;
        }
        _updatePip();
        notifyListeners();
      };
      r.onResize = () => notifyListeners();
      remoteRenderer = r;
    }
    if (isWeb && _webAudio == null) {
      final a = RTCVideoRenderer();
      await a.initialize();
      _webAudio = a;
    }
  }

  /// Браузер: привязать голос собеседника к невидимому <audio>.
  Future<void> _bindWebAudio(RTCTrackEvent e) async {
    final id = callId;
    if (id == null || !busy) return;
    await _ensureRenderers();
    final r = _webAudio;
    if (r == null || callId != id || !busy) return;
    MediaStream? st = e.streams.isNotEmpty ? e.streams.first : null;
    if (st == null) {
      try {
        _remoteAudioWrap ??= await createLocalMediaStream('raudio_$id');
        await _remoteAudioWrap!.addTrack(e.track);
        st = _remoteAudioWrap;
      } catch (_) {}
    }
    if (st == null) return;
    try {
      r.srcObject = st;
      // свои («local») потоки рендер глушит сам — а это голос собеседника
      r.muted = false;
    } catch (_) {}
  }

  Future<void> _openMedia({required bool withVideo}) async {
    // прошлый звонок ещё освобождает микрофон/камеру — дожидаемся (иначе на Windows
    // новый звонок может остаться без выбранного микрофона, а на Android — без динамика)
    final prev = _teardown;
    if (prev != null) {
      try {
        await prev.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    await _ensureRenderers();
    await _prepareDesktopDevices();
    _mic = await navigator.mediaDevices
        .getUserMedia({'audio': _audioConstraints(), 'video': false});
    CallDiag.log('mic opened: tracks=${_mic?.getAudioTracks().length} '
        'constraints=${_audioConstraints()} rss=${CallDiag.rssMb()}MB');
    if (isWindows) {
      final out = outId;
      if (out != null) {
        try {
          await Helper.selectAudioOutput(out);
        } catch (_) {}
      }
    }
    micOn = true;
    camOn = false;
    if (withVideo) {
      try {
        _cam = await navigator.mediaDevices
            .getUserMedia({'audio': false, 'video': _videoConstraints()});
        camOn = _cam!.getVideoTracks().isNotEmpty;
      } catch (_) {
        _cam = null; // нет камеры или доступа — разговариваем без видео
      }
    }
    localRenderer?.srcObject = camOn ? _cam : null;
  }

  Future<void> _createPc() async {
    final id = callId;
    final pc = await createPeerConnection({
      'iceServers': _iceServers,
      'sdpSemantics': 'unified-plan',
      'iceTransportPolicy': _relay ? 'relay' : 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceCandidatePoolSize': 2,
    });
    if (!_alive(id)) {
      // пока создавали соединение, звонок уже закончился
      try {
        await pc.dispose();
      } catch (_) {}
      try {
        await pc.close();
      } catch (_) {}
      throw StateError('call gone');
    }
    pc.onIceCandidate = (c) {
      final cand = c.candidate;
      if (cand == null || cand.isEmpty || id == null || callId != id) return;
      final data = {
        'candidate': cand,
        'sdpMid': c.sdpMid,
        'sdpMLineIndex': c.sdpMLineIndex,
      };
      if (!_signalReady) {
        _localIce.add(data);
        return;
      }
      if (outgoing && phase == CallPhase.outgoing && _myIce.length < 40) _myIce.add(data);
      _sig({'type': 'call.ice', 'call_id': id, 'candidate': data});
    };
    pc.onConnectionState = (s) {
      if (callId == id) _onPcState(s);
    };
    pc.onTrack = (e) {
      if (callId == id) _onTrack(e);
    };
    pc.onDataChannel = (ch) {
      if (callId != id) return;
      _dc ??= ch;
      _wireDc(ch);
    };
    _pc = pc;
  }

  Future<void> _openDataChannel() async {
    final init = RTCDataChannelInit()
      ..ordered = true
      ..negotiated = true
      ..id = 5;
    final ch = await _pc!.createDataChannel('ctl', init);
    _dc = ch;
    _wireDc(ch);
  }

  Future<void> _attachTracksCaller() async {
    final pc = _pc!;
    final mic = _mic!;
    for (final t in mic.getAudioTracks()) {
      await pc.addTrack(t, mic);
    }
    final cam = _cam;
    final vt = (cam != null && cam.getVideoTracks().isNotEmpty) ? cam.getVideoTracks().first : null;
    final init = RTCRtpTransceiverInit(
        direction: TransceiverDirection.SendRecv, streams: [cam ?? mic]);
    // видеоканал есть всегда: без камеры — пустой, его «заполнят» при включении камеры/экрана
    final tr = vt != null
        ? await pc.addTransceiver(
            track: vt, kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: init)
        : await pc.addTransceiver(kind: RTCRtpMediaType.RTCRtpMediaTypeVideo, init: init);
    _videoSender = tr.sender;
    canVideo = true;
    await _preferVp8(tr);
  }

  /// Компьютер: просим VP8 для видео. Он есть везде и декодируется программно,
  /// без системных кодеков Windows (H.265 через Media Foundation бывает без
  /// расширения HEVC — тогда картинки нет вообще).
  Future<void> _preferVp8(RTCRtpTransceiver? tr) async {
    if (!isDesktop || tr == null) return;
    try {
      final caps = await getRtpReceiverCapabilities('video');
      final list = caps.codecs ?? const <RTCRtpCodecCapability>[];
      bool vp8(RTCRtpCodecCapability c) => c.mimeType.toLowerCase() == 'video/vp8';
      bool hevc(RTCRtpCodecCapability c) {
        final m = c.mimeType.toLowerCase();
        return m == 'video/h265' || m == 'video/hevc';
      }

      if (!list.any(vp8)) return;
      final ordered = [...list.where(vp8), ...list.where((c) => !vp8(c) && !hevc(c))];
      await tr.setCodecPreferences(ordered);
      CallDiag.log('codec prefs: ${ordered.map((c) => c.mimeType).toSet().join(',')}');
    } catch (e) {
      CallDiag.log('codec prefs error: $e');
    }
  }

  Future<void> _attachTracksCallee() async {
    final pc = _pc!;
    final mic = _mic!;
    for (final t in mic.getAudioTracks()) {
      await pc.addTrack(t, mic);
    }
    final cam = _cam;
    final vt = (cam != null && cam.getVideoTracks().isNotEmpty) ? cam.getVideoTracks().first : null;
    RTCRtpTransceiver? vtr;
    final all = await pc.getTransceivers();
    for (final t in all) {
      if (t.receiver.track?.kind == 'video') {
        vtr = t;
        break;
      }
    }
    // на Windows у приёмника может не быть трека в списке — видеоканал у нас всегда второй
    if (vtr == null && all.length >= 2) vtr = all[1];
    if (vt != null) {
      // addTrack занимает предложенный видеоканал — без повторного согласования
      _videoSender = await pc.addTrack(vt, cam!);
    } else if (vtr != null) {
      await vtr.setDirection(TransceiverDirection.SendRecv);
      _videoSender = vtr.sender;
    }
    canVideo = _videoSender != null;
    await _preferVp8(vtr);
  }

  Future<void> _onTrack(RTCTrackEvent e) async {
    if (e.track.kind == 'audio') {
      _remoteAudioTrack = e.track;
      if (isWeb) await _bindWebAudio(e);
      return;
    }
    if (e.track.kind != 'video') return;
    final id = callId;
    if (id == null || !busy) return;
    await _ensureRenderers();
    if (callId != id || !busy) return;
    MediaStream? st = e.streams.isNotEmpty ? e.streams.first : null;
    if (st == null) {
      try {
        _remoteWrap ??= await createLocalMediaStream('remote_${callId ?? 'x'}');
        await _remoteWrap!.addTrack(e.track);
        st = _remoteWrap;
      } catch (_) {}
    }
    _remoteStream = st;
    _remoteVideoTrack = e.track;
    await _bindRemote();
    notifyListeners();
  }

  /// Привязать видео собеседника к экрану. force — «переподключить» (если кадры не пошли).
  Future<void> _bindRemote({bool force = false}) async {
    final r = remoteRenderer, st = _remoteStream;
    if (r == null || st == null) return;
    final tid = _remoteVideoTrack?.id;
    try {
      if (force) r.srcObject = null;
      if (tid != null && tid.isNotEmpty) {
        await r.setSrcObject(stream: st, trackId: tid);
      } else {
        r.srcObject = st;
      }
    } catch (_) {
      try {
        r.srcObject = st;
      } catch (_) {}
    }
    // браузер: голос играет _webAudio, а у видео звук выключаем — иначе он звучит дважды
    if (isWeb) {
      try {
        r.muted = true;
      } catch (_) {}
    }
  }

  /// Собеседник включил камеру/экран, а кадров всё нет — пробуем переподключить картинку.
  void _watchRemoteVideo() {
    _rebindTimer?.cancel();
    if (!(peerCam || peerScreen) || remoteVideoReady || _rebinds >= 4) return;
    final id = callId;
    _rebindTimer = Timer(const Duration(milliseconds: 1600), () async {
      if (callId != id || !busy || remoteVideoReady || !(peerCam || peerScreen)) return;
      _rebinds++;
      await _bindRemote(force: true);
      _watchRemoteVideo();
    });
  }

  Future<void> _flushIce() async {
    final pc = _pc;
    if (pc == null || !_remoteSet) return;
    final list = List.of(_pendingIce);
    _pendingIce.clear();
    for (final c in list) {
      await _addIce(pc, c);
    }
  }

  Future<void> _addIce(RTCPeerConnection pc, Map<String, dynamic> c) async {
    try {
      await pc.addCandidate(RTCIceCandidate(
          c['candidate'] as String?, c['sdpMid'] as String?, (c['sdpMLineIndex'] as num?)?.toInt()));
    } catch (_) {}
  }

  // ─────────────────────────────── звоним ───────────────────────────────

  static String _newId() {
    const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    final r = math.Random.secure();
    return 'c${List.generate(22, (_) => abc[r.nextInt(abc.length)]).join()}';
  }

  /// Позвонить в личный чат.
  Future<void> start({
    required String chatId,
    required String peerId,
    required String name,
    String? avatar,
    required bool video,
  }) async {
    if (busy) {
      if (this.chatId == chatId) expand();
      return;
    }
    await _resetNow();
    final id = _newId();
    callId = id;
    this.chatId = chatId;
    this.peerId = peerId;
    peerName = name;
    peerAvatar = avatar;
    this.video = video;
    outgoing = true;
    frontCam = true;
    peerCam = false;
    speakerOn = video && appState.callPref('speaker');
    minimized = false;
    phase = CallPhase.outgoing;
    _last = (chatId, peerId, name, avatar, video);
    CallDiag.log('--- outgoing call video=$video rss=${CallDiag.rssMb()}MB');
    notifyListeners();
    HapticFeedback.mediumImpact();
    CallNative.keepScreenOn(true);
    try {
      final prepF = Api.callPrepare(chatId);
      // ошибку разберём ниже; тут — чтобы она не считалась «необработанной», если упадёт микрофон
      unawaited(prepF.then<void>((_) {}, onError: (_) {}));
      await _openMedia(withVideo: video);
      if (!_alive(id)) {
        await _dropLocalMedia();
        return;
      }
      notifyListeners();
      final prep = await prepF;
      if (!_alive(id)) {
        await _dropLocalMedia();
        return;
      }
      _iceServers = ((prep['ice_servers'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      _relay = prep['relay'] == true;
      final peer = (prep['peer'] as Map?)?.cast<String, dynamic>();
      if (peer != null) {
        peerName = (peer['name'] as String?) ?? peerName;
        peerAvatar = (peer['avatar_url'] as String?) ?? peerAvatar;
      }
      await _createPc();
      await _applyDesktopDevices();
      await _attachTracksCaller();
      await _openDataChannel();
      final offer = await _pc!.createOffer({});
      await _pc!.setLocalDescription(offer);
      if (!_alive(id) || phase != CallPhase.outgoing) return;
      _inviteMsg = {
        'type': 'call.invite',
        'call_id': id,
        'chat_id': chatId,
        'video': video,
        'sdp': offer.sdp,
      };
      _sig(Map.of(_inviteMsg!));
      _signalReady = true;
      for (final c in _localIce) {
        _myIce.add(c);
        _sig({'type': 'call.ice', 'call_id': id, 'candidate': c});
      }
      _localIce.clear();
      _applySpeaker();
      _updateService();
      _endTimer?.cancel();
      _endTimer = Timer(const Duration(seconds: 60), () {
        if (callId == id && phase == CallPhase.outgoing) {
          _sig({'type': 'call.end', 'call_id': id});
          _finish('missed');
        }
      });
      notifyListeners();
    } on ApiException catch (e) {
      if (_alive(id)) _finish(e.status == 403 ? 'privacy' : 'error', message: e.message);
    } catch (e) {
      CallDiag.log('start error: $e');
      if (_alive(id)) {
        _sig({'type': 'call.end', 'call_id': id}, queue: false);
        _finish('error', message: _mediaError(e));
      }
    }
  }

  /// Позвонить ещё раз тому же человеку (с экрана «не отвечает»).
  Future<void> callBack() async {
    final l = _last;
    if (l == null) return;
    await start(chatId: l.$1, peerId: l.$2, name: l.$3, avatar: l.$4, video: l.$5);
  }

  String _mediaError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('permission') || s.contains('notallowed') || s.contains('denied')) {
      return 'Нет доступа к микрофону. Разреши его в настройках телефона';
    }
    return 'Не удалось начать звонок';
  }

  // ─────────────────────────────── нам звонят ───────────────────────────────

  void _onIncoming(Map<String, dynamic> m) {
    final id = m['call_id'] as String?;
    if (id == null) return;
    if (id == callId) {
      // повтор после переподключения: кандидаты, пришедшие за это время, не теряем
      for (final e in (m['ice'] as List?) ?? const []) {
        _onRemoteIce((e as Map).cast<String, dynamic>());
      }
      return;
    }
    if (busy) {
      // уже разговариваем — у звонящего будет «линия занята»
      _sig({'type': 'call.end', 'call_id': id, 'reason': 'busy'});
      return;
    }
    _resetSync();
    final from = (m['from'] as Map?)?.cast<String, dynamic>() ?? const {};
    callId = id;
    chatId = m['chat_id'] as String?;
    peerId = (from['id'] as String?) ?? '';
    peerName = (from['name'] as String?) ?? 'Звонок';
    peerAvatar = from['avatar_url'] as String?;
    video = m['video'] == true;
    outgoing = false;
    peerCam = video;
    _remoteOffer = m['sdp'] as String?;
    _pendingIce
      ..clear()
      ..addAll(((m['ice'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()));
    _iceServers = ((m['ice_servers'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    _relay = m['relay'] == true;
    _signalReady = true;
    minimized = false;
    phase = CallPhase.incoming;
    _last = (chatId ?? '', peerId, peerName, peerAvatar, video);
    _sig({'type': 'call.ringing', 'call_id': id}, queue: false);
    CallNative.ring(true,
        sound: appState.callPref('ring'), vibrate: appState.callPref('vibrate'));
    CallNative.showOverLockScreen(true);
    CallNative.keepScreenOn(true);
    if (!_foreground || isAndroid) {
      Notif.showIncomingCall(callId: id, name: peerName, video: video, avatarUrl: peerAvatar);
    }
    bringAppToFront(); // компьютер: окно Connecto выходит наверх
    final left = (m['ring_left'] as num?)?.toInt() ?? 45;
    _endTimer?.cancel();
    _endTimer = Timer(Duration(seconds: left + 6), () {
      if (callId == id && phase == CallPhase.incoming) _finish('missed');
    });
    notifyListeners();
  }

  void _onNotifAction(String? action, String? payload) {
    if (payload == null || payload != callId) return;
    if (action == 'answer') {
      accept();
    } else if (action == 'decline') {
      decline();
    }
  }

  /// Ответить. withVideo — включить свою камеру (для видеозвонка по умолчанию да).
  Future<void> accept({bool? withVideo}) async {
    if (phase != CallPhase.incoming) return;
    final id = callId!;
    final offer = _remoteOffer;
    CallNative.ring(false);
    Notif.cancelCall();
    phase = CallPhase.connecting;
    final wantVideo = withVideo ?? video;
    CallDiag.log('--- accept call video=$wantVideo rss=${CallDiag.rssMb()}MB');
    speakerOn = wantVideo && appState.callPref('speaker');
    notifyListeners();
    try {
      if (offer == null) throw StateError('no offer');
      await _openMedia(withVideo: wantVideo);
      if (!_alive(id)) {
        await _dropLocalMedia();
        return;
      }
      await _createPc();
      await _applyDesktopDevices();
      await _pc!.setRemoteDescription(RTCSessionDescription(offer, 'offer'));
      _remoteSet = true;
      await _attachTracksCallee();
      await _openDataChannel();
      final answer = await _pc!.createAnswer({});
      await _pc!.setLocalDescription(answer);
      await _flushIce();
      if (!_alive(id)) return;
      _answerSdp = answer.sdp;
      _sig({'type': 'call.accept', 'call_id': id, 'sdp': answer.sdp});
      _applySpeaker();
      _updateService();
      _armConnectTimeout();
      notifyListeners();
    } catch (e) {
      CallDiag.log('accept error: $e');
      if (_alive(id)) {
        _sig({'type': 'call.end', 'call_id': id, 'reason': 'failed'});
        _finish('error', message: _mediaError(e));
      }
    }
  }

  /// Отклонить. reply — быстрый ответ текстом («Не могу говорить»).
  void decline({String? reply}) {
    if (phase != CallPhase.incoming) return;
    final id = callId;
    final cid = chatId;
    _sig({'type': 'call.decline', 'call_id': id});
    if (reply != null && reply.isNotEmpty && cid != null) {
      Api.sendMessage(cid, text: reply).catchError((_) => <String, dynamic>{});
    }
    _finish('declined_me');
  }

  /// Положить трубку (или отменить вызов).
  void hangup() {
    final id = callId;
    if (id == null) return;
    switch (phase) {
      case CallPhase.incoming:
        decline();
        break;
      case CallPhase.outgoing:
        _sig({'type': 'call.end', 'call_id': id});
        _finish('cancelled');
        break;
      case CallPhase.connecting:
      case CallPhase.active:
        _sig({'type': 'call.end', 'call_id': id});
        _finish('ended');
        break;
      case CallPhase.ended:
        dismissEnded();
        break;
      case CallPhase.idle:
        break;
    }
  }

  // ─────────────────────────────── события сервера ───────────────────────────────

  void _onWs(Map<String, dynamic> m) {
    final t = m['type'] as String?;
    if (t == null || !t.startsWith('call.')) return;
    final id = m['call_id'] as String?;
    switch (t) {
      case 'call.incoming':
        _onIncoming(m);
        break;
      case 'call.sent':
        if (id == callId && phase == CallPhase.outgoing) {
          peerOffline = m['online'] != true;
          notifyListeners();
        }
        break;
      case 'call.ringing':
        if (id == callId && phase == CallPhase.outgoing && !ringing) {
          ringing = true;
          peerOffline = false;
          CallNative.tone('ringback');
          notifyListeners();
        }
        break;
      case 'call.accepted':
        if (id == callId && outgoing && phase == CallPhase.outgoing) {
          _onAccepted(m['sdp'] as String?);
        }
        break;
      case 'call.taken':
        // ответили на другом телефоне этого аккаунта
        if (id == callId &&
            (phase == CallPhase.incoming ||
                (phase == CallPhase.connecting && !outgoing && m['device'] != appState.deviceId))) {
          _finish('taken');
        }
        break;
      case 'call.restart':
        if (id == callId && outgoing && phase == CallPhase.active) _restartIce(force: true);
        break;
      case 'call.ended':
        if (id == callId && busy) _onRemoteEnded(m['reason'] as String? ?? 'ended');
        break;
      case 'call.ice':
        if (id == callId && busy) {
          final c = (m['candidate'] as Map?)?.cast<String, dynamic>();
          if (c != null) _onRemoteIce(c);
        }
        break;
      case 'call.sdp':
        if (id == callId && busy) _onRemoteSdp(m);
        break;
      case 'call.error':
        if (id == callId && busy) {
          final reason = m['reason'] as String? ?? 'error';
          if (reason == 'gone') {
            _finish(phase == CallPhase.active ? 'ended' : 'failed');
          } else {
            _finish(reason == 'privacy' ? 'privacy' : 'error', message: m['message'] as String?);
          }
        }
        break;
    }
  }

  Future<void> _onAccepted(String? sdp) async {
    final pc = _pc;
    if (sdp == null || pc == null) return;
    CallNative.tone('none');
    ringing = false;
    phase = CallPhase.connecting;
    _endTimer?.cancel();
    notifyListeners();
    try {
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      _remoteSet = true;
      await _flushIce();
      _armConnectTimeout();
    } catch (_) {
      _sig({'type': 'call.end', 'call_id': callId, 'reason': 'failed'});
      _finish('failed');
    }
  }

  void _onRemoteEnded(String reason) {
    switch (reason) {
      case 'busy':
        _finish('busy');
        break;
      case 'declined':
        _finish(outgoing ? 'declined' : 'declined_me');
        break;
      case 'missed':
        _finish('missed');
        break;
      case 'cancelled':
        _finish('cancelled');
        break;
      case 'failed':
        _finish('failed');
        break;
      default:
        _finish('ended');
    }
  }

  Future<void> _onRemoteIce(Map<String, dynamic> c) async {
    final pc = _pc;
    if (pc == null || !_remoteSet) {
      if (_pendingIce.length < 80) _pendingIce.add(c);
      return;
    }
    await _addIce(pc, c);
  }

  /// Сокет переподключился: сверяем звонок с сервером и доотправляем потерянное.
  void _onWsReady() {
    final id = callId;
    if (busy && id != null) {
      if (outgoing && phase == CallPhase.outgoing) {
        if (!_signalReady) return;
        final inv = _inviteMsg;
        if (inv != null) _sig(Map.of(inv), queue: false); // сервер повтор проигнорирует
        for (final c in _myIce) {
          _sig({'type': 'call.ice', 'call_id': id, 'candidate': c}, queue: false);
        }
      }
      if (!outgoing && phase == CallPhase.connecting && _answerSdp != null) {
        _sig({'type': 'call.accept', 'call_id': id, 'sdp': _answerSdp}, queue: false);
      }
      _sig({'type': 'call.sync', 'call_id': id}, queue: false);
      if (phase == CallPhase.active && reconnecting) _kickReconnect();
    } else {
      _sig({'type': 'call.sync', 'call_id': null}, queue: false);
    }
  }

  Future<void> _onRemoteSdp(Map<String, dynamic> m) async {
    final pc = _pc;
    final sdp = m['sdp'] as String?;
    final type = m['sdp_type'] as String?;
    if (pc == null || sdp == null) return;
    try {
      if (type == 'offer') {
        // собеседник перезапустил соединение (сменил сеть)
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
        final answer = await pc.createAnswer({});
        await pc.setLocalDescription(answer);
        _sig(
            {'type': 'call.sdp', 'call_id': callId, 'sdp': answer.sdp, 'sdp_type': 'answer'});
      } else if (type == 'answer') {
        // устаревший ответ на старое предложение не применяем
        if (pc.signalingState != RTCSignalingState.RTCSignalingStateHaveLocalOffer) return;
        await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
      }
    } catch (_) {}
  }

  // ─────────────────────────────── соединение ───────────────────────────────

  void _armConnectTimeout() {
    _connectTimer?.cancel();
    final id = callId;
    _connectTimer = Timer(const Duration(seconds: 35), () {
      if (callId == id && phase == CallPhase.connecting) {
        _sig({'type': 'call.end', 'call_id': id, 'reason': 'failed'});
        _finish('failed');
      }
    });
  }

  void _onPcState(RTCPeerConnectionState s) {
    CallDiag.log('pc state: $s rss=${CallDiag.rssMb()}MB');
    switch (s) {
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        _disconnectTimer?.cancel();
        _disconnectTimer = null;
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _connectTimer?.cancel();
        final first = phase != CallPhase.active;
        reconnecting = false;
        _restarts = 0;
        if (first && busy) {
          phase = CallPhase.active;
          connectedAt ??= DateTime.now();
          ringing = false;
          CallNative.tone('connect');
          HapticFeedback.mediumImpact();
          _tick?.cancel();
          _tick = Timer.periodic(const Duration(seconds: 1), (_) {
            final c = connectedAt;
            if (c != null) elapsed.value = DateTime.now().difference(c);
          });
          _stats?.cancel();
          // часто — ради плавной анимации голоса; качество связи считаем реже
          if (!diagFlag('NO_STATS')) {
            _stats = Timer.periodic(
                Duration(milliseconds: isDesktop ? 150 : 250), (_) => _pollStats());
          }
          _watchRemoteVideo();
          _computeKey();
          _applySpeaker();
          _updateService();
          _updatePip();
          _sendState();
        }
        _updateProximity();
        notifyListeners();
        break;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        if (phase != CallPhase.active) return;
        reconnecting = true;
        notifyListeners();
        final failed = s == RTCPeerConnectionState.RTCPeerConnectionStateFailed;
        final rid = callId;
        // пока связи нет — каждые 5 с пробуем восстановить (сеть могла смениться у любого из двоих)
        _reconnectTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
          if (!reconnecting || !_alive(rid)) {
            _reconnectTimer?.cancel();
            _reconnectTimer = null;
            return;
          }
          _kickReconnect();
        });
        if (failed) {
          _kickReconnect();
        } else {
          Timer(const Duration(seconds: 2), () {
            if (reconnecting && _alive(rid)) _kickReconnect();
          });
        }
        if (_disconnectTimer == null) {
          final id = callId;
          _disconnectTimer = Timer(const Duration(seconds: 30), () {
            _disconnectTimer = null;
            if (callId == id && reconnecting && busy) {
              _sig({'type': 'call.end', 'call_id': id, 'reason': 'failed'});
              _finish('failed');
            }
          });
        }
        break;
      default:
        break;
    }
  }

  /// Восстановить связь: звонящий перезапускает ICE, собеседник просит его об этом.
  void _kickReconnect() {
    if (outgoing) {
      _restartIce();
    } else {
      _sig({'type': 'call.restart', 'call_id': callId}, queue: false);
    }
  }

  Future<void> _restartIce({bool force = false}) async {
    final pc = _pc;
    if (!outgoing || pc == null || _restarts >= 10) return;
    final now = DateTime.now();
    if (!force && now.difference(_lastRestart).inMilliseconds < 2500) return;
    _lastRestart = now;
    _restarts++;
    try {
      final last = _lastOffer;
      if (pc.signalingState == RTCSignalingState.RTCSignalingStateHaveLocalOffer && last != null) {
        // прошлое предложение ещё без ответа — повторяем его, а не плодим новые
        _sig({'type': 'call.sdp', 'call_id': callId, 'sdp': last, 'sdp_type': 'offer'},
            queue: false);
        return;
      }
      try {
        await pc.restartIce();
      } catch (_) {}
      final offer = await pc.createOffer(isWeb
          ? {'iceRestart': true}
          : {
              'mandatory': {'IceRestart': 'true'},
              'optional': [],
            });
      await pc.setLocalDescription(offer);
      _lastOffer = offer.sdp;
      _sig({'type': 'call.sdp', 'call_id': callId, 'sdp': offer.sdp, 'sdp_type': 'offer'});
    } catch (_) {}
  }

  static double? _num(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  void _pollStats() {
    if (_pc == null || _statsRun != null) return;
    final f = _collectStats();
    _statsRun = f;
    f.whenComplete(() {
      if (identical(_statsRun, f)) _statsRun = null;
    });
  }

  Future<void> _collectStats() async {
    final pc = _pc;
    if (pc == null) return;
    // Windows: полный отчёт — раз в 3 с (библиотека на каждом запросе теряет немного
    // памяти, и чем больше отчёт, тем больше); для анимации голоса — маленькие отчёты
    // только по своему и чужому звуку
    final full = (_statsTick++ % (isDesktop ? 20 : 4)) == 0;
    try {
      List<StatsReport> reports;
      if (isDesktop && !full) {
        final lt = _mic?.getAudioTracks().firstOrNull;
        final rt = _remoteAudioTrack;
        final parts = await Future.wait([
          if (lt != null) pc.getStats(lt),
          if (rt != null) pc.getStats(rt),
        ]);
        reports = [for (final l in parts) ...l];
      } else {
        reports = await pc.getStats();
      }
      if (!identical(pc, _pc)) return;
      final byId = full ? {for (final r in reports) r.id: r} : const <String, StatsReport>{};
      double? rtt;
      String? localId;
      num lost = 0, recv = 0;
      double? level, mine;
      for (final r in reports) {
        final v = r.values;
        final t = r.type;
        if (t == 'inbound-rtp') {
          final kind = (v['kind'] ?? v['mediaType'])?.toString();
          if (kind == 'audio') level = _num(v['audioLevel']) ?? level;
          if (full) {
            lost += _num(v['packetsLost']) ?? 0;
            recv += _num(v['packetsReceived']) ?? 0;
          }
        } else if (t == 'media-source') {
          final kind = (v['kind'] ?? v['mediaType'])?.toString();
          if (kind == 'audio') mine = _num(v['audioLevel']) ?? mine;
        } else if (full && t == 'candidate-pair') {
          final nominated = v['nominated'] == true || v['nominated'] == 'true';
          if (nominated && v['state'] == 'succeeded') {
            rtt = _num(v['currentRoundTripTime']) ?? rtt;
            localId = v['localCandidateId']?.toString();
          }
        }
      }
      if (level != null) peerLevel.value = _levelCurve(level);
      if (!micOn) {
        myLevel.value = 0;
      } else if (mine != null) {
        myLevel.value = _levelCurve(mine);
      }
      if (!full) return;
      if (isDesktop) _diagStats(reports, byId);
      if (localId != null) {
        relayed = byId[localId]?.values['candidateType'] == 'relay';
      }
      final dl = lost - _lastLost;
      final dr = recv - _lastRecv;
      _lastLost = lost;
      _lastRecv = recv;
      final lossPct = (dl > 0 && dl + dr > 0) ? dl / (dl + dr) * 100 : 0.0;
      rttMs = ((rtt ?? 0) * 1000).round();
      final q = (rttMs > 0 && rttMs < 280 && lossPct < 2)
          ? 3
          : ((rttMs < 600 && lossPct < 7) ? 2 : 1);
      if (q != quality) {
        quality = q;
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Раз в ~3 секунды пишем в журнал главное: уходит ли звук, какое видео, память.
  void _diagStats(List<StatsReport> reports, Map<String, StatsReport> byId) {
    try {
      String codec(Map v) => byId[v['codecId']?.toString()]?.values['mimeType']?.toString() ?? '?';
      final parts = <String>['rss=${CallDiag.rssMb()}MB', 'mic=$micOn cam=$camOn screen=$screenOn peerCam=$peerCam ready=$remoteVideoReady min=$minimized'];
      for (final r in reports) {
        final v = r.values;
        final kind = (v['kind'] ?? v['mediaType'])?.toString();
        switch (r.type) {
          case 'media-source':
            if (kind == 'audio') {
              parts.add('micSrc level=${v['audioLevel']} energy=${v['totalAudioEnergy']}');
            }
            break;
          case 'outbound-rtp':
            parts.add('out-$kind ${codec(v)} bytes=${v['bytesSent']} pkts=${v['packetsSent']}'
                '${kind == 'video' ? ' frames=${v['framesEncoded']} ${v['frameWidth']}x${v['frameHeight']}' : ''}');
            break;
          case 'inbound-rtp':
            parts.add('in-$kind ${codec(v)} bytes=${v['bytesReceived']} pkts=${v['packetsReceived']}'
                '${kind == 'video' ? ' decoded=${v['framesDecoded']} dropped=${v['framesDropped']} ${v['frameWidth']}x${v['frameHeight']}' : ' level=${v['audioLevel']}'}');
            break;
        }
      }
      parts.add('relay=$relayed rtt=${rttMs}ms q=$quality');
      CallDiag.log('stats: ${parts.join(' | ')}');
    } catch (_) {}
  }

  /// audioLevel (0..1, линейно) → «насколько громко» для анимации.
  static double _levelCurve(double v) => math.min(1.0, math.sqrt(math.max(0.0, v)) * 1.6);

  Future<void> _computeKey() async {
    try {
      final l = await _pc?.getLocalDescription();
      final r = await _pc?.getRemoteDescription();
      final fps = <String>[];
      for (final sdp in [l?.sdp, r?.sdp]) {
        if (sdp == null) continue;
        final m = RegExp(r'a=fingerprint:(\S+) (\S+)').firstMatch(sdp);
        if (m != null) fps.add('${m.group(1)} ${m.group(2)}'.toUpperCase());
      }
      if (fps.length < 2) return;
      fps.sort();
      final h = await Sha256().hash(utf8.encode(fps.join('|')));
      final b = h.bytes;
      emojiKey = [
        for (var i = 0; i < 4; i++)
          kCallKeyEmojis[((b[i * 2] << 8) | b[i * 2 + 1]) % kCallKeyEmojis.length]
      ];
      notifyListeners();
    } catch (_) {}
  }

  // ─────────────────────────────── data channel ───────────────────────────────

  void _wireDc(RTCDataChannel ch) {
    ch.onDataChannelState = (s) {
      if (s == RTCDataChannelState.RTCDataChannelOpen) _sendState();
    };
    ch.onMessage = (msg) {
      if (msg.isBinary) return;
      try {
        final d = (jsonDecode(msg.text) as Map).cast<String, dynamic>();
        switch (d['t']) {
          case 'state':
            final wasOff = !peerCam && !peerScreen;
            peerMic = d['mic'] != false;
            peerCam = d['cam'] == true;
            peerScreen = d['screen'] == true;
            if (wasOff && (peerCam || peerScreen)) _rebinds = 0;
            _watchRemoteVideo();
            _updateProximity();
            _updatePip();
            notifyListeners();
            break;
          case 'r':
            final e = d['e'];
            if (e is String && e.length <= 16) {
              reactions.add(CallReaction(e, false, ++_seq));
              HapticFeedback.lightImpact();
            }
            break;
        }
      } catch (_) {}
    };
  }

  void _dcSend(Map<String, dynamic> m) {
    final ch = _dc;
    if (ch == null || ch.state != RTCDataChannelState.RTCDataChannelOpen) return;
    try {
      ch.send(RTCDataChannelMessage(jsonEncode(m)));
    } catch (_) {}
  }

  void _sendState() =>
      _dcSend({'t': 'state', 'mic': micOn, 'cam': camOn || screenOn, 'screen': screenOn});

  void sendReaction(String emoji) {
    reactions.add(CallReaction(emoji, true, ++_seq));
    _dcSend({'t': 'r', 'e': emoji});
    HapticFeedback.selectionClick();
  }

  // ─────────────────────────────── кнопки ───────────────────────────────

  void toggleMic() {
    micOn = !micOn;
    if (!micOn) myLevel.value = 0;
    for (final t in _mic?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      t.enabled = micOn;
    }
    HapticFeedback.selectionClick();
    _sendState();
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    if (!canVideo || _videoSender == null) return;
    HapticFeedback.selectionClick();
    if (screenOn) await _stopScreen(restoreCamera: false);
    if (camOn) {
      await _cameraOff();
    } else {
      await _cameraOn();
    }
  }

  Future<void> _cameraOff() async {
    camOn = false;
    notifyListeners();
    try {
      await _videoSender?.replaceTrack(null);
    } catch (_) {}
    final cam = _cam;
    _cam = null;
    localRenderer?.srcObject = null;
    await _disposeStream(cam);
    _sendState();
    _updateService();
    _updateProximity();
    _updatePip();
  }

  Future<void> _cameraOn() async {
    try {
      final cam = await navigator.mediaDevices
          .getUserMedia({'audio': false, 'video': _videoConstraints()});
      final vt = cam.getVideoTracks().first;
      if (!busy) {
        await _disposeStream(cam);
        return;
      }
      await _videoSender?.replaceTrack(vt);
      _cam = cam;
      camOn = true;
      localRenderer?.srcObject = cam;
      if (!speakerOn && appState.callPref('speaker')) {
        speakerOn = true;
        _applySpeaker();
      }
      _sendState();
      _updateService();
      _updateProximity();
      _updatePip();
      notifyListeners();
    } catch (e) {
      lastHint.value = 'Нет доступа к камере';
    }
  }

  /// Короткая подсказка поверх экрана звонка («Нет доступа к камере» и т.п.).
  final ValueNotifier<String?> lastHint = ValueNotifier(null);

  Future<void> switchCamera() async {
    final t = _cam?.getVideoTracks().firstOrNull;
    if (t == null) return;
    HapticFeedback.selectionClick();
    if (isDesktop) {
      // у компьютера несколько веб-камер — переключаем по кругу
      final cams = await devices('videoinput');
      if (cams.length < 2) {
        lastHint.value = 'Другой камеры не найдено';
        return;
      }
      final i = cams.indexWhere((d) => d.deviceId == camId);
      await selectCamera(cams[(i + 1) % cams.length].deviceId);
      return;
    }
    if (isWeb) {
      await _webFlipCamera();
      return;
    }
    try {
      await Helper.switchCamera(t);
      frontCam = !frontCam;
    } catch (_) {}
    notifyListeners();
  }

  /// Браузер на телефоне: Helper.switchCamera там не работает — открываем другую
  /// камеру (facingMode) и подменяем трек без пересогласования.
  Future<void> _webFlipCamera() async {
    final old = _cam;
    if (old == null || !busy) return;
    final want = !frontCam;
    // телефон обычно не даёт открыть две камеры сразу — сначала отпускаем текущую
    _cam = null;
    localRenderer?.srcObject = null;
    await _disposeStream(old);
    MediaStream? cam;
    frontCam = want;
    try {
      cam = await navigator.mediaDevices
          .getUserMedia({'audio': false, 'video': _videoConstraints()});
    } catch (_) {
      frontCam = !want;
      lastHint.value = 'Другой камеры не найдено';
      try {
        cam = await navigator.mediaDevices
            .getUserMedia({'audio': false, 'video': _videoConstraints()});
      } catch (_) {}
    }
    final vt = cam?.getVideoTracks().firstOrNull;
    if (cam == null || vt == null || !busy) {
      await _disposeStream(cam);
      camOn = false;
      try {
        await _videoSender?.replaceTrack(null);
      } catch (_) {}
      _sendState();
      notifyListeners();
      return;
    }
    try {
      await _videoSender?.replaceTrack(vt);
    } catch (_) {}
    _cam = cam;
    localRenderer?.srcObject = cam;
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    HapticFeedback.selectionClick();
    await _applySpeaker();
    _updateProximity();
    notifyListeners();
  }

  Future<void> _applySpeaker() async {
    if (isDesktop) return; // на компьютере звук идёт в выбранные «Устройства»
    try {
      if (speakerOn) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      } else {
        await Helper.setSpeakerphoneOn(false);
      }
    } catch (_) {}
  }

  /// Куда выводить звук: динамик, трубка, Bluetooth, наушники.
  Future<List<MediaDeviceInfo>> audioOutputs() async {
    try {
      return await Helper.audiooutputs;
    } catch (_) {
      return const [];
    }
  }

  Future<void> selectOutput(MediaDeviceInfo d) async {
    try {
      await Helper.selectAudioOutput(d.deviceId);
      speakerOn = d.deviceId.toLowerCase().contains('speaker');
    } catch (_) {}
    _updateProximity();
    notifyListeners();
  }

  // ── компьютер: выбор устройств и того, что показывать ──

  /// Выбранные устройства (null — по умолчанию системы).
  String? micId;
  String? outId;
  String? camId;

  // что человек выбрал сам (запоминаем между звонками)
  static const _kMic = 'call_dev_mic', _kOut = 'call_dev_out', _kCam = 'call_dev_cam';
  String? _savedMic, _savedOut, _savedCam;
  bool _devLoaded = false;

  /// Компьютер: какие микрофон, динамики и камеру брать.
  /// Сначала — выбранные раньше, потом — «по умолчанию» в Windows, потом — первое
  /// не виртуальное устройство (иначе flutter_webrtc берёт просто первое в списке).
  Future<void> _prepareDesktopDevices() async {
    if (!isDesktop) return;
    try {
      if (!_devLoaded) {
        final p = await SharedPreferences.getInstance();
        _savedMic = p.getString(_kMic);
        _savedOut = p.getString(_kOut);
        _savedCam = p.getString(_kCam);
        _devLoaded = true;
      }
      final all = await navigator.mediaDevices.enumerateDevices();
      List<MediaDeviceInfo> of(String k) =>
          all.where((d) => d.kind == k && d.deviceId.isNotEmpty).toList();
      String? pick(List<MediaDeviceInfo> list, String? saved, String? sys) {
        if (list.isEmpty) return null;
        bool has(String? id) => id != null && list.any((d) => d.deviceId == id);
        if (has(saved)) return saved;
        if (has(sys)) return sys;
        for (final d in list) {
          if (!looksVirtual(d.label)) return d.deviceId;
        }
        return list.first.deviceId;
      }

      final sysMic = WinAudio.defaultId(capture: true);
      final sysOut = WinAudio.defaultId(capture: false);
      micId = pick(of('audioinput'), _savedMic, sysMic);
      outId = pick(of('audiooutput'), _savedOut, sysOut);
      camId = pick(of('videoinput'), _savedCam, null);
      for (final d in all) {
        CallDiag.log('device ${d.kind}: "${d.label}" id=${d.deviceId}');
      }
      CallDiag.log('windows default: mic=$sysMic out=$sysOut');
      CallDiag.log('chosen: mic=$micId out=$outId cam=$camId (saved mic=$_savedMic)');
    } catch (e) {
      CallDiag.log('devices error: $e');
    }
  }

  /// Windows: при создании первого соединения WebRTC сам переключает микрофон и
  /// динамики на «устройства связи по умолчанию» (и до этого момента список
  /// звуковых устройств вообще пуст). Поэтому выбираем их ещё раз — уже после
  /// создания соединения, до начала разговора.
  Future<void> _applyDesktopDevices() async {
    if (!isWindows) return;
    await _prepareDesktopDevices();
    final mic = micId, out = outId;
    if (mic != null) {
      try {
        await Helper.selectAudioInput(mic);
      } catch (e) {
        CallDiag.log('selectAudioInput error: $e');
      }
    }
    if (out != null) {
      try {
        await Helper.selectAudioOutput(out);
      } catch (e) {
        CallDiag.log('selectAudioOutput error: $e');
      }
    }
    CallDiag.log('devices applied after pc: mic=$mic out=$out');
  }

  Future<void> _saveDevice(String key, String id) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(key, id);
    } catch (_) {}
  }

  /// Микрофоны, динамики и камеры: kind = audioinput / audiooutput / videoinput.
  Future<List<MediaDeviceInfo>> devices(String kind) async {
    try {
      final all = await navigator.mediaDevices.enumerateDevices();
      return all.where((d) => d.kind == kind && d.deviceId.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> selectMic(String deviceId) async {
    micId = deviceId;
    _savedMic = deviceId;
    _saveDevice(_kMic, deviceId);
    try {
      // libwebrtc сам остановит запись, сменит устройство и запустит снова
      await Helper.selectAudioInput(deviceId);
    } catch (e) {
      CallDiag.log('selectMic error: $e');
      lastHint.value = 'Не удалось переключить микрофон';
    }
    notifyListeners();
  }

  Future<void> selectSpeakerDevice(String deviceId) async {
    outId = deviceId;
    _savedOut = deviceId;
    _saveDevice(_kOut, deviceId);
    try {
      await Helper.selectAudioOutput(deviceId);
    } catch (_) {
      lastHint.value = 'Не удалось переключить звук';
    }
    notifyListeners();
  }

  /// Другая камера: если видео уже идёт — подменяем его без перезвона.
  Future<void> selectCamera(String deviceId) async {
    camId = deviceId;
    _savedCam = deviceId;
    _saveDevice(_kCam, deviceId);
    if (camOn && !screenOn) {
      final old = _cam;
      try {
        final cam = await navigator.mediaDevices
            .getUserMedia({'audio': false, 'video': _videoConstraints()});
        final vt = cam.getVideoTracks().first;
        if (!busy) {
          await _disposeStream(cam);
          return;
        }
        await _videoSender?.replaceTrack(vt);
        _cam = cam;
        localRenderer?.srcObject = cam;
        await _disposeStream(old);
      } catch (_) {
        lastHint.value = 'Эта камера недоступна';
      }
    }
    notifyListeners();
  }

  /// Экраны и окна для демонстрации (с миниатюрами).
  Future<List<DesktopCapturerSource>> screenSources() async {
    try {
      return await desktopCapturer.getSources(
          types: [SourceType.Screen, SourceType.Window],
          thumbnailSize: ThumbnailSize(320, 180));
    } catch (_) {
      return const [];
    }
  }

  Future<void> toggleScreenShare({DesktopCapturerSource? source}) async {
    if (screenOn) {
      await _stopScreen();
      return;
    }
    if (_videoSender == null || phase != CallPhase.active) return;
    if (isDesktop) {
      if (source != null) await _startDesktopShare(source);
      return;
    }
    HapticFeedback.selectionClick();
    if (!isWeb) {
      // в браузере разрешение и выбор окна показывает сам getDisplayMedia
      bool ok;
      try {
        ok = await Helper.requestCapturePermission();
      } catch (_) {
        ok = false;
      }
      if (!ok || phase != CallPhase.active) return;
      // Android 14: сервис с типом «демонстрация экрана» — после разрешения, до захвата
      await CallNative.service(true,
          title: peerName,
          text: 'Демонстрация экрана',
          since: (connectedAt ?? DateTime.now()).millisecondsSinceEpoch,
          mic: true,
          camera: camOn,
          screen: true);
      await Future.delayed(const Duration(milliseconds: 350));
    }
    MediaStream? s;
    try {
      s = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'width': {'ideal': 1920},
          'height': {'ideal': 1080},
          'frameRate': {'ideal': 60.0},
        },
        'audio': false,
      });
      final t = s.getVideoTracks().first;
      if (phase != CallPhase.active || _videoSender == null) {
        await _disposeStream(s);
        return;
      }
      _camBeforeScreen = camOn;
      if (camOn) {
        final cam = _cam;
        _cam = null;
        camOn = false;
        localRenderer?.srcObject = null;
        await _disposeStream(cam);
      }
      await _videoSender!.replaceTrack(t);
      _screen = s;
      screenOn = true;
      t.onEnded = () {
        if (screenOn) _stopScreen();
      };
      _sendState();
      _updateService();
      _updateProximity();
      _updatePip();
      notifyListeners();
    } catch (_) {
      if (_screen != s) await _disposeStream(s);
      screenOn = false;
      if (busy) {
        _updateService();
        lastHint.value = 'Не удалось начать демонстрацию экрана';
      }
      notifyListeners();
    }
  }

  Future<void> _startDesktopShare(DesktopCapturerSource source) async {
    MediaStream? s;
    try {
      s = await navigator.mediaDevices.getDisplayMedia({
        'video': {
          'deviceId': {'exact': source.id},
          'mandatory': {
            'minWidth': 1920,
            'minHeight': 1080,
            'frameRate': appState.callPref('saver') ? 30.0 : 60.0,
          },
        },
        'audio': false,
      });
      final t = s.getVideoTracks().first;
      if (phase != CallPhase.active || _videoSender == null) {
        await _disposeStream(s);
        return;
      }
      _camBeforeScreen = camOn;
      if (camOn) {
        final cam = _cam;
        _cam = null;
        camOn = false;
        localRenderer?.srcObject = null;
        await _disposeStream(cam);
      }
      await _videoSender!.replaceTrack(t);
      _screen = s;
      screenOn = true;
      t.onEnded = () {
        if (screenOn) _stopScreen();
      };
      _sendState();
      notifyListeners();
    } catch (_) {
      if (_screen != s) await _disposeStream(s);
      screenOn = false;
      if (busy) lastHint.value = 'Не удалось начать демонстрацию экрана';
      notifyListeners();
    }
  }

  Future<void> _stopScreen({bool restoreCamera = true}) async {
    final s = _screen;
    _screen = null;
    if (!screenOn && s == null) return;
    screenOn = false;
    notifyListeners();
    try {
      await _videoSender?.replaceTrack(null);
    } catch (_) {}
    await _disposeStream(s);
    _updateService();
    if (restoreCamera && _camBeforeScreen && busy) {
      await _cameraOn();
    } else {
      _sendState();
    }
    _updatePip();
  }

  // ─────────────────────────────── окно ───────────────────────────────

  void minimize() {
    if (!busy) return;
    minimized = true;
    // ответили на заблокированном телефоне — дальше в приложение только после разблокировки
    CallNative.dismissKeyguard();
    notifyListeners();
  }

  /// Кнопка «назад»: полноэкранный звонок сворачивается; свёрнутый звонок на
  /// главном экране уводит приложение в фон, а не закрывает его (иначе звонок оборвётся).
  Future<bool> handleBack() async {
    if (phase == CallPhase.idle || pip) return false;
    if (!minimized) {
      if (phase == CallPhase.ended) {
        dismissEnded();
        return true;
      }
      if (phase == CallPhase.incoming) return true;
      minimize();
      return true;
    }
    final nav = navigatorKey?.currentState;
    if (nav != null && nav.canPop()) return false;
    if (busy) {
      CallNative.moveToBack();
      return true;
    }
    return false;
  }

  void expand() {
    minimized = false;
    notifyListeners();
  }

  // ─────────────────────────────── системное ───────────────────────────────

  bool _servicePending = false;

  void _updateService() {
    if (!busy || phase == CallPhase.incoming) return;
    if (!_foreground) {
      // Android не даёт запускать такой сервис из фона — запустим, когда вернёмся
      _servicePending = true;
      return;
    }
    _servicePending = false;
    CallNative.service(true,
        title: peerName,
        text: screenOn
            ? 'Демонстрация экрана'
            : (camOn || video ? 'Видеозвонок Connecto' : 'Звонок Connecto'),
        since: (connectedAt ?? DateTime.now()).millisecondsSinceEpoch,
        mic: true,
        camera: camOn,
        screen: screenOn);
  }

  void _updateProximity() {
    final on = appState.callPref('proximity') &&
        busy &&
        phase != CallPhase.incoming &&
        !speakerOn &&
        !camOn &&
        !screenOn &&
        !peerCam &&
        !peerScreen;
    CallNative.proximity(on);
  }

  void _updatePip() {
    final on = appState.callPref('pip') &&
        phase == CallPhase.active &&
        (camOn || ((peerCam || peerScreen) && remoteVideoReady));
    CallNative.allowPip(on);
  }

  Future<void> _disposeStream(MediaStream? s) async {
    if (s == null) return;
    try {
      for (final t in s.getTracks()) {
        await t.stop();
      }
    } catch (_) {}
    try {
      await s.dispose();
    } catch (_) {}
  }

  Future<void> _dropLocalMedia() async {
    final mic = _mic, cam = _cam;
    _mic = null;
    _cam = null;
    await _disposeStream(mic);
    await _disposeStream(cam);
  }

  // ─────────────────────────────── конец ───────────────────────────────

  void _finish(String reason, {String? message}) {
    if (!busy) return;
    CallDiag.log('finish: $reason ${message ?? ''} rss=${CallDiag.rssMb()}MB');
    endReason = reason;
    endMessage = message;
    lastDuration = connectedAt != null ? DateTime.now().difference(connectedAt!) : Duration.zero;
    phase = CallPhase.ended;
    minimized = false;
    CallNative.ring(false);
    Notif.cancelCall();
    CallNative.tone(switch (reason) {
      'busy' || 'declined' => 'busy',
      'taken' || 'declined_me' => 'none',
      _ => 'end',
    });
    if (reason != 'taken') HapticFeedback.heavyImpact();
    _teardown = _stopAll();
    final sticky = outgoing && kStickyEndReasons.contains(reason);
    _endTimer?.cancel();
    _endTimer = Timer(
        Duration(milliseconds: reason == 'taken' ? 10 : (sticky ? 9000 : 1700)), dismissEnded);
    notifyListeners();
  }

  void dismissEnded() {
    if (phase != CallPhase.ended) return;
    _resetSync();
    notifyListeners();
  }

  Future<void> _stopAll() async {
    _tick?.cancel();
    _stats?.cancel();
    _rebindTimer?.cancel();
    final statsRun = _statsRun;
    _disconnectTimer?.cancel();
    _disconnectTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connectTimer?.cancel();
    final pc = _pc, dc = _dc;
    final streams = [_mic, _cam, _screen, _remoteWrap, _remoteAudioWrap];
    _pc = null;
    _dc = null;
    if (dc != null) {
      dc.onMessage = null;
      dc.onDataChannelState = null;
    }
    _mic = null;
    _cam = null;
    _screen = null;
    _remoteWrap = null;
    _remoteAudioWrap = null;
    _videoSender = null;
    _remoteStream = null;
    _remoteVideoTrack = null;
    _remoteAudioTrack = null;
    screenOn = false;
    myLevel.value = 0;
    peerLevel.value = 0;
    localRenderer?.srcObject = null;
    remoteRenderer?.srcObject = null;
    try {
      _webAudio?.srcObject = null;
    } catch (_) {}
    CallNative.service(false);
    CallNative.keepScreenOn(false);
    CallNative.proximity(false);
    CallNative.allowPip(false);
    CallNative.showOverLockScreen(false);
    // запрос статистики ещё идёт — ждём, иначе нативная часть упадёт на закрытом соединении
    if (statsRun != null) {
      try {
        await statsRun.timeout(const Duration(milliseconds: 1500));
      } catch (_) {}
    }
    CallDiag.log('teardown: dispose pc');
    // порядок важен (особенно на Windows): dispose закрывает каналы, отписывается
    // от событий и отцепляет наблюдателя; только потом close убирает соединение
    try {
      await pc?.dispose();
    } catch (_) {}
    try {
      await pc?.close();
    } catch (_) {}
    CallDiag.log('teardown: pc closed, streams');
    for (final s in streams) {
      await _disposeStream(s);
    }
    CallDiag.log('teardown: done rss=${CallDiag.rssMb()}MB');
    if (isAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }
  }

  void _resetSync() {
    _endTimer?.cancel();
    _endTimer = null;
    final l = localRenderer, r = remoteRenderer, a = _webAudio;
    localRenderer = null;
    remoteRenderer = null;
    _webAudio = null;
    if (_pc != null || _mic != null) _teardown = _stopAll();
    // рендеры освобождаем после кадра, когда экран звонка уже убран
    WidgetsBinding.instance.addPostFrameCallback((_) {
      l?.dispose();
      r?.dispose();
      a?.dispose();
    });
    phase = CallPhase.idle;
    callId = null;
    chatId = null;
    peerId = '';
    peerName = '';
    peerAvatar = null;
    video = false;
    outgoing = false;
    ringing = false;
    peerOffline = false;
    reconnecting = false;
    connectedAt = null;
    endReason = null;
    endMessage = null;
    micOn = true;
    camOn = false;
    screenOn = false;
    frontCam = true;
    speakerOn = false;
    canVideo = true;
    peerMic = true;
    peerCam = false;
    peerScreen = false;
    remoteVideoReady = false;
    minimized = false;
    pip = false;
    emojiKey = const [];
    quality = 3;
    relayed = false;
    rttMs = 0;
    peerLevel.value = 0;
    elapsed.value = Duration.zero;
    lastHint.value = null;
    _remoteOffer = null;
    _pendingIce.clear();
    _localIce.clear();
    _myIce.clear();
    _inviteMsg = null;
    _answerSdp = null;
    _lastOffer = null;
    _lastRestart = DateTime(2000);
    _signalReady = false;
    _remoteSet = false;
    _iceServers = const [];
    _relay = false;
    _restarts = 0;
    _camBeforeScreen = false;
    _lastLost = 0;
    _lastRecv = 0;
    _statsTick = 0;
    _rebinds = 0;
    myLevel.value = 0;
  }

  Future<void> _resetNow() async {
    if (phase == CallPhase.ended) _resetSync();
  }
}

/// Короткий доступ.
CallManager get calls => CallManager.instance;

/// Причины, при которых экран «звонок не удался» ждёт человека (Закрыть / Перезвонить).
const Set<String> kStickyEndReasons = {'busy', 'missed', 'declined', 'failed', 'error', 'privacy'};

/// Ловит «назад» раньше навигатора (регистрируется до запуска приложения).
class _BackObserver extends WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() => calls.handleBack();
}
