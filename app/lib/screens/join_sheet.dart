import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Предпросмотр приглашения. Возвращает чат после вступления (или если уже там).
Future<Map<String, dynamic>?> showJoinPreview(BuildContext context,
    {required String code}) async {
  Map<String, dynamic> chat;
  try {
    chat = await Api.invitePreview(code);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
    return null;
  }
  if (!context.mounted) return null;
  if (chat['is_member'] == true) return chat;
  return showAppSheet<Map<String, dynamic>>(context, builder: (ctx) {
    return _JoinBody(chat: chat, code: code);
  });
}

class _JoinBody extends StatefulWidget {
  final Map<String, dynamic> chat;
  final String code;
  const _JoinBody({required this.chat, required this.code});
  @override
  State<_JoinBody> createState() => _JoinBodyState();
}

class _JoinBodyState extends State<_JoinBody> {
  bool _loading = false;

  Future<void> _join() async {
    setState(() => _loading = true);
    try {
      final c = await Api.joinByInvite(widget.code);
      if (mounted) Navigator.pop(context, c);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        toast(context, friendlyError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.chat;
    final isCh = c['type'] == 'channel';
    final n = (c['member_count'] as num?)?.toInt() ?? 0;
    final desc = (c['description'] as String?) ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Avatar(
            name: (c['title'] as String?) ?? '',
            url: c['avatar_url'] as String?,
            size: 86,
            radius: 28,
            useAccent: true,
            icon: isCh ? AppIcons.megaphone : AppIcons.users,
          ),
          const SizedBox(height: 14),
          Text((c['title'] as String?) ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
              isCh
                  ? 'Канал · ${plural(n, 'подписчик', 'подписчика', 'подписчиков')}'
                  : 'Группа · ${plural(n, 'участник', 'участника', 'участников')}',
              style: TextStyle(color: subtleText(context))),
          if (desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(desc,
                textAlign: TextAlign.center,
                maxLines: 5,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(height: 1.4)),
          ],
          const SizedBox(height: 20),
          PrimaryButton(
              label: isCh ? 'Подписаться' : 'Вступить в группу',
              icon: isCh ? AppIcons.bellPlus : AppIcons.userPlus,
              loading: _loading,
              onTap: _join),
        ],
      ),
    );
  }
}
