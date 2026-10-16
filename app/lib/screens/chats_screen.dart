import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../cache.dart';
import '../desktop_pane.dart';
import '../e2e.dart';
import '../notifications.dart';
import '../realtime.dart';
import '../stories.dart';
import '../theme.dart';
import '../widgets/frames.dart';
import '../widgets/shop_media.dart';
import '../widgets/story_widgets.dart';
import '../widgets/ui.dart';
import 'chat_screen.dart';
import 'create_channel_screen.dart';
import 'create_group_screen.dart';
import 'join_sheet.dart';
import 'mute_sheet.dart';
import 'new_chat_screen.dart';
import 'story_create_screen.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

/// Размеры строки в списке чатов (как в Telegram: строка ~64 px, аватар 50).
const double kChatAvatar = 50;
const double kChatPadV = 7;

class _ChatsScreenState extends State<ChatsScreen> {
  List<dynamic> _chats = [];
  // анимация появления строк — только при первом показе списка,
  // а не каждый раз, когда строка заново появляется при прокрутке
  bool _introDone = false;
  bool _introArmed = false;
  bool _loading = true;
  bool _failed = false; // список не загрузился (нет сети)

  // выбор нескольких чатов (долгое нажатие)
  final Set<String> _sel = {};
  bool get _selecting => _sel.isNotEmpty;

  void _toggleSel(String cid) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_sel.remove(cid)) _sel.add(cid);
    });
  }

  List<Map<String, dynamic>> get _selChats => _chats
      .map((e) => (e as Map).cast<String, dynamic>())
      .where((c) => _sel.contains(c['id']))
      .toList();

  void _clearSel() => setState(() => _sel.clear());

  Future<void> _bulkRead() async {
    final ids = _sel.toList();
    _clearSel();
    for (final id in ids) {
      Notif.cancelChat(id);
    }
    await Future.wait(ids.map((id) => Api.markRead(id).catchError((_) {})));
    _load();
  }

  void _bulkMute() {
    final list = _selChats;
    final allMuted = list.every((c) => appState.isMuted(c['id'] as String));
    for (final c in list) {
      final id = c['id'] as String;
      if (allMuted) {
        appState.unmute(id);
      } else if (!appState.isMuted(id)) {
        appState.muteFor(id, null);
      }
    }
    toast(context, allMuted ? 'Звук включён' : 'Без звука: ${list.length}',
        icon: allMuted ? AppIcons.bell : AppIcons.bellOff);
    _clearSel();
  }

  void _bulkArchive() {
    final list = _selChats;
    final allArchived = list.every((c) => appState.isArchived(c['id'] as String));
    for (final c in list) {
      appState.setArchived(c['id'] as String, !allArchived);
    }
    toast(context, allArchived ? 'Вернули из архива' : 'В архиве: ${list.length}',
        icon: AppIcons.archive);
    _clearSel();
  }

  Future<void> _bulkDelete() async {
    final list = _selChats;
    if (list.isEmpty) return;
    final ok = await confirm(context,
        title: 'Удалить ${plural(list.length, 'чат', 'чата', 'чатов')}?',
        body: 'Личные переписки удалятся у тебя, из групп и каналов ты выйдешь.',
        action: 'Удалить',
        danger: true);
    if (!ok || !mounted) return;
    final ids = list.map((c) => c['id'] as String).toSet();
    setState(() {
      _chats.removeWhere((x) => ids.contains((x as Map)['id']));
      _sel.clear();
    });
    for (final id in ids) {
      try {
        await Api.deleteChat(id);
        appState.setArchived(id, false);
        if (appState.isPinned(id)) appState.togglePin(id);
      } catch (_) {}
    }
    if (mounted) toast(context, 'Удалено: ${ids.length}', icon: AppIcons.trash2);
    _load();
  }

  void _openArchive(List<Map<String, dynamic>> archivedList) {
    HapticFeedback.mediumImpact();
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ArchivedChatsScreen(
                chats: archivedList,
                openChat: _openChat,
                onChanged: () => setState(() {})))).then((_) => _load());
  }

  void _archiveMenu() {
    showAppSheet(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetItem(
            icon: AppIcons.eyeOff,
            title: 'Скрыть архив',
            onTap: () {
              Navigator.pop(ctx);
              appState.setArchiveHidden(true);
              toast(context, 'Архив скрыт. Чтобы открыть — удерживай «Connecto» сверху',
                  icon: AppIcons.archive);
            },
          ),
          const SizedBox(height: 6),
        ],
      );
    });
  }
  bool _searching = false;
  String _query = '';
  final _searchCtrl = TextEditingController();
  Timer? _poll;
  Timer? _reloadDeb;

  // «печатает…» по чатам: chatId -> подпись, + таймеры авто-сброса
  final Map<String, String> _activity = {};
  final Map<String, Timer> _activityTimers = {};

  // глобальный поиск
  List<dynamic> _people = [];
  List<dynamic> _public = [];
  bool _searchBusy = false;
  Timer? _searchDeb;

  /// На компьютере открытый справа чат подсвечивается в списке.
  void _onPane() {
    if (mounted) setState(() {});
  }

  SlidableController? _activeSlidable;

  void _closeActiveSlidable() {
    final cur = _activeSlidable;
    if (cur != null) {
      if (cur.actionPaneType.value != ActionPaneType.none && !cur.closing) {
        cur.close();
      }
      _activeSlidable = null;
    }
  }

  @override
  void initState() {
    super.initState();
    Realtime.addListener(_onMsg);
    appState.addListener(_onAppState);
    stories.addListener(_onStories);
    DesktopPane.currentChatId.addListener(_onPane);
    _loadCache();
    _load();
    stories.refresh();
    _poll = Timer.periodic(
        Duration(seconds: appState.energySaving ? 40 : 15), (_) => _load());
  }

  @override
  void dispose() {
    DesktopPane.currentChatId.removeListener(_onPane);
    _poll?.cancel();
    _reloadDeb?.cancel();
    _searchDeb?.cancel();
    for (final t in _activityTimers.values) {
      t.cancel();
    }
    Realtime.removeListener(_onMsg);
    appState.removeListener(_onAppState);
    stories.removeListener(_onStories);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onStories() {
    if (mounted) setState(() {});
  }

  String? _lastUser;
  void _onAppState() {
    // сменили аккаунт — перезагружаем список
    if (_lastUser != appState.myUserId) {
      _lastUser = appState.myUserId;
      if (mounted) {
        setState(() {
          _chats = [];
          _loading = true;
        });
      }
      _loadCache();
      _load();
      stories.refresh();
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _loadCache() async {
    _lastUser = appState.myUserId;
    final cached = await Cache.loadChats();
    if (cached != null && mounted && _chats.isEmpty) {
      setState(() {
        _chats = cached;
        _loading = false;
      });
      _decryptPreviews(cached);
    }
  }

  /// Превью зашифрованных последних сообщений расшифровываем на телефоне.
  Future<void> _decryptPreviews(List<dynamic> list) async {
    var changed = false;
    for (final raw in list) {
      final c = raw as Map;
      final env = c['last_enc'] as String?;
      if (env == null) continue;
      final known = E2E.cachedEnv(env);
      if (known != null) {
        c['last_message'] = known;
        continue;
      }
      final t = await E2E.open(env);
      if (t != null) {
        c['last_message'] = t;
        changed = true;
      }
    }
    if (changed && mounted) setState(() {});
  }

  void _reloadSoon() {
    _reloadDeb?.cancel();
    _reloadDeb = Timer(const Duration(milliseconds: 250), _load);
  }

  void _onMsg(Map<String, dynamic> m) {
    final type = m['type'];
    if (type == 'message') {
      final cid = m['chat_id'] as String?;
      if (cid != null) _clearActivity(cid);
      _reloadSoon();
    } else if (type == 'chat_deleted' ||
        type == 'cleared' ||
        type == 'chat_added' ||
        type == 'chat_updated' ||
        type == 'read' ||
        type == 'msg_deleted') {
      _reloadSoon();
    } else if (type == 'user_status') {
      final uid = m['user_id'] as String?;
      if (uid != null) {
        bool changed = false;
        for (final raw in _chats) {
          final c = raw as Map;
          if (c['peer_id'] == uid) {
            c['peer_online'] = m['online'] == true;
            if (m['last_seen'] != null) {
              c['peer_last_seen'] = m['last_seen'];
            }
            changed = true;
          }
        }
        if (changed && mounted) setState(() {});
      }
    } else if (type == 'typing') {
      final cid = m['chat_id'] as String?;
      if (cid == null || m['user_id'] == appState.myUserId) return;
      final state = m['state'] as String? ?? 'typing';
      if (state == 'stop') {
        _clearActivity(cid);
        return;
      }
      final chat = _chats.cast<Map<String, dynamic>?>().firstWhere(
          (c) => c?['id'] == cid,
          orElse: () => null);
      // в обращении печатает другой админ (от имени Connecto) — это не собеседник
      if (chat != null && chat['support'] == true && m['user_id'] == chat['support_bot_id']) return;
      final isGroup = chat != null && chat['type'] == 'group';
      final who = isGroup ? '${(m['name'] as String?) ?? 'Кто-то'} ' : '';
      final label = switch (state) {
        'voice' => '${who}записывает голосовое…',
        'video' => '${who}записывает видеосообщение…',
        'upload_photo' => '${who}отправляет фото…',
        'upload_video' => '${who}отправляет видео…',
        'upload_file' => '${who}отправляет файл…',
        _ => '${who}печатает…',
      };
      setState(() => _activity[cid] = label);
      _activityTimers[cid]?.cancel();
      _activityTimers[cid] = Timer(const Duration(seconds: 5), () => _clearActivity(cid));
    }
  }

  void _clearActivity(String chatId) {
    _activityTimers.remove(chatId)?.cancel();
    if (_activity.remove(chatId) != null && mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final list = await Api.chats();
      Cache.saveChats(list);
      appState.syncMutes(list);
      if (mounted) {
        // уже известные расшифровки подставляем сразу — без мигания «🔒 Сообщение»
        for (final raw in list) {
          final c = raw as Map;
          final env = c['last_enc'] as String?;
          final known = env == null ? null : E2E.cachedEnv(env);
          if (known != null) c['last_message'] = known;
        }
        setState(() {
          _chats = list;
          _loading = false;
          _failed = false;
        });
        _decryptPreviews(list);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  // ── поиск ──

  void _onQuery(String v) {
    setState(() => _query = v);
    _searchDeb?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() {
        _people = [];
        _public = [];
        _searchBusy = false;
      });
      return;
    }
    setState(() => _searchBusy = true);
    _searchDeb = Timer(const Duration(milliseconds: 350), () async {
      try {
        final code = Api.inviteCodeOf(q);
        final results = await Future.wait([
          code == null ? Api.searchUsers(q) : Future.value(<dynamic>[]),
          code == null && q.replaceAll('@', '').length >= 2
              ? Api.searchPublicChats(q)
              : Future.value(<dynamic>[]),
        ]);
        if (mounted && _query.trim() == q) {
          setState(() {
            _people = results[0];
            _public = results[1];
          });
        }
      } catch (_) {
      } finally {
        if (mounted && _query.trim() == q) setState(() => _searchBusy = false);
      }
    });
  }

  void _closeSearch() => setState(() {
        _searching = false;
        _query = '';
        _searchCtrl.clear();
        _people = [];
        _public = [];
      });

  Future<void> _openUser(Map<String, dynamic> u) async {
    try {
      final chat = await Api.createChat(type: 'direct', memberIds: [u['id'] as String]);
      if (!mounted) return;
      _openChat(chat);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  void _openChat(Map<String, dynamic> c) {
    openChatScreen(context, c).then((_) => _load());
  }

  // ── создание ──

  void _compose() {
    showAppSheet(context, builder: (ctx) {
      void go(Widget page) async {
        Navigator.pop(ctx);
        final r = await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
        _load();
        if (r is Map<String, dynamic> && mounted) _openChat(r);
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SheetItem(
              icon: AppIcons.messageCirclePlus,
              title: 'Новый чат',
              subtitle: 'Найти человека по юзернейму',
              onTap: () => go(const NewChatScreen())),
          SheetItem(
              icon: AppIcons.users,
              title: 'Новая группа',
              subtitle: 'Общение до 200 000 участников',
              onTap: () => go(const CreateGroupScreen())),
          SheetItem(
              icon: AppIcons.megaphone,
              title: 'Новый канал',
              subtitle: 'Публикации для подписчиков',
              onTap: () => go(const CreateChannelScreen())),
          SheetItem(
              icon: AppIcons.link,
              title: 'Вступить по ссылке',
              subtitle: 'Ссылка-приглашение в группу или канал',
              onTap: () async {
                Navigator.pop(ctx);
                final link = await askText(context,
                    title: 'Ссылка-приглашение',
                    hint: 'http://…/j/код',
                    action: 'Открыть',
                    maxLength: 300);
                if (link == null || link.isEmpty || !mounted) return;
                final code = Api.inviteCodeOf(link) ?? link.trim();
                final chat = await showJoinPreview(context, code: code);
                if (chat != null && mounted) {
                  _load();
                  _openChat(chat);
                }
              }),
          const SizedBox(height: 6),
        ],
      );
    });
  }

  // ── действия с чатом ──

  Future<void> _deleteChat(Map<String, dynamic> c) async {
    final cid = c['id'] as String;
    final type = c['type'] as String? ?? 'direct';
    final owner = c['my_role'] == 'owner';
    String? scope;
    if (type == 'direct') {
      scope = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Удалить чат?'),
          content: Text('Удалить переписку с ${c['title'] ?? 'собеседником'} только у себя или у обоих?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'me'), child: const Text('У себя')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'both'),
                child: const Text('У обоих', style: TextStyle(color: kDanger))),
          ],
        ),
      );
    } else {
      final what = type == 'channel' ? 'канал' : 'группу';
      scope = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(owner ? 'Удалить $what?' : 'Покинуть $what?'),
          content: Text(owner
              ? 'Можно просто выйти (права перейдут админу) или удалить $what для всех.'
              : 'Ты больше не будешь получать сообщения.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
            TextButton(onPressed: () => Navigator.pop(ctx, 'me'), child: const Text('Выйти')),
            if (owner)
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'both'),
                  child: const Text('Удалить для всех', style: TextStyle(color: kDanger))),
          ],
        ),
      );
    }
    if (scope == null) return;
    setState(() => _chats.removeWhere((x) => x['id'] == cid));
    try {
      await Api.deleteChat(cid, both: scope == 'both');
      appState.setArchived(cid, false);
      if (appState.isPinned(cid)) appState.togglePin(cid);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
    _load();
  }

  void _togglePin(String cid) {
    if (!appState.togglePin(cid)) {
      toast(context,
          appState.isPremium
              ? 'Можно закрепить до ${appState.pinLimit} чатов'
              : 'Можно закрепить до ${appState.pinLimit} чатов. С Premium — до $kPremiumPinned',
          icon: AppIcons.pin,
          error: true);
    }
  }

  void _chatMenu(Map<String, dynamic> c) {
    final cid = c['id'] as String;
    final archived = appState.isArchived(cid);
    final muted = appState.isMuted(cid);
    final pinned = appState.isPinned(cid);
    final peerId = c['peer_id'] as String?;
    final unread = (c['unread_count'] as num?)?.toInt() ?? 0;
    final type = c['type'] as String? ?? 'direct';
    showAppSheet(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 6, 18, 8),
            child: Row(
              children: [
                _avatarOf(c, 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Text((c['title'] as String?) ?? 'Чат',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                ),
              ],
            ),
          ),
          SheetItem(
              icon: pinned ? AppIcons.pinOff : AppIcons.pin,
              title: pinned ? 'Открепить' : 'Закрепить',
              onTap: () {
                Navigator.pop(ctx);
                _togglePin(cid);
              }),
          if (unread > 0)
            SheetItem(
                icon: AppIcons.checkCheck,
                title: 'Отметить прочитанным',
                onTap: () async {
                  Navigator.pop(ctx);
                  await Api.markRead(cid);
                  _load();
                }),
          SheetItem(
            icon: muted ? AppIcons.bell : AppIcons.bellOff,
            title: muted ? 'Включить звук' : 'Без звука',
            onTap: () {
              Navigator.pop(ctx);
              if (muted) {
                appState.unmute(cid);
              } else {
                showMuteSheet(context, cid);
              }
            },
          ),
          SheetItem(
            icon: archived ? AppIcons.archiveRestore : AppIcons.archive,
            title: archived ? 'Убрать из архива' : 'В архив',
            onTap: () {
              appState.setArchived(cid, !archived);
              Navigator.pop(ctx);
            },
          ),
          if (peerId != null && c['is_system'] != true)
            SheetItem(
              icon: AppIcons.ban,
              title: 'Заблокировать',
              danger: true,
              onTap: () async {
                Navigator.pop(ctx);
                if (!await confirm(context,
                    title: 'Заблокировать ${c['title']}?',
                    body: 'Пользователь не сможет писать тебе и не увидит твой профиль.',
                    action: 'Заблокировать',
                    danger: true)) {
                  return;
                }
                try {
                  await Api.blockUser(peerId);
                  if (mounted) toast(context, 'Пользователь заблокирован', icon: AppIcons.ban);
                } catch (e) {
                  if (mounted) toast(context, friendlyError(e), error: true);
                }
              },
            ),
          SheetItem(
            icon: type == 'direct' ? AppIcons.trash2 : AppIcons.logOut,
            title: type == 'direct'
                ? 'Удалить чат'
                : (c['my_role'] == 'owner'
                    ? 'Удалить или покинуть'
                    : (type == 'channel' ? 'Отписаться' : 'Покинуть группу')),
            danger: true,
            onTap: () {
              Navigator.pop(ctx);
              _deleteChat(c);
            },
          ),
          const SizedBox(height: 6),
        ],
      );
    });
  }

  // ── отрисовка ──

  static Widget _avatarOf(Map<String, dynamic> c, double size) {
    final type = c['type'] as String? ?? 'direct';
    final name = (c['title'] as String?) ?? 'Чат';
    IconData? icon;
    if (c['is_system'] == true) icon = AppIcons.shieldCheck;
    if (type == 'channel') icon = AppIcons.megaphone;
    if (type == 'group') icon = AppIcons.users;
    if (c['peer_is_bot'] == true && c['is_system'] != true) icon = AppIcons.bot;
    return Avatar(
      name: name,
      url: c['avatar_url'] as String?,
      size: size,
      radius: type == 'direct' ? null : size * 0.33,
      icon: icon,
      useAccent: type != 'direct' || c['is_system'] == true,
      online: c['peer_online'] == true,
    );
  }

  String _time(String? iso) {
    if (iso == null) return '';
    final d = parseServerTime(iso);
    if (d == null) return '';
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
      return 'вчера';
    }
    if (now.difference(d).inDays < 7) {
      return const ['пн', 'вт', 'ср', 'чт', 'пт', 'сб', 'вс'][d.weekday - 1];
    }
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';
  }

  Widget _tile(Map<String, dynamic> c, int index) {
    final cid = c['id'] as String;
    final archived = appState.isArchived(cid);
    final muted = appState.isMuted(cid);
    final pinned = appState.isPinned(cid);
    final peer = c['type'] == 'direct' && c['is_system'] != true ? c['peer_id'] as String? : null;
    Widget avatar = _avatarOf(c, kChatAvatar);
    if (c['frame'] is Map) {
      avatar = FramedAvatar(
        size: kChatAvatar,
        frame: (c['frame'] as Map).cast<String, dynamic>(),
        child: avatar,
      );
    }
    if (peer != null && stories.hasActive(peer)) {
      avatar = GestureDetector(
        onTap: () => openStoriesOf(context, peer),
        child: StoryRing(
          active: true,
          unseen: stories.hasUnseen(peer),
          width: 2.2,
          gap: 2,
          child: _avatarOf(c, kChatAvatar - 8.4),
        ),
      );
    }
    final tile = _ChatTile(
      chat: c,
      avatar: avatar,
      activity: _activity[cid],
      time: _time((c['last_time'] as String?) ?? (c['created_at'] as String?)),
      muted: muted,
      pinned: pinned,
      selecting: _selecting,
      selected: _sel.contains(cid),
      open: DesktopPane.active && DesktopPane.currentChatId.value == cid,
      onTap: () {
        if (_activeSlidable != null &&
            _activeSlidable!.actionPaneType.value != ActionPaneType.none) {
          _closeActiveSlidable();
          return;
        }
        _selecting ? _toggleSel(cid) : _openChat(c);
      },
      onLongPress: () => _toggleSel(cid),
    );
    return _ChatSlidableWrapper(
      key: ValueKey('slid_wrap_$cid'),
      onOpen: (ctrl) => _activeSlidable = ctrl,
      builder: (context, controller) {
        return Slidable(
          key: ValueKey(cid),
          controller: controller,
          groupTag: 'chats',
          enabled: !_selecting,
          startActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.40,
            children: [
              _SwipeAction(
                icon: archived ? AppIcons.archiveRestore : AppIcons.archive,
                label: archived ? 'Вернуть' : 'Архив',
                colors: const [Color(0xFF64748B), Color(0xFF94A3B8)],
                onTap: () => setState(() => appState.setArchived(cid, !archived)),
              ),
              _SwipeAction(
                icon: muted ? AppIcons.bell : AppIcons.bellOff,
                label: muted ? 'Звук' : 'Тихо',
                colors: const [Color(0xFFF59E0B), Color(0xFFFBBF24)],
                onTap: () {
                  if (muted) {
                    appState.unmute(cid);
                  } else {
                    showMuteSheet(context, cid);
                  }
                },
              ),
            ],
          ),
          endActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.40,
            children: [
              _SwipeAction(
                icon: pinned ? AppIcons.pinOff : AppIcons.pin,
                label: pinned ? 'Открепить' : 'Закрепить',
                colors: accentGradient(appState.accent).colors,
                onTap: () => _togglePin(cid),
              ),
              _SwipeAction(
                icon: AppIcons.trash2,
                label: 'Удалить',
                colors: const [Color(0xFFE11D48), Color(0xFFFB7185)],
                onTap: () => _deleteChat(c),
              ),
            ],
          ),
          child: RepaintBoundary(
            child: index < 12 && !_introDone ? FadeSlideIn(delayMs: 20 * index, child: tile) : tile,
          ),
        );
      },
    );
  }

  List<Map<String, dynamic>> _sorted(List<Map<String, dynamic>> list) {
    final pins = appState.pinnedChats;
    final pinned = <Map<String, dynamic>>[];
    for (final id in pins) {
      for (final c in list) {
        if (c['id'] == id) pinned.add(c);
      }
    }
    final rest = list.where((c) => !pins.contains(c['id'])).toList();
    return [...pinned, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final all = _chats.map((e) => (e as Map).cast<String, dynamic>()).toList();
    var shown = all;
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase().replaceAll('@', '');
      shown = all.where((c) {
        final t = (c['title'] as String? ?? '').toLowerCase();
        final h = (c['handle'] as String? ?? '').toLowerCase();
        final m = (c['last_message'] as String? ?? '').toLowerCase();
        return t.contains(q) || h.contains(q) || m.contains(q);
      }).toList();
    }
    if (!_introArmed && all.isNotEmpty) {
      _introArmed = true;
      Future.delayed(const Duration(milliseconds: 900), () => _introDone = true);
    }
    final archivedList = shown.where((c) => appState.isArchived(c['id'] as String)).toList();
    final visible = _sorted(shown.where((c) => !appState.isArchived(c['id'] as String)).toList());
    final memberIds = all.map((c) => c['id']).toSet();
    final myPeerIds = all.map((c) => c['peer_id']).whereType<String>().toSet();
    final people = _people
        .map((e) => (e as Map).cast<String, dynamic>())
        .where((u) => !myPeerIds.contains(u['id']))
        .toList();
    final publics = _public
        .map((e) => (e as Map).cast<String, dynamic>())
        .where((c) => !memberIds.contains(c['id']))
        .toList();
    final inviteCode = _query.isEmpty ? null : Api.inviteCodeOf(_query);
    final archivedUnread = archivedList.fold<int>(
        0, (s, c) => s + ((c['unread_count'] as num?)?.toInt() ?? 0));
    final totalUnread = all
        .where((c) =>
            !appState.isArchived(c['id'] as String) && !appState.isMuted(c['id'] as String))
        .fold<int>(0, (s, c) => s + ((c['unread_count'] as num?)?.toInt() ?? 0));
    if (appState.unreadTotal.value != totalUnread) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        appState.unreadTotal.value = totalUnread;
        if (totalUnread == 0) Notif.cancelAll();
      });
    }

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selecting) _clearSel();
      },
      child: Scaffold(
      backgroundColor: Colors.transparent,
      body: SlidableAutoCloseBehavior(
        child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([_load(), stories.refresh()]);
        },
        color: appState.accent,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _closeActiveSlidable,
          child: CustomScrollView(
            cacheExtent: 600,
          slivers: [
            SliverAppBar(
              floating: true,
              pinned: true,
              leading: _selecting
                  ? IconButton(icon: const Icon(AppIcons.x), onPressed: _clearSel)
                  : null,
              title: _selecting
                  ? AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: Text('Выбрано: ${_sel.length}', key: ValueKey(_sel.length)),
                    )
                  : _searching
                  ? TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      onChanged: _onQuery,
                      decoration: const InputDecoration(
                          hintText: 'Люди, чаты, каналы, ссылка',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none),
                    )
                  : ValueListenableBuilder<bool>(
                      valueListenable: Realtime.connected,
                      builder: (_, ok, __) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 250),
                        child: ok || _loading
                            ? GestureDetector(
                                key: const ValueKey('t'),
                                // долгое нажатие на заголовок открывает архив (даже скрытый)
                                onLongPress: () => _openArchive(archivedList),
                                child: const Text('Connecto'),
                              )
                            : Row(
                                key: const ValueKey('c'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2.2, color: appState.accent)),
                                  const SizedBox(width: 10),
                                  const Text('Соединение…'),
                                ],
                              ),
                      ),
                    ),
              actions: _selecting
                  ? [
                      IconButton(
                          tooltip: 'Прочитать',
                          icon: const Icon(AppIcons.checkCheck),
                          onPressed: _bulkRead),
                      IconButton(
                          tooltip: 'Звук',
                          icon: const Icon(AppIcons.bellOff),
                          onPressed: _bulkMute),
                      IconButton(
                          tooltip: 'Архив',
                          icon: const Icon(AppIcons.archive),
                          onPressed: _bulkArchive),
                      IconButton(
                          tooltip: 'Удалить',
                          icon: const Icon(AppIcons.trash2, color: kDanger),
                          onPressed: _bulkDelete),
                      if (_sel.length == 1)
                        IconButton(
                          tooltip: 'Ещё',
                          icon: const Icon(AppIcons.ellipsisVertical),
                          onPressed: () {
                            final c = _selChats.first;
                            _clearSel();
                            _chatMenu(c);
                          },
                        ),
                      const SizedBox(width: 4),
                    ]
                  : [
                if (!_searching) ...[
                  _StoryHeaderBtn(onTap: () => openStoryCreate(context)),
                  const SizedBox(width: 8),
                ],
                _CircleBtn(
                  icon: _searching ? AppIcons.x : AppIcons.search,
                  tooltip: _searching ? 'Закрыть поиск' : 'Поиск',
                  onTap: () {
                    if (_searching) {
                      _closeSearch();
                    } else {
                      setState(() => _searching = true);
                    }
                  },
                ),
                const SizedBox(width: 12),
              ],
            ),
            if (!_searching && _query.isEmpty && appState.myUserId != null)
              SliverToBoxAdapter(
                child: AnimatedSize(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeOutCubic,
                  child: ListenableBuilder(
                    listenable: stories,
                    builder: (_, __) => stories.loaded &&
                            (stories.mine != null || stories.others.isNotEmpty)
                        ? const StoriesBar()
                        : const SizedBox(width: double.infinity, height: 0),
                  ),
                ),
              ),
            if (_loading && all.isEmpty)
              const SliverToBoxAdapter(child: ListSkeleton())
            else ...[
              if (inviteCode != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: SectionCard(children: [
                      SettingsTile(
                        icon: AppIcons.link,
                        title: 'Открыть приглашение',
                        subtitle: 'Посмотреть группу или канал по ссылке',
                        onTap: () async {
                          final chat = await showJoinPreview(context, code: inviteCode);
                          if (chat != null && mounted) {
                            _closeSearch();
                            _load();
                            _openChat(chat);
                          }
                        },
                      ),
                    ]),
                  ),
                ),
              if (archivedList.isNotEmpty && _query.isEmpty && !appState.archiveHidden)
                SliverToBoxAdapter(
                  child: ListTile(
                    onLongPress: _archiveMenu,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                    minVerticalPadding: kChatPadV,
                    visualDensity: const VisualDensity(vertical: -2),
                    horizontalTitleGap: 14,
                    leading: Container(
                      width: kChatAvatar,
                      height: kChatAvatar,
                      decoration: const BoxDecoration(
                          gradient: LinearGradient(
                              colors: [Color(0xFF64748B), Color(0xFF94A3B8)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight),
                          shape: BoxShape.circle),
                      child: const Icon(AppIcons.archive, color: Colors.white),
                    ),
                    title: const Text('Архив',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    subtitle: Text(
                        archivedList.map((c) => c['title'] ?? '').take(3).join(', '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: archivedUnread > 0
                        ? CountBadge(archivedUnread, muted: true)
                        : Text('${archivedList.length}',
                            style: TextStyle(color: subtleText(context))),
                    onTap: () => _openArchive(archivedList),
                  ),
                ),
              if (visible.isEmpty && _query.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _failed && _chats.isEmpty
                      ? EmptyState(
                          icon: AppIcons.wifiOff,
                          mascot: 'empty_no_internet',
                          title: 'Нет соединения',
                          subtitle: 'Проверь интернет — чаты появятся, как только связь вернётся',
                          action: FilledButton.icon(
                            onPressed: () {
                              setState(() => _loading = true);
                              _load();
                            },
                            icon: const Icon(AppIcons.refreshCw, size: 18),
                            label: const Text('Повторить'),
                          ),
                        )
                      : EmptyState(
                          icon: AppIcons.messageCirclePlus,
                          mascot: 'empty_no_chats',
                          title: 'Пока нет чатов',
                          subtitle: 'Найди друзей по юзернейму или создай группу',
                          action: FilledButton.icon(
                            onPressed: _compose,
                            icon: const Icon(AppIcons.penLine, size: 18),
                            label: const Text('Начать'),
                          ),
                        ),
                )
              else ...[
                if (_query.isNotEmpty && visible.isNotEmpty)
                  const SliverToBoxAdapter(child: _Header('ЧАТЫ')),
                SliverList.builder(
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _tile(visible[i], i),
                ),
              ],
              if (_query.isNotEmpty && people.isNotEmpty) ...[
                const SliverToBoxAdapter(child: _Header('ЛЮДИ')),
                SliverList.builder(
                  itemCount: people.length,
                  itemBuilder: (context, i) {
                    final u = people[i];
                    final name = (u['display_name'] as String?) ?? (u['username'] as String? ?? '?');
                    final handle = u['handle'] as String?;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                      leading: Avatar(
                          name: name,
                          url: u['avatar_url'] as String?,
                          size: 48,
                          icon: u['is_bot'] == true ? AppIcons.bot : null),
                      title: NameBadges(name,
                          verified: u['is_verified'] == true,
                          premium: u['is_premium'] == true,
                          bot: u['is_bot'] == true),
                      subtitle: handle != null ? Text('@$handle') : null,
                      onTap: () => _openUser(u),
                    );
                  },
                ),
              ],
              if (_query.isNotEmpty && publics.isNotEmpty) ...[
                const SliverToBoxAdapter(child: _Header('ГЛОБАЛЬНЫЙ ПОИСК')),
                SliverList.builder(
                  itemCount: publics.length,
                  itemBuilder: (context, i) {
                    final c = publics[i];
                    final isCh = c['type'] == 'channel';
                    final n = (c['member_count'] as num?)?.toInt() ?? 0;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
                      leading: _avatarOf(c, 48),
                      title: Text((c['title'] as String?) ?? '',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '@${c['handle']} · ${isCh ? plural(n, 'подписчик', 'подписчика', 'подписчиков') : plural(n, 'участник', 'участника', 'участников')}'),
                      onTap: () => _openChat(c),
                    );
                  },
                ),
              ],
              if (_query.isNotEmpty &&
                  !_searchBusy &&
                  visible.isEmpty &&
                  people.isEmpty &&
                  publics.isEmpty &&
                  inviteCode == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                      icon: AppIcons.searchX,
                      mascot: 'empty_not_found',
                      title: 'Ничего не нашлось',
                      subtitle: 'Проверь юзернейм или вставь ссылку-приглашение'),
                ),
              if (_query.isNotEmpty && _searchBusy)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ),
            ],
            SliverFillRemaining(
              hasScrollBody: false,
              fillOverscroll: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeActiveSlidable,
                child: const SizedBox(height: 120),
              ),
            ),
          ],
        ),
      ),
      ),
      ),
      floatingActionButton: _selecting
          ? null
          : Padding(
        padding: const EdgeInsets.only(bottom: 82),
        child: Pressable(
          onTap: () {
            HapticFeedback.lightImpact();
            _compose();
          },
          scale: 0.92,
          child: Tooltip(
            message: 'Новый чат',
            child: Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                gradient: accentGradient(appState.accent),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                      color: appState.accent.withValues(alpha: 0.45),
                      blurRadius: 20,
                      offset: const Offset(0, 8)),
                ],
              ),
              child: const Center(
                child: Icon(AppIcons.penLine, color: Colors.white, size: 26),
              ),
            ),
          ),
        ),
      ),
    ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 16, 6),
        child: Text(text,
            style: TextStyle(
                color: subtleText(context),
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6)),
      );
}

class ArchivedChatsScreen extends StatefulWidget {
  final List<Map<String, dynamic>> chats;
  final void Function(Map<String, dynamic>) openChat;
  final VoidCallback onChanged;
  const ArchivedChatsScreen(
      {super.key, required this.chats, required this.openChat, required this.onChanged});

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  late final List<Map<String, dynamic>> _list = List.of(widget.chats);

  void _unarchive(String cid) {
    appState.setArchived(cid, false);
    widget.onChanged();
    setState(() => _list.removeWhere((c) => c['id'] == cid));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Архив'),
        actions: [
          ListenableBuilder(
            listenable: appState,
            builder: (context, _) => IconButton(
              tooltip: appState.archiveHidden ? 'Показывать в списке чатов' : 'Скрыть из списка чатов',
              icon: Icon(appState.archiveHidden ? AppIcons.eye : AppIcons.eyeOff),
              onPressed: () {
                final hide = !appState.archiveHidden;
                appState.setArchiveHidden(hide);
                toast(
                    context,
                    hide
                        ? 'Архив скрыт. Открыть — удерживай «Connecto» сверху'
                        : 'Архив снова виден в списке чатов',
                    icon: AppIcons.archive);
              },
            ),
          ),
        ],
      ),
      body: _list.isEmpty
          ? const EmptyState(
              icon: AppIcons.archive,
              title: 'Архив пуст',
              subtitle: 'Смахни чат вправо, чтобы убрать его сюда')
          : SlidableAutoCloseBehavior(
              child: ListView.builder(
              itemCount: _list.length,
              itemBuilder: (context, i) {
                final c = _list[i];
                final cid = c['id'] as String;
                return Slidable(
                  key: ValueKey(cid),
                  groupTag: 'archive',
                  startActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    extentRatio: 0.20,
                    children: [
                      _SwipeAction(
                        icon: AppIcons.archiveRestore,
                        label: 'Вернуть',
                        colors: accentGradient(appState.accent).colors,
                        onTap: () => _unarchive(cid),
                      ),
                    ],
                  ),
                  child: _ChatTile(
                    chat: c,
                    avatar: _ChatsScreenState._avatarOf(c, 54),
                    time: '',
                    muted: appState.isMuted(cid),
                    pinned: false,
                    onTap: () => widget.openChat(c),
                    onLongPress: () => _unarchive(cid),
                  ),
                );
              },
            ),
            ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  const _CircleBtn({required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget btn = Pressable(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      scale: 0.90,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: cardColor(context).withValues(alpha: dark ? 0.75 : 0.88),
          shape: BoxShape.circle,
          border: Border.all(color: hairline(context)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? 0.18 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (c, a) => RotationTransition(
              turns: Tween(begin: 0.75, end: 1.0).animate(a),
              child: FadeTransition(opacity: a, child: c)),
          child: Icon(icon, key: ValueKey(icon), size: 20),
        ),
      ),
    );

    if (tooltip != null) {
      btn = Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

class _StoryHeaderBtn extends StatelessWidget {
  final VoidCallback onTap;
  const _StoryHeaderBtn({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'Опубликовать историю',
      child: Pressable(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        scale: 0.90,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cardColor(context).withValues(alpha: dark ? 0.75 : 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: appState.accent.withValues(alpha: 0.35), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: appState.accent.withValues(alpha: 0.20),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(AppIcons.camera, size: 20, color: appState.accent),
              Positioned(
                right: 7,
                bottom: 7,
                child: Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    gradient: accentGradient(appState.accent),
                    shape: BoxShape.circle,
                    border: Border.all(color: cardColor(context), width: 1.2),
                  ),
                  child: const Center(
                    child: Icon(Icons.add, size: 6, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  final Map<String, dynamic> chat;
  final Widget avatar;
  final String? activity;
  final String time;
  final bool muted;
  final bool pinned;
  final bool selecting;
  final bool selected;
  final bool open; // чат открыт справа (компьютер)
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _ChatTile({
    required this.chat,
    required this.avatar,
    this.activity,
    required this.time,
    required this.muted,
    required this.pinned,
    this.selecting = false,
    this.selected = false,
    this.open = false,
    required this.onTap,
    required this.onLongPress,
  });

  /// Аватар с галочкой выбора.
  Widget _avatarSel(BuildContext context) {
    if (!selecting) return avatar;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          bottom: -2,
          child: AnimatedScale(
            scale: selected ? 1 : 0.85,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: selected ? appState.accent : Theme.of(context).scaffoldBackgroundColor,
                shape: BoxShape.circle,
                border: Border.all(
                    color: selected ? Theme.of(context).scaffoldBackgroundColor : subtleText(context),
                    width: 2),
              ),
              child: selected ? const Icon(AppIcons.check, size: 13, color: Colors.white) : null,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = chat;
    final title = (c['title'] as String?) ?? 'Чат';
    final unread = (c['unread_count'] as num?)?.toInt() ?? 0;
    final lastMine = c['last_mine'] == true;
    final lastRead = c['last_read'] == true;
    final lastKind = c['last_kind'] as String?;
    final sender = c['last_sender'] as String?;
    final msg = (c['last_message'] as String?) ??
        (c['type'] == 'channel' ? 'Канал создан' : 'Нет сообщений');
    final type = c['type'] as String? ?? 'direct';
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final look = chatFrameLook(context);
    final framed = look != null;
    void tap() {
      // если у этого чата открыты действия — сначала плавно закрываем их
      final ctrl = Slidable.of(context);
      if (ctrl != null && ctrl.ratio != 0) {
        ctrl.close();
        return;
      }
      onTap();
    }

    final content = Padding(
      padding: framed
          ? const EdgeInsets.fromLTRB(12, kChatPadV, 0, kChatPadV)
          : const EdgeInsets.fromLTRB(14, kChatPadV, 0, 0),
      child: Row(
        children: [
          Padding(padding: EdgeInsets.only(bottom: framed ? 0 : kChatPadV), child: _avatarSel(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _titleRow(context, title, type, muted, lastMine, lastRead, lastKind, time, unread,
                    framed),
                const SizedBox(height: 2),
                _previewRow(context, msg, sender, lastKind, unread, framed),
                if (!framed) ...[
                  const SizedBox(height: 8),
                  Divider(height: 0.8, thickness: 0.8, color: hairline(context)),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (look != null) {
      final r = BorderRadius.circular(look.radius);
      return Padding(
        padding: const EdgeInsets.fromLTRB(10, 3, 10, 3),
        child: FramedBox(
          look: look,
          radius: r,
          child: Material(
            color: (selected || open)
                ? appState.accent.withValues(alpha: open ? 0.2 : 0.14)
                : (pinned ? appState.accent.withValues(alpha: 0.06) : Colors.transparent),
            child: InkWell(
              onTap: tap,
              onLongPress: () {
                HapticFeedback.mediumImpact();
                onLongPress();
              },
              onSecondaryTap: onLongPress, // правый клик мышью
              splashColor: appState.accent.withValues(alpha: 0.10),
              highlightColor: appState.accent.withValues(alpha: 0.06),
              child: content,
            ),
          ),
        ),
      );
    }

    return Material(
      color: (selected || open)
          ? Color.alphaBlend(appState.accent.withValues(alpha: open ? 0.18 : 0.12), bg)
          : (pinned ? Color.alphaBlend(appState.accent.withValues(alpha: 0.05), bg) : bg),
      child: InkWell(
        onTap: tap,
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onLongPress();
        },
        onSecondaryTap: onLongPress, // правый клик мышью
        splashColor: appState.accent.withValues(alpha: 0.08),
        highlightColor: appState.accent.withValues(alpha: 0.05),
        child: content,
      ),
    );
  }

  Widget _titleRow(BuildContext context, String title, String type, bool muted, bool lastMine,
      bool lastRead, String? lastKind, String time, int unread, bool framed) {
    final c = chat;
    return Row(
                    children: [
                      if (type == 'group')
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(AppIcons.users, size: 14, color: subtleText(context)),
                        ),
                      if (type == 'channel')
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(AppIcons.megaphone, size: 14, color: subtleText(context)),
                        ),
                      Expanded(
                        child: NameBadges(title,
                            verified: c['is_verified'] == true,
                            premium: c['peer_premium'] == true,
                            emoji: c['peer_emoji_status'] as String?,
                            bot: c['peer_is_bot'] == true && c['is_system'] != true,
                            style: TextStyle(
                                fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w600,
                                fontSize: 16,
                                height: 1.2)),
                      ),
                      if (c['support'] == true) const _SupportChip(),
                      if (muted)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(AppIcons.bellOff, size: 14, color: subtleText(context)),
                        ),
                      const SizedBox(width: 6),
                      if (lastMine && lastKind != 'service' && type != 'channel')
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(lastRead ? AppIcons.checkCheck : AppIcons.check,
                              size: 15, color: appState.accent),
                        ),
                      Text(time,
                          style: TextStyle(
                              fontSize: 12,
                              color: unread > 0 && !muted ? appState.accent : subtleText(context),
                              fontWeight: unread > 0 ? FontWeight.w700 : FontWeight.w500)),
                      SizedBox(width: framed ? 14 : 16),
                    ],
                  );
  }

  Widget _previewRow(BuildContext context, String msg, String? sender, String? lastKind,
      int unread, bool framed) {
    return Row(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: activity != null
                              ? Text(activity!,
                                  key: const ValueKey('a'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: appState.accent,
                                      fontSize: 14.5,
                                      height: 1.25,
                                      fontStyle: FontStyle.italic))
                              : Text.rich(
                                  TextSpan(children: [
                                    if (sender != null && lastKind != 'service')
                                      TextSpan(
                                          text: '$sender: ',
                                          style: TextStyle(
                                              color: Theme.of(context).textTheme.bodyMedium?.color,
                                              fontWeight: FontWeight.w600)),
                                    TextSpan(
                                        text: msg.replaceAll('\n', ' '),
                                        style: TextStyle(
                                            fontStyle: lastKind == 'service'
                                                ? FontStyle.italic
                                                : FontStyle.normal)),
                                  ]),
                                  key: const ValueKey('m'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: subtleText(context), fontSize: 14.5, height: 1.25)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (unread > 0)
                        CountBadge(unread, muted: muted)
                      else if (pinned)
                        Transform.rotate(
                          angle: 0.6,
                          child: Icon(AppIcons.pin, size: 15, color: subtleText(context)),
                        ),
                      SizedBox(width: framed ? 14 : 16),
                    ],
                  );
  }
}

/// Метка «поддержка» у обращений в списке чатов админа.
class _SupportChip extends StatelessWidget {
  const _SupportChip();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          appState.accent.withValues(alpha: 0.22),
          appState.accent.withValues(alpha: 0.10),
        ]),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: appState.accent.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.lifeBuoy, size: 11, color: appState.accent),
          const SizedBox(width: 3),
          Text('поддержка',
              style: TextStyle(
                  fontSize: 10.5, fontWeight: FontWeight.w800, color: appState.accent)),
        ],
      ),
    );
  }
}

/// Действие при смахивании: крупная скруглённая плитка с градиентом и понятной иконкой без текста.
class _SwipeAction extends StatelessWidget {
  final IconData icon;
  final String? label;
  final List<Color> colors;
  final VoidCallback onTap;
  const _SwipeAction(
      {required this.icon, this.label, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Widget btn = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 3),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
              colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
                color: colors.first.withValues(alpha: 0.35),
                blurRadius: 10,
                offset: const Offset(0, 3)),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: 26),
      ),
    );

    if (label != null && label!.isNotEmpty) {
      btn = Tooltip(
        message: label!,
        child: btn,
      );
    }

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          Slidable.of(context)?.close();
          onTap();
        },
        child: btn,
      ),
    );
  }
}

class _ChatSlidableWrapper extends StatefulWidget {
  final Widget Function(BuildContext context, SlidableController controller) builder;
  final void Function(SlidableController controller) onOpen;
  const _ChatSlidableWrapper({super.key, required this.builder, required this.onOpen});

  @override
  State<_ChatSlidableWrapper> createState() => _ChatSlidableWrapperState();
}

class _ChatSlidableWrapperState extends State<_ChatSlidableWrapper>
    with SingleTickerProviderStateMixin {
  late final SlidableController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SlidableController(this);
    _controller.actionPaneType.addListener(_handleTypeChange);
  }

  void _handleTypeChange() {
    if (_controller.actionPaneType.value != ActionPaneType.none) {
      widget.onOpen(_controller);
    }
  }

  @override
  void dispose() {
    _controller.actionPaneType.removeListener(_handleTypeChange);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(context, _controller);
  }
}

