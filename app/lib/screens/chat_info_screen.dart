import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../realtime.dart';
import '../theme.dart';
import '../widgets/member_card.dart';
import '../widgets/shared_media.dart';
import '../widgets/ui.dart';
import '../widgets/user_picker.dart';
import 'chat_screen.dart';
import 'mute_sheet.dart';
import 'report_sheet.dart';
import 'user_info_screen.dart';

/// Профиль группы или канала: описание, ссылка, участники, управление.
/// Возвращает 'left', если пользователь вышел/удалил чат.
class ChatInfoScreen extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic>? chat;
  const ChatInfoScreen({super.key, required this.chatId, this.chat});

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  late Map<String, dynamic> _chat =
      Map<String, dynamic>.from(widget.chat ?? {'id': widget.chatId});
  List<Map<String, dynamic>> _members = [];
  bool _membersLoading = true;
  String? _membersError;
  final _q = TextEditingController();

  bool get _isChannel => _chat['type'] == 'channel';
  String get _role => (_chat['my_role'] as String?) ?? '';
  bool get _isOwner => _role == 'owner';
  bool get _isAdmin => _role == 'owner' || _role == 'admin';
  bool get _isMember => _chat['is_member'] == true;
  bool get _canAdd =>
      _isMember && (_isAdmin || (!_isChannel && _chat['members_can_add'] == true));
  bool get _canSeeMembers => _isMember && (!_isChannel || _isAdmin);
  String get _title => (_chat['title'] as String?) ?? '';
  int get _count => (_chat['member_count'] as num?)?.toInt() ?? _members.length;

  @override
  void initState() {
    super.initState();
    Realtime.addListener(_onEvent);
    _reload();
  }

  @override
  void dispose() {
    Realtime.removeListener(_onEvent);
    _q.dispose();
    super.dispose();
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['chat_id'] != widget.chatId) return;
    if (e['type'] == 'chat_updated') _reload();
    if (e['type'] == 'chat_deleted' && mounted) Navigator.pop(context, 'left');
    if (e['type'] == 'message' && e['kind'] == 'service') _loadMembers();
  }

  Future<void> _reload() async {
    try {
      final c = await Api.chatInfo(widget.chatId);
      if (mounted) setState(() => _chat = c);
    } catch (_) {}
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    if (!_canSeeMembers) {
      if (mounted) setState(() => _membersLoading = false);
      return;
    }
    try {
      final list = await Api.members(widget.chatId);
      if (!mounted) return;
      setState(() {
        _members = list.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _membersLoading = false;
        _membersError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _membersLoading = false;
          _membersError = friendlyError(e);
        });
      }
    }
  }

  // ── действия ──

  String? get _publicLink {
    final h = _chat['handle'] as String?;
    if (h == null || h.isEmpty) return null;
    return '@$h';
  }

  void _copy(String text, String what) {
    Clipboard.setData(ClipboardData(text: text));
    toast(context, '$what скопирована', icon: AppIcons.copy);
  }

  Future<void> _regenerate() async {
    final ok = await confirm(context,
        title: 'Сбросить ссылку?',
        body: 'Старая ссылка перестанет работать. Уже вступившие останутся.',
        action: 'Сбросить',
        danger: true);
    if (!ok) return;
    try {
      final r = await Api.regenerateInvite(widget.chatId);
      if (!mounted) return;
      setState(() => _chat['invite_link'] = r['invite_link']);
      toast(context, 'Создана новая ссылка', icon: AppIcons.link);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _addMembers() async {
    final exclude = _members.map((m) => m['id'] as String).toSet();
    final picked = await pickUsers(context,
        title: _isChannel ? 'Добавить подписчиков' : 'Добавить участников',
        action: 'Добавить',
        exclude: exclude,
        includeBots: _isAdmin);
    if (picked == null || picked.isEmpty || !mounted) return;
    try {
      final r = await Api.addMembers(
          widget.chatId, picked.map((u) => u['id'] as String).toList());
      if (!mounted) return;
      final added = (r['added'] as List?)?.length ?? 0;
      final skipped = ((r['skipped'] as List?) ?? const [])
          .map((e) => (e as Map)['name'])
          .join(', ');
      if (skipped.isNotEmpty) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Не всех удалось добавить'),
            content: Text(
                '$skipped запретил(и) приглашать себя в группы. Отправь им ссылку-приглашение.'),
            actions: [
              if (_chat['invite_link'] != null)
                TextButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _copy(_chat['invite_link'] as String, 'Ссылка');
                    },
                    child: const Text('Скопировать ссылку')),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
            ],
          ),
        );
      } else if (added > 0 && mounted) {
        toast(context,
            'Добавлено: ${plural(added, 'человек', 'человека', 'человек')}',
            icon: AppIcons.userPlus);
      }
      _reload();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  void _memberSheet(Map<String, dynamic> m) {
    final id = m['id'] as String;
    final me = id == appState.myUserId;
    final role = m['role'] as String? ?? 'member';
    final name = userName(m);
    final canKick = _isAdmin && !me && role != 'owner' && (role == 'member' || _isOwner);
    showAppSheet(context, builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Avatar(name: name, url: m['avatar_url'] as String?, size: 44),
            title: NameBadges(name,
                verified: m['is_verified'] == true,
                premium: m['is_premium'] == true,
                bot: m['is_bot'] == true),
            subtitle: Text(_roleLabel(role) ?? lastSeenText(
                parseServerTime(m['last_seen'] as String? ?? ''),
                online: m['online'] == true)),
          ),
          Divider(height: 1, color: hairline(ctx)),
          SheetItem(
              icon: AppIcons.userRound,
              title: 'Профиль',
              onTap: () => go(() => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => UserInfoScreen(userId: id, name: name))))),
          if (!me)
            SheetItem(
                icon: AppIcons.messageCircle,
                title: 'Написать',
                onTap: () => go(() => openDirectChat(context, id))),
          if (_isOwner && !me && role == 'member')
            SheetItem(
                icon: AppIcons.shieldPlus,
                title: 'Назначить администратором',
                onTap: () => go(() => _setRole(id, 'admin', name))),
          if (_isOwner && !me && role == 'admin')
            SheetItem(
                icon: AppIcons.shieldMinus,
                title: 'Снять права администратора',
                onTap: () => go(() => _setRole(id, 'member', name))),
          if (_isOwner && !me && m['is_bot'] != true)
            SheetItem(
                icon: AppIcons.crown,
                title: 'Передать права владельца',
                onTap: () => go(() => _transfer(id, name))),
          if (canKick)
            SheetItem(
                icon: AppIcons.userMinus,
                title: _isChannel ? 'Удалить из канала' : 'Удалить из группы',
                danger: true,
                onTap: () => go(() => _kick(id, name))),
          const SizedBox(height: 6),
        ],
      );
    });
  }

  String? _roleLabel(String role) => switch (role) {
        'owner' => 'владелец',
        'admin' => 'администратор',
        _ => null,
      };

  Future<void> _setRole(String id, String role, String name) async {
    try {
      await Api.setMemberRole(widget.chatId, id, role);
      if (!mounted) return;
      toast(context,
          role == 'admin' ? '$name теперь администратор' : '$name больше не администратор',
          icon: AppIcons.shield);
      _loadMembers();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _transfer(String id, String name) async {
    final ok = await confirm(context,
        title: 'Передать права владельца?',
        body: '$name станет владельцем ${_isChannel ? 'канала' : 'группы'}. '
            'Вы останетесь администратором. Отменить это сможет только новый владелец.',
        action: 'Передать',
        danger: true);
    if (!ok) return;
    try {
      await Api.transferOwnership(widget.chatId, id);
      if (!mounted) return;
      toast(context, 'Права владельца переданы', icon: AppIcons.crown);
      _reload();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _kick(String id, String name) async {
    final ok = await confirm(context,
        title: 'Удалить $name?',
        body: 'Пользователь попадёт в чёрный список и не сможет вернуться по ссылке, '
            'пока вы его не разблокируете.',
        action: 'Удалить',
        danger: true);
    if (!ok) return;
    try {
      await Api.kickMember(widget.chatId, id);
      if (!mounted) return;
      setState(() => _members.removeWhere((m) => m['id'] == id));
      toast(context, '$name удалён(а)', icon: AppIcons.userMinus);
      _reload();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _toggle(String key, bool v) async {
    setState(() => _chat[key] = v);
    try {
      final c = await Api.editChat(widget.chatId, {key: v});
      if (mounted) setState(() => _chat = c);
    } catch (e) {
      if (mounted) {
        setState(() => _chat[key] = !v);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _leave() async {
    final ok = await confirm(context,
        title: _isChannel ? 'Покинуть канал?' : 'Покинуть группу?',
        body: _isOwner
            ? 'Вы владелец. Права перейдут другому администратору или самому давнему участнику.'
            : null,
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

  Future<void> _deleteForAll() async {
    final ok = await confirm(context,
        title: _isChannel ? 'Удалить канал?' : 'Удалить группу?',
        body: 'Все сообщения и участники будут удалены навсегда. Это нельзя отменить.',
        action: 'Удалить навсегда',
        danger: true);
    if (!ok) return;
    try {
      await Api.deleteChat(widget.chatId, both: true);
      if (mounted) Navigator.pop(context, 'left');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _join() async {
    try {
      final c = await Api.joinPublic(widget.chatId);
      if (mounted) setState(() => _chat = c);
      _loadMembers();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  // ── UI ──

  Widget _action(IconData icon, String label, VoidCallback onTap, {bool danger = false}) =>
      ProfileAction(icon: icon, label: label, onTap: onTap, danger: danger);

  @override
  Widget build(BuildContext context) {
    final muted = appState.isMuted(widget.chatId);
    final desc = (_chat['description'] as String?) ?? '';
    final invite = _chat['invite_link'] as String?;
    final q = _q.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? _members
        : _members
            .where((m) =>
                userName(m).toLowerCase().contains(q) ||
                ((m['handle'] as String?) ?? '').toLowerCase().contains(q))
            .toList();
    final online = _members.where((m) => m['online'] == true).length;
    final typeLabel = _isChannel
        ? (_publicLink != null ? 'публичный канал' : 'частный канал')
        : (_publicLink != null ? 'публичная группа' : 'частная группа');
    final countLabel = _isChannel
        ? plural(_count, 'подписчик', 'подписчика', 'подписчиков')
        : plural(_count, 'участник', 'участника', 'участников');

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (_isAdmin)
            TextButton(
              onPressed: () async {
                final r = await Navigator.push<Map<String, dynamic>>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => EditChatScreen(chat: _chat)));
                if (r != null && mounted) setState(() => _chat = r);
              },
              child: const Text('Изменить', style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          children: [
            FadeSlideIn(
              child: Column(
                children: [
                  Hero(
                    tag: 'chat-avatar-${widget.chatId}',
                    child: Avatar(
                      name: _title,
                      url: _chat['avatar_url'] as String?,
                      size: 108,
                      icon: _isChannel ? AppIcons.megaphone : AppIcons.users,
                    ),
                  ),
                  const SizedBox(height: 14),
                  NameBadges(_title,
                      verified: _chat['is_verified'] == true,
                      maxLines: 2,
                      style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      _canSeeMembers && online > 0 && !_isChannel
                          ? '$countLabel, $online в сети'
                          : '$countLabel · $typeLabel',
                      style: TextStyle(color: subtleText(context))),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_isMember)
              FadeSlideIn(
                delayMs: 60,
                child: Row(
                  children: [
                    _action(muted ? AppIcons.bell : AppIcons.bellOff,
                        muted ? 'Вкл. звук' : 'Без звука', () async {
                      showMuteSheet(context, widget.chatId);
                    }),
                    if (_canAdd)
                      _action(AppIcons.userPlus, 'Добавить', _addMembers),
                    if (invite != null || _publicLink != null)
                      _action(AppIcons.share2, 'Ссылка',
                          () => _copy(invite ?? _publicLink!, 'Ссылка')),
                    _action(AppIcons.logOut, 'Выйти', _leave, danger: true),
                  ],
                ),
              )
            else
              PrimaryButton(
                  label: _isChannel ? 'Подписаться' : 'Вступить',
                  icon: AppIcons.userPlus,
                  onTap: _join),
            const SizedBox(height: 18),
            if (desc.isNotEmpty || _publicLink != null) ...[
              SectionCard(children: [
                if (desc.isNotEmpty)
                  ListTile(
                    leading: IconTile(AppIcons.info),
                    title: SelectableText(desc, style: const TextStyle(height: 1.35)),
                    subtitle: Text('Описание', style: TextStyle(color: subtleText(context))),
                  ),
                if (_publicLink != null)
                  ListTile(
                    leading: IconTile(AppIcons.atSign),
                    title: Text(_publicLink!,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text('Публичная ссылка — найти можно через поиск',
                        style: TextStyle(color: subtleText(context))),
                    trailing: IconButton(
                        icon: const Icon(AppIcons.copy),
                        onPressed: () => _copy(_publicLink!, 'Ссылка')),
                  ),
              ]),
              const SizedBox(height: 16),
            ],
            if (invite != null) ...[
              const SectionLabel('Ссылка-приглашение'),
              SectionCard(children: [
                ListTile(
                  leading: IconTile(AppIcons.link),
                  title: Text(invite,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('По ней можно вступить без поиска',
                      style: TextStyle(color: subtleText(context))),
                  onTap: () => _copy(invite, 'Ссылка'),
                  trailing: IconButton(
                      icon: const Icon(AppIcons.copy),
                      onPressed: () => _copy(invite, 'Ссылка')),
                ),
                SettingsTile(
                    icon: AppIcons.refreshCw,
                    title: 'Сбросить ссылку',
                    onTap: _regenerate,
                    chevron: false),
              ]),
              const SizedBox(height: 16),
            ],
            if (_isAdmin) ...[
              const SectionLabel('Управление'),
              SectionCard(children: [
                if (!_isChannel)
                  SwitchTile(
                    icon: AppIcons.messageSquare,
                    title: 'Участники могут писать',
                    subtitle: 'Иначе — только администраторы',
                    value: _chat['members_can_send'] != false,
                    onChanged: (v) => _toggle('members_can_send', v),
                  ),
                if (!_isChannel)
                  SwitchTile(
                    icon: AppIcons.userPlus,
                    title: 'Участники могут добавлять',
                    subtitle: 'Приглашать своих знакомых',
                    value: _chat['members_can_add'] == true,
                    onChanged: (v) => _toggle('members_can_add', v),
                  ),
                SettingsTile(
                  icon: AppIcons.userX,
                  title: 'Чёрный список',
                  subtitle: 'Удалённые пользователи',
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => _BansScreen(chatId: widget.chatId))),
                ),
              ]),
              const SizedBox(height: 16),
            ],
            if (_canSeeMembers) ...[
              SectionLabel(_isChannel ? 'Подписчики · $_count' : 'Участники · $_count'),
              if (_members.length > 8)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: AppTextField(
                      controller: _q,
                      hint: 'Поиск участников',
                      icon: AppIcons.search,
                      onChanged: (_) => setState(() {})),
                ),
              if (_canAdd)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: SectionCard(children: [
                    SettingsTile(
                        icon: AppIcons.userPlus,
                        title: _isChannel ? 'Добавить подписчиков' : 'Добавить участников',
                        onTap: _addMembers,
                        chevron: false),
                  ]),
                ),
              if (_membersLoading)
                const Padding(
                    padding: EdgeInsets.all(16), child: Shimmer(height: 40, radius: 12))
              else if (_membersError != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_membersError!, style: TextStyle(color: subtleText(context))),
                )
              else
                for (final m in shown) _memberTile(m),
              const SizedBox(height: 16),
            ],
            if (_isMember) ...[
              const SectionLabel('Вложения'),
              SharedMediaCard(chatId: widget.chatId),
              const SizedBox(height: 16),
            ],
            SectionCard(children: [
              if (_isMember)
                SettingsTile(
                    icon: AppIcons.logOut,
                    title: _isChannel ? 'Покинуть канал' : 'Покинуть группу',
                    danger: true,
                    onTap: _leave,
                    chevron: false),
              if (_isOwner)
                SettingsTile(
                    icon: AppIcons.trash2,
                    title: _isChannel ? 'Удалить канал' : 'Удалить группу',
                    subtitle: 'Для всех участников',
                    danger: true,
                    onTap: _deleteForAll,
                    chevron: false),
              if (!_isOwner)
                SettingsTile(
                    icon: AppIcons.flag,
                    title: 'Пожаловаться',
                    danger: true,
                    onTap: () => showReportSheet(context,
                        type: _isChannel ? 'channel' : 'person', chatId: widget.chatId),
                    chevron: false),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _memberTile(Map<String, dynamic> m) {
    return MemberCard(
      member: m,
      onTap: () => _memberSheet(m),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Редактирование группы/канала
// ─────────────────────────────────────────────────────────────

class EditChatScreen extends StatefulWidget {
  final Map<String, dynamic> chat;
  const EditChatScreen({super.key, required this.chat});
  @override
  State<EditChatScreen> createState() => _EditChatScreenState();
}

class _EditChatScreenState extends State<EditChatScreen> {
  late final _title = TextEditingController(text: widget.chat['title'] as String? ?? '');
  late final _desc =
      TextEditingController(text: widget.chat['description'] as String? ?? '');
  late final _handle = TextEditingController(text: widget.chat['handle'] as String? ?? '');
  late bool _public = (widget.chat['handle'] as String?)?.isNotEmpty == true;
  late String? _avatar = widget.chat['avatar_url'] as String?;
  bool _uploading = false;
  bool _saving = false;

  bool get _isChannel => widget.chat['type'] == 'channel';

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final x = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024);
    if (x == null) return;
    setState(() => _uploading = true);
    try {
      final up = await Api.uploadPath(x.path);
      if (mounted) setState(() => _avatar = up['url'] as String?);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      toast(context, 'Название не может быть пустым', error: true);
      return;
    }
    final handle = _public ? _handle.text.trim().replaceFirst('@', '') : '';
    if (_public && !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{3,31}$').hasMatch(handle)) {
      toast(context, 'Ссылка: 4–32 символа, латиница, цифры и _, начинается с буквы',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final c = await Api.editChat(widget.chat['id'] as String, {
        'title': title,
        'description': _desc.text.trim(),
        'avatar_url': _avatar ?? '',
        'handle': handle,
      });
      if (mounted) {
        toast(context, 'Сохранено');
        Navigator.pop(context, c);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isChannel ? 'Канал' : 'Группа')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: Pressable(
              onTap: _uploading ? null : _pickAvatar,
              child: Stack(
                children: [
                  Avatar(
                      name: _title.text,
                      url: _avatar,
                      size: 104,
                      icon: _isChannel ? AppIcons.megaphone : AppIcons.users),
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                          color: Colors.black38, shape: BoxShape.circle),
                      child: _uploading
                          ? const Center(
                              child: CircularProgressIndicator(color: Colors.white))
                          : const Icon(AppIcons.camera, color: Colors.white, size: 30),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_avatar != null && _avatar!.isNotEmpty)
            Center(
              child: TextButton(
                  onPressed: () => setState(() => _avatar = ''),
                  child: const Text('Удалить фото', style: TextStyle(color: kDanger))),
            ),
          const SizedBox(height: 18),
          AppTextField(
              controller: _title,
              hint: 'Название',
              icon: AppIcons.type,
              maxLength: 128,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 12),
          AppTextField(
              controller: _desc,
              hint: 'Описание (необязательно)',
              icon: AppIcons.info,
              maxLines: 4,
              maxLength: 500),
          const SizedBox(height: 22),
          SectionLabel(_isChannel ? 'Тип канала' : 'Тип группы'),
          SectionCard(children: [
            _typeTile(false),
            _typeTile(true),
          ]),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _public
                ? Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: AppTextField(
                      controller: _handle,
                      hint: 'ссылка',
                      prefixText: '@',
                      icon: AppIcons.atSign,
                      maxLength: 32,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text(
                _public
                    ? 'Публичный ${_isChannel ? 'канал' : 'чат'} находят через поиск по @ссылке, '
                        'а читать его можно даже без вступления.'
                    : 'В частный ${_isChannel ? 'канал' : 'чат'} можно попасть только по ссылке-приглашению.',
                style: TextStyle(color: subtleText(context), fontSize: 12.5, height: 1.35)),
          ),
          const SizedBox(height: 26),
          PrimaryButton(label: 'Сохранить', loading: _saving, onTap: _save),
        ],
      ),
    );
  }

  Widget _typeTile(bool pub) {
    final sel = _public == pub;
    return ListTile(
      onTap: () => setState(() => _public = pub),
      leading: Icon(pub ? AppIcons.globe : AppIcons.lock,
          color: sel ? appState.accent : subtleText(context)),
      title: Text(pub ? 'Публичный' : 'Частный',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(pub ? 'Виден в поиске' : 'Вход только по ссылке',
          style: TextStyle(color: subtleText(context))),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? appState.accent : subtleText(context), width: sel ? 7 : 2),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Чёрный список чата
// ─────────────────────────────────────────────────────────────

class _BansScreen extends StatefulWidget {
  final String chatId;
  const _BansScreen({required this.chatId});
  @override
  State<_BansScreen> createState() => _BansScreenState();
}

class _BansScreenState extends State<_BansScreen> {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.chatBans(widget.chatId);
      if (mounted) {
        setState(() {
          _list = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _unban(Map<String, dynamic> u) async {
    try {
      await Api.unbanMember(widget.chatId, u['id'] as String);
      if (!mounted) return;
      setState(() => _list.remove(u));
      toast(context, '${userName(u)} может вернуться по ссылке',
          icon: AppIcons.userCheck);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чёрный список')),
      body: _loading
          ? const SingleChildScrollView(child: ListSkeleton(count: 4))
          : _list.isEmpty
              ? const EmptyState(
                  icon: AppIcons.userCheck,
                  title: 'Никого нет',
                  subtitle: 'Сюда попадают удалённые из чата пользователи')
              : ListView(
                  children: [
                    for (final u in _list)
                      ListTile(
                        leading: Avatar(
                            name: userName(u), url: u['avatar_url'] as String?, size: 44),
                        title: Text(userName(u),
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        trailing: TextButton(
                            onPressed: () => _unban(u), child: const Text('Вернуть')),
                      ),
                  ],
                ),
    );
  }
}
