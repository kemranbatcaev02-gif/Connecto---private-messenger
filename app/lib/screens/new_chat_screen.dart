import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/user_picker.dart';
import 'create_group_screen.dart';
import 'create_channel_screen.dart';

/// «Новый чат»: выбор человека → возвращает чат (Map) для открытия.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});
  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  bool _busy = false;
  List<Map<String, dynamic>> _bots = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pick());
    Api.builtinBots().then((r) {
      if (mounted) {
        setState(() => _bots = r.map((e) => (e as Map).cast<String, dynamic>()).toList());
      }
    }).catchError((_) {});
  }

  /// Открыть личку с полезным ботом.
  Future<void> _openBot(Map<String, dynamic> b) async {
    setState(() => _busy = true);
    try {
      final chat = await Api.createChat(type: 'direct', memberIds: [b['id'] as String]);
      if (mounted) Navigator.pop(context, chat);
    } catch (e) {
      if (mounted) {
        toast(context, friendlyError(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _pick() async {
    final r = await pickUsers(context,
        title: 'Новый чат', multi: false, includeBots: true);
    if (!mounted) return;
    // передумал искать — остаёмся здесь: группа, канал, полезные боты
    if (r == null || r.isEmpty) return;
    setState(() => _busy = true);
    try {
      final chat =
          await Api.createChat(type: 'direct', memberIds: [r.first['id'] as String]);
      if (mounted) Navigator.pop(context, chat);
    } catch (e) {
      if (mounted) {
        toast(context, friendlyError(e), error: true);
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Новый чат')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SectionCard(children: [
                  SettingsTile(
                      icon: AppIcons.userSearch,
                      title: 'Найти человека',
                      onTap: _pick),
                  SettingsTile(
                      icon: AppIcons.users,
                      title: 'Создать группу',
                      onTap: () async {
                        final c = await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const CreateGroupScreen()));
                        if (c != null && context.mounted) Navigator.pop(context, c);
                      }),
                  SettingsTile(
                      icon: AppIcons.megaphone,
                      title: 'Создать канал',
                      onTap: () async {
                        final c = await Navigator.push(context,
                            MaterialPageRoute(builder: (_) => const CreateChannelScreen()));
                        if (c != null && context.mounted) Navigator.pop(context, c);
                      }),
                ]),
                if (_bots.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 22, 6, 8),
                    child: Text('ПОЛЕЗНЫЕ БОТЫ',
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: subtleText(context))),
                  ),
                  SectionCard(children: [
                    for (final b in _bots)
                      ListTile(
                        onTap: () => _openBot(b),
                        leading: CircleAvatar(
                          radius: 22,
                          backgroundColor: appState.accent.withValues(alpha: 0.15),
                          child: Text(b['emoji'] as String? ?? '🤖',
                              style: const TextStyle(fontSize: 22)),
                        ),
                        title: Text(b['display_name'] as String? ?? '',
                            style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(b['bio'] as String? ?? '',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                      ),
                  ]),
                ],
              ],
            ),
    );
  }
}
