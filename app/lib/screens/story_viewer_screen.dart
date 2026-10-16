import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../stories.dart';
import '../theme.dart';
import '../widgets/shared_media.dart';
import '../widgets/story_overlays.dart';
import '../widgets/ui.dart';
import 'appearance_screen.dart' show premiumGate;
import 'user_info_screen.dart';

const kStoryReactions = ['❤️', '🔥', '😂', '😮', '😢', '👍', '🎉', '😍'];

String storyAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'только что';
  if (d.inMinutes < 60) return '${d.inMinutes} мин назад';
  if (d.inHours < 24) return '${d.inHours} ч назад';
  if (d.inDays < 7) return '${d.inDays} д назад';
  return '${t.day.toString().padLeft(2, '0')}.${t.month.toString().padLeft(2, '0')}.${t.year}';
}

/// Открыть просмотр историй: [groups] — кружки, [groupIndex] — с кого начать.
Future<void> openStoryViewer(BuildContext context, List<StoryGroup> groups, int groupIndex,
    {int? startAt, bool markViews = true}) async {
  if (groups.isEmpty) return;
  await Navigator.of(context).push(PageRouteBuilder(
    opaque: false,
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) => StoryViewerScreen(
      groups: groups,
      initialGroup: math.max(0, math.min(groupIndex, groups.length - 1)),
      startAt: startAt,
      markViews: markViews,
    ),
    transitionsBuilder: (_, a, __, child) {
      final c = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: c,
        child: ScaleTransition(scale: Tween(begin: 0.9, end: 1.0).animate(c), child: child),
      );
    },
  ));
  stories.resort();
}

class StoryViewerScreen extends StatefulWidget {
  final List<StoryGroup> groups;
  final int initialGroup;
  final int? startAt;
  final bool markViews;
  const StoryViewerScreen({
    super.key,
    required this.groups,
    required this.initialGroup,
    this.startAt,
    this.markViews = true,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen> {
  late final PageController _pc = PageController(initialPage: widget.initialGroup);
  late int _page = widget.initialGroup;
  late final List<StoryGroup> _groups = List.of(widget.groups);
  double _dragY = 0;
  bool _closing = false;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    Navigator.of(context).maybePop();
  }

  void _nextGroup() {
    if (_page < _groups.length - 1) {
      _pc.nextPage(duration: const Duration(milliseconds: 380), curve: Curves.easeInOutCubic);
    } else {
      _close();
    }
  }

  void _prevGroup() {
    if (_page > 0) {
      _pc.previousPage(duration: const Duration(milliseconds: 380), curve: Curves.easeInOutCubic);
    }
  }

  void _removeGroup(StoryGroup g) {
    final i = _groups.indexOf(g);
    if (i < 0) return;
    if (_groups.length == 1) {
      _close();
      return;
    }
    setState(() => _groups.removeAt(i));
    if (_page >= _groups.length) _page = _groups.length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final t = (_dragY / 600).clamp(0.0, 1.0);
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 1 - t * 0.9),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onVerticalDragUpdate: (d) {
          if (d.delta.dy > 0 || _dragY > 0) {
            setState(() => _dragY = math.max(0, _dragY + d.delta.dy));
          }
        },
        onVerticalDragEnd: (d) {
          if (_dragY > 130 || (d.primaryVelocity ?? 0) > 800) {
            _close();
          } else {
            setState(() => _dragY = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragY),
          child: Transform.scale(
            scale: 1 - t * 0.18,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(_dragY > 0 ? 24 : 0),
              child: PageView.builder(
                controller: _pc,
                itemCount: _groups.length,
                onPageChanged: (i) => setState(() => _page = i),
                itemBuilder: (context, i) {
                  final g = _groups[i];
                  final player = _GroupPlayer(
                    key: ValueKey(g.userId),
                    group: g,
                    active: i == _page,
                    paused: _dragY > 0,
                    startAt: i == widget.initialGroup ? widget.startAt : null,
                    markViews: widget.markViews,
                    onNextGroup: _nextGroup,
                    onPrevGroup: _prevGroup,
                    onClose: _close,
                    onEmpty: () => _removeGroup(g),
                  );
                  // «куб» при перелистывании людей
                  return AnimatedBuilder(
                    animation: _pc,
                    child: player,
                    builder: (context, child) {
                      double value = 0;
                      if (_pc.hasClients && _pc.position.haveDimensions) {
                        value = (_pc.page ?? _page.toDouble()) - i;
                      }
                      value = value.clamp(-1.0, 1.0);
                      if (value == 0 || !appState.motion) return child!;
                      final leaving = value > 0;
                      return Transform(
                        alignment: leaving ? Alignment.centerRight : Alignment.centerLeft,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0012)
                          ..rotateY(-value * math.pi / 2.2),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            child!,
                            IgnorePointer(
                              child: ColoredBox(
                                  color: Colors.black.withValues(alpha: value.abs() * 0.55)),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Истории одного человека: прогресс, переходы, ответы.
class _GroupPlayer extends StatefulWidget {
  final StoryGroup group;
  final bool active;
  final bool paused;
  final int? startAt;
  final bool markViews;
  final VoidCallback onNextGroup;
  final VoidCallback onPrevGroup;
  final VoidCallback onClose;
  final VoidCallback onEmpty;
  const _GroupPlayer({
    super.key,
    required this.group,
    required this.active,
    required this.paused,
    required this.startAt,
    required this.markViews,
    required this.onNextGroup,
    required this.onPrevGroup,
    required this.onClose,
    required this.onEmpty,
  });

  @override
  State<_GroupPlayer> createState() => _GroupPlayerState();
}

class _GroupPlayerState extends State<_GroupPlayer> with TickerProviderStateMixin {
  late int _i = math.max(0,
      math.min(widget.startAt ?? widget.group.startIndex, widget.group.stories.length - 1));
  String? _endedId; // защита от двойного автоперехода
  late final AnimationController _progress =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _autoNext();
        });
  late final AnimationController _heart =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  VideoPlayerController? _video;
  AudioPlayer? _music;
  String? _musicFor; // id истории, для которой играет музыка
  bool _loading = true;
  bool _holding = false;
  bool _muted = false;
  bool _sheetOpen = false;
  String? _burst;
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();
  int _loadToken = 0;

  StoryItem get _story => widget.group.stories[_i];
  bool get _mine => widget.group.isMe || _story.mine;

  bool get _shouldPlay =>
      widget.active && !widget.paused && !_holding && !_sheetOpen && !_replyFocus.hasFocus;

  @override
  void initState() {
    super.initState();
    _replyFocus.addListener(() {
      _syncPlay();
      if (mounted) setState(() {});
    });
    _reply.addListener(() {
      if (mounted) setState(() {});
    });
    // _load использует context (precacheImage → inherited widgets) — не в initState
    if (widget.group.stories.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _load();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _GroupPlayer old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active && widget.active) {
      _endedId = null;
      _markViewed();
    }
    _syncPlay();
  }

  @override
  void dispose() {
    _progress.dispose();
    _heart.dispose();
    _video?.dispose();
    _music?.dispose();
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  void _syncPlay() {
    if (!mounted) return;
    final play = _shouldPlay && !_loading;
    final v = _video;
    final m = _music;
    if (play) {
      if (v != null) {
        if (!v.value.isPlaying) v.play();
      } else if (!_progress.isAnimating && _progress.value < 1) {
        _progress.forward();
      }
      if (m != null && m.state != PlayerState.playing) m.resume();
    } else {
      if (v != null && v.value.isPlaying) v.pause();
      if (_progress.isAnimating) _progress.stop();
      if (m != null && m.state == PlayerState.playing) m.pause();
    }
  }

  void _markViewed() {
    if (!widget.active || widget.group.stories.isEmpty) return;
    final s = _story;
    if (s.mine) return;
    if (!s.seen) {
      s.seen = true;
      stories.markSeen(s.id);
    }
    if (widget.markViews) {
      Api.viewStory(s.id, stealth: stories.stealth && appState.isPremium);
    }
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    _progress.stop();
    _progress.value = 0;
    final old = _video;
    _video = null;
    old?.removeListener(_onVideo);
    old?.dispose();
    final oldMusic = _music;
    _music = null;
    _musicFor = null;
    oldMusic?.dispose();
    setState(() => _loading = true);
    final s = _story;
    final url = mediaUrl(s.mediaUrl);
    if (s.isVideo) {
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      try {
        await c.initialize();
        if (token != _loadToken || !mounted) {
          c.dispose();
          return;
        }
        await c.setVolume(_muted || s.musicUrl != null ? 0 : 1);
        if (token != _loadToken || !mounted) {
          c.dispose();
          return;
        }
        c.addListener(_onVideo);
        _video = c;
        final dur = c.value.duration;
        _progress.duration =
            dur.inMilliseconds > 0 ? dur : const Duration(seconds: 15);
      } catch (_) {
        c.dispose();
        if (token != _loadToken || !mounted) return;
        _progress.duration = const Duration(seconds: 4);
      }
    } else {
      // с музыкой фото показываем дольше
      _progress.duration = Duration(seconds: s.musicUrl != null ? 15 : 6);
      try {
        await precacheImage(NetworkImage(url), context);
      } catch (_) {}
      if (token != _loadToken || !mounted) return;
    }
    // музыка истории
    if (s.musicUrl != null) {
      try {
        final p = AudioPlayer();
        await p.setReleaseMode(ReleaseMode.loop);
        await p.setVolume(_muted ? 0 : 1);
        await p.setSource(UrlSource(mediaUrl(s.musicUrl)));
        if (token != _loadToken || !mounted) {
          p.dispose();
          return;
        }
        _music = p;
        _musicFor = s.id;
      } catch (_) {}
    }
    // заранее подгружаем следующую картинку
    if (_i + 1 < widget.group.stories.length) {
      final n = widget.group.stories[_i + 1];
      if (!n.isVideo && mounted) {
        precacheImage(NetworkImage(mediaUrl(n.mediaUrl)), context).catchError((_) {});
      }
    }
    setState(() => _loading = false);
    _markViewed();
    _syncPlay();
  }

  void _onVideo() {
    final c = _video;
    if (c == null) return;
    final v = c.value;
    if (!v.isInitialized || v.duration.inMilliseconds == 0) return;
    final f = v.position.inMilliseconds / v.duration.inMilliseconds;
    _progress.value = f.clamp(0.0, 0.999);
    if (v.position >= v.duration && !v.isPlaying) _autoNext();
  }

  void _autoNext() {
    if (widget.group.stories.isEmpty || _endedId == _story.id) return;
    _endedId = _story.id;
    _next();
  }

  void _next() {
    if (!mounted) return;
    if (_i < widget.group.stories.length - 1) {
      setState(() => _i++);
      _load();
    } else {
      widget.onNextGroup();
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _load();
    } else {
      widget.onPrevGroup();
      _progress.value = 0;
      _video?.seekTo(Duration.zero);
      _syncPlay();
    }
  }

  // ── действия ──

  Future<void> _react(String emoji) async {
    HapticFeedback.mediumImpact();
    final s = _story;
    final off = s.myReaction == emoji;
    setState(() {
      s.myReaction = off ? null : emoji;
      _burst = off ? null : emoji;
    });
    if (!off) _heart.forward(from: 0);
    try {
      await Api.reactStory(s.id, off ? null : emoji);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty) return;
    final s = _story;
    _reply.clear();
    _replyFocus.unfocus();
    try {
      final chat = await Api.createChat(type: 'direct', memberIds: [widget.group.userId]);
      await Api.sendMessage(chat['id'] as String, text: text, storyId: s.id);
      if (mounted) toast(context, 'Ответ отправлен', icon: AppIcons.send);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<T?> _sheet<T>(Widget Function(BuildContext) builder, {bool scrollable = false}) async {
    setState(() => _sheetOpen = true);
    _syncPlay();
    final r = await showAppSheet<T>(context, builder: builder, scrollable: scrollable);
    if (mounted) {
      setState(() => _sheetOpen = false);
      _syncPlay();
    }
    return r;
  }

  Future<void> _openViewers() async {
    final s = _story;
    await _sheet((ctx) => _ViewersSheet(story: s), scrollable: true);
  }

  Future<void> _togglePin() async {
    final s = _story;
    try {
      final r = await Api.pinStory(s.id, !s.pinned);
      s.pinned = r['pinned'] == true;
      if (mounted) {
        setState(() {});
        toast(context, s.pinned ? 'История добавлена в профиль' : 'Убрана из профиля',
            icon: AppIcons.pin);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete() async {
    setState(() => _sheetOpen = true);
    _syncPlay();
    final ok = await confirm(context,
        title: 'Удалить историю?',
        body: 'Она пропадёт у всех, в том числе из профиля.',
        action: 'Удалить',
        danger: true);
    if (!mounted) return;
    setState(() => _sheetOpen = false);
    if (!ok) {
      _syncPlay();
      return;
    }
    final s = _story;
    try {
      await Api.deleteStory(s.id);
      stories.refreshSoon();
      if (!mounted) return;
      widget.group.stories.removeAt(_i);
      if (widget.group.stories.isEmpty) {
        widget.onEmpty();
        return;
      }
      if (_i >= widget.group.stories.length) _i = widget.group.stories.length - 1;
      setState(() {});
      _load();
      if (mounted) toast(context, 'История удалена', icon: AppIcons.trash2);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
      _syncPlay();
    }
  }

  Future<void> _more() async {
    final s = _story;
    await _sheet((ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_mine) ...[
              SheetItem(
                icon: AppIcons.eye,
                title: 'Просмотры',
                subtitle: '${s.viewsCount} · реакций ${s.reactionsCount}',
                onTap: () {
                  Navigator.pop(ctx);
                  _openViewers();
                },
              ),
              SheetItem(
                icon: AppIcons.pin,
                title: s.pinned ? 'Убрать из профиля' : 'Показывать в профиле',
                onTap: () {
                  Navigator.pop(ctx);
                  _togglePin();
                },
              ),
              SheetItem(
                icon: AppIcons.trash2,
                title: 'Удалить историю',
                danger: true,
                onTap: () {
                  Navigator.pop(ctx);
                  _delete();
                },
              ),
            ] else ...[
              SheetItem(
                icon: AppIcons.user,
                title: 'Открыть профиль',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => UserInfoScreen(
                              userId: widget.group.userId, name: widget.group.name)));
                },
              ),
              SheetItem(
                icon: AppIcons.incognito,
                title: stories.stealth ? 'Выключить инкогнито' : 'Режим инкогнито',
                subtitle: 'Смотреть истории так, чтобы автор не узнал · Premium',
                onTap: () {
                  Navigator.pop(ctx);
                  if (!appState.isPremium) {
                    premiumGate(context, 'Режим инкогнито');
                    return;
                  }
                  stories.stealth = !stories.stealth;
                  toast(context,
                      stories.stealth ? 'Инкогнито включён' : 'Инкогнито выключен',
                      icon: AppIcons.incognito);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ));
  }

  // ── интерфейс ──

  Widget _media() {
    final s = _story;
    final v = _video;
    if (s.isVideo) {
      if (v == null || !v.value.isInitialized) return const SizedBox.expand();
      return Center(
        child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)),
      );
    }
    final url = mediaUrl(s.mediaUrl);
    return Stack(
      fit: StackFit.expand,
      children: [
        // размытый фон под картинкой другого формата
        ImageFiltered(
          imageFilter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Image.network(url, fit: BoxFit.cover, gaplessPlayback: true,
              errorBuilder: (_, __, ___) => const SizedBox()),
        ),
        ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
        Image.network(url,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => const Center(
                child: Icon(AppIcons.imageOff, color: Colors.white54, size: 48))),
      ],
    );
  }

  Widget _bars() {
    final n = widget.group.stories.length;
    return AnimatedBuilder(
      animation: _progress,
      builder: (_, __) => Row(
        children: [
          for (var k = 0; k < n; k++)
            Expanded(
              child: Container(
                height: 2.8,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: k < _i ? 1 : (k == _i ? _progress.value : 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() {
    final g = widget.group;
    final s = _story;
    return Row(
      children: [
        GestureDetector(
          onTap: _mine
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => UserInfoScreen(userId: g.userId, name: g.name))),
          child: Avatar(name: g.name, url: g.avatarUrl, size: 38),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_mine ? 'Моя история' : g.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      shadows: [Shadow(blurRadius: 8)])),
              Row(
                children: [
                  Text(storyAgo(s.createdAt),
                      style: const TextStyle(
                          color: Colors.white70, fontSize: 12.5, shadows: [Shadow(blurRadius: 8)])),
                  if (s.audience == 'contacts') ...[
                    const SizedBox(width: 6),
                    const Icon(AppIcons.users, size: 13, color: Colors.white70),
                  ],
                  if (s.pinned) ...[
                    const SizedBox(width: 6),
                    const Icon(AppIcons.pin, size: 13, color: Colors.white70),
                  ],
                  if (!s.active) ...[
                    const SizedBox(width: 6),
                    const Text('· в профиле',
                        style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (s.isVideo || s.musicUrl != null)
          _RoundBtn(
            icon: _muted ? AppIcons.volumeOff : AppIcons.volume2,
            onTap: () {
              setState(() => _muted = !_muted);
              _video?.setVolume(_muted || s.musicUrl != null ? 0 : 1);
              _music?.setVolume(_muted ? 0 : 1);
            },
          ),
        _RoundBtn(icon: AppIcons.ellipsisVertical, onTap: _more),
        _RoundBtn(icon: AppIcons.x, onTap: widget.onClose),
      ],
    );
  }

  Widget _bottom() {
    final s = _story;
    if (_mine) {
      return Row(
        children: [
          Pressable(
            onTap: _openViewers,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(AppIcons.eye, color: Colors.white, size: 19),
                  const SizedBox(width: 7),
                  Text('${s.viewsCount}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  if (s.reactionsCount > 0) ...[
                    const SizedBox(width: 12),
                    const Text('❤️', style: TextStyle(fontSize: 15)),
                    const SizedBox(width: 4),
                    Text('${s.reactionsCount}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ],
                ],
              ),
            ),
          ),
          const Spacer(),
          _RoundBtn(
              icon: s.pinned ? AppIcons.pinOff : AppIcons.pin,
              filled: true,
              onTap: _togglePin),
          const SizedBox(width: 8),
          _RoundBtn(icon: AppIcons.trash2, filled: true, onTap: _delete),
        ],
      );
    }
    final typing = _replyFocus.hasFocus || _reply.text.isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: typing
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      for (final e in kStoryReactions)
                        Pressable(
                          scale: 0.8,
                          onTap: () {
                            _replyFocus.unfocus();
                            _react(e);
                          },
                          child: Text(e, style: const TextStyle(fontSize: 30)),
                        ),
                    ],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                ),
                child: TextField(
                  controller: _reply,
                  focusNode: _replyFocus,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: Colors.white,
                  maxLength: 1000,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _sendReply(),
                  decoration: const InputDecoration(
                    hintText: 'Ответить…',
                    hintStyle: TextStyle(color: Colors.white70),
                    counterText: '',
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: _reply.text.trim().isNotEmpty
                  ? _RoundBtn(
                      key: const ValueKey('send'),
                      icon: AppIcons.send,
                      filled: true,
                      accent: true,
                      onTap: _sendReply)
                  : GestureDetector(
                      key: const ValueKey('heart'),
                      onTap: () => _react('❤️'),
                      onLongPress: () => _replyFocus.requestFocus(),
                      child: AnimatedScale(
                        scale: s.myReaction != null ? 1.12 : 1,
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.elasticOut,
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: s.myReaction != null
                              ? Text(s.myReaction!, style: const TextStyle(fontSize: 28))
                              : const Icon(AppIcons.heart, color: Colors.white, size: 30),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.group.stories.isEmpty) return const SizedBox();
    final s = _story;
    final pad = MediaQuery.of(context).padding;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        // медиа + жесты
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (_replyFocus.hasFocus) {
              _replyFocus.unfocus();
              return;
            }
            final w = MediaQuery.of(context).size.width;
            if (d.globalPosition.dx < w * 0.3) {
              _prev();
            } else {
              _next();
            }
          },
          onLongPressStart: (_) {
            setState(() => _holding = true);
            _syncPlay();
          },
          onLongPressEnd: (_) {
            setState(() => _holding = false);
            _syncPlay();
          },
          onDoubleTap: _mine ? null : () => _react('❤️'),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: KeyedSubtree(
              key: ValueKey(s.id),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _media(),
                  // текст, стикеры, погода — поверх медиа
                  if (s.overlays.isNotEmpty && !_loading)
                    IgnorePointer(child: StoryOverlayLayer(overlays: s.overlays)),
                ],
              ),
            ),
          ),
        ),
        if (_loading)
          const Center(
            child: SizedBox(
                width: 34,
                height: 34,
                child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white)),
          ),
        // верхняя тень, прогресс и шапка
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          child: IgnorePointer(
            ignoring: false,
            child: AnimatedOpacity(
              opacity: _holding ? 0 : 1,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: EdgeInsets.fromLTRB(8, pad.top + 8, 6, 24),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
                child: Column(
                  children: [
                    _bars(),
                    const SizedBox(height: 10),
                    _header(),
                  ],
                ),
              ),
            ),
          ),
        ),
        // подпись и ответ
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedOpacity(
            opacity: _holding ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            child: Container(
              padding: EdgeInsets.fromLTRB(12, 40, 12, pad.bottom + 12),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Color(0xB3000000), Color(0x00000000)],
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (s.musicTitle != null && _musicFor == s.id)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                        child: _MusicBadge(title: s.musicTitle!, playing: !_holding),
                      ),
                    ),
                  if (s.caption.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 14),
                      child: Text(s.caption,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15.5,
                              height: 1.35,
                              shadows: [Shadow(blurRadius: 10)])),
                    ),
                  _bottom(),
                ],
              ),
            ),
          ),
        ),
        // вспышка реакции
        if (_burst != null)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _heart,
              builder: (_, __) {
                final t = _heart.value;
                if (t == 0 || t == 1) return const SizedBox();
                final scale = Curves.elasticOut.transform(math.min(1.0, t * 1.6));
                final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3);
                return Center(
                  child: Opacity(
                    opacity: opacity.clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, -60 * t),
                      child: Transform.scale(
                        scale: 0.4 + scale * 1.2,
                        child: Text(_burst!, style: const TextStyle(fontSize: 90)),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool accent;
  const _RoundBtn(
      {super.key, required this.icon, required this.onTap, this.filled = false, this.accent = false});

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onTap: onTap,
      scale: 0.88,
      child: Container(
        width: filled ? 46 : 40,
        height: filled ? 46 : 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: accent ? accentGradient(appState.accent) : null,
          color: accent ? null : (filled ? Colors.white.withValues(alpha: 0.14) : null),
        ),
        child: Icon(icon, color: Colors.white, size: 22, shadows: const [Shadow(blurRadius: 8)]),
      ),
    );
  }
}

/// Кто посмотрел историю и какие реакции поставил.
class _ViewersSheet extends StatefulWidget {
  final StoryItem story;
  const _ViewersSheet({required this.story});
  @override
  State<_ViewersSheet> createState() => _ViewersSheetState();
}

class _ViewersSheetState extends State<_ViewersSheet> {
  List<dynamic>? _rows;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Api.storyViewers(widget.story.id);
      if (mounted) setState(() => _rows = r);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
            child: Row(
              children: [
                const IconTile(AppIcons.eye, size: 34),
                const SizedBox(width: 12),
                Text(
                    rows == null
                        ? 'Просмотры'
                        : 'Просмотры · ${rows.length}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(_error!, textAlign: TextAlign.center),
            )
          else if (rows == null)
            const Padding(
                padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 30),
              child: Text('Пока никто не посмотрел.\nЗагляни чуть позже 🙂',
                  textAlign: TextAlign.center, style: TextStyle(color: subtleText(context))),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (context, i) {
                  final r = (rows[i] as Map).cast<String, dynamic>();
                  final u = (r['user'] as Map).cast<String, dynamic>();
                  final at = parseServerTime(r['viewed_at'] as String? ?? '');
                  return FadeSlideIn(
                    delayMs: 25 * math.min(i, 12),
                    child: ListTile(
                      leading: Avatar(
                          name: u['display_name'] as String? ?? '?',
                          url: u['avatar_url'] as String?,
                          size: 42),
                      title: NameBadges(u['display_name'] as String? ?? '',
                          premium: u['is_premium'] == true,
                          verified: u['is_verified'] == true,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: at == null
                          ? null
                          : Text(storyAgo(at), style: TextStyle(color: subtleText(context))),
                      trailing: r['reaction'] != null
                          ? Text(r['reaction'] as String, style: const TextStyle(fontSize: 24))
                          : null,
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => UserInfoScreen(
                                    userId: u['id'] as String,
                                    name: u['display_name'] as String? ?? '')));
                      },
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}


/// Плашка «сейчас играет» с прыгающими столбиками.
class _MusicBadge extends StatefulWidget {
  final String title;
  final bool playing;
  const _MusicBadge({required this.title, required this.playing});
  @override
  State<_MusicBadge> createState() => _MusicBadgeState();
}

class _MusicBadgeState extends State<_MusicBadge> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

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
    return Container(
      constraints: const BoxConstraints(maxWidth: 240),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (_, __) => Row(
              children: [
                for (var i = 0; i < 3; i++)
                  Container(
                    width: 3,
                    height: widget.playing
                        ? 5 + 9 * (0.5 + 0.5 * math.sin(_c.value * 2 * math.pi + i * 1.7))
                        : 4,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(2)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
