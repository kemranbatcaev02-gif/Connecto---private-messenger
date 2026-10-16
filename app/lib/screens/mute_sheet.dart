import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Красивое меню «Без звука» с выбором длительности.
/// Возвращает Future — можно дождаться закрытия (например, чтобы обновить иконку).
Future<void> showMuteSheet(BuildContext context, String chatId) {
  final muted = appState.isMuted(chatId);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: cardColor(context),
          borderRadius: BorderRadius.circular(kRadiusL)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
              child: Row(
                children: [
                  Icon(AppIcons.bellOff, color: appState.accent, size: 20),
                  const SizedBox(width: 10),
                  const Text('Отключить уведомления',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                ],
              ),
            ),
            _opt(context, chatId, 'На 3 часа', const Duration(hours: 3)),
            _opt(context, chatId, 'На 8 часов', const Duration(hours: 8)),
            _opt(context, chatId, 'На 12 часов', const Duration(hours: 12)),
            _opt(context, chatId, 'Навсегда', null),
            if (muted) ...[
              Divider(height: 1, color: hairline(context)),
              ListTile(
                leading: IconTile(AppIcons.bell),
                title: Text('Включить звук',
                    style: TextStyle(
                        color: appState.accent, fontWeight: FontWeight.w700)),
                onTap: () {
                  appState.unmute(chatId);
                  Navigator.pop(context);
                },
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    ),
  );
}

Widget _opt(BuildContext context, String chatId, String label, Duration? dur) =>
    ListTile(
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
      onTap: () {
        appState.muteFor(chatId, dur);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Уведомления отключены: $label')));
      },
    );
