import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'chat_screen.dart';

/// Мои боты — как @BotFather: создать, токен, описание, команды, удалить.
class BotsScreen extends StatefulWidget {
  const BotsScreen({super.key});
  @override
  State<BotsScreen> createState() => _BotsScreenState();
}

class _BotsScreenState extends State<BotsScreen> {
  List<Map<String, dynamic>> _bots = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.myBots();
      if (!mounted) return;
      setState(() {
        _bots = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  Future<void> _create() async {
    final r = await showAppSheet<Map<String, dynamic>>(context,
        scrollable: true, builder: (ctx) => const _CreateBotSheet());
    if (r == null || !mounted) return;
    setState(() => _bots.add(r));
    await showTokenDialog(context, r['token'] as String? ?? '', created: true);
    if (!mounted) return;
    _open(r);
  }

  Future<void> _open(Map<String, dynamic> b) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => BotDetailScreen(bot: b)));
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final limit = appState.isPremium ? 20 : 5;
    return Scaffold(
      appBar: AppBar(title: const Text('Мои боты')),
      floatingActionButton: _bots.length < limit
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(AppIcons.plus),
              label: const Text('Создать бота'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [ListSkeleton(count: 3)])
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    EmptyState(
                        icon: AppIcons.wifiOff,
              mascot: 'empty_no_internet',
                        title: 'Не удалось загрузить',
                        subtitle: _error,
                        action: TextButton(onPressed: _load, child: const Text('Повторить'))),
                  ])
                : _bots.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 60),
                        EmptyState(
                          icon: AppIcons.bot,
                          title: 'Своих ботов пока нет',
                          subtitle:
                              'Бот — это аккаунт, которым управляет твоя программа. '
                              'Создай его, получи токен и подключи код на Python.',
                          action: SizedBox(
                            width: 220,
                            child: PrimaryButton(
                                label: 'Создать бота',
                                icon: AppIcons.plus,
                                onTap: _create),
                          ),
                        ),
                      ])
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                        children: [
                          SectionLabel('Боты · ${_bots.length}/$limit'),
                          SectionCard(children: [
                            for (final b in _bots)
                              ListTile(
                                onTap: () => _open(b),
                                leading: Avatar(
                                  name: (b['display_name'] as String?) ?? 'Бот',
                                  url: b['avatar_url'] as String?,
                                  size: 46,
                                  icon: (b['avatar_url'] as String?)?.isNotEmpty == true
                                      ? null
                                      : AppIcons.bot,
                                  useAccent: true,
                                ),
                                title: NameBadges((b['display_name'] as String?) ?? 'Бот',
                                    bot: true,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700, fontSize: 15.5)),
                                subtitle: Text('@${b['username']}',
                                    style: TextStyle(color: subtleText(context))),
                                trailing: Icon(AppIcons.chevronRight,
                                    color: subtleText(context)),
                              ),
                          ]),
                          if (!appState.isPremium) ...[
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              child: Text('Без Premium — до 5 ботов, с Premium — до 20.',
                                  style: TextStyle(
                                      color: subtleText(context), fontSize: 12.5)),
                            ),
                          ],
                        ],
                      ),
      ),
    );
  }
}

/// Показать токен (он виден только сразу после создания/смены).
Future<void> showTokenDialog(BuildContext context, String token, {bool created = false}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(created ? AppIcons.partyPopper : AppIcons.keyRound,
          color: appState.accent, size: 40),
      title: Text(created ? 'Бот создан!' : 'Новый токен'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Токен для доступа к Bot API. Храни его в секрете — '
              'с ним можно управлять ботом. Показываем один раз.'),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Theme.of(ctx).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12)),
            child: SelectableText(token,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5)),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: token));
              toast(ctx, 'Токен скопирован', icon: AppIcons.copy);
            },
            child: const Text('Скопировать')),
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Готово', style: TextStyle(fontWeight: FontWeight.w800))),
      ],
    ),
  );
}

class _CreateBotSheet extends StatefulWidget {
  const _CreateBotSheet();
  @override
  State<_CreateBotSheet> createState() => _CreateBotSheetState();
}

class _CreateBotSheetState extends State<_CreateBotSheet> {
  final _name = TextEditingController();
  final _user = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _name.dispose();
    _user.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final name = _name.text.trim();
    final user = _user.text.trim().replaceFirst('@', '');
    if (name.isEmpty) {
      toast(context, 'Придумай имя бота', error: true);
      return;
    }
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{1,28}bot$', caseSensitive: false).hasMatch(user)) {
      toast(context, 'Юзернейм: латиница, цифры, _ и в конце «bot» (напр. weather_bot)',
          error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final r = await Api.createBot(name, user);
      if (mounted) Navigator.pop(context, r);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Новый бот',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          AppTextField(
              controller: _name,
              hint: 'Имя (напр. Погода)',
              icon: AppIcons.bot,
              autofocus: true,
              maxLength: 64),
          const SizedBox(height: 10),
          AppTextField(
              controller: _user,
              hint: 'юзернейм, заканчивается на bot',
              prefixText: '@',
              icon: AppIcons.atSign,
              maxLength: 32,
              onSubmitted: (_) => _go()),
          const SizedBox(height: 16),
          PrimaryButton(label: 'Создать', loading: _loading, onTap: _go),
        ],
      ),
    );
  }
}

/// Управление одним ботом.
class BotDetailScreen extends StatefulWidget {
  final Map<String, dynamic> bot;
  const BotDetailScreen({super.key, required this.bot});
  @override
  State<BotDetailScreen> createState() => _BotDetailScreenState();
}

class _BotDetailScreenState extends State<BotDetailScreen> {
  late Map<String, dynamic> _b = Map<String, dynamic>.from(widget.bot);
  bool _uploading = false;

  String get _id => _b['id'] as String;
  List<Map<String, dynamic>> get _commands => ((_b['commands'] as List?) ?? const [])
      .map((e) => (e as Map).cast<String, dynamic>())
      .toList();

  Future<void> _edit(Map<String, dynamic> data, {String ok = 'Сохранено'}) async {
    try {
      final r = await Api.editBot(_id, data);
      if (!mounted) return;
      setState(() => _b = {..._b, ...r});
      toast(context, ok);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _rename() async {
    final v = await askText(context,
        title: 'Имя бота',
        initial: (_b['display_name'] as String?) ?? '',
        maxLength: 64);
    if (v != null && v.isNotEmpty) _edit({'display_name': v});
  }

  Future<void> _about() async {
    final v = await askText(context,
        title: 'Описание',
        hint: 'Что умеет бот — видно в профиле и в пустом чате',
        initial: (_b['bio'] as String?) ?? '',
        maxLength: 300);
    if (v != null) _edit({'bio': v});
  }

  Future<void> _photo() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 800);
      if (x == null || !mounted) return;
      setState(() => _uploading = true);
      final up = await Api.uploadPath(x.path);
      await _edit({'avatar_url': up['url']}, ok: 'Фото обновлено');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addCommand() async {
    final cmd = TextEditingController();
    final desc = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая команда'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: cmd,
                autofocus: true,
                decoration: const InputDecoration(prefixText: '/', hintText: 'start')),
            const SizedBox(height: 10),
            TextField(
                controller: desc,
                decoration: const InputDecoration(hintText: 'Описание (напр. Запустить бота)')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Добавить', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    final name = cmd.text.trim().replaceFirst('/', '').toLowerCase();
    if (ok != true) return;
    if (!RegExp(r'^[a-z0-9_]{1,32}$').hasMatch(name)) {
      if (mounted) toast(context, 'Команда: латиница в нижнем регистре, цифры и _', error: true);
      return;
    }
    final list = _commands..removeWhere((c) => c['command'] == name);
    list.add({'command': name, 'description': desc.text.trim()});
    _edit({'commands': list}, ok: 'Команда /$name добавлена');
  }

  void _removeCommand(Map<String, dynamic> c) {
    final list = _commands..removeWhere((x) => x['command'] == c['command']);
    _edit({'commands': list}, ok: 'Команда удалена');
  }

  Future<void> _newToken() async {
    final ok = await confirm(context,
        title: 'Выпустить новый токен?',
        body: 'Старый токен сразу перестанет работать — обнови его в своём коде.',
        action: 'Выпустить',
        danger: true);
    if (!ok) return;
    try {
      final r = await Api.regenerateBotToken(_id);
      if (!mounted) return;
      await showTokenDialog(context, r['token'] as String? ?? '');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete() async {
    final ok = await confirm(context,
        title: 'Удалить бота?',
        body: '@${_b['username']} и вся его переписка будут удалены навсегда.',
        action: 'Удалить',
        danger: true);
    if (!ok) return;
    try {
      await Api.deleteBot(_id);
      if (!mounted) return;
      toast(context, 'Бот удалён', icon: AppIcons.trash2);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  String get _example => '''import requests, time

TOKEN = "ТВОЙ_ТОКЕН"
API = f"$kBaseUrl/bot{TOKEN}"

offset = 0
while True:
    r = requests.get(f"{API}/getUpdates",
                     params={"offset": offset, "timeout": 25}).json()
    for u in r["result"]:
        offset = u["update_id"] + 1
        m = u.get("message")
        if not m:
            continue
        text = m.get("text") or ""
        reply = "Привет! Я бот 🤖" if text == "/start" else "Ты написал: " + text
        requests.post(f"{API}/sendMessage",
                      json={"chat_id": m["chat"]["id"], "text": reply})''';

  @override
  Widget build(BuildContext context) {
    final name = (_b['display_name'] as String?) ?? 'Бот';
    final bio = (_b['bio'] as String?) ?? '';
    final webhook = (_b['webhook'] as String?) ?? '';
    return Scaffold(
      appBar: AppBar(title: Text('@${_b['username']}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          FadeSlideIn(
            child: Column(
              children: [
                Pressable(
                  onTap: _uploading ? null : _photo,
                  child: Stack(
                    children: [
                      Avatar(
                          name: name,
                          url: _b['avatar_url'] as String?,
                          size: 96,
                          useAccent: true,
                          icon: AppIcons.bot),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                              color: appState.accent,
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Theme.of(context).scaffoldBackgroundColor,
                                  width: 3)),
                          child: _uploading
                              ? const Padding(
                                  padding: EdgeInsets.all(6),
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(AppIcons.camera,
                                  color: Colors.white, size: 15),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                NameBadges(name,
                    bot: true,
                    style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
                Text('@${_b['username']}', style: TextStyle(color: subtleText(context))),
              ],
            ),
          ),
          const SizedBox(height: 18),
          PrimaryButton(
              label: 'Открыть чат с ботом',
              icon: AppIcons.messageCircle,
              onTap: () => openDirectChat(context, _id)),
          const SizedBox(height: 18),
          const SectionLabel('Профиль'),
          SectionCard(children: [
            SettingsTile(icon: AppIcons.pencil, title: 'Имя', subtitle: name, onTap: _rename),
            SettingsTile(
                icon: AppIcons.info,
                title: 'Описание',
                subtitle: bio.isEmpty ? 'Не задано' : bio,
                onTap: _about),
          ]),
          const SizedBox(height: 18),
          SectionLabel('Команды · ${_commands.length}'),
          SectionCard(children: [
            for (final c in _commands)
              ListTile(
                leading: IconTile(AppIcons.squareSlash),
                title: Text('/${c['command']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: (c['description'] as String? ?? '').isEmpty
                    ? null
                    : Text(c['description'] as String,
                        style: TextStyle(color: subtleText(context))),
                trailing: IconButton(
                    icon: Icon(AppIcons.x, color: subtleText(context), size: 18),
                    onPressed: () => _removeCommand(c)),
              ),
            SettingsTile(
                icon: AppIcons.plus,
                title: 'Добавить команду',
                onTap: _addCommand,
                chevron: false),
          ]),
          const SizedBox(height: 18),
          const SectionLabel('Доступ к API'),
          SectionCard(children: [
            SettingsTile(
                icon: AppIcons.keyRound,
                title: 'Выпустить новый токен',
                subtitle: 'Старый перестанет работать',
                onTap: _newToken),
            SettingsTile(
                icon: AppIcons.webhook,
                title: 'Webhook',
                subtitle: webhook.isEmpty
                    ? 'Не задан — бот получает сообщения через getUpdates'
                    : webhook,
                chevron: false),
          ]),
          const SizedBox(height: 18),
          const SectionLabel('Пример кода (Python)'),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SelectableText(_example,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12, height: 1.45)),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _example));
                      toast(context, 'Код скопирован', icon: AppIcons.copy);
                    },
                    icon: const Icon(AppIcons.copy, size: 18),
                    label: const Text('Скопировать'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
                'Методы: getMe, getUpdates, sendMessage, sendPhoto, sendDocument, sendVideo, '
                'editMessageText, deleteMessage, sendChatAction, setWebhook, deleteWebhook, '
                'getWebhookInfo, setMyCommands, getMyCommands, getChat.',
                style: TextStyle(color: subtleText(context), fontSize: 12.5, height: 1.4)),
          ),
          const SizedBox(height: 18),
          SectionCard(children: [
            SettingsTile(
                icon: AppIcons.trash2,
                title: 'Удалить бота',
                danger: true,
                onTap: _delete,
                chevron: false),
          ]),
        ],
      ),
    );
  }
}
