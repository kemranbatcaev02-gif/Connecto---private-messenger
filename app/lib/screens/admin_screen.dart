import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/shared_media.dart';
import '../widgets/story_widgets.dart';
import '../widgets/ui.dart';
import 'admin_gifts.dart';
import 'user_info_screen.dart';

/// Админ-панель: статистика, пользователи, поддержка, жалобы, промокоды, рассылка.
class AdminScreen extends StatelessWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 11,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Админ-панель'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: appState.accent,
            labelColor: appState.accent,
            unselectedLabelColor: subtleText(context),
            labelStyle: const TextStyle(fontWeight: FontWeight.w800),
            tabs: const [
              Tab(text: 'Обзор'),
              Tab(text: 'Люди'),
              Tab(text: 'Premium'),
              Tab(text: 'Чаты'),
              Tab(text: 'Поддержка'),
              Tab(text: 'Жалобы'),
              Tab(text: 'Промокоды'),
              Tab(text: 'Экономика'),
              Tab(text: 'Подарки'),
              Tab(text: 'Обновления'),
              Tab(text: 'Истории'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _StatsTab(),
            _UsersTab(),
            _PremiumTab(),
            _ChatsTab(),
            _SupportTab(),
            _ReportsTab(),
            _PromoTab(),
            _EconomyTab(),
            AdminGiftsTab(),
            AdminReleaseTab(),
            _StoriesTab(),
          ],
        ),
      ),
    );
  }
}

String _date(String? iso) {
  final d = parseServerTime(iso ?? '');
  if (d == null) return '';
  return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

Widget _errorView(String error, VoidCallback retry) => ListView(children: [
      const SizedBox(height: 60),
      EmptyState(
          icon: AppIcons.wifiOff,
          title: 'Не удалось загрузить',
          subtitle: error,
          action: TextButton(onPressed: retry, child: const Text('Повторить'))),
    ]);

// ─────────────────────────────── обзор ───────────────────────────────

class _StatsTab extends StatefulWidget {
  const _StatsTab();
  @override
  State<_StatsTab> createState() => _StatsTabState();
}

class _StatsTabState extends State<_StatsTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _s;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await Api.adminStats();
      if (mounted) setState(() {
        _s = s;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  /// Почему не приходят коды: проверка SMTP и тестовое письмо себе.
  Future<void> _mailCheck() async {
    try {
      final r = await Api.adminMailCheck(send: true);
      if (!mounted) return;
      final sent = r['sent'];
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Почта'),
          content: Text('${r['status']}\n\n'
              '${sent == true ? 'Тестовое письмо отправлено тебе — проверь почту и «Спам».' : sent == false ? 'Тестовое письмо не ушло.' : ''}'),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Ок'))],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _broadcast() async {
    final textCtrl = TextEditingController();
    final usersCtrl = TextEditingController();
    String target = 'all';

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          final accent = appState.accent;

          final targets = [
            ('all', 'Всем', AppIcons.users, const Color(0xFF3B82F6)),
            ('premium', 'Premium', AppIcons.star, const Color(0xFFF59E0B)),
            ('non_premium', 'Без Premium', AppIcons.person, const Color(0xFF8B5CF6)),
            ('restricted', 'Ограниченным', AppIcons.lockClosed, const Color(0xFFEF4444)),
            ('specific', 'Выбранным', AppIcons.contact, const Color(0xFF10B981)),
          ];

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            title: const Row(
              children: [
                Icon(AppIcons.megaphone, size: 22),
                SizedBox(width: 10),
                Text('Рассылка Connecto', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Кому отправить:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: targets.map((t) {
                        final sel = target == t.$1;
                        return InkWell(
                          onTap: () => setDialogState(() => target = t.$1),
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? t.$4.withValues(alpha: 0.18) : (isDark ? const Color(0xFF23252B) : const Color(0xFFF1F3F5)),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: sel ? t.$4 : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(t.$3, size: 15, color: sel ? t.$4 : (isDark ? Colors.white70 : Colors.black87)),
                                const SizedBox(width: 6),
                                Text(
                                  t.$2,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                    color: sel ? t.$4 : (isDark ? Colors.white70 : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (target == 'specific') ...[
                      const SizedBox(height: 14),
                      TextField(
                        controller: usersCtrl,
                        decoration: InputDecoration(
                          labelText: 'Получатели (username, @тег или ID)',
                          hintText: '@alice, @bob, id...',
                          filled: true,
                          fillColor: isDark ? const Color(0xFF1E2025) : const Color(0xFFF5F6F8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                          isDense: true,
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    const Text('Текст сообщения:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: textCtrl,
                      minLines: 3,
                      maxLines: 7,
                      maxLength: 4000,
                      decoration: InputDecoration(
                        hintText: 'Текст придёт в чат «Connecto» от имени системы...',
                        filled: true,
                        fillColor: isDark ? const Color(0xFF1E2025) : const Color(0xFFF5F6F8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Отмена', style: TextStyle(color: subtleText(ctx))),
              ),
              FilledButton.icon(
                onPressed: () {
                  final text = textCtrl.text.trim();
                  if (text.isEmpty) return;
                  final userIds = target == 'specific'
                      ? usersCtrl.text
                          .split(RegExp(r'[,;\s]+'))
                          .map((s) => s.trim())
                          .where((s) => s.isNotEmpty)
                          .toList()
                      : <String>[];
                  Navigator.pop(ctx, {'text': text, 'target': target, 'userIds': userIds});
                },
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(AppIcons.send, size: 16),
                label: const Text('Отправить', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || !mounted) return;
    final text = result['text'] as String;
    final t = result['target'] as String;
    final uids = (result['userIds'] as List<String>?) ?? [];
    try {
      final n = await Api.adminBroadcast(text, target: t, userIds: uids);
      if (mounted) {
        toast(context, 'Отправлено: ${plural(n, 'пользователю', 'пользователям', 'пользователям')}',
            icon: AppIcons.send);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _s == null) return _errorView(_error!, _load);
    final s = _s;
    final items = [
      [AppIcons.users, 'Пользователи', s?['users'], const Color(0xFF3B82F6)],
      [AppIcons.wifi, 'Сейчас в сети', s?['online'], kSuccess],
      [AppIcons.star, 'Premium', s?['premium'], kPremium],
      [AppIcons.ban, 'Забанены', s?['banned'], kDanger],
      [AppIcons.messageCircle, 'Личные чаты', s?['direct'], const Color(0xFF8B5CF6)],
      [AppIcons.users, 'Группы', s?['groups'], const Color(0xFF14B8A6)],
      [AppIcons.megaphone, 'Каналы', s?['channels'], const Color(0xFFF97316)],
      [AppIcons.bot, 'Боты', s?['bots'], const Color(0xFFEC4899)],
      [AppIcons.messagesSquare, 'Сообщения', s?['messages'], const Color(0xFF6366F1)],
      [AppIcons.monitorSmartphone, 'Сеансы', s?['sessions'], const Color(0xFF64748B)],
      [AppIcons.coin, 'Коинов у людей', s?['coins_total'], kPremium],
      [AppIcons.gift, 'Подарков', s?['gifts'], const Color(0xFFEC4899)],
      [AppIcons.stories, 'Историй', s?['stories'], const Color(0xFFA855F7)],
      [AppIcons.creditCard, 'Оплачено, ₽', s?['payments_rub'], kSuccess],
    ];
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.7,
            children: [
              for (var i = 0; i < items.length; i++)
                FadeSlideIn(
                  delayMs: i * 30,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: cardColor(context),
                        borderRadius: BorderRadius.circular(kRadius)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(items[i][0] as IconData, color: items[i][3] as Color, size: 22),
                        s == null
                            ? const Shimmer(width: 60, height: 22)
                            : Text('${items[i][2] ?? 0}',
                                style: const TextStyle(
                                    fontSize: 24, fontWeight: FontWeight.w900)),
                        Text(items[i][1] as String,
                            style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (s != null) ...[
            _BarChart(
                title: 'Регистрации за 14 дней',
                data: (s['daily_users'] as List?) ?? const [],
                color: const Color(0xFF3B82F6)),
            const SizedBox(height: 12),
            _BarChart(
                title: 'Сообщения за 14 дней',
                data: (s['daily_messages'] as List?) ?? const [],
                color: const Color(0xFF8B5CF6)),
            const SizedBox(height: 16),
          ],
          PrimaryButton(
              label: appState.isPremium ? 'Продлить себе Premium' : 'Выдать себе Premium',
              icon: AppIcons.star,
              gradient: kPremiumGradient,
              onTap: () async {
                final r = await grantPremiumFlow(context, appState.myUserId ?? '',
                    isPremium: appState.isPremium);
                if (r != null) _load();
              }),
          const SizedBox(height: 10),
          PrimaryButton(
              label: 'Рассылка всем пользователям',
              icon: AppIcons.megaphone,
              onTap: _broadcast),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _mailCheck,
            icon: const Icon(AppIcons.mail, size: 18),
            label: const Text('Проверить почту (коды входа)'),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── люди ───────────────────────────────

class _UsersTab extends StatefulWidget {
  const _UsersTab();
  @override
  State<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<_UsersTab> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final l = await Api.adminUsers(_q.text.trim());
      if (!mounted) return;
      setState(() {
        _users = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
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

  void _replace(Map<String, dynamic> u, Map<String, dynamic> n) {
    final i = _users.indexOf(u);
    if (i >= 0) setState(() => _users[i] = {...u, ...n});
  }

  Future<void> _premium(Map<String, dynamic> u) async {
    final r = await grantPremiumFlow(context, u['id'] as String,
        isPremium: u['is_premium'] == true);
    if (r != null && mounted) _replace(u, r);
  }

  Future<void> _ban(Map<String, dynamic> u) async {
    final banned = u['banned'] == true;
    if (!banned) {
      final ok = await confirm(context,
          title: 'Заблокировать ${u['display_name'] ?? u['username']}?',
          body: 'Все его сеансы завершатся, войти он не сможет.',
          action: 'Забанить',
          danger: true);
      if (!ok) return;
    }
    try {
      await Api.adminSetBan(u['id'] as String, !banned);
      if (!mounted) return;
      _replace(u, {'banned': !banned});
      toast(context, banned ? 'Разбанен' : 'Забанен', icon: AppIcons.ban);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> u) async {
    final ok = await confirm(context,
        title: 'Удалить аккаунт навсегда?',
        body: '${u['display_name'] ?? u['username']} (${u['email'] ?? ''}) и все его данные будут удалены.',
        action: 'Удалить',
        danger: true);
    if (!ok) return;
    try {
      await Api.adminDeleteUser(u['id'] as String);
      if (!mounted) return;
      setState(() => _users.remove(u));
      toast(context, 'Аккаунт удалён', icon: AppIcons.trash2);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  void _sheet(Map<String, dynamic> u) {
    final isAdmin = u['is_admin'] == true;
    showAppSheet(context, scrollable: true, builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      return SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Avatar(
              name: (u['display_name'] as String?) ?? '?',
              url: u['avatar_url'] as String?,
              size: 44),
          title: NameBadges((u['display_name'] as String?) ?? (u['username'] as String? ?? ''),
              premium: u['is_premium'] == true, bot: u['is_bot'] == true),
          subtitle: Text(
              '${u['email'] ?? ''}\nс ${_date(u['created_at'] as String?)}',
              style: TextStyle(color: subtleText(ctx), fontSize: 12.5)),
          isThreeLine: true,
        ),
        Divider(height: 1, color: hairline(ctx)),
        SheetItem(
            icon: AppIcons.userRound,
            title: 'Профиль',
            onTap: () => go(() => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => UserInfoScreen(
                        userId: u['id'] as String,
                        name: (u['display_name'] as String?) ?? ''))))),
        SheetItem(
            icon: AppIcons.copy,
            title: 'Скопировать ID',
            onTap: () => go(() {
                  Clipboard.setData(ClipboardData(text: u['id'] as String));
                  toast(context, 'ID скопирован', icon: AppIcons.copy);
                })),
        SheetItem(
            icon: AppIcons.chart,
            title: 'Карточка пользователя',
            onTap: () => go(() async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => _UserDetailScreen(userId: u['id'] as String)));
                  _load();
                })),
        SheetItem(
            icon: AppIcons.star, title: 'Premium', onTap: () => go(() => _premium(u))),
        if (u['is_bot'] != true)
          SheetItem(
              icon: AppIcons.gift,
              title: 'Подарить подарок от Connecto',
              onTap: () => go(() => adminGiftFlow(context, u['id'] as String))),
        if (u['is_bot'] != true)
          SheetItem(
              icon: AppIcons.history,
              title: 'История коинов',
              onTap: () => go(() => adminCoinHistory(context, u['id'] as String,
                  (u['display_name'] as String?) ?? ''))),
        if (u['is_bot'] != true)
          SheetItem(
              icon: AppIcons.coin,
              title: 'Коины',
              subtitle: 'Сейчас: ${u['coins'] ?? 0}',
              onTap: () => go(() async {
                    final r = await giveCoinsFlow(context, u['id'] as String);
                    if (r != null && mounted) _replace(u, r);
                  })),
        SheetItem(
            icon: AppIcons.verified,
            title: u['is_verified'] == true ? 'Снять галочку' : 'Выдать галочку ✓',
            onTap: () => go(() async {
                  try {
                    final r = await Api.adminVerify(u['id'] as String, u['is_verified'] != true);
                    if (mounted) _replace(u, r);
                    if (u['id'] == appState.myUserId) appState.refreshMe();
                  } catch (e) {
                    if (mounted) toast(context, friendlyError(e), error: true);
                  }
                })),
        if (u['is_bot'] != true)
          SheetItem(
              icon: AppIcons.send,
              title: 'Написать от Connecto',
              onTap: () => go(() => adminMessageFlow(context, u['id'] as String))),
        if (!isAdmin)
          SheetItem(
              icon: u['banned'] == true ? AppIcons.userCheck : AppIcons.ban,
              title: u['banned'] == true ? 'Разбанить' : 'Забанить',
              danger: u['banned'] != true,
              onTap: () => go(() => _ban(u))),
        if (!isAdmin)
          SheetItem(
              icon: AppIcons.trash2,
              title: 'Удалить аккаунт',
              danger: true,
              onTap: () => go(() => _delete(u))),
        const SizedBox(height: 6),
      ]));
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: AppTextField(
            controller: _q,
            hint: 'Имя, @юзернейм или почта',
            icon: AppIcons.search,
            onSubmitted: (_) => _load(),
            suffix: IconButton(icon: const Icon(AppIcons.arrowRight), onPressed: _load),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: _loading && _users.isEmpty
                ? ListView(children: const [ListSkeleton()])
                : _error != null
                    ? _errorView(_error!, _load)
                    : ListView.builder(
                        itemCount: _users.length,
                        itemBuilder: (context, i) {
                          final u = _users[i];
                          final banned = u['banned'] == true;
                          return ListTile(
                            onTap: () => _sheet(u),
                            leading: Avatar(
                                name: (u['display_name'] as String?) ?? '?',
                                url: u['avatar_url'] as String?,
                                size: 44,
                                online: u['online'] == true),
                            title: NameBadges(
                                (u['display_name'] as String?) ??
                                    (u['username'] as String? ?? ''),
                                premium: u['is_premium'] == true,
                                bot: u['is_bot'] == true,
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    decoration: banned ? TextDecoration.lineThrough : null)),
                            subtitle: Text(
                                [
                                  if (u['handle'] != null) '@${u['handle']}',
                                  if (u['email'] != null) u['email'],
                                ].join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                            trailing: banned
                                ? const Icon(AppIcons.ban, color: kDanger, size: 18)
                                : (u['is_admin'] == true
                                    ? const Icon(AppIcons.shield, color: kWarning, size: 18)
                                    : null),
                          );
                        },
                      ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────── поддержка ───────────────────────────────

class _SupportTab extends StatefulWidget {
  const _SupportTab();
  @override
  State<_SupportTab> createState() => _SupportTabState();
}

class _SupportTabState extends State<_SupportTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminSupport();
      if (!mounted) return;
      setState(() {
        _list = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return ListView(children: const [ListSkeleton()]);
    if (_error != null) return _errorView(_error!, _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: _list.isEmpty
          ? ListView(children: const [
              SizedBox(height: 60),
              EmptyState(
                  icon: AppIcons.headset,
                  title: 'Обращений нет',
                  subtitle: 'Когда кто-то напишет в чат «Connecto», он появится здесь'),
            ])
          : ListView.builder(
              itemCount: _list.length,
              itemBuilder: (context, i) {
                final s = _list[i];
                final u = (s['user'] as Map).cast<String, dynamic>();
                final waiting = s['waiting'] == true;
                return ListTile(
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => _SupportChat(
                                chatId: s['chat_id'] as String,
                                name: (u['display_name'] as String?) ?? '')));
                    _load();
                  },
                  leading: Avatar(
                      name: (u['display_name'] as String?) ?? '?',
                      url: u['avatar_url'] as String?,
                      size: 46),
                  title: Text((u['display_name'] as String?) ?? '',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text((s['last_text'] as String?) ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subtleText(context))),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(_date(s['last_time'] as String?).split(' ').first,
                          style: TextStyle(color: subtleText(context), fontSize: 11.5)),
                      const SizedBox(height: 4),
                      if (waiting)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                              color: appState.accent, borderRadius: BorderRadius.circular(8)),
                          child: const Text('ждёт',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800)),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _SupportChat extends StatefulWidget {
  final String chatId;
  final String name;
  const _SupportChat({required this.chatId, required this.name});
  @override
  State<_SupportChat> createState() => _SupportChatState();
}

class _SupportChatState extends State<_SupportChat> {
  List<Map<String, dynamic>> _msgs = [];
  bool _loading = true;
  final _c = TextEditingController();
  final _scroll = ScrollController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _c.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminSupportMessages(widget.chatId);
      if (!mounted) return;
      setState(() {
        _msgs = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  Future<void> _send() async {
    final t = _c.text.trim();
    if (t.isEmpty) return;
    setState(() => _sending = true);
    try {
      await Api.adminSupportReply(widget.chatId, t);
      _c.clear();
      await _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.name)),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: _msgs.length,
                    itemBuilder: (context, i) {
                      final m = _msgs[i];
                      final fromBot = m['sender_is_bot'] == true;
                      return Align(
                        alignment: fromBot ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
                          constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.78),
                          decoration: BoxDecoration(
                            gradient: fromBot ? accentGradient(appState.accent) : null,
                            color: fromBot ? null : cardColor(context),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                  m['kind'] == 'text'
                                      ? (m['text'] as String? ?? '')
                                      : '📎 ${m['kind']}',
                                  style: TextStyle(color: fromBot ? Colors.white : null)),
                              const SizedBox(height: 2),
                              Text(_date(m['created_at'] as String?),
                                  style: TextStyle(
                                      fontSize: 10.5,
                                      color: fromBot ? Colors.white70 : subtleText(context))),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
              child: Row(
                children: [
                  Expanded(
                    child: AppTextField(
                        controller: _c,
                        hint: 'Ответ от имени Connecto',
                        maxLines: 4,
                        onSubmitted: (_) => _send()),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(AppIcons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── жалобы ───────────────────────────────

class _ReportsTab extends StatefulWidget {
  const _ReportsTab();
  @override
  State<_ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<_ReportsTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminReports();
      if (!mounted) return;
      setState(() {
        _list = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
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

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return ListView(children: const [ListSkeleton()]);
    if (_error != null) return _errorView(_error!, _load);
    return RefreshIndicator(
      onRefresh: _load,
      child: _list.isEmpty
          ? ListView(children: const [
              SizedBox(height: 60),
              EmptyState(icon: AppIcons.flag, title: 'Жалоб нет 🎉'),
            ])
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _list.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, i) {
                final r = _list[i];
                final target = (r['target_name'] as String?) ?? (r['chat_title'] as String?);
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: cardColor(context), borderRadius: BorderRadius.circular(kRadius)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(AppIcons.flag, color: kDanger, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(target ?? 'Без цели',
                                style: const TextStyle(fontWeight: FontWeight.w800)),
                          ),
                          Text(_date((r['time'] ?? r['created_at']) as String?),
                              style: TextStyle(color: subtleText(context), fontSize: 11.5)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text((r['reason'] as String?)?.isNotEmpty == true
                          ? r['reason'] as String
                          : 'Причина не указана'),
                      if (r['target_id'] != null) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                    builder: (_) => UserInfoScreen(
                                        userId: r['target_id'] as String,
                                        name: target ?? ''))),
                            child: const Text('Открыть профиль'),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }
}

// ─────────────────────────────── промокоды ───────────────────────────────

class _PromoTab extends StatefulWidget {
  const _PromoTab();
  @override
  State<_PromoTab> createState() => _PromoTabState();
}

class _PromoTabState extends State<_PromoTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminPromos();
      if (!mounted) return;
      setState(() {
        _list = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
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
    final code = TextEditingController();
    final days = TextEditingController(text: '30');
    final coins = TextEditingController(text: '0');
    final uses = TextEditingController(text: '1');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новый промокод'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                    labelText: 'Код', hintText: 'пусто — сгенерировать')),
            const SizedBox(height: 10),
            TextField(
                controller: days,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Дней Premium (0 — без Premium)')),
            const SizedBox(height: 10),
            TextField(
                controller: coins,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Коинов (0 — без коинов)')),
            const SizedBox(height: 10),
            TextField(
                controller: uses,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Сколько раз можно применить')),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Создать', style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final d = int.tryParse(days.text.trim()) ?? 0;
    final c = int.tryParse(coins.text.trim()) ?? 0;
    final u = int.tryParse(uses.text.trim()) ?? 0;
    if (d < 0 || c < 0 || u < 1 || (d == 0 && c == 0)) {
      toast(context, 'Укажи дни Premium и/или коины, количество — больше 0', error: true);
      return;
    }
    try {
      final r = await Api.adminCreatePromo(d, u,
          coins: c, code: code.text.trim().isEmpty ? null : code.text.trim());
      if (!mounted) return;
      Clipboard.setData(ClipboardData(text: r['code'] as String));
      toast(context, 'Код ${r['code']} создан и скопирован', icon: AppIcons.ticket);
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await confirm(context,
        title: 'Удалить код ${p['code']}?', action: 'Удалить', danger: true);
    if (!ok) return;
    try {
      await Api.adminDeletePromo(p['code'] as String);
      if (mounted) setState(() => _list.remove(p));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return ListView(children: const [ListSkeleton()]);
    if (_error != null) return _errorView(_error!, _load);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(AppIcons.plus),
          label: const Text('Промокод')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 60),
                EmptyState(
                    icon: AppIcons.ticket,
                    title: 'Промокодов нет',
                    subtitle: 'Создай код — его можно ввести в разделе Premium'),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  SectionCard(children: [
                    for (final p in _list)
                      ListTile(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: p['code'] as String));
                          toast(context, 'Скопировано', icon: AppIcons.copy);
                        },
                        leading: IconTile(AppIcons.ticket, color: kPremium),
                        title: Text(p['code'] as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontFamily: 'monospace')),
                        subtitle: Text(
                            '${[
                              if ((p['days'] as num).toInt() > 0)
                                'Premium ${plural((p['days'] as num).toInt(), 'день', 'дня', 'дней')}',
                              if (((p['coins'] as num?) ?? 0).toInt() > 0) '${p['coins']} коинов',
                            ].join(' + ')} · '
                            'осталось ${(p['uses_left'] as num).toInt()}',
                            style: TextStyle(color: subtleText(context))),
                        trailing: IconButton(
                            icon: const Icon(AppIcons.trash2, color: kDanger, size: 20),
                            onPressed: () => _delete(p)),
                      ),
                  ]),
                ],
              ),
      ),
    );
  }
}


// ─────────────────────────────── общие действия ───────────────────────────────

/// Выдать/продлить/снять Premium любому (в т.ч. себе). Возвращает обновлённого пользователя.
Future<Map<String, dynamic>?> grantPremiumFlow(BuildContext context, String userId,
    {bool isPremium = false}) async {
  if (userId.isEmpty) return null;
  final days = await showAppSheet<int>(context, builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final d in const [7, 30, 90, 365, 3650])
        SheetItem(
            icon: AppIcons.star,
            title: d == 3650
                ? 'Навсегда (10 лет)'
                : '${isPremium ? 'Продлить' : 'Выдать'} на ${plural(d, 'день', 'дня', 'дней')}',
            onTap: () => Navigator.pop(ctx, d)),
      SheetItem(
          icon: AppIcons.pencil,
          title: 'Своё количество дней',
          onTap: () async {
            final v = await askText(ctx,
                title: 'Сколько дней?', keyboard: TextInputType.number, maxLength: 4);
            if (ctx.mounted) Navigator.pop(ctx, int.tryParse(v ?? ''));
          }),
      if (isPremium)
        SheetItem(
            icon: AppIcons.x,
            title: 'Снять Premium',
            danger: true,
            onTap: () => Navigator.pop(ctx, 0)),
      const SizedBox(height: 6),
    ]);
  });
  if (days == null || days < 0 || days > 3650) return null;
  try {
    final r = await Api.adminSetPremium(userId, days);
    if (userId == appState.myUserId) await appState.refreshMe();
    if (context.mounted) {
      toast(context, days == 0 ? 'Premium снят' : 'Premium выдан ⭐', icon: AppIcons.star);
    }
    return r;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
    return null;
  }
}

/// Начислить (или списать минусом) коины пользователю.
Future<Map<String, dynamic>?> giveCoinsFlow(BuildContext context, String userId) async {
  final amount = await showAppSheet<int>(context, builder: (ctx) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      for (final a in const [50, 100, 500, 1000, 5000])
        SheetItem(
            icon: AppIcons.coin,
            title: 'Начислить $a',
            onTap: () => Navigator.pop(ctx, a)),
      SheetItem(
          icon: AppIcons.pencil,
          title: 'Своё количество (минус — списать)',
          onTap: () async {
            final v = await askText(ctx,
                title: 'Сколько коинов?',
                keyboard: const TextInputType.numberWithOptions(signed: true),
                maxLength: 8);
            if (ctx.mounted) Navigator.pop(ctx, int.tryParse((v ?? '').trim()));
          }),
      const SizedBox(height: 6),
    ]);
  });
  if (amount == null || amount == 0) return null;
  try {
    final r = await Api.adminGiveCoins(userId, amount);
    if (userId == appState.myUserId) await appState.refreshMe();
    if (context.mounted) {
      toast(context, amount > 0 ? '+$amount коинов начислено' : 'Списано ${-amount}',
          icon: AppIcons.coin);
    }
    return r;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
    return null;
  }
}

/// Отправить пользователю сообщение от имени Connecto.
Future<void> adminMessageFlow(BuildContext context, String userId) async {
  final t = await askText(context,
      title: 'Сообщение от Connecto',
      hint: 'Придёт в чат «Connecto»',
      action: 'Отправить',
      maxLength: 4000);
  if (t == null || t.isEmpty) return;
  try {
    await Api.adminMessageUser(userId, t);
    if (context.mounted) toast(context, 'Отправлено', icon: AppIcons.send);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
  }
}

/// Столбчатый график по дням.
class _BarChart extends StatelessWidget {
  final String title;
  final List data;
  final Color color;
  const _BarChart({required this.title, required this.data, required this.color});

  @override
  Widget build(BuildContext context) {
    final values = data.map((e) => ((e as Map)['count'] as num?)?.toInt() ?? 0).toList();
    final maxV = values.fold<int>(1, (m, v) => v > m ? v : m);
    final total = values.fold<int>(0, (s, v) => s + v);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: cardColor(context), borderRadius: BorderRadius.circular(kRadius)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(title, style: const TextStyle(fontWeight: FontWeight.w800))),
              Text('$total', style: TextStyle(color: color, fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < values.length; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Tooltip(
                        message: '${(data[i] as Map)['date']}: ${values[i]}',
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: values[i] / maxV),
                          duration: Duration(milliseconds: 400 + i * 30),
                          curve: Curves.easeOutCubic,
                          builder: (_, v, __) => Container(
                            height: 4 + 86 * v,
                            decoration: BoxDecoration(
                              color: i == values.length - 1
                                  ? color
                                  : color.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text('14 дней назад',
                  style: TextStyle(color: subtleText(context), fontSize: 11)),
              const Spacer(),
              Text('сегодня', style: TextStyle(color: subtleText(context), fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────── карточка ───────────────────────────────

class _UserDetailScreen extends StatefulWidget {
  final String userId;
  const _UserDetailScreen({required this.userId});
  @override
  State<_UserDetailScreen> createState() => _UserDetailScreenState();
}

class _UserDetailScreenState extends State<_UserDetailScreen> {
  Map<String, dynamic>? _u;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await Api.adminUserDetail(widget.userId);
      if (mounted) setState(() => _u = u);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _logoutAll() async {
    final ok = await confirm(context,
        title: 'Завершить все сеансы?',
        body: 'Пользователь выйдет на всех устройствах.',
        action: 'Завершить',
        danger: true);
    if (!ok) return;
    try {
      final n = await Api.adminLogoutUser(widget.userId);
      if (!mounted) return;
      toast(context, 'Завершено сеансов: $n', icon: AppIcons.logOut);
      _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Widget _stat(String label, Object? v, IconData icon) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
              color: cardColor(context), borderRadius: BorderRadius.circular(kRadius)),
          child: Column(
            children: [
              Icon(icon, color: appState.accent, size: 20),
              const SizedBox(height: 4),
              Text('${v ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
              Text(label, style: TextStyle(color: subtleText(context), fontSize: 11.5)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final u = _u;
    return Scaffold(
      appBar: AppBar(title: const Text('Карточка')),
      body: u == null
          ? (_error != null
              ? _errorView(_error!, _load)
              : ListView(children: const [ListSkeleton(count: 5)]))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  Center(
                    child: Avatar(
                        name: (u['display_name'] as String?) ?? '?',
                        url: u['avatar_url'] as String?,
                        size: 84,
                        online: u['online'] == true),
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: NameBadges((u['display_name'] as String?) ?? '',
                        verified: u['is_verified'] == true,
                        premium: u['is_premium'] == true,
                        emoji: u['emoji_status'] as String?,
                        bot: u['is_bot'] == true,
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  Center(
                    child: Text(
                        [
                          if (u['handle'] != null) '@${u['handle']}',
                          if (u['email'] != null) u['email'],
                        ].join(' · '),
                        style: TextStyle(color: subtleText(context))),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    _stat('чатов', u['chats'], AppIcons.messagesSquare),
                    _stat('сообщений', u['messages'], AppIcons.messageCircle),
                    _stat('ботов', u['bots'], AppIcons.bot),
                  ]),
                  const SizedBox(height: 16),
                  SectionCard(children: [
                    SettingsTile(
                        icon: AppIcons.clock,
                        title: 'Регистрация',
                        subtitle: _date(u['created_at'] as String?),
                        chevron: false),
                    SettingsTile(
                        icon: AppIcons.eye,
                        title: 'Последний визит',
                        subtitle: u['online'] == true ? 'в сети' : _date(u['last_seen'] as String?),
                        chevron: false),
                    SettingsTile(
                        icon: AppIcons.star,
                        iconColor: kPremium,
                        title: u['is_premium'] == true ? 'Premium активен' : 'Без Premium',
                        subtitle: u['premium_until'] != null
                            ? 'до ${_date(u['premium_until'] as String?)}'
                            : null,
                        onTap: () async {
                          final r = await grantPremiumFlow(context, widget.userId,
                              isPremium: u['is_premium'] == true);
                          if (r != null) _load();
                        }),
                  ]),
                  const SizedBox(height: 16),
                  SectionLabel('Сеансы · ${((u['sessions'] as List?) ?? const []).length}'),
                  SectionCard(children: [
                    for (final raw in (u['sessions'] as List?) ?? const [])
                      ListTile(
                        leading: IconTile(AppIcons.smartphone),
                        title: Text('${(raw as Map)['platform'] ?? 'Устройство'}'
                            '${(raw['city'] ?? '').toString().isNotEmpty ? ' · ${raw['city']}' : ''}'),
                        subtitle: Text(
                            '${raw['ip'] ?? ''} · ${_date(raw['last_active'] as String?)}',
                            style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                      ),
                    SettingsTile(
                        icon: AppIcons.logOut,
                        title: 'Завершить все сеансы',
                        danger: true,
                        chevron: false,
                        onTap: _logoutAll),
                  ]),
                  const SizedBox(height: 16),
                  SectionCard(children: [
                    SettingsTile(
                        icon: AppIcons.send,
                        title: 'Написать от Connecto',
                        onTap: () => adminMessageFlow(context, widget.userId)),
                    SettingsTile(
                        icon: AppIcons.userRound,
                        title: 'Открыть профиль',
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => UserInfoScreen(
                                    userId: widget.userId,
                                    name: (u['display_name'] as String?) ?? '')))),
                  ]),
                ],
              ),
            ),
    );
  }
}

// ─────────────────────────────── Premium ───────────────────────────────

class _PremiumTab extends StatefulWidget {
  const _PremiumTab();
  @override
  State<_PremiumTab> createState() => _PremiumTabState();
}

class _PremiumTabState extends State<_PremiumTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminPremiumUsers();
      if (!mounted) return;
      setState(() {
        _list = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
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

  Future<void> _grantByName() async {
    final q = await askText(context,
        title: 'Кому выдать Premium?', hint: 'Имя, @юзернейм или почта', action: 'Найти');
    if (q == null || q.isEmpty || !mounted) return;
    try {
      final found = (await Api.adminUsers(q))
          .map((e) => (e as Map).cast<String, dynamic>())
          .where((u) => u['is_bot'] != true)
          .toList();
      if (!mounted) return;
      if (found.isEmpty) {
        toast(context, 'Никого не нашли', error: true);
        return;
      }
      final u = found.length == 1
          ? found.first
          : await showAppSheet<Map<String, dynamic>>(context, scrollable: true,
              builder: (ctx) {
              return ListView(shrinkWrap: true, children: [
                for (final x in found.take(30))
                  ListTile(
                    leading: Avatar(
                        name: (x['display_name'] as String?) ?? '?',
                        url: x['avatar_url'] as String?,
                        size: 40),
                    title: Text((x['display_name'] as String?) ?? ''),
                    subtitle: Text((x['email'] as String?) ?? ''),
                    onTap: () => Navigator.pop(ctx, x),
                  ),
              ]);
            });
      if (u == null || !mounted) return;
      final r = await grantPremiumFlow(context, u['id'] as String,
          isPremium: u['is_premium'] == true);
      if (r != null) _load();
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return ListView(children: const [ListSkeleton()]);
    if (_error != null) return _errorView(_error!, _load);
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _grantByName,
        icon: const Icon(AppIcons.star),
        label: const Text('Выдать Premium'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _list.isEmpty
            ? ListView(children: const [
                SizedBox(height: 60),
                EmptyState(
                    icon: AppIcons.star,
                    title: 'Пока ни у кого нет Premium',
                    subtitle: 'Выдай подписку кнопкой ниже — хоть себе'),
              ])
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  SectionLabel('Активных подписок · ${_list.length}'),
                  SectionCard(children: [
                    for (final u in _list)
                      ListTile(
                        onTap: () async {
                          final r = await grantPremiumFlow(context, u['id'] as String,
                              isPremium: true);
                          if (r != null) _load();
                        },
                        leading: Avatar(
                            name: (u['display_name'] as String?) ?? '?',
                            url: u['avatar_url'] as String?,
                            size: 42),
                        title: NameBadges((u['display_name'] as String?) ?? '',
                            premium: true,
                            emoji: u['emoji_status'] as String?,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                        subtitle: Text('до ${_date(u['premium_until'] as String?)}',
                            style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                        trailing: Icon(AppIcons.chevronRight, color: subtleText(context)),
                      ),
                  ]),
                ],
              ),
      ),
    );
  }
}

// ─────────────────────────────── чаты ───────────────────────────────

class _ChatsTab extends StatefulWidget {
  const _ChatsTab();
  @override
  State<_ChatsTab> createState() => _ChatsTabState();
}

class _ChatsTabState extends State<_ChatsTab> with AutomaticKeepAliveClientMixin {
  final _q = TextEditingController();
  List<Map<String, dynamic>> _list = [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminChats(_q.text.trim());
      if (!mounted) return;
      setState(() {
        _list = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
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

  void _sheet(Map<String, dynamic> c) {
    showAppSheet(context, builder: (ctx) {
      void go(VoidCallback f) {
        Navigator.pop(ctx);
        f();
      }

      return Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: Avatar(
              name: (c['title'] as String?) ?? '',
              url: c['avatar_url'] as String?,
              size: 44,
              icon: c['type'] == 'channel' ? AppIcons.megaphone : AppIcons.users),
          title: NameBadges((c['title'] as String?) ?? '', verified: c['is_verified'] == true),
          subtitle: Text(
              '${c['type'] == 'channel' ? 'канал' : 'группа'} · владелец: ${c['owner_name'] ?? '—'}',
              style: TextStyle(color: subtleText(ctx))),
        ),
        Divider(height: 1, color: hairline(ctx)),
        SheetItem(
            icon: AppIcons.verified,
            title: c['is_verified'] == true ? 'Снять галочку' : 'Выдать галочку ✓',
            onTap: () => go(() async {
                  try {
                    final r = await Api.adminVerifyChat(c['id'] as String, c['is_verified'] != true);
                    if (!mounted) return;
                    final i = _list.indexOf(c);
                    if (i >= 0) setState(() => _list[i] = r);
                  } catch (e) {
                    if (mounted) toast(context, friendlyError(e), error: true);
                  }
                })),
        if (c['owner_id'] != null)
          SheetItem(
              icon: AppIcons.userRound,
              title: 'Владелец',
              onTap: () => go(() => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => _UserDetailScreen(userId: c['owner_id'] as String))))),
        SheetItem(
            icon: AppIcons.trash2,
            title: 'Удалить для всех',
            danger: true,
            onTap: () => go(() async {
                  final ok = await confirm(context,
                      title: 'Удалить «${c['title']}»?',
                      body: 'Все сообщения и участники будут удалены навсегда.',
                      action: 'Удалить',
                      danger: true);
                  if (!ok) return;
                  try {
                    await Api.adminDeleteChat(c['id'] as String);
                    if (mounted) setState(() => _list.remove(c));
                  } catch (e) {
                    if (mounted) toast(context, friendlyError(e), error: true);
                  }
                })),
        const SizedBox(height: 6),
      ]);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: AppTextField(
            controller: _q,
            hint: 'Название или @ссылка',
            icon: AppIcons.search,
            onSubmitted: (_) => _load(),
            suffix: IconButton(icon: const Icon(AppIcons.arrowRight), onPressed: _load),
          ),
        ),
        Expanded(
          child: _loading
              ? ListView(children: const [ListSkeleton()])
              : _error != null
                  ? _errorView(_error!, _load)
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: _list.isEmpty
                          ? ListView(children: const [
                              SizedBox(height: 60),
                              EmptyState(icon: AppIcons.users, title: 'Групп и каналов нет'),
                            ])
                          : ListView.builder(
                              itemCount: _list.length,
                              itemBuilder: (context, i) {
                                final c = _list[i];
                                return ListTile(
                                  onTap: () => _sheet(c),
                                  leading: Avatar(
                                      name: (c['title'] as String?) ?? '',
                                      url: c['avatar_url'] as String?,
                                      size: 44,
                                      icon: c['type'] == 'channel'
                                          ? AppIcons.megaphone
                                          : AppIcons.users),
                                  title: NameBadges((c['title'] as String?) ?? '',
                                      verified: c['is_verified'] == true,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700, fontSize: 15)),
                                  subtitle: Text(
                                      '${c['type'] == 'channel' ? 'канал' : 'группа'} · '
                                      '${c['member_count']} уч. · ${c['messages']} сообщ.'
                                      '${c['handle'] != null ? ' · @${c['handle']}' : ''}',
                                      style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                                );
                              },
                            ),
                    ),
        ),
      ],
    );
  }
}


// ─────────────────────────────── подарки и коины ───────────────────────────────

/// Выбрать подарок и подарить его пользователю от имени Connecto (бесплатно).
Future<void> adminGiftFlow(BuildContext context, String userId) async {
  List<Map<String, dynamic>> gifts;
  try {
    final d = await Api.giftCatalog();
    gifts = ((d['gifts'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
    return;
  }
  if (!context.mounted) return;
  final g = await showAppSheet<Map<String, dynamic>>(context, scrollable: true, builder: (ctx) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text('Подарок от Connecto',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          Flexible(
            child: GridView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.74),
              itemCount: gifts.length,
              itemBuilder: (_, i) => GiftTile(
                gift: gifts[i],
                onTap: () => Navigator.pop(ctx, gifts[i]),
                footer: const Text('бесплатно', style: TextStyle(fontSize: 11.5)),
              ),
            ),
          ),
        ],
      ),
    );
  });
  if (g == null || !context.mounted) return;
  final text = await askText(context,
      title: 'Подпись к подарку', hint: 'Подарок от команды Connecto 💜', maxLength: 200);
  if (text == null || !context.mounted) return;
  try {
    await Api.adminGift(userId, g['id'] as String, text: text);
    if (context.mounted) toast(context, 'Подарок «${g['title']}» отправлен', icon: AppIcons.gift);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
  }
}

Future<void> adminCoinHistory(BuildContext context, String userId, String name) async {
  List<dynamic> rows;
  try {
    rows = await Api.adminUserCoins(userId);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
    return;
  }
  if (!context.mounted) return;
  await showAppSheet(context, scrollable: true, builder: (ctx) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text('Коины · $name',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          ),
          if (rows.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('Операций пока нет'))
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final t = (rows[i] as Map).cast<String, dynamic>();
                  final a = (t['amount'] as num).toInt();
                  return ListTile(
                    dense: true,
                    title: Text(t['title'] as String? ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(_date(t['created_at'] as String?)),
                    trailing: Text('${a > 0 ? '+' : ''}$a',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            color: a > 0 ? kSuccess : Theme.of(ctx).colorScheme.onSurface)),
                  );
                },
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  });
}

class _EconomyTab extends StatefulWidget {
  const _EconomyTab();
  @override
  State<_EconomyTab> createState() => _EconomyTabState();
}

class _EconomyTabState extends State<_EconomyTab> with AutomaticKeepAliveClientMixin {
  Map<String, dynamic>? _d;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await Api.adminEconomy();
      if (mounted) setState(() {
        _d = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Widget _stat(String label, int value, IconData icon, Color c) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cardColor(context), borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconTile(icon, color: c, size: 32),
              const SizedBox(height: 8),
              Text(fmtCoins(value), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
              Text(label, style: TextStyle(color: subtleText(context), fontSize: 12.5)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _d == null) return _errorView(_error!, _load);
    final d = _d;
    if (d == null) return ListView(children: const [ListSkeleton()]);
    final gifts = ((d['gifts'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final top = ((d['top'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    final txs = ((d['transactions'] as List?) ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            _stat('коинов выдано', (d['coins_issued'] as num?)?.toInt() ?? 0, AppIcons.coin, kPremium),
            const SizedBox(width: 10),
            _stat('коинов потрачено', (d['coins_spent'] as num?)?.toInt() ?? 0, AppIcons.swap, kDanger),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            _stat('подарков всего', (d['gifts_total'] as num?)?.toInt() ?? 0, AppIcons.gift, const Color(0xFFEC4899)),
            const SizedBox(width: 10),
            _stat('выручка подарков',
                gifts.fold<int>(0, (s, g) => s + ((g['revenue'] as num?)?.toInt() ?? 0)),
                AppIcons.trophy, kSuccess),
          ]),
          const SizedBox(height: 18),
          const SectionLabel('Подарки'),
          SectionCard(children: [
            for (final g in gifts)
              ListTile(
                leading: GiftArt(gift: g, size: 40, animate: false),
                title: Text(g['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text(
                    'куплено ${g['sold']}${g['supply'] != null ? ' из ${g['supply']}' : ''}'
                    ' · обменяли ${g['converted']} · улучшили ${g['upgraded']}',
                    style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                trailing: CoinAmount((g['price'] as num).toInt(), size: 13),
              ),
          ]),
          const SizedBox(height: 18),
          const SectionLabel('Самые богатые'),
          SectionCard(children: [
            if (top.isEmpty)
              const Padding(padding: EdgeInsets.all(16), child: Text('Пока ни у кого нет коинов')),
            for (var i = 0; i < top.length; i++)
              ListTile(
                leading: Avatar(
                    name: top[i]['display_name'] as String? ?? '?',
                    url: top[i]['avatar_url'] as String?,
                    size: 38),
                title: Text('${i + 1}. ${top[i]['display_name']}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                trailing: CoinAmount((top[i]['coins'] as num).toInt(), size: 13.5),
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => _UserDetailScreen(userId: top[i]['id'] as String))),
              ),
          ]),
          const SizedBox(height: 18),
          const SectionLabel('Последние операции'),
          SectionCard(children: [
            for (final t in txs)
              ListTile(
                dense: true,
                title: Text(t['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${t['name']} · ${_date(t['created_at'] as String?)}',
                    style: TextStyle(color: subtleText(context))),
                trailing: Text(
                    '${((t['amount'] as num).toInt()) > 0 ? '+' : ''}${t['amount']}',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        color: ((t['amount'] as num).toInt()) > 0 ? kSuccess : kDanger)),
              ),
          ]),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _StoriesTab extends StatefulWidget {
  const _StoriesTab();
  @override
  State<_StoriesTab> createState() => _StoriesTabState();
}

class _StoriesTabState extends State<_StoriesTab> with AutomaticKeepAliveClientMixin {
  List<Map<String, dynamic>>? _list;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final l = await Api.adminStories();
      if (mounted) {
        setState(() {
          _list = l.map((e) => (e as Map).cast<String, dynamic>()).toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _delete(Map<String, dynamic> s) async {
    final ok = await confirm(context,
        title: 'Удалить историю?',
        body: 'Автор: ${s['user']?['display_name'] ?? ''}. Она пропадёт у всех.',
        action: 'Удалить',
        danger: true);
    if (!ok) return;
    try {
      await Api.adminDeleteStory(s['id'] as String);
      if (mounted) setState(() => _list?.remove(s));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_error != null && _list == null) return _errorView(_error!, _load);
    final list = _list;
    if (list == null) return ListView(children: const [ListSkeleton()]);
    return RefreshIndicator(
      onRefresh: _load,
      child: list.isEmpty
          ? ListView(children: const [
              SizedBox(height: 60),
              EmptyState(icon: AppIcons.stories, title: 'Историй пока нет'),
            ])
          : GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 8, crossAxisSpacing: 8, childAspectRatio: 0.62),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final s = list[i];
                final u = (s['user'] as Map?)?.cast<String, dynamic>() ?? const {};
                return GestureDetector(
                  onTap: () => _delete(s),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      StoryThumb(
                          mediaUrl: mediaUrl(s['media_url'] as String?),
                          video: s['kind'] == 'video',
                          radius: 12),
                      Positioned(
                        left: 6,
                        right: 6,
                        bottom: 6,
                        child: Text(u['display_name'] as String? ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                shadows: [Shadow(blurRadius: 6)])),
                      ),
                      Positioned(
                        right: 6,
                        top: 6,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45), shape: BoxShape.circle),
                          child: const Icon(AppIcons.trash2, color: Colors.white, size: 14),
                        ),
                      ),
                      if (s['active'] == true)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                                color: kSuccess,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 1.4)),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
