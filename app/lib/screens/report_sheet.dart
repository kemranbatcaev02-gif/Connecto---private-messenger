import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';

/// Меню жалобы с причинами. type: 'person' | 'channel' | 'bot'.
void showReportSheet(BuildContext context,
    {required String type, String? targetId, String? chatId}) {
  const reasons = {
    'person': [
      'Спам',
      'Оскорбления и травля',
      'Мошенничество',
      'Порнография',
      'Фейковый аккаунт',
      'Другое',
    ],
    'channel': [
      'Спам',
      'Насилие и жестокость',
      'Порнография',
      'Наркотики',
      'Нарушение авторских прав',
      'Терроризм / экстремизм',
      'Другое',
    ],
    'bot': [
      'Спам',
      'Вредоносное поведение',
      'Мошенничество',
      'Фишинг / вирусы',
      'Другое',
    ],
  };
  final title = {
        'person': 'Пожаловаться на пользователя',
        'channel': 'Пожаловаться на канал',
        'bot': 'Пожаловаться на бота',
      }[type] ??
      'Пожаловаться';
  final list = reasons[type] ?? reasons['person']!;

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const Icon(AppIcons.flag,
                      color: Color(0xFFF43F5E), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ],
              ),
            ),
            for (final r in list)
              Column(
                children: [
                  Divider(height: 1, color: hairline(context)),
                  ListTile(
                    title: Text(r),
                    trailing: Icon(AppIcons.chevronRight,
                        color: subtleText(context), size: 18),
                    onTap: () async {
                      Navigator.pop(context);
                      String reason = r;
                      if (r == 'Другое') {
                        final custom = await _askText(context);
                        if (custom == null || custom.trim().isEmpty) return;
                        reason = custom.trim();
                      }
                      await Api.report(
                          targetId: targetId, chatId: chatId, reason: reason);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Жалоба отправлена. Спасибо!')));
                      }
                    },
                  ),
                ],
              ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _askText(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Опишите причину'),
      content: TextField(
        controller: c,
        autofocus: true,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'Что не так?'),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена')),
        TextButton(
            onPressed: () => Navigator.pop(context, c.text),
            child: Text('Отправить',
                style: TextStyle(color: appState.accent))),
      ],
    ),
  );
}
