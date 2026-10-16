import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../io/local_files.dart';
import '../stories.dart';
import '../theme.dart';
import '../widgets/effects.dart' show videoDuration;
import '../widgets/music_search.dart';
import '../widgets/shared_media.dart' show mediaUrl;
import '../widgets/story_overlays.dart';
import '../widgets/ui.dart';
import 'appearance_screen.dart' show premiumGate;
import 'premium_screen.dart';

const int kFreeStoryVideoSec = 30;
const int kPremiumStoryVideoSec = 60;

String _fmtDate(String? iso) {
  final d = parseServerTime(iso ?? '');
  if (d == null) return '';
  const m = ['янв', 'фев', 'мар', 'апр', 'мая', 'июн', 'июл', 'авг', 'сен', 'окт', 'ноя', 'дек'];
  return '${d.day} ${m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// Новая история: проверка лимита → выбор фото/видео → редактор.
Future<void> openStoryCreate(BuildContext context) async {
  Map<String, dynamic> lim = stories.limits;
  try {
    lim = await Api.storyLimits();
    stories.limits = lim;
  } catch (_) {}
  if (!context.mounted) return;
  final left = (lim['left'] as num?)?.toInt() ?? 1;
  if (left <= 0) {
    final premium = lim['premium'] == true;
    showAppSheet(context, builder: (ctx) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const IconTile(AppIcons.hourglass, size: 64),
            const SizedBox(height: 14),
            Text(premium ? 'Лимит на сегодня' : 'Истории на этой неделе закончились',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
                premium
                    ? 'С Premium можно до ${lim['limit']} историй в день. Попробуй завтра.'
                    : 'Без Premium — ${lim['limit']} истории в неделю. '
                        'Следующую можно выложить ${_fmtDate(lim['next_at'] as String?)}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subtleText(ctx), height: 1.4)),
            const SizedBox(height: 18),
            if (!premium)
              PrimaryButton(
                label: 'Истории без ограничений',
                gradient: kPremiumGradient,
                icon: AppIcons.star,
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                      context, MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
              ),
          ],
        ),
      );
    });
    return;
  }
  final src = await showAppSheet<String>(context, builder: (ctx) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 2),
          child: Row(
            children: [
              const Text('Новая история',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const Spacer(),
              if (lim['premium'] != true)
                Text('осталось $left из ${lim['limit'] ?? 2}',
                    style: TextStyle(color: subtleText(ctx), fontSize: 12.5)),
            ],
          ),
        ),
        SheetItem(
            icon: AppIcons.gallery,
            title: 'Фото из галереи',
            onTap: () => Navigator.pop(ctx, 'photo')),
        SheetItem(
            icon: AppIcons.camera,
            title: 'Снять фото',
            onTap: () => Navigator.pop(ctx, 'camera')),
        SheetItem(
            icon: AppIcons.video,
            title: 'Видео из галереи',
            subtitle: 'До ${appState.isPremium ? kPremiumStoryVideoSec : kFreeStoryVideoSec} секунд',
            onTap: () => Navigator.pop(ctx, 'video')),
        SheetItem(
            icon: AppIcons.clapperboard,
            title: 'Снять видео',
            onTap: () => Navigator.pop(ctx, 'camvideo')),
        const SizedBox(height: 8),
      ],
    );
  });
  if (src == null || !context.mounted) return;
  final picker = ImagePicker();
  final maxSec = appState.isPremium ? kPremiumStoryVideoSec : kFreeStoryVideoSec;
  XFile? x;
  var kind = 'image';
  try {
    switch (src) {
      case 'photo':
        x = await picker.pickImage(
            source: ImageSource.gallery, imageQuality: 90, maxWidth: 1440);
      case 'camera':
        x = await picker.pickImage(source: ImageSource.camera, imageQuality: 90, maxWidth: 1440);
      case 'video':
        kind = 'video';
        x = await picker.pickVideo(
            source: ImageSource.gallery, maxDuration: Duration(seconds: maxSec));
      default:
        kind = 'video';
        x = await picker.pickVideo(
            source: ImageSource.camera, maxDuration: Duration(seconds: maxSec));
    }
  } catch (_) {
    if (context.mounted) toast(context, 'Не удалось открыть галерею', error: true);
    return;
  }
  if (x == null || !context.mounted) return;
  if (kind == 'video') {
    final d = await videoDuration(x.path);
    if (!context.mounted) return;
    if (d != null && d.inMilliseconds > (maxSec + 1) * 1000) {
      if (appState.isPremium) {
        toast(context, 'Видео для истории — до $maxSec секунд', error: true);
      } else {
        premiumGate(context, 'Видео до $kPremiumStoryVideoSec секунд');
      }
      return;
    }
  }
  await Navigator.push(
    context,
    MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryComposeScreen(path: x!.path, kind: kind)),
  );
}

/// Редактор: превью, текст с эффектами, стикеры, погода, время, музыка,
/// подпись, кому показывать, в профиль, срок.
class StoryComposeScreen extends StatefulWidget {
  final String path;
  final String kind;
  const StoryComposeScreen({super.key, required this.path, required this.kind});

  @override
  State<StoryComposeScreen> createState() => _StoryComposeScreenState();
}

class _StoryComposeScreenState extends State<StoryComposeScreen> {
  final _caption = TextEditingController();
  VideoPlayerController? _video;
  String _audience = 'all';
  bool _pinned = false;
  int _hours = 24;
  bool _busy = false;
  String _stage = '';

  // наложения
  final List<Map<String, dynamic>> _overlays = [];
  int? _dragging;
  bool _overTrash = false;
  double _baseScale = 1, _baseRot = 0;

  // музыка
  String? _musicPath; // свой файл с устройства (загрузим при публикации)
  String? _musicUrl; // отрывок из поиска — уже у нас на сервере
  String? _musicTitle;
  String? _musicName; // имя файла (для загрузки из браузера)
  AudioPlayer? _music;
  bool get _hasMusic => _musicPath != null || _musicUrl != null;

  bool get _isVideo => widget.kind == 'video';

  @override
  void initState() {
    super.initState();
    if (_isVideo) _initVideo();
  }

  Future<void> _initVideo() async {
    final c = localVideo(widget.path);
    try {
      await c.initialize();
      await c.setLooping(true);
      if (_music != null) await c.setVolume(0); // уже выбрана музыка
      await c.play();
      if (!mounted) {
        c.dispose();
        return;
      }
      setState(() => _video = c);
    } catch (_) {
      c.dispose();
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _video?.dispose();
    _music?.dispose();
    super.dispose();
  }

  // ── текст ──

  Future<void> _editText([int? index]) async {
    final cur = index != null ? _overlays[index] : null;
    final r = await Navigator.of(context).push<Map<String, dynamic>>(PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => _TextEditor(initial: cur),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (!mounted || r == null) return;
    setState(() {
      final empty = (r['text'] as String? ?? '').trim().isEmpty;
      if (index != null) {
        if (empty) {
          _overlays.removeAt(index);
        } else {
          _overlays[index] = {..._overlays[index], ...r};
        }
      } else if (!empty) {
        _overlays.add({'type': 'text', 'x': 0.5, 'y': 0.42, 'scale': 1.0, 'rot': 0.0, ...r});
      }
    });
  }

  // ── стикеры и виджеты ──

  Future<void> _stickers() async {
    final r = await showAppSheet<Map<String, dynamic>>(context,
        scrollable: true, builder: (ctx) => const _StickerSheet());
    if (!mounted || r == null) return;
    if (r['type'] == 'music') {
      _pickMusic();
      return;
    }
    if (r['type'] == 'weather') {
      await _addWeather();
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _overlays.add({'x': 0.5, 'y': 0.5, 'scale': 1.0, 'rot': 0.0, ...r}));
  }

  Future<void> _addWeather() async {
    toast(context, 'Узнаём погоду…', icon: AppIcons.globe);
    double? lat, lon;
    try {
      if (await Geolocator.isLocationServiceEnabled()) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.always || perm == LocationPermission.whileInUse) {
          final pos = await Geolocator.getCurrentPosition(
              locationSettings: const LocationSettings(accuracy: LocationAccuracy.low))
              .timeout(const Duration(seconds: 8));
          lat = pos.latitude;
          lon = pos.longitude;
        }
      }
    } catch (_) {}
    try {
      final w = await Api.weather(lat: lat, lon: lon);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      setState(() => _overlays.add({
            'type': 'weather',
            'temp': w['temp'],
            'emoji': w['emoji'],
            'text': w['text'],
            'city': w['city'],
            'style': 'glass',
            'x': 0.5,
            'y': 0.3,
            'scale': 1.0,
            'rot': 0.0,
          }));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  // ── музыка ──

  /// Музыка: найти трек (отрывок 30 с) или взять файл с устройства.
  Future<void> _pickMusic() async {
    final how = await showAppSheet<String>(context, builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SheetItem(
            icon: AppIcons.search,
            title: 'Найти трек',
            onTap: () => Navigator.pop(ctx, 'search')),
        SheetItem(
            icon: AppIcons.file,
            title: 'Файл с устройства',
            onTap: () => Navigator.pop(ctx, 'file')),
        const SizedBox(height: 6),
      ]);
    });
    if (!mounted || how == null) return;
    if (how == 'search') {
      await _searchMusic();
    } else {
      await _pickMusicFile();
    }
  }

  Future<void> _searchMusic() async {
    final t = await showMusicSearch(context);
    if (!mounted || t == null) return;
    toast(context, 'Загружаем отрывок…', icon: AppIcons.headphones);
    try {
      final up = await Api.musicImport(t['preview'] as String);
      final url = up['url'] as String;
      final artist = (t['artist'] as String? ?? '').trim();
      final name = (t['title'] as String? ?? '').trim();
      _music?.dispose();
      _music = null;
      final p = AudioPlayer();
      try {
        await p.setReleaseMode(ReleaseMode.loop);
        await p.play(UrlSource(mediaUrl(url)));
      } catch (_) {
        p.dispose();
        rethrow;
      }
      if (!mounted) {
        p.dispose();
        return;
      }
      _video?.setVolume(0);
      setState(() {
        _music = p;
        _musicUrl = url;
        _musicPath = null;
        _musicTitle = artist.isEmpty ? name : '$artist — $name';
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _pickMusicFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.audio, withData: kIsWeb);
      final f = res?.files.single;
      if (f == null || !mounted) return;
      // в браузере у файла нет пути — держим байты в памяти (blob:-ссылка)
      final local = kIsWeb
          ? (f.bytes == null ? null : await writeTempBytes(f.bytes!, f.name))
          : f.path;
      if (local == null || !mounted) return;
      final size = f.size;
      if (size > 25 * 1024 * 1024) {
        toast(context, 'Трек больше 25 МБ — выбери покороче', error: true);
        return;
      }
      var title = f.name;
      final dot = title.lastIndexOf('.');
      if (dot > 0) title = title.substring(0, dot);
      _music?.dispose();
      _music = null;
      final p = AudioPlayer();
      try {
        await p.setReleaseMode(ReleaseMode.loop);
        await p.play(localAudio(local));
      } catch (_) {
        p.dispose();
        rethrow;
      }
      if (!mounted) {
        p.dispose();
        return;
      }
      _video?.setVolume(0);
      setState(() {
        _music = p;
        _musicPath = local;
        _musicName = f.name;
        _musicUrl = null;
        _musicTitle = title;
      });
    } catch (_) {
      if (mounted) toast(context, 'Не удалось открыть музыку', error: true);
    }
  }

  void _removeMusic() {
    _music?.dispose();
    _video?.setVolume(1);
    setState(() {
      _music = null;
      _musicPath = null;
      _musicUrl = null;
      _musicTitle = null;
    });
  }

  // ── публикация ──

  Future<void> _publish() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _stage = 'Загружаем…';
    });
    try {
      final up = await Api.uploadPath(widget.path);
      String? musicUrl = _musicUrl;
      if (musicUrl == null && _musicPath != null) {
        if (mounted) setState(() => _stage = 'Музыка…');
        final mu = await Api.uploadPath(_musicPath!, fileName: _musicName);
        musicUrl = mu['url'] as String?;
      }
      if (!mounted) return;
      setState(() => _stage = 'Публикуем…');
      final r = await Api.createStory(
        mediaUrl: up['url'] as String,
        kind: widget.kind,
        caption: _caption.text.trim(),
        audience: _audience,
        pinned: _pinned,
        hours: _hours,
        overlays: _overlays,
        musicUrl: musicUrl,
        musicTitle: musicUrl != null ? _musicTitle : null,
      );
      final lim = r['limits'];
      if (lim is Map) stories.limits = lim.cast<String, dynamic>();
      await stories.refresh();
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context);
      toast(context, 'История опубликована', icon: AppIcons.stories);
    } catch (e) {
      if (mounted) {
        toast(context, friendlyError(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Widget _chip(String label, bool on, VoidCallback onTap, {IconData? icon, bool locked = false}) {
    return Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: on ? Colors.black : Colors.white),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                    color: on ? Colors.black : Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
            if (locked) ...[
              const SizedBox(width: 4),
              const Icon(AppIcons.star, size: 14, color: kPremium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _tool(IconData icon, String label, VoidCallback onTap, {bool active = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Pressable(
        onTap: onTap,
        scale: 0.88,
        child: Column(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: active ? Colors.white : Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: active ? Colors.black : Colors.white, size: 23),
            ),
            const SizedBox(height: 3),
            Text(label,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(blurRadius: 6)])),
          ],
        ),
      ),
    );
  }

  /// Элемент, который можно таскать, щипать и крутить.
  Widget _editable(int i, Size size) {
    final o = _overlays[i];
    return placeOverlay(
      o,
      size,
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (o['type'] == 'text') {
            _editText(i);
          } else if (o['type'] == 'weather' || o['type'] == 'time') {
            // смена оформления виджета
            final cur = kChipStyles.indexOf(o['style'] as String? ?? 'glass');
            setState(() => o['style'] = kChipStyles[(cur + 1) % kChipStyles.length]);
            HapticFeedback.selectionClick();
          }
        },
        onScaleStart: (d) {
          _baseScale = ((o['scale'] as num?) ?? 1).toDouble();
          _baseRot = ((o['rot'] as num?) ?? 0).toDouble();
          setState(() => _dragging = i);
        },
        onScaleUpdate: (d) {
          final trashY = size.height - 110;
          final over = (d.focalPoint.dy > trashY) &&
              (d.focalPoint.dx - size.width / 2).abs() < 70;
          if (over != _overTrash) HapticFeedback.selectionClick();
          setState(() {
            o['x'] = (((o['x'] as num?) ?? 0.5) + d.focalPointDelta.dx / size.width).clamp(0.0, 1.0);
            o['y'] = (((o['y'] as num?) ?? 0.5) + d.focalPointDelta.dy / size.height).clamp(0.0, 1.0);
            if (d.pointerCount > 1) {
              o['scale'] = (_baseScale * d.scale).clamp(0.35, 4.0);
              o['rot'] = _baseRot + d.rotation;
            }
            _overTrash = over;
          });
        },
        onScaleEnd: (_) {
          setState(() {
            if (_overTrash && _dragging != null && _dragging! < _overlays.length) {
              _overlays.removeAt(_dragging!);
              HapticFeedback.mediumImpact();
            }
            _dragging = null;
            _overTrash = false;
          });
        },
        child: StoryOverlayView(data: o, maxWidth: size.width * 0.86),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final premium = appState.isPremium;
    final v = _video;
    final dragging = _dragging != null;
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: false,
      body: LayoutBuilder(builder: (context, c) {
        final size = c.biggest;
        return Stack(
          fit: StackFit.expand,
          children: [
            // превью
            if (_isVideo)
              v == null
                  ? const Center(child: CircularProgressIndicator(color: Colors.white))
                  : Center(
                      child: AspectRatio(aspectRatio: v.value.aspectRatio, child: VideoPlayer(v)))
            else
              localImage(widget.path, fit: BoxFit.contain),
            // наложения
            for (var i = 0; i < _overlays.length; i++) _editable(i, size),
            // шапка
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              top: dragging ? -120 : 0,
              left: 0,
              right: 0,
              child: Container(
                padding: EdgeInsets.fromLTRB(8, pad.top + 6, 12, 18),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x99000000), Color(0x00000000)],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(AppIcons.x, color: Colors.white),
                      onPressed: _busy ? null : () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    _chip(_audience == 'all' ? 'Все' : 'Контакты', true, () {
                      setState(() => _audience = _audience == 'all' ? 'contacts' : 'all');
                    }, icon: _audience == 'all' ? AppIcons.globe : AppIcons.users),
                  ],
                ),
              ),
            ),
            // инструменты справа
            AnimatedPositioned(
              duration: const Duration(milliseconds: 200),
              right: dragging ? -80 : 10,
              top: pad.top + 70,
              child: Column(
                children: [
                  _tool(AppIcons.type, 'Текст', () => _editText()),
                  _tool(AppIcons.smile, 'Стикеры', _stickers),
                  _tool(AppIcons.headphones, 'Музыка', !_hasMusic ? _pickMusic : _removeMusic,
                      active: _hasMusic),
                ],
              ),
            ),
            // музыка
            if (_musicTitle != null && !dragging)
              Positioned(
                left: 12,
                top: pad.top + 70,
                child: GestureDetector(
                  onTap: _removeMusic,
                  child: _MusicChip(title: _musicTitle!, removable: true),
                ),
              ),
            // корзина при перетаскивании
            if (dragging)
              Positioned(
                left: 0,
                right: 0,
                bottom: 40 + pad.bottom,
                child: Center(
                  child: AnimatedScale(
                    scale: _overTrash ? 1.3 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: _overTrash ? kDanger : Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.6)),
                      ),
                      child: const Icon(AppIcons.trash2, color: Colors.white),
                    ),
                  ),
                ),
              ),
            // низ: настройки и подпись
            if (!dragging)
              Positioned(
                left: 0,
                right: 0,
                bottom: MediaQuery.of(context).viewInsets.bottom,
                child: Container(
                  padding: EdgeInsets.fromLTRB(
                      12, 30, 12, (MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : pad.bottom + 12)),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0xCC000000), Color(0x00000000)],
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _chip('В профиль', _pinned, () => setState(() => _pinned = !_pinned),
                                icon: AppIcons.pin),
                            const SizedBox(width: 8),
                            for (final h in const [6, 12, 24, 48]) ...[
                              _chip('$h ч', _hours == h, () {
                                if (h != 24 && !premium) {
                                  premiumGate(context, 'Срок истории $h ч');
                                  return;
                                }
                                setState(() => _hours = h);
                              }, locked: h != 24 && !premium),
                              const SizedBox(width: 8),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: _caption,
                                enabled: !_busy,
                                minLines: 1,
                                maxLines: 4,
                                maxLength: 500,
                                style: const TextStyle(color: Colors.white),
                                cursorColor: Colors.white,
                                textCapitalization: TextCapitalization.sentences,
                                decoration: const InputDecoration(
                                  hintText: 'Добавить подпись…',
                                  hintStyle: TextStyle(color: Colors.white70),
                                  counterText: '',
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  disabledBorder: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(vertical: 13),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Pressable(
                            onTap: _busy ? null : _publish,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 50,
                              padding: EdgeInsets.symmetric(horizontal: _busy ? 16 : 20),
                              decoration: BoxDecoration(
                                gradient: accentGradient(appState.accent),
                                borderRadius: BorderRadius.circular(25),
                                boxShadow: [
                                  BoxShadow(
                                      color: appState.accent.withValues(alpha: 0.5),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6)),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_busy)
                                    const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2.2, color: Colors.white))
                                  else
                                    const Icon(AppIcons.send, color: Colors.white, size: 20),
                                  const SizedBox(width: 8),
                                  Text(_busy ? _stage : 'Опубликовать',
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w800)),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// Плашка «музыка» на истории.
class _MusicChip extends StatelessWidget {
  final String title;
  final bool removable;
  const _MusicChip({required this.title, this.removable = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🎵', style: TextStyle(fontSize: 15)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
          ),
          if (removable) ...[
            const SizedBox(width: 6),
            const Icon(AppIcons.x, color: Colors.white70, size: 16),
          ],
        ],
      ),
    );
  }
}

/// Редактор текста: стиль, шрифт, цвет.
class _TextEditor extends StatefulWidget {
  final Map<String, dynamic>? initial;
  const _TextEditor({this.initial});
  @override
  State<_TextEditor> createState() => _TextEditorState();
}

class _TextEditorState extends State<_TextEditor> {
  late final _c = TextEditingController(text: widget.initial?['text'] as String? ?? '');
  late String _style = widget.initial?['style'] as String? ?? 'plain';
  late String _font = widget.initial?['font'] as String? ?? kStoryFonts.first;
  late String _color = widget.initial?['color'] as String? ?? '#FFFFFF';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _done() {
    Navigator.pop(context, {
      'text': _c.text.trim(),
      'style': _style,
      'font': _font,
      'color': _color,
    });
  }

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding;
    final styleName = kStoryTextStyles.firstWhere((e) => e.$1 == _style, orElse: () => kStoryTextStyles.first).$2;
    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: 0.55),
      // клавиатуру учитываем вручную (SizedBox внизу), иначе отступ двойной
      resizeToAvoidBottomInset: false,
      body: Column(
        children: [
          SizedBox(height: pad.top + 6),
          Row(
            children: [
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  final i = kStoryTextStyles.indexWhere((e) => e.$1 == _style);
                  setState(() => _style = kStoryTextStyles[(i + 1) % kStoryTextStyles.length].$1);
                  HapticFeedback.selectionClick();
                },
                style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text('Стиль: $styleName'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  final i = kStoryFonts.indexOf(_font);
                  setState(() => _font = kStoryFonts[(i + 1) % kStoryFonts.length]);
                  HapticFeedback.selectionClick();
                },
                style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: Text('Аа', style: storyFont(_font, size: 16)),
              ),
              const Spacer(),
              TextButton(
                onPressed: _done,
                child: const Text('Готово',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              const SizedBox(width: 8),
            ],
          ),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // живой предпросмотр эффекта
                    if (_c.text.trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: StoryOverlayView(
                          data: {'type': 'text', 'text': _c.text, 'style': _style, 'font': _font, 'color': _color},
                          maxWidth: MediaQuery.of(context).size.width - 48,
                        ),
                      ),
                    TextField(
                      controller: _c,
                      autofocus: true,
                      maxLines: null,
                      maxLength: 200,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                      style: storyFont(_font, size: 22, color: Colors.white.withValues(alpha: 0.85)),
                      cursorColor: Colors.white,
                      decoration: const InputDecoration(
                        hintText: 'Напиши что-нибудь…',
                        hintStyle: TextStyle(color: Colors.white54),
                        counterText: '',
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(
            height: 54,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (final c in kStoryColors)
                  GestureDetector(
                    onTap: () => setState(() => _color = colorHex(c)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 34,
                      height: 34,
                      margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: colorHex(c) == _color ? Colors.white : Colors.white38,
                            width: colorHex(c) == _color ? 3 : 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + pad.bottom + 6),
        ],
      ),
    );
  }
}

/// Стикеры: свои, эмодзи и виджеты (погода, время, музыка).
class _StickerSheet extends StatefulWidget {
  const _StickerSheet();
  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  int _tab = 0;

  Widget _tabBtn(int i, String label) {
    final on = _tab == i;
    return Expanded(
      child: Pressable(
        onTap: () => setState(() => _tab = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: on ? appState.accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: on ? appState.accent : subtleText(context))),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    const months = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа',
      'сентября', 'октября', 'ноября', 'декабря'];
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              _tabBtn(0, 'Стикеры'),
              _tabBtn(1, 'Эмодзи'),
              _tabBtn(2, 'Виджеты'),
            ]),
          ),
          Flexible(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: switch (_tab) {
                  0 => ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      children: [
                        // стикеры-картинки — сеткой 3×N
                        GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          children: [
                            for (final st in kStoryStickers.where((e) => e.$1.startsWith('st_')))
                              Pressable(
                                scale: 0.9,
                                onTap: () => Navigator.pop(context, {'type': 'sticker', 'id': st.$1}),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Image.asset('assets/stickers/${st.$1}.webp',
                                      filterQuality: FilterQuality.medium,
                                      errorBuilder: (_, __, ___) => const SizedBox()),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          alignment: WrapAlignment.center,
                          children: [
                            for (final st in kStoryStickers.where((e) => !e.$1.startsWith('st_')))
                              Pressable(
                                onTap: () => Navigator.pop(context, {'type': 'sticker', 'id': st.$1}),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2A2F3A),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: StorySticker(id: st.$1, size: 0.75),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text('Скоро здесь появятся целые наборы стикеров ✨',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: subtleText(context), fontSize: 13)),
                      ],
                    ),
                  1 => GridView.count(
                      shrinkWrap: true,
                      crossAxisCount: 6,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      children: [
                        for (final e in kStoryEmojis)
                          Pressable(
                            scale: 0.8,
                            onTap: () => Navigator.pop(context, {'type': 'emoji', 'emoji': e}),
                            child: Center(child: Text(e, style: const TextStyle(fontSize: 32))),
                          ),
                      ],
                    ),
                  _ => ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                      children: [
                        SheetItem(
                          icon: AppIcons.sun,
                          title: 'Погода',
                          subtitle: 'Температура там, где ты сейчас',
                          onTap: () => Navigator.pop(context, {'type': 'weather'}),
                        ),
                        SheetItem(
                          icon: AppIcons.clock,
                          title: 'Время',
                          subtitle: 'Часы и дата на истории',
                          onTap: () => Navigator.pop(context, {
                            'type': 'time',
                            'time':
                                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                            'date': '${now.day} ${months[now.month - 1]}',
                            'style': 'glass',
                          }),
                        ),
                        SheetItem(
                          icon: AppIcons.headphones,
                          title: 'Музыка',
                          subtitle: 'Трек с телефона — заиграет у всех, кто смотрит',
                          onTap: () => Navigator.pop(context, {'type': 'music'}),
                        ),
                      ],
                    ),
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
