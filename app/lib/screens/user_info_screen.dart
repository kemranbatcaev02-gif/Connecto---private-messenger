import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../calls/call_manager.dart';
import '../theme.dart';
import '../stories.dart';
import '../widgets/shop_media.dart';
import '../widgets/effects.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/premium_gift.dart';
import '../widgets/profile_showcase.dart';
import '../widgets/shared_media.dart';
import '../widgets/story_widgets.dart';
import '../widgets/ui.dart';
import 'chat_screen.dart';
import 'image_viewer.dart';
import 'mute_sheet.dart';
import 'report_sheet.dart';

/// Профиль пользователя (или бота).
/// chatId — личный чат с ним, если открыт из чата (для вложений и звука).
class UserInfoScreen extends StatefulWidget {
  final String userId;
  final String? chatId;
  final String name;
  final String? avatarUrl;
  const UserInfoScreen({
    super.key,
    required this.userId,
    this.chatId,
    this.name = '',
    this.avatarUrl,
  });

  @override
  State<UserInfoScreen> createState() => _UserInfoScreenState();
}

class _UserInfoScreenState extends State<UserInfoScreen> {
  Map<String, dynamic> _u = {};
  bool _loading = true;
  String? _error;
  final _showcase = GlobalKey<ProfileShowcaseState>();

  bool get _hasStories => _u['has_stories'] == true || stories.hasActive(widget.userId);
  bool get _unseenStories => stories.groupOf(widget.userId)?.hasUnseen ?? _u['has_stories'] == true;

  Future<void> _gift() async {
    final sent = await showGiftShop(context, toUserId: widget.userId, toName: _name);
    if (sent) _showcase.currentState?.reload();
  }

  /// Аватар: с кольцом историй (тап — смотреть), иначе — открыть фото.
  Widget _avatarWith(Widget avatar, String? url, {double size = 60}) {
    final frame = _u['frame'] is Map ? (_u['frame'] as Map).cast<String, dynamic>() : null;
    if (!_hasStories && frame != null) {
      return GestureDetector(
        onTap: url != null && url.isNotEmpty
            ? () => openImageViewer(context, url: mediaUrl(url))
            : null,
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: FramedAvatar(size: size, frame: frame, child: avatar),
        ),
      );
    }
    if (_hasStories) {
      return GestureDetector(
        onTap: () => openStoriesOf(context, widget.userId).then((_) {
          if (mounted) setState(() {});
        }),
        child: StoryRing(active: true, unseen: _unseenStories, width: 3, gap: 3, child: avatar),
      );
    }
    // рамка, которую человек выбрал себе (премиум-рамки — пока у него Premium)
    final ring = _u['avatar_ring'] as String?;
    return GestureDetector(
      onTap: url != null && url.isNotEmpty ? () => openImageViewer(context, url: mediaUrl(url)) : null,
      child: ring == null || ring == 'none'
          ? avatar
          : AvatarRing(style: ring, width: 3, child: avatar),
    );
  }

  bool get _isMe => widget.userId == appState.myUserId;

  /// Личный чат с человеком: открыли из чата — он, иначе — тот, что вернул сервер.
  String? get _chatId => widget.chatId ?? _u['chat_id'] as String?;

  /// Звук: включить сразу, выключить — выбрать на сколько.
  Future<void> _toggleMute() async {
    var cid = _chatId;
    try {
      cid ??= (await Api.createChat(type: 'direct', memberIds: [widget.userId]))['id'] as String;
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
      return;
    }
    if (!mounted) return;
    _u['chat_id'] = cid;
    if (appState.isMuted(cid)) {
      appState.unmute(cid);
      setState(() {});
      toast(context, 'Звук включён', icon: AppIcons.bell);
    } else {
      await showMuteSheet(context, cid);
      if (mounted) setState(() {});
    }
  }
  bool get _isBot => _u['is_bot'] == true;
  bool get _blocked => _u['blocked_by_me'] == true;

  String get _name {
    final n = [(_u['display_name'] as String?) ?? '', (_u['last_name'] as String?) ?? '']
        .where((x) => x.isNotEmpty)
        .join(' ');
    return n.isNotEmpty ? n : (widget.name.isNotEmpty ? widget.name : 'Пользователь');
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await Api.userProfile(widget.userId);
      if (mounted) {
        setState(() {
          _u = u;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, '$what скопирован', icon: AppIcons.copy);
  }

  /// Позвонить (личный чат создаётся, если его ещё нет).
  Future<void> _call(bool video) async {
    if (_blocked) {
      toast(context, 'Сначала разблокируй пользователя', icon: AppIcons.ban);
      return;
    }
    try {
      final chatId = _chatId ??
          (await Api.createChat(type: 'direct', memberIds: [widget.userId]))['id'] as String;
      await calls.start(
        chatId: chatId,
        peerId: widget.userId,
        name: _name,
        avatar: (_u['avatar_url'] as String?) ?? widget.avatarUrl,
        video: video,
      );
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  void _message() {
    if (widget.chatId != null) {
      Navigator.pop(context);
    } else {
      openDirectChat(context, widget.userId);
    }
  }

  Future<void> _toggleBlock() async {
    if (_blocked) {
      try {
        await Api.unblockUser(widget.userId);
        if (!mounted) return;
        setState(() => _u['blocked_by_me'] = false);
        toast(context, 'Разблокировано', icon: AppIcons.userCheck);
      } catch (e) {
        if (mounted) toast(context, friendlyError(e), error: true);
      }
      return;
    }
    var deleteChat = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text('Заблокировать $_name?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_isBot
                  ? 'Бот больше не сможет присылать вам сообщения.'
                  : 'Он(а) не сможет писать вам, звать в группы, видеть ваш статус и фото.'),
              if (widget.chatId != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: deleteChat,
                  onChanged: (v) => setLocal(() => deleteChat = v ?? false),
                  title: const Text('Удалить чат у себя'),
                ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Заблокировать',
                    style: TextStyle(color: kDanger, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await Api.blockUser(widget.userId);
      if (deleteChat && widget.chatId != null) {
        await Api.deleteChat(widget.chatId!);
      }
      if (!mounted) return;
      setState(() => _u['blocked_by_me'] = true);
      toast(context, 'Заблокировано', icon: AppIcons.ban);
      if (deleteChat) {
        Navigator.of(context).popUntil((r) => r.isFirst);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Widget _action(IconData icon, String label, VoidCallback onTap,
          {Color? color, bool danger = false, bool primary = false}) =>
      ProfileAction(
          icon: icon, label: label, onTap: onTap, color: color, danger: danger, primary: primary);

  /// Звонок: выбрать аудио или видео.
  Future<void> _chooseCall() async {
    final video = await showAppSheet<bool>(context, builder: (ctx) {
      Widget tile(IconData icon, String title, String sub, bool v) => Expanded(
            child: Pressable(
              onTap: () => Navigator.pop(ctx, v),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 10),
                decoration: BoxDecoration(
                  color: Theme.of(ctx).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(kRadius),
                ),
                child: Column(children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle, gradient: accentGradient(appState.accent)),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 10),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(sub,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: subtleText(ctx), fontSize: 12)),
                ]),
              ),
            ),
          );
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Позвонить $_name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          const SizedBox(height: 14),
          Row(children: [
            tile(AppIcons.phone, 'Аудиозвонок', 'только голос', false),
            const SizedBox(width: 10),
            tile(AppIcons.video, 'Видеозвонок', 'с камерой', true),
          ]),
        ]),
      );
    });
    if (video != null) _call(video);
  }

  /// Меню «⋮»: подарки, звук, жалоба, блокировка.
  Future<void> _menu() async {
    await showAppSheet<void>(context, builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      return Column(mainAxisSize: MainAxisSize.min, children: [
        if (!_isBot) ...[
          SheetItem(icon: AppIcons.gift, title: 'Подарить подарок', onTap: () => go(_gift)),
          SheetItem(
              icon: AppIcons.crown,
              title: 'Подарить Premium',
              onTap: () => go(() => showPremiumGift(context, toUserId: widget.userId, toName: _name))),
        ],
        if (_u['handle'] is String && (_u['handle'] as String).isNotEmpty)
          SheetItem(
              icon: AppIcons.copy,
              title: 'Скопировать юзернейм',
              onTap: () => go(() => _copy('@${_u['handle']}', 'Юзернейм'))),
        SheetItem(
            icon: AppIcons.flag,
            title: 'Пожаловаться',
            onTap: () => go(() => showReportSheet(context,
                type: _isBot ? 'bot' : 'person', targetId: widget.userId, chatId: widget.chatId))),
        SheetItem(
            icon: _blocked ? AppIcons.userCheck : AppIcons.ban,
            title: _blocked ? 'Разблокировать' : 'Заблокировать',
            danger: !_blocked,
            onTap: () => go(_toggleBlock)),
        const SizedBox(height: 8),
      ]);
    });
  }

  Widget _info(IconData icon, String value, String label, {VoidCallback? onTap}) => InfoTile(
        icon: icon,
        title: Text(value),
        label: label,
        onTap: onTap,
        trailing: onTap == null
            ? null
            : Icon(AppIcons.copy, size: 18, color: subtleText(context).withValues(alpha: 0.7)),
      );

  @override
  Widget build(BuildContext context) {
    final avatar = (_u['avatar_url'] as String?) ?? widget.avatarUrl;
    final handle = _u['handle'] as String?;
    final bio = (_u['bio'] as String?) ?? '';
    final phone = (_u['phone'] as String?) ?? '';
    final bday = (_u['birthday'] as String?) ?? '';
    final online = _u['online'] == true;
    final status = _isBot
        ? 'бот'
        : lastSeenText(parseServerTime(_u['last_seen'] as String? ?? ''), online: online);
    final commands = ((_u['commands'] as List?) ?? const [])
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();
    final muted = _chatId != null && appState.isMuted(_chatId!);

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (!_isMe && _u.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Pressable(
                onTap: _menu,
                scale: 0.9,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: appState.accent.withValues(alpha: 0.14),
                  ),
                  child: Icon(AppIcons.ellipsisVertical, color: appState.accent, size: 22),
                ),
              ),
            ),
        ],
      ),
      body: _error != null && _u.isEmpty
          ? EmptyState(
              icon: AppIcons.userX,
              title: 'Профиль недоступен',
              subtitle: _error,
              action: TextButton(
                  onPressed: () {
                    setState(() {
                      _loading = true;
                      _error = null;
                    });
                    _load();
                  },
                  child: const Text('Повторить')))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  FadeSlideIn(
                    child: (_u['cover_url'] as String?)?.isNotEmpty == true
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(kRadiusL),
                            child: AspectRatio(
                              aspectRatio: 1,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  CoverView(
                                      url: _u['cover_url'] as String,
                                      kind: _u['cover_kind'] as String?),
                                  Positioned.fill(
                                      child: ProfileFxOverlay(
                                          fx: _u['profile_fx'] is Map
                                              ? (_u['profile_fx'] as Map).cast<String, dynamic>()
                                              : null)),
                                  const DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topCenter,
                                        end: Alignment.bottomCenter,
                                        stops: [0.45, 1],
                                        colors: [Colors.transparent, Color(0xCC000000)],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 16,
                                    right: 16,
                                    bottom: 16,
                                    child: Row(
                                      children: [
                                        _avatarWith(
                                            Avatar(
                                                name: _name,
                                                url: avatar,
                                                size: _hasStories ? 52 : 60,
                                                online: online),
                                            avatar,
                                            size: _hasStories ? 52 : 60),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              NameBadges(_name,
                                                  verified: _u['is_verified'] == true,
                                                  premium: _u['is_premium'] == true,
                                                  emoji: _u['emoji_status'] as String?,
                                                  bot: _isBot,
                                                  maxLines: 2,
                                                  style: const TextStyle(
                                                      fontSize: 21,
                                                      fontWeight: FontWeight.w800,
                                                      color: Colors.white)),
                                              const SizedBox(height: 2),
                                              Text(_blocked ? 'заблокирован(а)' : status,
                                                  style: TextStyle(
                                                      color: online && !_isBot
                                                          ? const Color(0xFF86EFAC)
                                                          : Colors.white70,
                                                      fontWeight: FontWeight.w600)),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Column(
                      children: [
                        _avatarWith(
                            Hero(
                              tag: widget.chatId != null
                                  ? 'chat-avatar-${widget.chatId}'
                                  : 'user-avatar-${widget.userId}',
                              child: Avatar(
                                  name: _name,
                                  url: avatar,
                                  size: _hasStories ? 100 : 112,
                                  online: online),
                            ),
                            avatar,
                            size: _hasStories ? 100 : 112),
                        const SizedBox(height: 14),
                        NameBadges(_name,
                            verified: _u['is_verified'] == true,
                            premium: _u['is_premium'] == true,
                            emoji: _u['emoji_status'] as String?,
                            bot: _isBot,
                            maxLines: 2,
                            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 4),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 200),
                          child: Text(_loading ? ' ' : (_blocked ? 'заблокирован(а)' : status),
                              key: ValueKey('$_loading$status$_blocked'),
                              style: TextStyle(
                                  color: online && !_isBot ? kSuccess : subtleText(context),
                                  fontWeight: online ? FontWeight.w600 : FontWeight.w400)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (!_isMe)
                    FadeSlideIn(
                      delayMs: 60,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: _isBot ? 64 : 28),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _action(AppIcons.messageCircle, 'Чат', _message, primary: true),
                            _action(muted ? AppIcons.bellOff : AppIcons.bell,
                                muted ? 'Включить звук' : 'Выключить звук', _toggleMute,
                                color: muted ? kWarning : null),
                            if (!_isBot) _action(AppIcons.phone, 'Позвонить', _chooseCall),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: 18),
                  if (_loading)
                    const SectionCard(children: [
                      Padding(padding: EdgeInsets.all(16), child: Shimmer(height: 18)),
                      Padding(padding: EdgeInsets.all(16), child: Shimmer(height: 18)),
                    ])
                  else if (handle != null || bio.isNotEmpty || phone.isNotEmpty || bday.isNotEmpty)
                    FadeSlideIn(
                      delayMs: 100,
                      child: SectionCard(children: [
                        if (bio.isNotEmpty)
                          _info(AppIcons.info, bio, _isBot ? 'Описание' : 'О себе'),
                        if (handle != null && handle.isNotEmpty)
                          _info(AppIcons.atSign, '@$handle', 'Имя пользователя',
                              onTap: () => _copy('@$handle', 'Юзернейм')),
                        if (phone.isNotEmpty)
                          _info(AppIcons.phone, phone, 'Телефон',
                              onTap: () => _copy(phone, 'Номер')),
                        if (bday.isNotEmpty) _info(AppIcons.cake, _fmtBday(bday), 'День рождения'),
                      ]),
                    ),
                  if (!_isBot && _u.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    FadeSlideIn(
                      delayMs: 140,
                      child: ProfileShowcase(
                        key: _showcase,
                        userId: widget.userId,
                        name: _name,
                        avatarUrl: avatar,
                        onGift: _isMe ? null : _gift,
                      ),
                    ),
                  ],
                  if (commands.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const SectionLabel('Команды бота'),
                    SectionCard(children: [
                      for (final c in commands)
                        ListTile(
                          leading: IconTile(AppIcons.squareSlash),
                          title: Text('/${c['command']}',
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: (c['description'] as String? ?? '').isEmpty
                              ? null
                              : Text(c['description'] as String,
                                  style: TextStyle(color: subtleText(context))),
                        ),
                    ]),
                  ],
                  if (_chatId != null) ...[
                    const SizedBox(height: 16),
                    const SectionLabel('Вложения'),
                    SharedMediaCard(chatId: _chatId!),
                  ],

                ],
              ),
            ),
    );
  }

  String _fmtBday(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    const months = [
      'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
