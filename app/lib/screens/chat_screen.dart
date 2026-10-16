import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show FontFeature, MaskFilter, BlurStyle, ImageFilter;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import '../icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:camera/camera.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:video_player/video_player.dart';
import 'package:screen_brightness/screen_brightness.dart';

import '../api.dart';
import '../app_state.dart';
import '../cache.dart';
import '../calls/call_manager.dart';
import '../desktop_pane.dart';
import '../notifications.dart';
import '../platform.dart';
import '../e2e.dart';
import '../io/local_files.dart';
import '../media_cache.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/frames.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/shared_media.dart';
import '../widgets/shop_media.dart';
import '../widgets/story_widgets.dart';
import '../widgets/translate_sheet.dart';
import '../widgets/ui.dart';
import '../widgets/user_picker.dart';
import '../file_opener.dart';
import 'appearance_screen.dart';
import 'chat_info_screen.dart';
import 'image_viewer.dart';
import 'join_sheet.dart';
import 'mute_sheet.dart';
import 'report_sheet.dart';
import 'user_info_screen.dart';
import 'video_screen.dart';

part 'chat_parts.dart';
part 'voice_parts.dart';
part 'effect_parts.dart';
part 'round_parts.dart';

const List<String> _kEmojis = [
  '😀','😃','😄','😁','😆','😅','😂','🤣','🙂','🙃','😉','😊','😇','🥰','😍','🤩',
  '😘','😗','😚','😙','😋','😛','😜','🤪','😝','🤑','🤗','🤭','🤫','🤔','🤐','😐',
  '😴','😌','😔','😪','🤤','😷','🤒','🤕','🥳','🥺','😎','🤓','🧐','😏','😒','🙄',
  '😬','😥','😮','😯','😲','😳','🥵','🥶','😱','😨','😰','😢','😭','😤','😡','🤬',
  '👍','👎','👌','🤙','✌️','🤞','🫶','🙏','👏','🙌','💪','🫡','👀','🔥','💯','✨',
  '⚡','🎉','🎂','❤️','🧡','💛','💚','💙','💜','🖤','🤍','💔','💕','💦','⭐','🌚',
  '🍕','🍔','🍟','☕','🍺','🎮','⚽','🏀','🚗','✈️','🎧','🎸','💰','📎','📍','✅','❌','💤',
];

/// Быстрые реакции в меню сообщения.
const List<String> _kQuickReactions = ['❤️', '👍', '😂', '🔥', '😮', '😢', '👎', '🎉'];

class Message {
  final String id;
  final String kind; // text|image|video|file|voice|round|call|location|contact|service
  String text; // меняется при редактировании
  final String? mediaUrl; // относительный, полный = kBaseUrl + mediaUrl
  final String? fileName;
  final bool mine;
  final String time;
  final String senderId;
  final String senderName;
  final String? senderAvatar;
  final Map<String, dynamic>? senderFrame;
  final bool senderBot;
  final bool senderVerified;
  final bool senderPremium;
  final String? forwardedName;
  List<Map<String, dynamic>> reactions;
  bool read;
  bool uploading;
  bool failed;
  String? localPath; // локальный файл, пока грузится
  String? replyToId;
  final String? forwardedFrom;
  bool edited;
  bool pinned;
  final DateTime dt;
  final String? effect;
  bool sealed;
  final DateTime? openAt;
  final DateTime? expiresAt;
  /// Доп. данные: {'gift': {...}} или {'story': {...}}.
  final Map<String, dynamic>? extra;
  /// Сквозное шифрование: конверт с сервера (текст расшифровывается на телефоне).
  String? enc;
  bool decrypting;
  Message(this.id, this.kind, this.text, this.mediaUrl, this.fileName, this.mine,
      this.time,
      {this.senderId = '',
      this.senderName = '',
      this.senderAvatar,
      this.senderFrame,
      this.senderBot = false,
      this.senderVerified = false,
      this.senderPremium = false,
      this.forwardedName,
      List<Map<String, dynamic>>? reactions,
      this.read = false,
      this.uploading = false,
      this.failed = false,
      this.localPath,
      this.replyToId,
      this.forwardedFrom,
      this.edited = false,
      this.pinned = false,
      this.effect,
      this.sealed = false,
      this.openAt,
      this.expiresAt,
      this.extra,
      this.enc,
      this.decrypting = false,
      DateTime? dt})
      : reactions = reactions ?? [],
        dt = dt ?? DateTime.now();

  bool get isService => kind == 'service';
  bool get isGift => kind == 'gift';
  Map<String, dynamic>? get gift => (extra?['gift'] as Map?)?.cast<String, dynamic>();
  Map<String, dynamic>? get story => (extra?['story'] as Map?)?.cast<String, dynamic>();
  bool get isTemp => id.startsWith('tmp_');
}

List<Map<String, dynamic>> _reactionsOf(dynamic raw) =>
    ((raw as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

bool _sameReactions(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i]['emoji'] != b[i]['emoji'] ||
        a[i]['count'] != b[i]['count'] ||
        a[i]['mine'] != b[i]['mine']) {
      return false;
    }
  }
  return true;
}

/// Открыть чат по данным из списка чатов / поиска.
Future<dynamic> openChatScreen(BuildContext context, Map<String, dynamic> c) {
  if (DesktopPane.ready) {
    // на компьютере чат открывается справа, список остаётся слева
    return DesktopPane.open(
      ChatScreen(
        key: ValueKey('chat-${c['id']}'),
        chatId: c['id'] as String,
        name: (c['title'] as String?) ?? 'Чат',
        chat: c,
      ),
      chatId: c['id'] as String,
    );
  }
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ChatScreen(
        chatId: c['id'] as String,
        name: (c['title'] as String?) ?? 'Чат',
        chat: c,
      ),
    ),
  );
}

/// Открыть личный чат с пользователем (создаётся на сервере, если его нет).
Future<void> openDirectChat(BuildContext context, String userId,
    {bool replace = false, String? draft}) async {
  try {
    final chat = await Api.createChat(type: 'direct', memberIds: [userId]);
    if (!context.mounted) return;
    if (DesktopPane.ready) {
      DesktopPane.open(
        ChatScreen(
            key: ValueKey('chat-${chat['id']}'),
            chatId: chat['id'] as String,
            name: (chat['title'] as String?) ?? 'Чат',
            chat: chat,
            draft: draft),
        chatId: chat['id'] as String,
      );
      return;
    }
    final route = MaterialPageRoute(
        builder: (_) => ChatScreen(
            chatId: chat['id'] as String,
            name: (chat['title'] as String?) ?? 'Чат',
            chat: chat,
            draft: draft));
    if (replace) {
      Navigator.pushReplacement(context, route);
    } else {
      Navigator.push(context, route);
    }
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
  }
}

class ChatScreen extends StatefulWidget {
  final String chatId;
  final String name;
  final Map<String, dynamic>? chat;
  /// Готовый текст в поле ввода (например, заказ продавцу) — отправляет сам человек.
  final String? draft;
  const ChatScreen({
    super.key,
    required this.chatId,
    this.name = 'Чат',
    this.chat,
    this.draft,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/// Строка списка: сообщение с признаками «первое/последнее в серии».
class _Row {
  final Message m;
  final bool first;
  final bool last;
  _Row(this.m, this.first, this.last);
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _picker = ImagePicker();
  final _recorder = AudioRecorder();
  bool _hasText = false;
  bool _loading = true;
  final List<Message> _messages = [];
  Timer? _poll;
  Timer? _ttlTimer;
  DateTime _lastRefresh = DateTime.fromMillisecondsSinceEpoch(0);

  // сведения о чате (тип, роль, права)
  late Map<String, dynamic> _chat = Map<String, dynamic>.from(widget.chat ??
      {
        'id': widget.chatId,
        'type': 'direct',
        'title': widget.name,
        'is_member': true,
        'can_send': true,
      });
  bool _joining = false;
  bool _blockedByMe = false;
  List<Map<String, dynamic>> _botCommands = [];
  String? _botBio;

  String get _type => (_chat['type'] as String?) ?? 'direct';
  bool get _isChannel => _type == 'channel';
  bool get _isGroup => _type == 'group';
  bool get _isDirect => _type == 'direct';
  bool get _isMember => _chat['is_member'] != false;
  bool get _isAdmin => _chat['my_role'] == 'owner' || _chat['my_role'] == 'admin';
  bool get _isOwner => _chat['my_role'] == 'owner';
  bool get _canSend => _isMember && (_chat['can_send'] != false);
  bool get _isSystem => _chat['is_system'] == true;
  /// Админ смотрит обращение в поддержку: ответы уходят от имени Connecto.
  bool get _isSupport => _chat['support'] == true;
  bool _isMineId(Object? senderId) =>
      senderId == appState.myUserId ||
      (_isSupport && senderId != null && senderId == _chat['support_bot_id']);
  bool get _isBot => _chat['peer_is_bot'] == true && !_isSystem;
  bool get _peerDeleted => _isDirect && !_isSystem && _chat['peer_id'] == null && _chat.containsKey('peer_id');
  String get _title => (_chat['title'] as String?) ?? widget.name;
  int get _memberCount => (_chat['member_count'] as num?)?.toInt() ?? 0;
  bool get _canPin => _isMember && (_isDirect || _isAdmin);
  String? get _peerId => _chat['peer_id'] as String?;
  bool get _canCall =>
      _isDirect && !_isSystem && !_isBot && !_isSupport && !_peerDeleted && _isMember && _peerId != null;

  bool _callWasBusy = false;

  /// Начался звонок (входящий или исходящий) — останавливаем запись и воспроизведение.
  void _onCallState() {
    final b = calls.busy;
    if (b && !_callWasBusy) {
      if (_recording) _finishRecording(cancel: true);
      VoiceHub.stop();
      RoundHub.stop();
    }
    _callWasBusy = b;
  }

  /// Позвонить собеседнику (video — сразу с камерой).
  void _startCall(bool video) {
    if (!_canCall) return;
    if (_blockedByMe) {
      toast(context, 'Сначала разблокируй пользователя', icon: AppIcons.ban);
      return;
    }
    if (_recording) _finishRecording(cancel: true);
    calls.start(
      chatId: widget.chatId,
      peerId: _peerId!,
      name: _title,
      avatar: _chat['avatar_url'] as String?,
      video: video,
    );
  }

  // ответ / редактирование / закреп
  Message? _replyTo;
  Message? _editing;
  bool _pinHidden = false;

  // эмодзи-панель вместо клавиатуры
  bool _emojiOpen = false;
  late final FocusNode _inputFocus = FocusNode(onKeyEvent: _onInputKey);

  /// Компьютер: Enter — отправить, Shift+Enter — новая строка.
  KeyEventResult _onInputKey(FocusNode node, KeyEvent e) {
    if (!desktopUx || e is! KeyDownEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      if (HardwareKeyboard.instance.isShiftPressed) return KeyEventResult.ignored;
      if (_hasText) _send();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.escape && (_replyTo != null || _editing != null)) {
      setState(() {
        if (_editing != null) _input.clear();
        _replyTo = null;
        _editing = null;
      });
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // перетаскивание файлов в окно (компьютер)
  bool _dragOver = false;

  Widget _dropWrap(Widget child) {
    if (!desktopUx || !_canSend) return child;
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragOver = true),
      onDragExited: (_) => setState(() => _dragOver = false),
      onDragDone: (d) {
        setState(() => _dragOver = false);
        final all = kIsWeb
            ? d.files.toList()
            : d.files.where((f) => !FileSystemEntity.isDirectorySync(f.path)).toList();
        if (all.length < d.files.length) {
          toast(context, 'Папки не отправляются — только файлы', icon: AppIcons.paperclip);
        }
        final files = all.take(10).toList();
        if (files.length < all.length) {
          toast(context, 'За раз — не больше 10 файлов', icon: AppIcons.paperclip);
        }
        for (final f in files) {
          _sendMedia(f.path, _kindByName(f.name), fileName: f.name);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          if (_dragOver)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  margin: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: appState.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(kRadiusL),
                    border: Border.all(color: appState.accent, width: 2),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(AppIcons.upload, size: 54, color: appState.accent),
                        const SizedBox(height: 10),
                        Text('Отпусти, чтобы отправить',
                            style: TextStyle(
                                color: appState.accent,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _kindByName(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot >= 0 ? name.substring(dot + 1).toLowerCase() : '';
    if (const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'}.contains(ext)) return 'image';
    if (const {'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi', '3gp'}.contains(ext)) return 'video';
    return 'file';
  }

  // выбор нескольких сообщений
  bool _selectMode = false;
  final Set<String> _selected = {};

  // прокрутка: «вниз» + новые сообщения, пока листаешь историю
  bool _atBottom = true;
  int _newBelow = 0;
  final Map<String, GlobalKey> _keys = {};
  String? _highlightId;
  final Set<String> _fresh = {}; // появившиеся только что — с анимацией

  // статус собеседника
  bool _peerOnline = false;
  DateTime? _peerLastSeen;
  Timer? _presencePoll;

  // голосовые
  bool _recording = false;
  bool _micHeld = false; // палец ещё на кнопке записи
  bool _voiceStarting = false;
  bool _locked = false;
  bool _paused = false;
  bool _cancelHover = false;
  String? _recPath;
  String _recExt = 'm4a';
  final Stopwatch _recWatch = Stopwatch();
  Timer? _recTimer;
  final ValueNotifier<double> _ampVN = ValueNotifier(0.0);
  final ValueNotifier<Duration> _recTimeVN = ValueNotifier(Duration.zero);
  final ValueNotifier<Offset> _dragVN = ValueNotifier(Offset.zero);
  final ValueNotifier<int> _samplesVN = ValueNotifier(0);
  final List<double> _recSamples = [];
  StreamSubscription<Amplitude>? _ampSub;

  // видеосообщения (кружочки)
  bool _roundRec = false; // кнопка записывает кружочек, а не голосовое
  bool _roundStarted = false; // камера уже пишет
  CameraController? _cam;
  Future<void>? _camClosing; // прошлая запись ещё закрывает камеру
  List<CameraDescription> _cams = const [];
  bool _camFront = true;
  bool _torch = false;
  int _flipTick = 0; // смена камеры — кружок «переворачивается»
  bool _screenLit = false; // экран на полной яркости («вспышка» фронталки)
  double _zoom = 1, _zoomMin = 1, _zoomMax = 1, _zoomBase = 1;

  // «печатает…»
  String? _peerActivity;
  IconData? _peerActivityIcon;
  Timer? _activityClear;
  Timer? _typingStop;
  bool _typingSent = false;

  // поиск по сообщениям
  bool _searching = false;
  String _searchQ = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    appState.currentOpenChatId = widget.chatId;
    if (widget.draft != null && widget.draft!.isNotEmpty) {
      _input.text = widget.draft!;
      _hasText = true;
    }
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
      if (has) _pingTyping();
    });
    _scroll.addListener(_onScroll);
    Realtime.addListener(_onIncoming);
    calls.addListener(_onCallState);
    VoiceHub.queue = _voiceQueue;
    _peerOnline = _chat['peer_online'] == true;
    _peerLastSeen = parseServerTime((_chat['peer_last_seen'] as String?) ?? '');
    _refresh();
    _loadInfo();
    Notif.cancelChat(widget.chatId);
    if (_isMember) Api.markRead(widget.chatId);
    if (_isDirect && !_isSystem) {
      E2E.check(widget.chatId).then((v) {
        if (mounted && v != _e2e) setState(() => _e2e = v);
      });
    }
    // резервный опрос: WebSocket доставляет мгновенно, опрос — страховка
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      final since = DateTime.now().difference(_lastRefresh).inSeconds;
      final wsOk = Realtime.connected.value;
      if (!wsOk || since >= (appState.energySaving ? 60 : 25)) _refresh();
    });
    _ttlTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_messages.any((m) => m.expiresAt != null)) return;
      final now = DateTime.now();
      // перестраиваем чат, только если что-то исчезло; таймеры в пузырях тикают сами
      if (_messages.any((m) => m.expiresAt != null && m.expiresAt!.isBefore(now))) {
        setState(() => _messages.removeWhere(
            (m) => m.expiresAt != null && m.expiresAt!.isBefore(now)));
      } else {
        _ttlTick.value++;
      }
    });
    _presencePoll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_isDirect) _refreshPresence();
    });
  }

  @override
  void dispose() {
    _screenLight(false);
    DesktopPane.chatClosed(widget.chatId);
    if (appState.currentOpenChatId == widget.chatId) {
      appState.currentOpenChatId = null;
    }
    if (_typingSent) Realtime.typing(widget.chatId, 'stop');
    _poll?.cancel();
    _ttlTimer?.cancel();
    _presencePoll?.cancel();
    _activityClear?.cancel();
    _typingStop?.cancel();
    _recTimer?.cancel();
    _ampSub?.cancel();
    Realtime.removeListener(_onIncoming);
    calls.removeListener(_onCallState);
    if (_recording && !_roundRec) {
      _recorder.stop().catchError((_) => null);
    }
    if (_roundRec) Realtime.typing(widget.chatId, 'stop');
    _recorder.dispose();
    _input.dispose();
    _inputFocus.dispose();
    _ampVN.dispose();
    _recTimeVN.dispose();
    _dragVN.dispose();
    _samplesVN.dispose();
    final cam = _cam;
    _cam = null;
    if (cam != null) {
      (() async {
        try {
          if (cam.value.isRecordingVideo) await cam.stopVideoRecording();
        } catch (_) {}
        try {
          await cam.dispose();
        } catch (_) {}
      })();
    }
    if (VoiceHub.queue == _voiceQueue) VoiceHub.queue = null;
    if (VoiceHub.now.value?.item.chatId == widget.chatId) VoiceHub.stop();
    _searchCtrl.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // ─────────────────────────────── загрузка ───────────────────────────────

  Future<void> _loadInfo() async {
    try {
      final c = await Api.chatInfo(widget.chatId);
      if (!mounted) return;
      final wasSupport = _isSupport;
      setState(() {
        _chat = c;
        _peerOnline = c['peer_online'] == true;
        final ls = c['peer_last_seen'] as String?;
        if (ls != null) _peerLastSeen = parseServerTime(ls);
      });
      if (!wasSupport && _isSupport) {
        // открыли обращение без данных чата (например, из пуша) — пересобираем «свои»
        setState(() {
          _messages.removeWhere((m) => !m.isTemp);
          _loading = true; // как первая загрузка: без «новых снизу» и с прокруткой в конец
        });
        _refresh();
      }
      if (_isDirect) _refreshPresence();
    } catch (e) {
      if (e is ApiException && (e.status == 403 || e.status == 404) && mounted) {
        toast(context, e.message, error: true);
        Navigator.of(context).maybePop();
      }
    }
  }

  Future<void> _refreshPresence() async {
    if (!_isDirect || !_isMember) return;
    final p = await Api.peerInfo(widget.chatId);
    if (p == null || !mounted) return;
    setState(() {
      _peerOnline = p['online'] == true;
      final ls = p['last_seen'] as String?;
      _peerLastSeen = (ls != null) ? parseServerTime(ls) : _peerLastSeen;
      _blockedByMe = p['blocked_by_me'] == true;
      _botBio = p['bio'] as String?;
      _botCommands = ((p['commands'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    });
  }

  String _fmt(String? iso) {
    final d = parseServerTime(iso ?? '') ?? DateTime.now();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Сегодня';
    if (diff == 1) return 'Вчера';
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    final m = months[d.month - 1];
    return d.year == now.year ? '${d.day} $m' : '${d.day} $m ${d.year}';
  }

  Message _fromMap(Map<String, dynamic> m, {String? localPath}) => Message(
        m['id'] as String,
        m['kind'] as String? ?? 'text',
        m['enc'] != null
            ? (E2E.cachedEnv(m['enc'] as String) ?? E2E.pending)
            : (m['text'] as String? ?? ''),
        m['media_url'] as String?,
        m['file_name'] as String?,
        _isMineId(m['sender_id']),
        _fmt(m['created_at'] as String?),
        senderId: m['sender_id'] as String? ?? '',
        senderName: m['sender_name'] as String? ?? '',
        senderAvatar: m['sender_avatar'] as String?,
        senderFrame: m['sender_frame'] is Map ? (m['sender_frame'] as Map).cast<String, dynamic>() : null,
        senderBot: m['sender_is_bot'] == true,
        senderVerified: m['sender_verified'] == true,
        senderPremium: m['sender_premium'] == true,
        forwardedName: m['forwarded_name'] as String?,
        reactions: _reactionsOf(m['reactions']),
        read: m['read'] == true,
        replyToId: m['reply_to_id'] as String?,
        forwardedFrom: m['forwarded_from'] as String?,
        edited: m['edited'] == true,
        pinned: m['pinned'] == true,
        effect: m['effect'] as String?,
        sealed: m['sealed'] == true,
        openAt: parseServerTime(m['open_at'] as String? ?? ''),
        expiresAt: parseServerTime(m['expires_at'] as String? ?? ''),
        extra: (m['extra'] as Map?)?.cast<String, dynamic>(),
        enc: m['enc'] as String?,
        decrypting: m['enc'] != null && E2E.cachedEnv(m['enc'] as String) == null,
        localPath: localPath,
        dt: parseServerTime(m['created_at'] as String? ?? ''),
      );

  bool _addFromMap(Map<String, dynamic> m) {
    final id = m['id'] as String?;
    if (id == null || _messages.any((x) => x.id == id)) return false;
    if (appState.isMsgHidden(id)) return false; // удалено «у себя»
    _messages.add(_fromMap(m));
    _messages.sort((x, y) => x.dt.compareTo(y.dt));
    return true;
  }

  /// Заменить временное сообщение настоящим (или убрать, если оно уже пришло).
  void _resolveTemp(String tempId, Map<String, dynamic> real, {String? localPath}) {
    _fresh.remove(tempId);
    _keys.remove(tempId);
    final idx = _messages.indexWhere((x) => x.id == tempId);
    final realId = real['id'] as String?;
    if (realId != null && _messages.any((x) => x.id == realId)) {
      if (idx >= 0) _messages.removeAt(idx);
      return;
    }
    final msg = _fromMap(real, localPath: localPath);
    if (idx >= 0) {
      _messages[idx] = msg;
    } else {
      _messages.add(msg);
    }
    _messages.sort((x, y) => x.dt.compareTo(y.dt));
  }

  Future<void> _refresh() async {
    _lastRefresh = DateTime.now();
    final first = _loading;
    try {
      final list = await Api.messages(widget.chatId);
      if (_isMember) Cache.saveMessages(widget.chatId, list);
      final before = _messages.length;
      var changed = false;
      final serverIds = <String>{};
      DateTime? oldest;
      for (final raw in list) {
        final m = (raw as Map).cast<String, dynamic>();
        final id = m['id'] as String?;
        if (id == null) continue;
        serverIds.add(id);
        final dt = parseServerTime(m['created_at'] as String? ?? '');
        if (dt != null && (oldest == null || dt.isBefore(oldest))) oldest = dt;
        Message? existing;
        for (final x in _messages) {
          if (x.id == id) {
            existing = x;
            break;
          }
        }
        if (existing == null) {
          if (_addFromMap(m) && !first) _fresh.add(id);
          continue;
        }
        if (existing.sealed && m['sealed'] != true) {
          // капсула открылась — подменяем на настоящее содержимое
          final idx = _messages.indexOf(existing);
          _messages[idx] = _fromMap(m);
          _fresh.add(id);
          changed = true;
          if (mounted && m['effect'] == null) HapticFeedback.mediumImpact();
          continue;
        }
        if (m['read'] == true && !existing.read) {
          existing.read = true;
          changed = true;
        }
        final srvEnc = m['enc'] as String?;
        if (srvEnc != null) {
          // зашифрованное: сравниваем конверты, а не пустой текст с сервера
          if (srvEnc != existing.enc) {
            final known = E2E.cachedEnv(srvEnc);
            existing
              ..enc = srvEnc
              ..edited = m['edited'] == true
              ..text = known ?? E2E.pending
              ..decrypting = known == null;
            changed = true;
          }
        } else {
          final srvText = m['text'] as String? ?? existing.text;
          if (existing.text != srvText || existing.enc != null) {
            existing.text = srvText;
            existing.enc = null;
            existing.edited = m['edited'] == true;
            changed = true;
          }
        }
        final srvPinned = m['pinned'] == true;
        if (srvPinned != existing.pinned) {
          existing.pinned = srvPinned;
          changed = true;
        }
        final r = _reactionsOf(m['reactions']);
        if (!_sameReactions(r, existing.reactions)) {
          existing.reactions = r;
          changed = true;
        }
      }
      // сообщения, удалённые пока нас не было
      if (oldest != null) {
        final o = oldest;
        final n = _messages.length;
        _messages.removeWhere(
            (x) => !x.isTemp && !x.dt.isBefore(o) && !serverIds.contains(x.id));
        if (_messages.length != n) changed = true;
      } else if (list.isEmpty && _messages.any((x) => !x.isTemp)) {
        _messages.removeWhere((x) => !x.isTemp);
        changed = true;
      }
      if (mounted && (_messages.length != before || changed || first)) {
        setState(() {});
        if (first) {
          _scrollToEnd(jump: true);
        } else if (_messages.length > before) {
          _onNewBelow(_messages.length - before);
        }
      }
    } catch (_) {
      // нет сети — подгружаем сообщения из кэша
      if (_messages.isEmpty) {
        final cached = await Cache.loadMessages(widget.chatId);
        if (cached != null && mounted) {
          setState(() {
            for (final m in cached) {
              _addFromMap((m as Map).cast<String, dynamic>());
            }
          });
          _scrollToEnd(jump: true);
        }
      }
    }
    if (_loading && mounted) setState(() => _loading = false);
    _decryptPending();
    _checkGifts();
  }

  // ─────────────────────── сквозное шифрование ───────────────────────

  bool _e2e = false; // личный чат зашифрован — показываем замок в шапке
  bool _decryptBusy = false;

  /// Расшифровать все сообщения, у которых пока только конверт.
  Future<void> _decryptPending() async {
    if (_decryptBusy) return;
    _decryptBusy = true;
    try {
      while (mounted) {
        final todo = _messages.where((m) => m.decrypting && m.enc != null).toList();
        if (todo.isEmpty) break;
        for (final m in todo) {
          final t = await E2E.open(m.enc!, id: m.id);
          m.text = t ?? E2E.unavailable;
          m.decrypting = false;
        }
        if (mounted) setState(() {});
      }
    } finally {
      _decryptBusy = false;
    }
  }

  // ─────────────────────── подарки: показ при входе в чат ───────────────────────

  bool _revealing = false;

  /// Новые подарки мне в этом чате — красиво показываем по одному (не больше трёх),
  /// каждый только один раз. Старые (до обновления) просто отмечаем.
  Future<void> _checkGifts() async {
    if (_revealing || !mounted) return;
    final now = DateTime.now();
    final pending = _messages
        .where((m) => m.isGift && m.gift != null && !m.mine && !m.isTemp && !m.sealed &&
            !appState.isGiftRevealed(m.id))
        .toList();
    if (pending.isEmpty) return;
    _revealing = true;
    try {
      final fresh = <Message>[];
      for (final m in pending) {
        if (now.difference(m.dt).inDays >= 3) {
          appState.markGiftRevealed(m.id);
        } else {
          fresh.add(m);
        }
      }
      if (fresh.isEmpty) return;
      // дождёмся, пока экран чата доедет
      await Future.delayed(const Duration(milliseconds: 450));
      for (var i = 0; i < fresh.length; i++) {
        final m = fresh[i];
        appState.markGiftRevealed(m.id);
        if (i >= 3 || !mounted) continue;
        final data = m.gift!;
        final g = (data['gift'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final anon = data['anonymous'] == true;
        final fromConnecto = data['from_connecto'] == true;
        await showGiftReveal(
          context,
          {
            'gift': g,
            'serial': data['serial'],
            'supply': g['supply'],
            'text': m.text,
            'anonymous': anon,
            if (!anon && !fromConnecto) 'from': {'display_name': m.senderName},
          },
          title: fromConnecto
              ? 'Подарок от Connecto'
              : (anon ? 'Анонимный подарок' : 'Вам подарок!'),
        );
      }
    } finally {
      _revealing = false;
    }
    // пока показывали, мог прийти ещё один подарок
    if (mounted &&
        _messages.any((m) =>
            m.isGift && m.gift != null && !m.mine && !m.isTemp && !appState.isGiftRevealed(m.id))) {
      _checkGifts();
    }
  }

  void _onIncoming(Map<String, dynamic> msg) {
    if (msg['type'] == 'user_status') {
      final uid = msg['user_id'] as String?;
      if (_isDirect && uid != null && uid == _chat['peer_id']) {
        if (mounted) {
          setState(() {
            _peerOnline = msg['online'] == true;
            final ls = msg['last_seen'] as String?;
            if (ls != null) _peerLastSeen = parseServerTime(ls);
          });
        }
      }
      return;
    }
    if (msg['chat_id'] != widget.chatId) return;
    final type = msg['type'];
    switch (type) {
      case 'typing':
        if (!_isMineId(msg['user_id'])) {
          final who = _isGroup ? (msg['name'] as String?) : null;
          _showPeerActivity(msg['state'] as String? ?? 'typing', who: who);
        }
        return;
      case 'reactions':
        final id = msg['id'] as String?;
        final raw = _reactionsOf(msg['reactions']);
        for (final m in _messages) {
          if (m.id == id) {
            m.reactions = raw
                .map((r) => <String, dynamic>{
                      ...r,
                      'mine': ((r['user_ids'] as List?) ?? const [])
                          .contains(appState.myUserId),
                    })
                .toList();
          }
        }
        if (mounted) setState(() {});
        return;
      case 'chat_updated':
        _loadInfo();
        return;
      case 'chat_deleted':
        if (mounted) {
          toast(context,
              _isDirect ? 'Чат удалён собеседником' : 'Вы больше не участник этого чата',
              error: true);
          Navigator.of(context).maybePop();
        }
        return;
      case 'cleared':
        if (mounted) setState(() => _messages.removeWhere((m) => !m.isTemp));
        return;
      case 'edited':
        final id = msg['id'] as String?;
        final enc = msg['enc'] as String?;
        for (final m in _messages) {
          if (m.id == id) {
            m.edited = true;
            if (enc != null) {
              if (enc != m.enc) {
                m.enc = enc;
                // уже знаем этот конверт (своя правка) — сразу, иначе расшифровываем
                final known = E2E.cachedEnv(enc);
                if (known != null) {
                  m.text = known;
                } else {
                  m.decrypting = true;
                  E2E.open(enc).then((t) {
                    if (!mounted || m.enc != enc) return;
                    setState(() {
                      m.text = t ?? E2E.unavailable;
                      m.decrypting = false;
                    });
                  });
                }
              }
            } else {
              m.enc = null;
              m.text = msg['text'] as String? ?? m.text;
            }
            break;
          }
        }
        if (mounted) setState(() {});
        return;
      case 'msg_deleted':
        if (mounted) setState(() => _messages.removeWhere((m) => m.id == msg['id']));
        return;
      case 'pinned':
        final id = msg['id'] as String?;
        final val = msg['pinned'] == true;
        for (final m in _messages) {
          if (val) m.pinned = false; // один закреп
          if (m.id == id) m.pinned = val;
        }
        if (mounted) setState(() => _pinHidden = false);
        return;
      case 'read':
        var changed = false;
        for (final m in _messages) {
          if (m.mine && !m.read && !m.isTemp) {
            m.read = true;
            changed = true;
          }
        }
        if (changed && mounted) setState(() {});
        return;
      case 'message':
        break;
      default:
        return;
    }
    final id = msg['id'] as String?;
    if (id == null || _messages.any((x) => x.id == id)) return;
    final mine = _isMineId(msg['sender_id']);
    if (!mine) _showPeerActivity('stop');
    // своё зашифрованное «эхо» пришло раньше ответа сервера — дождёмся ответа, без дублей
    if (mine && msg['enc'] != null && E2E.cachedEnv(msg['enc'] as String) == null &&
        _messages.any((x) => x.isTemp && x.uploading)) {
      return;
    }
    // своё текстовое, которое ещё «в пути» — заменяем временное на месте
    if (mine && msg['kind'] == 'text') {
      final tmp = _messages.where((x) =>
          x.isTemp && x.uploading && x.kind == 'text' && x.text == msg['text']);
      if (tmp.isNotEmpty) {
        setState(() => _resolveTemp(tmp.first.id, msg));
        return;
      }
    }
    setState(() {
      if (_addFromMap(msg)) _fresh.add(id);
    });
    if (msg['enc'] != null) _decryptPending();
    if (!mine && msg['effect'] != null && msg['sealed'] != true) {
      playEffect(context, msg['effect'] as String?);
    }
    if (mine) {
      _scrollToEnd();
    } else {
      _onNewBelow(1);
      Notif.cancelChat(widget.chatId);
      if (_isMember) Api.markRead(widget.chatId); // мы в чате — сразу читаем
      if (msg['kind'] == 'gift') _checkGifts();
    }
  }

  // ─────────────────────────────── прокрутка ───────────────────────────────

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final p = _scroll.position;
    final at = p.maxScrollExtent - p.pixels < 160;
    if (at != _atBottom) {
      setState(() {
        _atBottom = at;
        if (at) _newBelow = 0;
      });
    }
  }

  void _onNewBelow(int n) {
    if (_atBottom) {
      _scrollToEnd();
    } else if (mounted) {
      setState(() => _newBelow += n);
    }
  }

  void _scrollToEnd({bool jump = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final target = _scroll.position.maxScrollExtent;
      if (jump || !appState.motion) {
        _scroll.jumpTo(target);
        // картинки догружаются и меняют высоту — дожимаем ещё раз
        Future.delayed(const Duration(milliseconds: 120), () {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      } else {
        if (_scroll.position.pixels < target) {
          _scroll.animateTo(target,
              duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic);
        }
      }
    });
    if (_newBelow != 0 && mounted) setState(() => _newBelow = 0);
  }

  /// Прокрутить к сообщению (ответ / закреп) и подсветить его.
  void _jumpTo(String? id) {
    if (id == null) return;
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx < 0) {
      toast(context, 'Сообщение удалено или слишком старое', icon: AppIcons.info);
      return;
    }
    if (_searching) {
      setState(() {
        _searching = false;
        _searchQ = '';
        _searchCtrl.clear();
      });
    }
    void show() {
      final ctx = _keys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx,
            alignment: 0.4,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic);
      }
      setState(() => _highlightId = id);
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (mounted && _highlightId == id) setState(() => _highlightId = null);
      });
    }

    if (_keys[id]?.currentContext != null) {
      show();
      return;
    }
    // элемент ещё не построен — прыгаем примерно к нему и пробуем снова
    if (_scroll.hasClients) {
      final frac = idx / math.max(1, _messages.length - 1);
      _scroll.jumpTo(_scroll.position.maxScrollExtent * frac);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) show();
      });
    });
  }

  // ─────────────────────────────── «печатает» ───────────────────────────────

  void _pingTyping() {
    if (_isChannel || !_canSend) return;
    if (!_typingSent) {
      Realtime.typing(widget.chatId, 'typing');
      _typingSent = true;
    }
    _typingStop?.cancel();
    _typingStop = Timer(const Duration(seconds: 3), () {
      _typingSent = false;
      Realtime.typing(widget.chatId, 'stop');
    });
  }

  void _showPeerActivity(String state, {String? who}) {
    final p = who == null || who.isEmpty ? '' : '$who ';
    final label = switch (state) {
      'voice' => '${p}записывает голосовое…',
      'video' => '${p}записывает видеосообщение…',
      'upload_photo' => '${p}отправляет фото…',
      'upload_video' => '${p}отправляет видео…',
      'upload' || 'upload_file' => '${p}отправляет файл…',
      'stop' => '',
      _ => '${p}печатает…',
    };
    final icon = switch (state) {
      'voice' => AppIcons.mic,
      'video' => AppIcons.video,
      'upload_photo' => AppIcons.image,
      'upload_video' => AppIcons.clapperboard,
      'upload' || 'upload_file' => AppIcons.paperclip,
      'stop' => null,
      _ => AppIcons.penLine,
    };
    _activityClear?.cancel();
    if (label.isEmpty) {
      if (_peerActivity != null && mounted) {
        setState(() {
          _peerActivity = null;
          _peerActivityIcon = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _peerActivity = label;
        _peerActivityIcon = icon;
      });
    }
    _activityClear = Timer(const Duration(seconds: 5), () {
      if (mounted) {
        setState(() {
          _peerActivity = null;
          _peerActivityIcon = null;
        });
      }
    });
  }

  // ─────────────────────────────── отправка ───────────────────────────────

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;

    if (_editing != null) {
      final target = _editing!;
      _input.clear();
      setState(() => _editing = null);
      if (target.text == text) return;
      final old = target.text;
      setState(() {
        target.text = text;
        target.edited = true;
      });
      try {
        await Api.editMessage(widget.chatId, target.id, text);
      } catch (e) {
        if (mounted) {
          setState(() => target.text = old);
          toast(context, friendlyError(e), error: true);
        }
      }
      return;
    }

    final reply = _replyTo;
    _input.clear();
    setState(() => _replyTo = null);
    _typingStop?.cancel();
    if (_typingSent) {
      _typingSent = false;
      Realtime.typing(widget.chatId, 'stop');
    }
    await _sendText(text, replyTo: reply);
  }

  /// Оптимистичная отправка текста: пузырь появляется сразу с «часиками».
  Future<void> _sendText(String text,
      {Message? replyTo, String? effect, bool silent = false, DateTime? openAt}) async {
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final temp = Message(tempId, 'text', text, null, null, true,
        _fmt(DateTime.now().toIso8601String()),
        senderId: appState.myUserId ?? '',
        senderName: appState.displayName,
        uploading: true,
        effect: effect,
        openAt: openAt,
        replyToId: replyTo?.id);
    setState(() {
      _messages.add(temp);
      _fresh.add(tempId);
    });
    _scrollToEnd();
    try {
      if (effect != null) playEffect(context, effect);
      final m = await Api.sendMessage(widget.chatId,
          text: text, replyToId: replyTo?.id, effect: effect, silent: silent, openAt: openAt);
      if (mounted) setState(() => _resolveTemp(tempId, m));
    } catch (e) {
      if (mounted) {
        setState(() {
          temp.uploading = false;
          temp.failed = true;
        });
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  /// Особая отправка (долгое нажатие на «отправить»): эффект, без звука, капсула.
  Future<void> _specialSend() async {
    final text = _input.text.trim();
    if (text.isEmpty || _editing != null) return;
    HapticFeedback.mediumImpact();
    _inputFocus.unfocus();
    final choice = await showAppSheet<String>(context, builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Container(
                constraints: const BoxConstraints(maxWidth: 260),
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                decoration: myBubbleDecoration(BorderRadius.circular(16)),
                child: Text(text,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 14),
            const SectionLabel('Эффект при получении'),
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 0.95,
              children: [
                for (final f in kFx)
                  Pressable(
                    onTap: () => Navigator.pop(ctx, 'fx:${f.id}'),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).scaffoldBackgroundColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Stack(
                        children: [
                          Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(f.emoji, style: const TextStyle(fontSize: 28)),
                                const SizedBox(height: 4),
                                Text(f.title,
                                    style: const TextStyle(
                                        fontSize: 11.5, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          if (f.premium)
                            const Positioned(
                              right: 5,
                              top: 5,
                              child: Icon(AppIcons.star, color: kPremium, size: 14),
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SectionCard(children: [
              SettingsTile(
                icon: AppIcons.bellOff,
                iconColor: const Color(0xFF64748B),
                title: 'Отправить без звука',
                subtitle: 'Придёт без уведомления',
                chevron: false,
                onTap: () => Navigator.pop(ctx, 'silent'),
              ),
              SettingsTile(
                icon: AppIcons.timer,
                iconColor: const Color(0xFFB0457A),
                title: 'Капсула времени',
                subtitle: 'Откроется только в выбранный момент',
                onTap: () => Navigator.pop(ctx, 'capsule'),
              ),
            ]),
          ],
        ),
      );
    });
    if (choice == null || !mounted) return;
    final reply = _replyTo;
    if (choice.startsWith('fx:')) {
      final f = fxOf(choice.substring(3));
      if (f == null) return;
      if (f.premium && !appState.isPremium) {
        premiumGate(context, 'Эффект «${f.title}»');
        return;
      }
      _input.clear();
      setState(() => _replyTo = null);
      await _sendText(text, replyTo: reply, effect: f.id);
    } else if (choice == 'silent') {
      _input.clear();
      setState(() => _replyTo = null);
      await _sendText(text, replyTo: reply, silent: true);
      if (mounted) toast(context, 'Отправлено без звука', icon: AppIcons.bellOff);
    } else if (choice == 'capsule') {
      final at = await _pickCapsuleTime();
      if (at == null || !mounted) return;
      _input.clear();
      setState(() => _replyTo = null);
      await _sendText(text, replyTo: reply, openAt: at);
      if (mounted) {
        toast(context, 'Капсула запечатана до ${_capsuleDate(at)}', icon: AppIcons.lock);
      }
    }
  }

  Future<DateTime?> _pickCapsuleTime() async {
    final now = DateTime.now();
    final presets = <String, DateTime>{
      'Через 1 час': now.add(const Duration(hours: 1)),
      'Завтра утром': DateTime(now.year, now.month, now.day + 1, 9),
      'Через неделю': now.add(const Duration(days: 7)),
      'Через месяц': DateTime(now.year, now.month + 1, now.day, now.hour, now.minute),
      'Новый год': DateTime(now.year + 1, 1, 1),
      'Через год': DateTime(now.year + 1, now.month, now.day, now.hour, now.minute),
    };
    final pick = await showAppSheet<Object>(context, builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 8),
          child: Text('Когда открыть капсулу?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        for (final e in presets.entries)
          SheetItem(
              icon: AppIcons.timer,
              title: e.key,
              subtitle: _capsuleDate(e.value),
              onTap: () => Navigator.pop(ctx, e.value)),
        SheetItem(
            icon: AppIcons.pencil,
            title: 'Выбрать дату и время',
            onTap: () => Navigator.pop(ctx, 'custom')),
        const SizedBox(height: 6),
      ]);
    });
    if (pick is DateTime) return pick;
    if (pick != 'custom' || !mounted) return null;
    final d = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: DateTime(now.year + 5),
      helpText: 'День открытия',
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 5))),
        helpText: 'Время открытия');
    if (t == null) return null;
    final at = DateTime(d.year, d.month, d.day, t.hour, t.minute);
    if (at.isBefore(DateTime.now().add(const Duration(minutes: 1)))) {
      if (mounted) toast(context, 'Выбери время хотя бы на минуту позже', error: true);
      return null;
    }
    return at;
  }

  Future<void> _setTtl() async {
    final cur = (_chat['ttl_seconds'] as num?)?.toInt() ?? 0;
    final v = await showAppSheet<int>(context, builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: Text('Автоудаление сообщений',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text('Новые сообщения исчезнут у всех через выбранное время.',
              style: TextStyle(color: subtleText(ctx), fontSize: 13)),
        ),
        for (final e in kTtlNames.entries)
          ListTile(
            leading: Icon(e.key == 0 ? AppIcons.ban : AppIcons.timer,
                color: e.key == cur ? appState.accent : subtleText(ctx)),
            title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing:
                e.key == cur ? Icon(AppIcons.circleCheck, color: appState.accent) : null,
            onTap: () => Navigator.pop(ctx, e.key),
          ),
        const SizedBox(height: 6),
      ]);
    });
    if (v == null || v == cur || !mounted) return;
    try {
      final c = await Api.setChatTtl(widget.chatId, v);
      if (mounted) setState(() => _chat = c);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _retry(Message m) async {
    final gif = m.kind == 'image' && (m.mediaUrl ?? '').startsWith('http');
    if (m.kind != 'text' && m.localPath == null && !gif) return; // повторять нечего
    setState(() => _messages.remove(m));
    if (m.kind == 'text') {
      await _sendText(m.text, replyTo: _findMsg(m.replyToId));
    } else if (m.localPath != null) {
      await _sendMedia(m.localPath!, m.kind, fileName: m.fileName, text: m.text);
    } else {
      await _sendGif(m.mediaUrl!);
    }
  }

  Message? _findMsg(String? id) {
    if (id == null) return null;
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  String _previewOf(Message m) {
    switch (m.kind) {
      case 'image':
        return '📷 Фото';
      case 'video':
        return '🎬 Видео';
      case 'file':
        return '📎 ${m.fileName ?? 'Файл'}';
      case 'voice':
        return '🎤 Голосовое';
      case 'round':
        return '📹 Видеосообщение';
      case 'call':
        return '📞 ${_callTitle(m)}';
      case 'location':
        return '📍 Геолокация';
      case 'contact':
        return '👤 Контакт';
      case 'gift':
        return '🎁 ${m.gift?['gift']?['title'] ?? 'Подарок'}';
      default:
        return m.text;
    }
  }

  String _authorOf(Message m) {
    if (m.mine && !_isChannel) return 'Вы';
    if (_isChannel) return _title;
    if (m.senderName.isNotEmpty) return m.senderName;
    return _title;
  }

  void _startReply(Message m) {
    setState(() {
      _replyTo = m;
      _editing = null;
    });
    _inputFocus.requestFocus();
  }

  void _startEdit(Message m) {
    setState(() {
      _editing = m;
      _replyTo = null;
      _input.text = m.text;
      _input.selection = TextSelection.collapsed(offset: _input.text.length);
    });
    _inputFocus.requestFocus();
  }

  bool _canDeleteForAll(Message m) =>
      _isMember && !m.isTemp && (m.mine || _isDirect || _isAdmin);

  Future<void> _deleteForAll(List<Message> list) async {
    final ids = list.map((m) => m.id).toSet();
    setState(() => _messages.removeWhere((x) => ids.contains(x.id)));
    var fails = 0;
    for (final m in list) {
      try {
        await Api.deleteMessage(widget.chatId, m.id);
      } catch (_) {
        fails++;
      }
    }
    if (fails > 0) {
      if (mounted) toast(context, 'Часть сообщений удалить не удалось', error: true);
      _refresh();
    }
  }

  void _deleteForMe(List<Message> list) {
    for (final m in list) {
      if (!m.isTemp) appState.hideMessage(m.id);
    }
    final ids = list.map((m) => m.id).toSet();
    setState(() => _messages.removeWhere((x) => ids.contains(x.id)));
  }

  void _deleteSheet(List<Message> list) {
    final n = list.length;
    final forAll = list.every(_canDeleteForAll);
    final suffix = n > 1 ? ' ($n)' : '';
    showAppSheet(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Text(
                n > 1 ? 'Удалить $n сообщений?' : 'Удалить сообщение?',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (forAll)
            SheetItem(
              icon: AppIcons.trash2,
              title: _isDirect
                  ? 'Удалить у меня и у ${_title.split(' ').first}$suffix'
                  : 'Удалить у всех$suffix',
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                _deleteForAll(list);
                _exitSelect();
              },
            ),
          SheetItem(
            icon: AppIcons.eyeOff,
            title: 'Удалить только у меня$suffix',
            onTap: () {
              Navigator.pop(ctx);
              _deleteForMe(list);
              _exitSelect();
            },
          ),
          const SizedBox(height: 6),
        ],
      );
    });
  }

  Future<void> _togglePin(Message m) async {
    final was = m.pinned;
    setState(() {
      for (final x in _messages) {
        x.pinned = false;
      }
      m.pinned = !was;
      _pinHidden = false;
    });
    try {
      await Api.pinMessage(widget.chatId, m.id, !was);
      if (mounted) {
        toast(context, was ? 'Сообщение откреплено' : 'Сообщение закреплено',
            icon: was ? AppIcons.pinOff : AppIcons.pin);
      }
    } catch (e) {
      if (mounted) {
        setState(() => m.pinned = was);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  /// Реакция: мгновенно меняем локально, потом берём точный ответ сервера.
  Future<void> _react(Message m, String emoji) async {
    if (!_isMember || m.isTemp || m.isService) return;
    HapticFeedback.selectionClick();
    final before = m.reactions.map((r) => Map<String, dynamic>.from(r)).toList();
    final list = m.reactions.map((r) => Map<String, dynamic>.from(r)).toList();
    final idx = list.indexWhere((r) => r['emoji'] == emoji);
    if (idx >= 0 && list[idx]['mine'] == true) {
      final c = ((list[idx]['count'] as num?)?.toInt() ?? 1) - 1;
      if (c <= 0) {
        list.removeAt(idx);
      } else {
        list[idx]['count'] = c;
        list[idx]['mine'] = false;
      }
    } else {
      final limit = appState.isPremium ? 3 : 1;
      final mineCount = list.where((r) => r['mine'] == true).length;
      if (mineCount >= limit) {
        // снимаем самую старую свою реакцию (сервер делает так же)
        final old = list.indexWhere((r) => r['mine'] == true);
        if (old >= 0) {
          final c = ((list[old]['count'] as num?)?.toInt() ?? 1) - 1;
          if (c <= 0) {
            list.removeAt(old);
          } else {
            list[old]['count'] = c;
            list[old]['mine'] = false;
          }
        }
      }
      final j = list.indexWhere((r) => r['emoji'] == emoji);
      if (j >= 0) {
        list[j]['count'] = ((list[j]['count'] as num?)?.toInt() ?? 0) + 1;
        list[j]['mine'] = true;
      } else {
        list.add({'emoji': emoji, 'count': 1, 'mine': true});
      }
    }
    setState(() => m.reactions = list);
    try {
      final srv = await Api.react(widget.chatId, m.id, emoji);
      if (mounted) setState(() => m.reactions = _reactionsOf(srv));
    } catch (e) {
      if (mounted) {
        setState(() => m.reactions = before);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _forward(List<Message> list) async {
    final target = await Navigator.push<Map<String, dynamic>>(
        context, MaterialPageRoute(builder: (_) => const _ForwardPicker()));
    if (target == null || !mounted) return;
    final chatId = target['id'] as String;
    var ok = 0;
    for (final m in list) {
      if (m.isTemp || m.isService || m.sealed || m.isGift || m.kind == 'call') continue;
      try {
        await Api.sendMessage(chatId,
            text: m.text,
            kind: m.kind,
            mediaUrl: m.mediaUrl,
            fileName: m.fileName,
            forwardedFrom: m.forwardedFrom ?? (m.senderId.isEmpty ? null : m.senderId));
        ok++;
      } catch (e) {
        if (mounted) toast(context, friendlyError(e), error: true);
        break;
      }
    }
    _exitSelect();
    if (ok > 0 && mounted) {
      toast(context,
          ok == 1 ? 'Переслано в «${target['title'] ?? 'чат'}»' : 'Переслано: $ok',
          icon: AppIcons.forward);
    }
  }

  // ─────────────────────────────── вложения ───────────────────────────────

  Future<void> _sendMedia(String path, String kind,
      {String? fileName, String text = ''}) async {
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final temp = Message(
      tempId, kind, text, null, fileName, true,
      _fmt(DateTime.now().toIso8601String()),
      senderId: appState.myUserId ?? '',
      uploading: true, localPath: path,
    );
    if (mounted) {
      setState(() {
        _messages.add(temp);
        _fresh.add(tempId);
      });
      _scrollToEnd();
    }
    final upState = kind == 'image'
        ? 'upload_photo'
        : (kind == 'video' ? 'upload_video' : 'upload_file');
    Realtime.typing(widget.chatId, upState);
    try {
      final up = await Api.uploadPath(path, fileName: fileName);
      final m = await Api.sendMessage(widget.chatId,
          kind: kind,
          text: text,
          mediaUrl: up['url'] as String?,
          fileName: fileName ?? up['file_name'] as String?);
      if (mounted) setState(() => _resolveTemp(tempId, m, localPath: path));
    } catch (e) {
      if (mounted) {
        setState(() {
          temp.uploading = false;
          temp.failed = true;
        });
        toast(context, friendlyError(e), error: true);
      }
    } finally {
      Realtime.typing(widget.chatId, 'stop');
    }
  }

  /// GIF из поиска: сервер забирает его к себе, потом уходит как обычная картинка.
  Future<void> _sendGif(String url) async {
    HapticFeedback.selectionClick();
    final tempId = 'tmp_${DateTime.now().microsecondsSinceEpoch}';
    final temp = Message(
      tempId, 'image', '', url, null, true,
      _fmt(DateTime.now().toIso8601String()),
      senderId: appState.myUserId ?? '',
      uploading: true,
    );
    if (mounted) {
      setState(() {
        _messages.add(temp);
        _fresh.add(tempId);
      });
      _scrollToEnd();
    }
    try {
      final up = await Api.gifImport(url);
      final m = await Api.sendMessage(widget.chatId,
          kind: 'image', text: '', mediaUrl: up['url'] as String?, fileName: 'GIF');
      if (mounted) setState(() => _resolveTemp(tempId, m));
    } catch (e) {
      if (mounted) {
        setState(() {
          temp.uploading = false;
          temp.failed = true;
        });
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _pickImage({bool camera = false}) async {
    try {
      final x = await _picker.pickImage(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          imageQuality: appState.imageQuality,
          maxWidth: appState.uploadQuality == 'economy' ? 1280 : 2560);
      if (x != null) _sendMedia(x.path, 'image');
    } catch (_) {
      if (mounted) toast(context, 'Нет доступа к фото или камере', error: true);
    }
  }

  Future<void> _pickMultiImages() async {
    try {
      final list = await _picker.pickMultiImage(
          imageQuality: appState.imageQuality,
          maxWidth: appState.uploadQuality == 'economy' ? 1280 : 2560);
      for (final x in list.take(10)) {
        _sendMedia(x.path, 'image');
      }
    } catch (_) {
      if (mounted) toast(context, 'Нет доступа к галерее', error: true);
    }
  }

  Future<void> _pickVideo({bool camera = false}) async {
    try {
      final x = await _picker.pickVideo(
          source: camera ? ImageSource.camera : ImageSource.gallery,
          maxDuration: const Duration(minutes: 10));
      if (x != null) _sendMedia(x.path, 'video');
    } catch (_) {
      if (mounted) toast(context, 'Нет доступа к видео', error: true);
    }
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(withData: kIsWeb);
      final f = res?.files.single;
      if (f == null) return;
      if (kIsWeb) {
        // в браузере у файла нет пути — держим байты в памяти (blob:-ссылка)
        final bytes = f.bytes;
        if (bytes == null) return;
        final url = await writeTempBytes(bytes, f.name);
        _sendMedia(url, _kindByName(f.name), fileName: f.name);
      } else if (f.path != null) {
        _sendMedia(f.path!, 'file', fileName: f.name);
      }
    } catch (_) {
      if (mounted) toast(context, 'Не удалось выбрать файл', error: true);
    }
  }

  Future<void> _pickLocation() async {
    toast(context, 'Определяю геолокацию…', icon: AppIcons.mapPin);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) toast(context, 'Включи геолокацию на телефоне', error: true);
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (mounted) toast(context, 'Нет доступа к геолокации', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      final m = await Api.sendMessage(widget.chatId,
          kind: 'location', text: '${pos.latitude},${pos.longitude}');
      if (mounted) {
        setState(() {
          if (_addFromMap(m)) _fresh.add(m['id'] as String);
        });
        _scrollToEnd();
      }
    } catch (e) {
      if (mounted) toast(context, 'Не удалось отправить геолокацию', error: true);
    }
  }

  Future<void> _pickContact() async {
    final picked = await pickUsers(context,
        title: 'Отправить контакт', multi: false, includeBots: true);
    if (picked == null || picked.isEmpty) return;
    final user = picked.first;
    final payload = jsonEncode({
      'name': userName(user),
      'handle': user['handle'] ?? '',
      'id': user['id'] ?? '',
    });
    try {
      final m = await Api.sendMessage(widget.chatId, kind: 'contact', text: payload);
      if (mounted) {
        setState(() {
          if (_addFromMap(m)) _fresh.add(m['id'] as String);
        });
        _scrollToEnd();
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  void _openAttach() {
    _inputFocus.unfocus();
    showAppSheet(context, builder: (ctx) {
      Widget tile(IconData icon, String title, Color color, VoidCallback onTap) {
        return Expanded(
          child: Pressable(
            onTap: () {
              Navigator.pop(ctx);
              onTap();
            },
            child: Column(
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(icon, color: color, size: 26),
                ),
                const SizedBox(height: 8),
                Text(title,
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        );
      }

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              tile(AppIcons.images, desktopUx ? 'Фото' : 'Галерея', const Color(0xFF3B82F6),
                  _pickMultiImages),
              if (!desktopUx)
                tile(AppIcons.camera, 'Камера', const Color(0xFF8B5CF6), () => _pickImage(camera: true)),
              tile(AppIcons.video, 'Видео', const Color(0xFFEC4899), _pickVideo),
              if (!desktopUx)
                tile(AppIcons.clapperboard, 'Снять видео', const Color(0xFFF97316),
                    () => _pickVideo(camera: true)),
              if (desktopUx) tile(AppIcons.file, 'Файл', const Color(0xFF14B8A6), _pickFile),
              if (desktopUx) tile(AppIcons.mapPin, 'Место', const Color(0xFF22C55E), _pickLocation),
            ]),
            const SizedBox(height: 18),
            Row(children: [
              if (!desktopUx) tile(AppIcons.file, 'Файл', const Color(0xFF14B8A6), _pickFile),
              if (!desktopUx)
                tile(AppIcons.mapPin, 'Место', const Color(0xFF22C55E), _pickLocation),
              tile(AppIcons.userRound, 'Контакт', const Color(0xFFF59E0B), _pickContact),
              const Expanded(child: SizedBox()),
              if (desktopUx) const Expanded(child: SizedBox()),
              if (desktopUx) const Expanded(child: SizedBox()),
            ]),
          ],
        ),
      );
    });
  }

  // ─────────────────────────────── голосовые ───────────────────────────────

  static const _maxVoice = Duration(minutes: 10);

  VoiceItem _voiceItemOf(Message m) {
    final meta = parseWave(m.text);
    return VoiceItem(
      id: m.id,
      chatId: widget.chatId,
      url: mediaUrl(m.mediaUrl),
      localPath: m.localPath,
      title: m.mine ? 'Вы' : (m.senderName.isEmpty ? _title : m.senderName),
      durationMs: meta?.durationMs ?? 0,
      mine: m.mine,
    );
  }

  List<VoiceItem> _voiceQueue() => _messages
      .where((m) => m.kind == 'voice' && m.mediaUrl != null && !m.isTemp)
      .map(_voiceItemOf)
      .toList();

  Future<void> _startVoice() async {
    if (_recording || _voiceStarting) return;
    _voiceStarting = true; // микрофон ещё включается — второе нажатие не запускает вторую запись
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) toast(context, 'Нет доступа к микрофону', error: true);
        return;
      }
      // пока показывался запрос доступа, палец уже отпустили — не пишем «в пустоту»
      if (!_micHeld) return;
      await VoiceHub.stop(); // не пишем поверх играющего голосового
      final dir = await tempDirPath(); // в браузере — null: запись живёт в памяти
      // AAC есть почти везде; в Chrome — Opus (webm); если ничего — WAV
      var enc = AudioEncoder.wav;
      for (final e in kIsWeb
          ? const [AudioEncoder.aacLc, AudioEncoder.opus]
          : const [AudioEncoder.aacLc]) {
        try {
          if (await _recorder.isEncoderSupported(e)) {
            enc = e;
            break;
          }
        } catch (_) {}
      }
      final ext = switch (enc) {
        AudioEncoder.aacLc => 'm4a',
        AudioEncoder.opus => 'webm',
        _ => 'wav',
      };
      final path =
          dir == null ? '' : '$dir/voice_${DateTime.now().millisecondsSinceEpoch}.$ext';
      await _recorder.start(
          RecordConfig(
            encoder: enc,
            bitRate: 96000,
            sampleRate: 44100,
            numChannels: 1,
            autoGain: true,
            echoCancel: true,
            noiseSuppress: true,
          ),
          path: path);
      _recPath = path;
      _recExt = ext;
      if (!_micHeld || !mounted) {
        // отпустили, пока микрофон включался — запись не начинаем
        try {
          await _recorder.cancel();
        } catch (_) {}
        _recPath = null;
        return;
      }
      HapticFeedback.mediumImpact();
      _recSamples.clear();
      _samplesVN.value = 0;
      _ampVN.value = 0;
      _dragVN.value = Offset.zero;
      _recTimeVN.value = Duration.zero;
      _recWatch
        ..reset()
        ..start();
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _recTimeVN.value = _recWatch.elapsed;
        if (_recWatch.elapsed >= _maxVoice) {
          _finishVoice(cancel: false);
          if (mounted) toast(context, 'Максимальная длина — 10 минут', icon: AppIcons.mic);
        }
      });
      _ampSub?.cancel();
      _ampSub = _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 80))
          .listen((a) {
        if (_paused) return;
        final d = a.current.isFinite ? a.current.clamp(-52.0, 0.0) : -52.0;
        final v = math.pow((d + 52) / 52, 1.7).toDouble();
        _ampVN.value = _ampVN.value * 0.4 + v * 0.6; // сглаживание
        _recSamples.add(v);
        _samplesVN.value = _recSamples.length;
      });
      setState(() {
        _recording = true;
        _locked = false;
        _paused = false;
        _cancelHover = false;
        _emojiOpen = false;
      });
      Realtime.typing(widget.chatId, 'voice');
    } catch (e) {
      if (mounted) toast(context, 'Не удалось начать запись', error: true);
    } finally {
      _voiceStarting = false;
    }
  }

  void _voiceDrag(Offset d) {
    if (!_recording || _locked) return;
    _dragVN.value = d;
    if (d.dy < -100 && d.dx > -60) {
      HapticFeedback.heavyImpact();
      setState(() => _locked = true);
      _dragVN.value = Offset.zero;
      return;
    }
    if (d.dx < -150) {
      // утянули далеко влево — отмена сразу, как в Telegram
      HapticFeedback.heavyImpact();
      _finishRecording(cancel: true);
      return;
    }
    final hover = d.dx < -80;
    if (hover != _cancelHover) {
      if (hover) HapticFeedback.selectionClick();
      setState(() => _cancelHover = hover);
    }
  }

  void _voiceRelease() {
    _micHeld = false;
    if (!_recording || _locked) return;
    _finishRecording(cancel: _cancelHover);
  }

  /// Нажали и держат кнопку записи: голосовое или кружочек — смотря что выбрано.
  void _startRecording() {
    _micHeld = true;
    if (appState.roundMode && !kIsWeb) {
      _startRound();
    } else {
      _startVoice();
    }
  }

  void _finishRecording({required bool cancel}) {
    if (_roundRec) {
      _finishRound(cancel: cancel);
    } else {
      _finishVoice(cancel: cancel);
    }
  }

  /// Короткое нажатие на кнопку записи: микрофон ⇄ камера.
  void _toggleRecordMode() {
    if (kIsWeb) {
      toast(context, 'Видеосообщения пока записываются только в приложении',
          icon: AppIcons.video);
      return;
    }
    HapticFeedback.selectionClick();
    appState.setRoundMode(!appState.roundMode);
    setState(() {});
  }

  // ─────────────────────────────── видеосообщения ───────────────────────────────

  CameraDescription _pickCam(bool front) {
    final want = front ? CameraLensDirection.front : CameraLensDirection.back;
    return _cams.firstWhere((d) => d.lensDirection == want, orElse: () => _cams.first);
  }

  Future<void> _startRound() async {
    if (_recording) return;
    if (calls.inCall) {
      toast(context, 'Во время звонка записать кружочек нельзя', icon: AppIcons.video);
      return;
    }
    _recording = true; // сразу — чтобы второе нажатие не начало запись параллельно
    await VoiceHub.stop();
    RoundHub.stop();
    if (!mounted) return;
    HapticFeedback.mediumImpact();
    _dragVN.value = Offset.zero;
    _recTimeVN.value = Duration.zero;
    _recWatch.reset();
    setState(() {
      _recording = true;
      _roundRec = true;
      _roundStarted = false;
      _locked = false;
      _paused = false;
      _cancelHover = false;
      _emojiOpen = false;
      _torch = false;
      _zoom = 1;
    });
    _screenLight(false);
    final closing = _camClosing;
    if (closing != null) {
      try {
        await closing; // камера ещё занята прошлым кружочком
      } catch (_) {}
    }
    CameraController? cam;
    try {
      if (_cams.isEmpty) _cams = await availableCameras();
      if (_cams.isEmpty) throw StateError('no camera');
      if (!_roundRec) return; // уже отпустили
      if (!_cams.any((d) => d.lensDirection == CameraLensDirection.front)) _camFront = false;
      cam = CameraController(_pickCam(_camFront), ResolutionPreset.medium,
          enableAudio: true, fps: 30, videoBitrate: 1600000, audioBitrate: 64000);
      _cam = cam;
      await cam.initialize();
      if (!_roundRec || _cam != cam) {
        if (_cam == cam) _cam = null;
        await cam.dispose();
        return; // отпустили палец раньше, чем камера проснулась
      }
      try {
        _zoomMin = await cam.getMinZoomLevel();
        _zoomMax = math.min(await cam.getMaxZoomLevel(), 8.0);
      } catch (_) {
        _zoomMin = 1;
        _zoomMax = 1;
      }
      _zoom = _zoomMin;
      try {
        await cam.lockCaptureOrientation(DeviceOrientation.portraitUp);
      } catch (_) {}
      await cam.startVideoRecording();
      if (!_roundRec || _cam != cam) {
        if (_cam == cam) _cam = null;
        try {
          final f = await cam.stopVideoRecording();
          deleteLocal(f.path);
        } catch (_) {}
        await cam.dispose();
        return;
      }
      _roundStarted = true;
      _recWatch
        ..reset()
        ..start();
      _recTimer?.cancel();
      _recTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
        _recTimeVN.value = _recWatch.elapsed;
        if (_recWatch.elapsed >= kRoundMax) {
          // минута — отправляем сами, как в Telegram
          _finishRound(cancel: false);
        }
      });
      Realtime.typing(widget.chatId, 'video');
      if (mounted) setState(() {});
    } catch (e) {
      if (cam != null && _cam != cam) {
        // эта попытка уже неактуальна (отпустили или начали новую) — просто закрываем её камеру
        try {
          await cam.dispose();
        } catch (_) {}
        return;
      }
      final wasActive = _roundRec;
      _cam = null;
      _roundStarted = false;
      _recTimer?.cancel();
      try {
        await cam?.dispose();
      } catch (_) {}
      _screenLight(false);
      if (mounted && wasActive) {
        setState(() {
          _recording = false;
          _roundRec = false;
          _locked = false;
        });
        toast(context, 'Нет доступа к камере или микрофону', error: true);
      }
    }
  }

  Future<void> _finishRound({required bool cancel}) async {
    if (!_roundRec) return;
    final cam = _cam;
    final started = _roundStarted;
    _recTimer?.cancel();
    _recWatch.stop();
    final dur = _recWatch.elapsed;
    _dragVN.value = Offset.zero;
    if (mounted) {
      setState(() {
        _recording = false;
        _roundRec = false;
        _roundStarted = false;
        _locked = false;
        _paused = false;
        _cancelHover = false;
        _torch = false;
      });
    }
    _screenLight(false);
    Realtime.typing(widget.chatId, 'stop');
    String? path;
    if (cam != null && started) {
      final done = Completer<void>();
      _camClosing = done.future;
      try {
        try {
          final f = await cam.stopVideoRecording();
          path = f.path;
        } catch (_) {}
        if (_cam == cam) _cam = null;
        // камеру выключаем после того, как круг исчез с экрана
        await WidgetsBinding.instance.endOfFrame;
        try {
          await cam.dispose();
        } catch (_) {}
      } finally {
        done.complete();
        if (_camClosing == done.future) _camClosing = null;
      }
    }
    // если камера ещё не проснулась — её закроет _startRound
    final tooShort = dur.inMilliseconds < 900;
    if (cancel || tooShort || path == null) {
      if (path != null) {
        deleteLocal(path);
      }
      if (!cancel && (tooShort || !started) && mounted) {
        toast(context, 'Удерживай кнопку, чтобы записать видеосообщение', icon: AppIcons.video);
      } else if (cancel) {
        HapticFeedback.lightImpact();
      }
      return;
    }
    HapticFeedback.lightImpact();
    _sendMedia(path, 'round', text: 'round:${dur.inMilliseconds}');
  }

  Future<void> _toggleRoundPause() async {
    final cam = _cam;
    if (cam == null || !_roundStarted) return;
    try {
      if (_paused) {
        await cam.resumeVideoRecording();
        _recWatch.start();
      } else {
        await cam.pauseVideoRecording();
        _recWatch.stop();
      }
      HapticFeedback.selectionClick();
      setState(() => _paused = !_paused);
    } catch (_) {
      if (mounted) toast(context, 'На этой камере пауза недоступна', icon: AppIcons.video);
    }
  }

  Future<void> _flipRoundCam() async {
    final cam = _cam;
    if (cam == null || _cams.length < 2) return;
    HapticFeedback.selectionClick();
    final front = !_camFront;
    setState(() => _flipTick++); // переворот кружка — пока камера переключается
    try {
      if (_torch && !_camFront) await cam.setFlashMode(FlashMode.off);
      await cam.setDescription(_pickCam(front));
      await cam.lockCaptureOrientation(DeviceOrientation.portraitUp).catchError((_) {});
      _camFront = front;
      _torch = false;
      _screenLight(false);
      try {
        _zoomMin = await cam.getMinZoomLevel();
        _zoomMax = math.min(await cam.getMaxZoomLevel(), 8.0);
      } catch (_) {}
      _zoom = _zoomMin;
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) toast(context, 'Не удалось сменить камеру', error: true);
    }
  }

  Future<void> _toggleTorch() async {
    final cam = _cam;
    if (cam == null) return;
    HapticFeedback.selectionClick();
    final on = !_torch;
    if (!_camFront && !isDesktop) {
      try {
        await cam.setFlashMode(on ? FlashMode.torch : FlashMode.off);
      } catch (_) {
        if (mounted) toast(context, 'У этой камеры нет вспышки', error: true);
        return;
      }
    }
    if (!mounted) return;
    // у фронтальной камеры «вспышка» — весь экран белый и яркость на максимум
    setState(() => _torch = on);
    if (_camFront || isDesktop) _screenLight(on);
  }

  /// Яркость экрана на максимум (и обратно) — только в приложении на телефоне.
  Future<void> _screenLight(bool on) async {
    if (_screenLit == on) return;
    _screenLit = on;
    if (!isNativeMobile) return;
    try {
      if (on) {
        await ScreenBrightness.instance.setApplicationScreenBrightness(1.0);
      } else {
        await ScreenBrightness.instance.resetApplicationScreenBrightness();
      }
    } catch (_) {}
  }

  Future<void> _setZoom(double z) async {
    final cam = _cam;
    if (cam == null) return;
    final v = z.clamp(_zoomMin, _zoomMax).toDouble();
    if ((v - _zoom).abs() < 0.02) return;
    setState(() => _zoom = v);
    try {
      await cam.setZoomLevel(v);
    } catch (_) {}
  }

  void _zoomStep() {
    final steps = <double>[_zoomMin, 2, 4, _zoomMax].where((z) => z >= _zoomMin && z <= _zoomMax).toList();
    final next = steps.firstWhere((z) => z > _zoom + 0.05, orElse: () => _zoomMin);
    _setZoom(next);
  }

  Future<void> _togglePause() async {
    try {
      if (_paused) {
        await _recorder.resume();
        _recWatch.start();
      } else {
        await _recorder.pause();
        _recWatch.stop();
        _ampVN.value = 0;
      }
      HapticFeedback.selectionClick();
      setState(() => _paused = !_paused);
    } catch (_) {}
  }

  Future<void> _finishVoice({required bool cancel}) async {
    if (!_recording) return;
    _recTimer?.cancel();
    _ampSub?.cancel();
    _ampSub = null;
    _recWatch.stop();
    final dur = _recWatch.elapsed;
    _ampVN.value = 0;
    _dragVN.value = Offset.zero;
    Realtime.typing(widget.chatId, 'stop');
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    path ??= _recPath;
    _recPath = null;
    if (path != null && path.isEmpty) path = null;
    final samples = List<double>.from(_recSamples);
    if (mounted) {
      setState(() {
        _recording = false;
        _locked = false;
        _paused = false;
        _cancelHover = false;
      });
    }
    final tooShort = dur.inMilliseconds < 700;
    if (cancel || tooShort || path == null) {
      if (path != null) {
        deleteLocal(path);
      }
      if (tooShort && !cancel && mounted) {
        toast(context, 'Удерживай кнопку, чтобы записать голосовое', icon: AppIcons.mic);
      } else if (cancel) {
        HapticFeedback.lightImpact();
      }
      return;
    }
    HapticFeedback.lightImpact();
    _sendMedia(path, 'voice',
        text: encodeWave(samples, dur.inMilliseconds),
        fileName: kIsWeb ? 'voice.$_recExt' : null);
  }

  // ─────────────────────────────── выбор ───────────────────────────────

  void _enterSelect(Message m) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectMode = true;
      _selected
        ..clear()
        ..add(m.id);
    });
  }

  void _toggleSelect(Message m) {
    if (m.isService) return;
    setState(() {
      if (!_selected.remove(m.id)) _selected.add(m.id);
      if (_selected.isEmpty) _selectMode = false;
    });
  }

  void _exitSelect() {
    if (!_selectMode) return;
    setState(() {
      _selectMode = false;
      _selected.clear();
    });
  }

  List<Message> get _selectedMessages =>
      _messages.where((m) => _selected.contains(m.id)).toList();

  // ─────────────────────────────── меню сообщения ───────────────────────────────

  void _bubbleActions(Message m) {
    if (m.isService) return;
    HapticFeedback.mediumImpact();
    _inputFocus.unfocus();
    if (m.isTemp) {
      showAppSheet(context, builder: (ctx) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          if (m.failed)
            SheetItem(
                icon: AppIcons.refreshCw,
                title: 'Отправить ещё раз',
                onTap: () {
                  Navigator.pop(ctx);
                  _retry(m);
                }),
          SheetItem(
              icon: AppIcons.trash2,
              title: 'Удалить',
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _messages.remove(m));
              }),
          const SizedBox(height: 6),
        ]);
      });
      return;
    }
    if (m.sealed) {
      showAppSheet(context, builder: (ctx) {
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Text(
                m.openAt != null
                    ? 'Капсула откроется ${_capsuleDate(m.openAt!)}'
                    : 'Капсула времени',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          SheetItem(
              icon: AppIcons.eyeOff,
              title: 'Удалить у меня',
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                _deleteForMe([m]);
              }),
          const SizedBox(height: 6),
        ]);
      });
      return;
    }
    final isText = m.kind == 'text';
    showAppSheet(context, scrollable: true, builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      return SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isMember)
              SizedBox(
                height: 58,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  children: [
                    for (final e in _kQuickReactions)
                      _ReactionPick(
                        emoji: e,
                        selected: m.reactions
                            .any((r) => r['emoji'] == e && r['mine'] == true),
                        onTap: () => go(() => _react(m, e)),
                      ),
                  ],
                ),
              ),
            if (_isMember) Divider(height: 1, color: hairline(ctx)),
            if (_canSend)
              SheetItem(
                  icon: AppIcons.reply,
                  title: 'Ответить',
                  onTap: () => go(() => _startReply(m))),
            if (isText)
              SheetItem(
                  icon: AppIcons.copy,
                  title: 'Копировать',
                  onTap: () => go(() {
                        Clipboard.setData(ClipboardData(text: m.text));
                        toast(context, 'Текст скопирован', icon: AppIcons.copy);
                      })),
            if (m.text.trim().isNotEmpty &&
                const {'text', 'image', 'video', 'file'}.contains(m.kind))
              SheetItem(
                  icon: AppIcons.languages,
                  title: 'Перевести',
                  onTap: () => go(() => showTranslateSheet(context, m.text))),
            if (m.mine && isText && _canSend)
              SheetItem(
                  icon: AppIcons.pencil,
                  title: 'Изменить',
                  onTap: () => go(() => _startEdit(m))),
            if (_canPin)
              SheetItem(
                  icon: m.pinned ? AppIcons.pinOff : AppIcons.pin,
                  title: m.pinned ? 'Открепить' : 'Закрепить',
                  onTap: () => go(() => _togglePin(m))),
            if (!m.isGift && m.kind != 'call')
              SheetItem(
                  icon: AppIcons.forward,
                  title: 'Переслать',
                  onTap: () => go(() => _forward([m]))),
            if (m.mediaUrl != null && m.kind != 'voice' && m.kind != 'round')
              SheetItem(
                  icon: AppIcons.download,
                  title: 'Открыть / сохранить',
                  onTap: () => go(() => FileOpener.openOrDownload(
                      context,
                      url: mediaUrl(m.mediaUrl),
                      fileName: m.fileName ?? 'файл',
                      localPath: m.localPath))),
            if (_isGroup && !m.mine && m.senderId.isNotEmpty)
              SheetItem(
                  icon: AppIcons.userRound,
                  title: 'Профиль: ${m.senderName}',
                  onTap: () => go(() => _openUser(m.senderId, m.senderName))),
            SheetItem(
                icon: AppIcons.listChecks,
                title: 'Выбрать',
                onTap: () => go(() => _enterSelect(m))),
            SheetItem(
                icon: AppIcons.trash2,
                title: 'Удалить',
                danger: true,
                onTap: () => go(() => _deleteSheet([m]))),
            const SizedBox(height: 6),
          ],
        ),
      );
    });
  }

  // ─────────────────────────────── меню чата ───────────────────────────────

  void _openUser(String userId, String name) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => UserInfoScreen(userId: userId, name: name)));
  }

  Future<void> _openInfo() async {
    if (_isDirect) {
      if (_peerId == null) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => UserInfoScreen(
                    userId: _peerId!,
                    chatId: widget.chatId,
                    name: _title,
                    avatarUrl: _chat['avatar_url'] as String?,
                  )));
      if (mounted) {
        _refreshPresence();
        setState(() {});
      }
      return;
    }
    final r = await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatInfoScreen(chatId: widget.chatId, chat: _chat)));
    if (!mounted) return;
    if (r == 'left') {
      Navigator.pop(context, 'left');
      return;
    }
    _loadInfo();
  }

  void _openMenu() {
    final muted = appState.isMuted(widget.chatId);
    showAppSheet(context, builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!_isDirect)
            SheetItem(
                icon: AppIcons.info,
                title: _isChannel ? 'О канале' : 'О группе',
                onTap: () => go(_openInfo)),
          if (_isDirect && _peerId != null)
            SheetItem(
                icon: AppIcons.userRound,
                title: 'Профиль',
                onTap: () => go(_openInfo)),
          if (_canCall)
            SheetItem(
                icon: AppIcons.phone,
                title: 'Позвонить',
                onTap: () => go(() => _startCall(false))),
          if (_canCall)
            SheetItem(
                icon: AppIcons.video,
                title: 'Видеозвонок',
                onTap: () => go(() => _startCall(true))),
          SheetItem(
              icon: AppIcons.search,
              title: 'Поиск по сообщениям',
              onTap: () => go(() => setState(() => _searching = true))),
          if (_isMember)
            SheetItem(
                icon: muted ? AppIcons.bell : AppIcons.bellOff,
                title: muted ? 'Включить уведомления' : 'Отключить уведомления',
                onTap: () => go(() => showMuteSheet(context, widget.chatId))),
          if (_isBot && _botCommands.isNotEmpty)
            SheetItem(
                icon: AppIcons.squareSlash,
                title: 'Команды бота',
                onTap: () => go(_showCommands)),
          if (_isMember && (_isDirect || _isAdmin) && !_isSystem && !_isBot && !_isSupport)
            SheetItem(
                icon: AppIcons.timer,
                title: 'Автоудаление',
                subtitle: kTtlNames[(_chat['ttl_seconds'] as num?)?.toInt() ?? 0],
                onTap: () => go(_setTtl)),
          if (_isMember)
            SheetItem(
                icon: AppIcons.eraser,
                title: 'Очистить историю',
                onTap: () => go(_clearHistory)),
          if (_isDirect && _peerId != null && !_isSystem)
            SheetItem(
                icon: _blockedByMe ? AppIcons.userCheck : AppIcons.ban,
                title: _blockedByMe
                    ? 'Разблокировать'
                    : (_isBot ? 'Остановить и заблокировать бота' : 'Заблокировать'),
                danger: !_blockedByMe,
                onTap: () => go(_toggleBlock)),
          if (!_isDirect && _isMember)
            SheetItem(
                icon: AppIcons.logOut,
                title: _isChannel ? 'Покинуть канал' : 'Покинуть группу',
                danger: true,
                onTap: () => go(_leave)),
          if (_isDirect && _isMember)
            SheetItem(
                icon: AppIcons.trash2,
                title: 'Удалить чат',
                danger: true,
                onTap: () => go(_deleteChat)),
          if (!_isSystem)
            SheetItem(
                icon: AppIcons.flag,
                title: 'Пожаловаться',
                danger: true,
                onTap: () => go(() => showReportSheet(context,
                    type: _isChannel ? 'channel' : (_isBot ? 'bot' : 'person'),
                    targetId: _peerId,
                    chatId: widget.chatId))),
          const SizedBox(height: 6),
        ],
      );
    });
  }

  Future<void> _clearHistory() async {
    final canAll = _isDirect || _isAdmin;
    final choice = await showAppSheet<String>(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Text('Очистить историю?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          if (canAll)
            SheetItem(
                icon: AppIcons.trash2,
                title: _isDirect ? 'Очистить у меня и у собеседника' : 'Очистить у всех участников',
                danger: true,
                onTap: () => Navigator.pop(ctx, 'all')),
          SheetItem(
              icon: AppIcons.eyeOff,
              title: 'Очистить только у меня',
              onTap: () => Navigator.pop(ctx, 'me')),
          const SizedBox(height: 6),
        ],
      );
    });
    if (choice == null || !mounted) return;
    try {
      await Api.clearHistory(widget.chatId, forAll: choice == 'all');
      if (!mounted) return;
      setState(() => _messages.removeWhere((m) => !m.isTemp));
      toast(context, 'История очищена', icon: AppIcons.eraser);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _toggleBlock() async {
    final id = _peerId;
    if (id == null) return;
    if (_blockedByMe) {
      try {
        await Api.unblockUser(id);
        if (mounted) {
          setState(() => _blockedByMe = false);
          toast(context, 'Пользователь разблокирован', icon: AppIcons.userCheck);
        }
      } catch (e) {
        if (mounted) toast(context, friendlyError(e), error: true);
      }
      return;
    }
    final ok = await confirm(context,
        title: _isBot ? 'Заблокировать бота?' : 'Заблокировать $_title?',
        body: _isBot
            ? 'Бот больше не сможет присылать вам сообщения.'
            : 'Он(а) не сможет писать вам, видеть ваш статус и фото профиля.',
        action: 'Заблокировать',
        danger: true);
    if (!ok) return;
    try {
      await Api.blockUser(id);
      if (mounted) {
        setState(() => _blockedByMe = true);
        toast(context, 'Заблокировано', icon: AppIcons.ban);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _leave() async {
    final ok = await confirm(context,
        title: _isChannel ? 'Покинуть канал?' : 'Покинуть группу?',
        body: _isOwner
            ? 'Вы владелец. Права перейдут другому администратору или самому давнему участнику.'
            : (_isChannel
                ? 'Вы перестанете получать публикации этого канала.'
                : 'Вы больше не будете получать сообщения из этой группы.'),
        action: 'Покинуть',
        danger: true);
    if (!ok) return;
    try {
      await Api.leaveChat(widget.chatId);
      if (mounted) Navigator.pop(context, 'left');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _deleteChat() async {
    bool both = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Удалить чат?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Переписка с $_title исчезнет из списка чатов.'),
              if (!_isSystem && !_isBot)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: both,
                  onChanged: (v) => setLocal(() => both = v ?? false),
                  title: Text('Удалить и у ${_title.split(' ').first}'),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Удалить',
                    style: TextStyle(color: kDanger, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.deleteChat(widget.chatId, both: both);
      if (mounted) Navigator.pop(context, 'left');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _join() async {
    setState(() => _joining = true);
    try {
      final c = await Api.joinPublic(widget.chatId);
      if (!mounted) return;
      setState(() => _chat = c);
      Api.markRead(widget.chatId);
      toast(context, _isChannel ? 'Вы подписались на канал' : 'Вы вступили в группу');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _joining = false);
    }
  }

  void _showCommands() {
    showAppSheet(context, scrollable: true, builder: (ctx) {
      return ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 6, 20, 6),
            child: Text('Команды бота',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          for (final c in _botCommands)
            ListTile(
              leading: IconTile(AppIcons.squareSlash),
              title: Text('/${c['command']}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: (c['description'] as String? ?? '').isEmpty
                  ? null
                  : Text(c['description'] as String,
                      style: TextStyle(color: subtleText(ctx))),
              onTap: () {
                Navigator.pop(ctx);
                _sendText('/${c['command']}');
              },
            ),
          const SizedBox(height: 8),
        ],
      );
    });
  }

  /// Нажатие на ссылку-приглашение внутри сообщения.
  Future<void> _openInvite(String code) async {
    final chat = await showJoinPreview(context, code: code);
    if (chat != null && mounted) openChatScreen(context, chat);
  }

  // ─────────────────────────────── эмодзи ───────────────────────────────

  void _toggleEmoji() {
    if (_emojiOpen) {
      setState(() => _emojiOpen = false);
      _inputFocus.requestFocus();
    } else {
      _inputFocus.unfocus();
      setState(() => _emojiOpen = true);
    }
  }

  void _insertEmoji(String e) {
    final t = _input.text;
    final sel = _input.selection;
    final pos = (sel.isValid && sel.baseOffset >= 0) ? sel.baseOffset : t.length;
    _input.text = t.substring(0, pos) + e + t.substring(pos);
    _input.selection = TextSelection.collapsed(offset: pos + e.length);
  }

  // ─────────────────────────────── UI ───────────────────────────────

  String _subtitle() {
    if (_peerActivity != null) return _peerActivity!;
    if (_isChannel) {
      return _memberCount == 0
          ? 'канал'
          : plural(_memberCount, 'подписчик', 'подписчика', 'подписчиков');
    }
    if (_isGroup) {
      return plural(_memberCount, 'участник', 'участника', 'участников');
    }
    if (_isSystem) return 'служебные уведомления';
    if (_isSupport) {
      return 'обращение в поддержку · ${lastSeenText(_peerLastSeen, online: _peerOnline)}';
    }
    if (_isBot) return 'бот';
    if (_peerDeleted) return 'аккаунт удалён';
    if (_blockedByMe) return 'заблокирован(а)';
    return lastSeenText(_peerLastSeen, online: _peerOnline);
  }

  PreferredSizeWidget _appBar() {
    if (_selectMode) {
      final sel = _selectedMessages;
      final allText = sel.isNotEmpty && sel.every((m) => m.kind == 'text');
      return AppBar(
        leading: IconButton(icon: const Icon(AppIcons.x), onPressed: _exitSelect),
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          child: Text('Выбрано: ${_selected.length}', key: ValueKey(_selected.length)),
        ),
        actions: [
          if (allText)
            IconButton(
                tooltip: 'Копировать',
                icon: const Icon(AppIcons.copy),
                onPressed: () {
                  Clipboard.setData(ClipboardData(
                      text: sel.map((m) => m.text).join('\n\n')));
                  _exitSelect();
                  toast(context, 'Скопировано', icon: AppIcons.copy);
                }),
          IconButton(
              tooltip: 'Переслать',
              icon: const Icon(AppIcons.forward),
              onPressed: sel.isEmpty ? null : () => _forward(sel)),
          IconButton(
              tooltip: 'Удалить',
              icon: const Icon(AppIcons.trash2, color: kDanger),
              onPressed: sel.isEmpty ? null : () => _deleteSheet(sel)),
          const SizedBox(width: 4),
        ],
      );
    }
    if (_searching) {
      return AppBar(
        titleSpacing: 0,
        leading: IconButton(
            icon: const Icon(AppIcons.arrowLeft),
            onPressed: () => setState(() {
                  _searching = false;
                  _searchQ = '';
                  _searchCtrl.clear();
                })),
        title: TextField(
          controller: _searchCtrl,
          autofocus: true,
          onChanged: (v) => setState(() => _searchQ = v),
          decoration: const InputDecoration(
              hintText: 'Поиск по сообщениям',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false),
        ),
      );
    }
    final activity = _peerActivity != null;
    final online = _isDirect && _peerOnline && !_isBot && !_isSystem;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppBar(
      automaticallyImplyLeading: false,
      titleSpacing: 8,
      title: Row(
        children: [
          // 1. Стрелочка назад — отдельная круглая / стеклянная кнопка
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: cardColor(context).withValues(alpha: isDark ? 0.6 : 0.78),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: hairline(context)),
                ),
                alignment: Alignment.center,
                child: const Icon(AppIcons.arrowLeft, size: 20),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 2. Аватарка (с поддержкой надетой рамки магазина)
          Hero(
            tag: 'chat-avatar-${widget.chatId}',
            child: FramedAvatar(
              size: 40,
              frame: _chat['frame'] is Map ? (_chat['frame'] as Map).cast<String, dynamic>() : null,
              child: Avatar(
                name: _title,
                url: _chat['avatar_url'] as String?,
                size: 40,
                online: online,
                useAccent: _isSystem,
                icon: _isSystem
                    ? AppIcons.shieldCheck
                    : (_isChannel
                        ? AppIcons.megaphone
                        : (_isGroup ? AppIcons.users : null)),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 3. Отдельный скруглённый прямоугольный стеклянный контейнер: имя + статус
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openInfo,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: cardColor(context).withValues(alpha: isDark ? 0.45 : 0.65),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: hairline(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: NameBadges(
                            _title,
                            verified: _chat['is_verified'] == true || _isSystem,
                            premium: _chat['peer_premium'] == true,
                            emoji: _chat['peer_emoji_status'] as String?,
                            bot: _isBot,
                            style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (_e2e)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Tooltip(
                              message: 'Сквозное шифрование',
                              child: Icon(AppIcons.lock, size: 12, color: subtleText(context)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Row(
                      children: [
                        if (activity && _peerActivityIcon != null) ...[
                          Icon(_peerActivityIcon, size: 12, color: appState.accent),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 200),
                            child: Text(
                              _subtitle(),
                              key: ValueKey(_subtitle()),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: activity || online ? FontWeight.w600 : FontWeight.w400,
                                color: activity
                                    ? appState.accent
                                    : (online ? kSuccess : subtleText(context)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 4. Отдельный стеклянный контейнер с 3 кнопками действий (поиск, таймер, меню)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            decoration: BoxDecoration(
              color: cardColor(context).withValues(alpha: isDark ? 0.45 : 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hairline(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Поиск',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(AppIcons.search, size: 18),
                  onPressed: () => setState(() => _searching = true),
                ),
                if (((_chat['ttl_seconds'] as num?)?.toInt() ?? 0) > 0)
                  Tooltip(
                    message: 'Автоудаление: ${kTtlNames[(_chat['ttl_seconds'] as num).toInt()] ?? ''}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(AppIcons.timer, size: 17, color: appState.accent),
                    ),
                  ),
                if (!_isDirect && _isMember && appState.isMuted(widget.chatId))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Icon(AppIcons.bellOff, size: 16, color: subtleText(context)),
                  ),
                IconButton(
                  tooltip: 'Меню',
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(6),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  icon: const Icon(AppIcons.ellipsisVertical, size: 18),
                  onPressed: _openMenu,
                ),
              ],
            ),
          ),
        ],
      ),
      actions: const [],
    );
  }

  List<Object> _buildRows(List<Message> shown) {
    final rows = <Object>[];
    DateTime? prevDay;
    for (var i = 0; i < shown.length; i++) {
      final m = shown[i];
      final d = m.dt;
      final day = DateTime(d.year, d.month, d.day);
      if (prevDay == null || day != prevDay) {
        rows.add(_dayLabel(d));
        prevDay = day;
      }
      bool sameRun(Message? a, Message b) =>
          a != null &&
          !a.isService &&
          !b.isService &&
          a.senderId == b.senderId &&
          b.dt.difference(a.dt).inMinutes.abs() < 5 &&
          a.dt.day == b.dt.day;
      final prev = i > 0 ? shown[i - 1] : null;
      final next = i < shown.length - 1 ? shown[i + 1] : null;
      rows.add(_Row(m, !sameRun(prev, m), next == null || !sameRun(m, next)));
    }
    return rows;
  }

  Widget _messageList(List<Message> shown) {
    final rows = _buildRows(shown);
    final replyNames = <String, String>{};
    return ListView.builder(
      controller: _scroll,
      cacheExtent: 600,
      padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final item = rows[i];
        if (item is String) return _DayPill(item);
        final row = item as _Row;
        final m = row.m;
        if (m.isService) {
          return _ServicePill(m.text, key: ValueKey(m.id));
        }
        final replied = _findMsg(m.replyToId);
        if (replied != null) {
          replyNames[replied.id] = _authorOf(replied);
        }
        final key = _keys.putIfAbsent(m.id, () => GlobalKey());
        Widget bubble = _Bubble(
          key: key,
          msg: m,
          chatId: widget.chatId,
          channel: _isChannel,
          group: _isGroup,
          first: row.first,
          last: row.last,
          highlighted: _highlightId == m.id,
          replyAuthor: replied != null ? replyNames[replied.id] : null,
          replyPreview: replied != null
              ? _previewOf(replied)
              : (m.replyToId != null ? 'Сообщение удалено' : null),
          selectMode: _selectMode,
          isSelected: _selected.contains(m.id),
          onSelectTap: () => _toggleSelect(m),
          onLongPress: () => _selectMode ? _toggleSelect(m) : _bubbleActions(m),
          onDoubleTap: () {
            if (!_selectMode) _react(m, '❤️');
          },
          onReact: (e) => _react(m, e),
          onReplyTap: () => _jumpTo(m.replyToId),
          onSenderTap: () => _openUser(m.senderId, m.senderName),
          onRetry: () => _retry(m),
          onCommand: _isBot && _canSend ? (c) => _sendText(c) : null,
          onInvite: _openInvite,
          onSwipeReply: _canSend && !_selectMode && !m.sealed ? () => _startReply(m) : null,
          onCapsuleOpened: _refresh,
          onEffect: (e) => playEffect(context, e),
          onCallBack: _canCall ? _startCall : null,
        );
        if (_fresh.contains(m.id)) {
          bubble = _MessageAppear(
              key: ValueKey('f${m.id}'),
              fromRight: m.mine && !_isChannel,
              onComplete: () => _fresh.remove(m.id),
              child: bubble);
        }
        return RepaintBoundary(child: bubble);
      },
    );
  }

  Widget _emptyHint() {
    if (_isSystem) {
      return const EmptyState(
        icon: AppIcons.shieldCheck,
        mascot: 'mascot',
        title: 'Служебные уведомления',
        subtitle:
            'Здесь появляются уведомления о входе в аккаунт и ответы поддержки. Напиши сюда, если нужна помощь.',
      );
    }
    if (_isBot) {
      return EmptyState(
        icon: AppIcons.bot,
        title: _title,
        subtitle: (_botBio != null && _botBio!.isNotEmpty)
            ? _botBio
            : 'Это бот. Нажми «Старт», чтобы начать.',
        action: _canSend && !_blockedByMe
            ? SizedBox(
                width: 200,
                child: PrimaryButton(
                    label: 'Старт',
                    icon: AppIcons.play,
                    onTap: () => _sendText('/start')),
              )
            : null,
      );
    }
    if (_isChannel) {
      return EmptyState(
        icon: AppIcons.megaphone,
        title: 'Пока нет публикаций',
        subtitle: _canSend
            ? 'Напиши первый пост — его увидят все подписчики'
            : 'Здесь появятся посты канала',
      );
    }
    if (_isGroup) {
      return const EmptyState(
        icon: AppIcons.users,
        mascot: 'empty_chat',
        title: 'Сообщений пока нет',
        subtitle: 'Напиши первым — поздоровайся с участниками 👋',
      );
    }
    return EmptyState(
      icon: AppIcons.messageCircle,
      mascot: 'empty_chat',
      title: 'Сообщений пока нет',
      subtitle: _e2e
          ? 'Отправь $_title первое сообщение 🙂\n🔒 Переписка защищена сквозным шифрованием'
          : 'Отправь $_title первое сообщение 🙂',
      action: _canSend && !_blockedByMe
          ? Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (final e in const ['👋', '😊', '🔥'])
                  Pressable(
                    onTap: () => _sendText(e),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: appState.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 26)),
                    ),
                  ),
              ],
            )
          : null,
    );
  }

  /// Нижняя часть: ввод, либо кнопка «Вступить», либо пояснение.
  Widget _bottom() {
    if (!_isMember) {
      return _BottomAction(
        label: _isChannel ? 'Подписаться' : 'Вступить в группу',
        icon: _isChannel ? AppIcons.bellPlus : AppIcons.userPlus,
        loading: _joining,
        onTap: _join,
      );
    }
    if (_peerDeleted) {
      return const _BottomInfo(text: 'Этот аккаунт удалён', icon: AppIcons.userX);
    }
    if (_isDirect && _blockedByMe) {
      return _BottomAction(
        label: _isBot ? 'Перезапустить бота' : 'Разблокировать',
        icon: AppIcons.userCheck,
        onTap: _toggleBlock,
        subtle: true,
      );
    }
    if (!_canSend) {
      if (_isChannel) {
        final muted = appState.isMuted(widget.chatId);
        return _BottomAction(
          label: muted ? 'Включить уведомления' : 'Выключить уведомления',
          icon: muted ? AppIcons.bell : AppIcons.bellOff,
          subtle: true,
          onTap: () {
            appState.toggleMute(widget.chatId);
            setState(() {});
          },
        );
      }
      return const _BottomInfo(
          text: 'Писать в группу могут только администраторы',
          icon: AppIcons.lock);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: (_replyTo != null || _editing != null)
              ? _replyEditBar()
              : const SizedBox(width: double.infinity),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            _InputBar(
              micHidden: _recording,
              controller: _input,
              focusNode: _inputFocus,
              hasText: _hasText,
              emojiOpen: _emojiOpen,
              hint: _isChannel
                  ? 'Публикация'
                  : (_isSupport ? 'Ответ от имени Connecto' : 'Сообщение'),
              showCommands: _isBot && _botCommands.isNotEmpty,
              onCommands: _showCommands,
              onSend: _send,
              onSendLong: _specialSend,
              onAttach: _openAttach,
              onEmoji: _toggleEmoji,
              onFieldTap: () {
                if (_emojiOpen) setState(() => _emojiOpen = false);
              },
              roundMode: appState.roundMode,
              onMicStart: _startRecording,
              onMicMove: _voiceDrag,
              onMicEnd: _voiceRelease,
              onMicTap: _toggleRecordMode,
            ),
            if (_recording && !_locked)
              Positioned.fill(child: IgnorePointer(child: FadeSlideIn(dy: 0, child: _recordingBar()))),
            if (_locked) Positioned.fill(child: FadeSlideIn(dy: 0, child: _lockedBar())),
            if (_recording && !_locked)
              Positioned(
                right: 11,
                bottom: 10 + 44 + MediaQuery.of(context).padding.bottom + 12,
                child: IgnorePointer(child: _LockPill(drag: _dragVN)),
              ),
            if (_recording)
              Positioned(
                right: -8,
                bottom: 10 + MediaQuery.of(context).padding.bottom - 18,
                child: _locked
                    ? _RecordBlob(
                        amp: _ampVN,
                        drag: _dragVN,
                        locked: true,
                        round: _roundRec,
                        onSend: () => _finishRecording(cancel: false))
                    : IgnorePointer(
                        child: _RecordBlob(
                            amp: _ampVN, drag: _dragVN, locked: false, round: _roundRec)),
              ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: _emojiOpen && !_recording
              ? _EmojiPanel(onPick: _insertEmoji, onGif: _canSend ? _sendGif : null)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _replyEditBar() {
    final editing = _editing != null;
    final m = _editing ?? _replyTo!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(editing ? AppIcons.pencil : AppIcons.reply,
                size: 20, color: appState.accent),
            const SizedBox(width: 10),
            Container(
              width: 3,
              height: 34,
              decoration: BoxDecoration(
                  color: appState.accent, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => _jumpTo(m.id),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(editing ? 'Редактирование' : 'Ответ: ${_authorOf(m)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: appState.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 13)),
                    Text(_previewOf(m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: subtleText(context), fontSize: 13)),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: Icon(AppIcons.x, color: subtleText(context), size: 20),
              onPressed: () => setState(() {
                if (editing) _input.clear();
                _replyTo = null;
                _editing = null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  /// Панель записи (палец держит кнопку): точка, таймер, «влево — отмена».
  Widget _recordingBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 70,
        padding: const EdgeInsets.fromLTRB(18, 0, 90, 0),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            _PulseDot(icon: _roundRec ? AppIcons.video : AppIcons.mic),
            const SizedBox(width: 10),
            _recClock(),
            const SizedBox(width: 12),
            Expanded(
              child: Center(child: _SlideHint(drag: _dragVN)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _recClock() => ValueListenableBuilder<Duration>(
        valueListenable: _recTimeVN,
        builder: (_, d, __) {
          final m = d.inMinutes;
          final sec = (d.inSeconds % 60).toString().padLeft(2, '0');
          final tenth = (d.inMilliseconds % 1000) ~/ 100;
          return Text('$m:$sec,$tenth',
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  fontFeatures: [FontFeature.tabularFigures()]));
        },
      );

  /// Запись «без рук»: удалить · волна · таймер · пауза · отправить.
  Widget _lockedBar() {
    return SafeArea(
      top: false,
      child: Container(
        height: 70,
        padding: const EdgeInsets.fromLTRB(6, 0, 96, 0),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Удалить',
              icon: const Icon(AppIcons.trash2, color: kDanger),
              onPressed: () => _finishRecording(cancel: true),
            ),
            _PulseDot(paused: _paused, icon: _roundRec ? AppIcons.video : AppIcons.mic),
            const SizedBox(width: 8),
            _recClock(),
            const SizedBox(width: 10),
            Expanded(
              child: _roundRec
                  ? Text(_paused ? 'Пауза' : 'Видеосообщение',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: subtleText(context), fontWeight: FontWeight.w600))
                  : AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _paused ? 0.45 : 1,
                      child: _LiveWave(
                          samples: _recSamples, listenable: _samplesVN, color: appState.accent),
                    ),
            ),
            IconButton(
              tooltip: _paused ? 'Продолжить' : 'Пауза',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: Icon(
                    _paused ? (_roundRec ? AppIcons.video : AppIcons.mic) : AppIcons.pause,
                    key: ValueKey(_paused),
                    color: appState.accent),
              ),
              onPressed: _roundRec ? _toggleRoundPause : _togglePause,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = _searchQ.trim().toLowerCase();
    final shown = (_searching && q.isNotEmpty)
        ? _messages
            .where((m) =>
                (m.kind == 'text' && m.text.toLowerCase().contains(q)) ||
                (m.fileName ?? '').toLowerCase().contains(q))
            .toList()
        : _messages;
    Message? pinnedMsg;
    for (final m in _messages) {
      if (m.pinned) pinnedMsg = m;
    }
    final bar = _appBar();
    final roundFlash = _roundRec && _torch && (_camFront || isDesktop);
    return PopScope(
      canPop: !_selectMode && !_emojiOpen && !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_selectMode) {
          _exitSelect();
        } else if (_emojiOpen) {
          setState(() => _emojiOpen = false);
        } else if (_searching) {
          setState(() {
            _searching = false;
            _searchQ = '';
            _searchCtrl.clear();
          });
        }
      },
      child: Stack(children: [
      Scaffold(
        appBar: bar,
        body: ChatBackground(
          child: _dropWrap(Column(
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: (pinnedMsg != null && !_pinHidden && !_searching)
                    ? _PinnedBanner(
                        text: _previewOf(pinnedMsg),
                        canUnpin: _canPin,
                        onClose: () => setState(() => _pinHidden = true),
                        onUnpin: () => _togglePin(pinnedMsg!),
                        onTap: () => _jumpTo(pinnedMsg!.id),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              _NowPlayingBar(chatId: widget.chatId, onTap: _jumpTo),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          if (_emojiOpen) setState(() => _emojiOpen = false);
                          _inputFocus.unfocus();
                        },
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 250),
                          child: _loading
                              ? const _ChatSkeleton()
                              : shown.isEmpty
                                  ? (_searching
                                      ? const EmptyState(
                                          icon: AppIcons.searchX,
                                          mascot: 'empty_not_found',
                                          title: 'Ничего не найдено')
                                      : _emptyHint())
                                  : _messageList(shown),
                        ),
                      ),
                    ),
                    if (_roundRec)
                      Positioned.fill(
                        child: FadeSlideIn(
                          dy: 0,
                          child: _RoundRecorderView(
                            cam: _cam,
                            ready: _roundStarted,
                            locked: _locked,
                            paused: _paused,
                            front: _camFront || isDesktop, // у веб-камеры «вспышка» — светлый экран
                            torch: _torch,
                            zoom: _zoom,
                            zoomMax: _zoomMax,
                            time: _recTimeVN,
                            onFlip: _flipRoundCam,
                            flipTick: _flipTick,
                            onTorch: _toggleTorch,
                            onZoomStep: _zoomStep,
                            onZoomStart: () => _zoomBase = _zoom,
                            onZoom: (s) => _setZoom(_zoomBase * s),
                          ),
                        ),
                      ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: AnimatedScale(
                        scale: _atBottom || _loading ? 0 : 1,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutBack,
                        child: _ScrollDownButton(
                            count: _newBelow, onTap: () => _scrollToEnd()),
                      ),
                    ),
                  ],
                ),
              ),
              // при «вспышке» фронталки панель тоже белая (дерево не меняется — запись не сбивается)
              Theme(
                data: roundFlash
                    ? Theme.of(context).copyWith(
                        scaffoldBackgroundColor: Colors.white,
                        colorScheme: Theme.of(context).colorScheme.copyWith(
                            surface: Colors.white,
                            onSurface: Colors.black87,
                            onSurfaceVariant: Colors.black54))
                    : Theme.of(context),
                child: _bottom(),
              ),
            ],
          )),
        ),
      ),
      // запись кружочка: шапка чата тоже размывается / становится белой
      if (_roundRec)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: MediaQuery.paddingOf(context).top + bar.preferredSize.height,
          child: IgnorePointer(child: _RoundShade(flash: roundFlash)),
        ),
      ]),
    );
  }
}
