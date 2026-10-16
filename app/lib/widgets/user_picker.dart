import 'dart:async';

import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import 'ui.dart';

/// Выбор людей: недавние собеседники + поиск по юзернейму/имени.
/// multi=false — возвращает список из одного человека сразу по нажатию.
Future<List<Map<String, dynamic>>?> pickUsers(
  BuildContext context, {
  String title = 'Выбери людей',
  bool multi = true,
  String action = 'Готово',
  Set<String> exclude = const {},
  bool allowEmpty = false,
  bool includeBots = false,
}) {
  return Navigator.push<List<Map<String, dynamic>>>(
    context,
    MaterialPageRoute(
      builder: (_) => UserPickerScreen(
        title: title,
        multi: multi,
        action: action,
        exclude: exclude,
        allowEmpty: allowEmpty,
        includeBots: includeBots,
      ),
    ),
  );
}

String userName(Map<String, dynamic> u) {
  final dn = (u['display_name'] as String?) ?? '';
  final ln = (u['last_name'] as String?) ?? '';
  final full = '$dn $ln'.trim();
  if (full.isNotEmpty) return full;
  return (u['username'] as String?) ?? 'Пользователь';
}

class UserPickerScreen extends StatefulWidget {
  final String title;
  final bool multi;
  final String action;
  final Set<String> exclude;
  final bool allowEmpty;
  final bool includeBots;
  const UserPickerScreen({
    super.key,
    required this.title,
    this.multi = true,
    this.action = 'Готово',
    this.exclude = const {},
    this.allowEmpty = false,
    this.includeBots = false,
  });

  @override
  State<UserPickerScreen> createState() => _UserPickerScreenState();
}

class _UserPickerScreenState extends State<UserPickerScreen> {
  final _q = TextEditingController();
  final List<Map<String, dynamic>> _recent = [];
  List<Map<String, dynamic>> _found = [];
  final Map<String, Map<String, dynamic>> _selected = {};
  bool _loadingRecent = true;
  bool _searching = false;
  Timer? _debounce;
  String _last = '';

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _q.dispose();
    super.dispose();
  }

  bool _ok(Map<String, dynamic> u) {
    final id = u['id'] as String?;
    if (id == null || id == appState.myUserId) return false;
    if (widget.exclude.contains(id)) return false;
    if (!widget.includeBots && u['is_bot'] == true) return false;
    return true;
  }

  Future<void> _loadRecent() async {
    try {
      final chats = await Api.chats();
      final seen = <String>{};
      for (final raw in chats) {
        final c = (raw as Map).cast<String, dynamic>();
        if (c['type'] != 'direct' || c['is_system'] == true) continue;
        final pid = c['peer_id'] as String?;
        if (pid == null || !seen.add(pid)) continue;
        final u = <String, dynamic>{
          'id': pid,
          'display_name': c['title'],
          'avatar_url': c['avatar_url'],
          'handle': c['handle'],
          'is_bot': c['peer_is_bot'] == true,
          'is_verified': c['is_verified'] == true,
          'is_premium': c['peer_premium'] == true,
          'online': c['peer_online'] == true,
        };
        if (_ok(u)) _recent.add(u);
      }
    } catch (_) {}
    if (mounted) setState(() => _loadingRecent = false);
  }

  void _onQuery(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(v));
    setState(() {});
  }

  Future<void> _search(String q) async {
    q = q.trim().replaceFirst('@', '');
    _last = q;
    if (q.isEmpty) {
      setState(() => _found = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final r = await Api.searchUsers(q);
      if (_last != q || !mounted) return;
      setState(() => _found = r
          .map((e) => (e as Map).cast<String, dynamic>())
          .where(_ok)
          .toList());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _tap(Map<String, dynamic> u) {
    final id = u['id'] as String;
    if (!widget.multi) {
      Navigator.pop(context, [u]);
      return;
    }
    setState(() {
      if (_selected.remove(id) == null) _selected[id] = u;
    });
  }

  void _done() => Navigator.pop(context, _selected.values.toList());

  @override
  Widget build(BuildContext context) {
    final list = _q.text.trim().isEmpty ? _recent : _found;
    final canDone = widget.allowEmpty || _selected.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (widget.multi)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 180),
              opacity: canDone ? 1 : 0.4,
              child: TextButton(
                onPressed: canDone ? _done : null,
                child: Text(
                    _selected.isEmpty
                        ? widget.action
                        : '${widget.action} (${_selected.length})',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          const SizedBox(width: 6),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: AppTextField(
              controller: _q,
              hint: 'Имя или @юзернейм',
              icon: AppIcons.search,
              onChanged: _onQuery,
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: _selected.isEmpty
                ? const SizedBox(width: double.infinity)
                : SizedBox(
                    height: 88,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (final u in _selected.values)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: GestureDetector(
                              onTap: () => _tap(u),
                              child: SizedBox(
                                width: 60,
                                child: Column(
                                  children: [
                                    Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        Avatar(
                                            name: userName(u),
                                            url: u['avatar_url'] as String?,
                                            size: 50),
                                        Positioned(
                                          right: -2,
                                          top: -2,
                                          child: Container(
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                                color: subtleText(context),
                                                shape: BoxShape.circle),
                                            child: const Icon(AppIcons.x,
                                                size: 13, color: Colors.white),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(userName(u),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
          ),
          if (_searching) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _loadingRecent && _q.text.trim().isEmpty
                ? const SingleChildScrollView(child: ListSkeleton(count: 6))
                : list.isEmpty
                    ? EmptyState(
                        icon: AppIcons.userSearch,
                        mascot: _q.text.trim().isEmpty ? null : 'empty_not_found',
                        title: _q.text.trim().isEmpty
                            ? 'Найди человека'
                            : 'Никого не нашли',
                        subtitle: _q.text.trim().isEmpty
                            ? 'Введи имя или @юзернейм — покажем, кого можно добавить'
                            : 'Проверь написание юзернейма',
                      )
                    : ListView.builder(
                        itemCount: list.length + 1,
                        itemBuilder: (context, i) {
                          if (i == 0) {
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
                              child: SectionLabel(_q.text.trim().isEmpty
                                  ? 'Недавние'
                                  : 'Результаты поиска'),
                            );
                          }
                          final u = list[i - 1];
                          final id = u['id'] as String;
                          final sel = _selected.containsKey(id);
                          final handle = u['handle'] as String?;
                          return FadeSlideIn(
                            delayMs: i > 10 ? 250 : i * 25,
                            child: ListTile(
                              onTap: () => _tap(u),
                              leading: Avatar(
                                name: userName(u),
                                url: u['avatar_url'] as String?,
                                size: 46,
                                online: u['online'] == true,
                              ),
                              title: NameBadges(userName(u),
                                  verified: u['is_verified'] == true,
                                  premium: u['is_premium'] == true,
                                  bot: u['is_bot'] == true,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700, fontSize: 15.5)),
                              subtitle: handle != null && handle.isNotEmpty
                                  ? Text('@$handle',
                                      style: TextStyle(color: subtleText(context)))
                                  : null,
                              trailing: widget.multi
                                  ? AnimatedContainer(
                                      duration: const Duration(milliseconds: 180),
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: sel ? appState.accent : Colors.transparent,
                                        border: Border.all(
                                            color: sel
                                                ? appState.accent
                                                : subtleText(context),
                                            width: 2),
                                      ),
                                      child: sel
                                          ? const Icon(AppIcons.check,
                                              size: 16, color: Colors.white)
                                          : null,
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
