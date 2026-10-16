import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'chat_screen.dart';

Future<void> launchLink(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

/// Открыть чат «Connecto» (уведомления о входе + поддержка).
Future<void> openSupportChat(BuildContext context) async {
  try {
    final chats = await Api.chats();
    Map<String, dynamic>? sys;
    for (final raw in chats) {
      final c = (raw as Map).cast<String, dynamic>();
      if (c['is_system'] == true) {
        sys = c;
        break;
      }
    }
    if (!context.mounted) return;
    if (sys == null) {
      toast(context, 'Чат поддержки пока недоступен, попробуй позже', error: true);
      return;
    }
    openChatScreen(context, sys);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  static const _faq = [
    [
      'Как найти человека?',
      'Нажми на поиск в списке чатов и введи его @юзернейм или имя. '
          'Свой юзернейм задаётся в «Профиль → Изменить».'
    ],
    [
      'Как создать группу или канал?',
      'В списке чатов нажми на карандаш → «Новая группа» или «Новый канал». '
          'Сделай его публичным, чтобы его находили по @ссылке, или частным — '
          'тогда вступить можно только по ссылке-приглашению.'
    ],
    [
      'Как назначить администратора?',
      'Открой группу → нажми на название → выбери участника → «Назначить администратором». '
          'Это может владелец.'
    ],
    [
      'Как ответить на сообщение?',
      'Смахни сообщение влево или удерживай его и выбери «Ответить». '
          'Двойное нажатие ставит ❤️.'
    ],
    [
      'Как записать голосовое?',
      'Удерживай кнопку микрофона. Сдвинь влево — отмена, вверх — запись без рук.'
    ],
    [
      'Что такое облачный пароль?',
      'Второй пароль для входа на новом устройстве. Даже если кто-то узнает основной пароль '
          'и получит код из письма, без облачного пароля он не войдёт.'
    ],
    [
      'Мне не приходят уведомления',
      'Проверь «Настройки → Уведомления», звук конкретного чата (меню ⋮) и разрешение '
          'на уведомления для Connecto в настройках телефона.'
    ],
    [
      'Как сделать своего бота?',
      '«Настройки → Мои боты → Создать». Ты получишь токен и пример кода на Python — '
          'бот работает через Bot API, похожий на Telegram.'
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Помощь')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          FadeSlideIn(
            child: Pressable(
              onTap: () => openSupportChat(context),
              scale: 0.98,
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: accentGradient(appState.accent),
                  borderRadius: BorderRadius.circular(kRadiusL),
                ),
                child: const Row(
                  children: [
                    Icon(AppIcons.headset, color: Colors.white, size: 32),
                    SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Написать в поддержку',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          SizedBox(height: 2),
                          Text('Ответим прямо в чате «Connecto»',
                              style: TextStyle(color: Colors.white, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Icon(AppIcons.chevronRight, color: Colors.white),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Частые вопросы'),
          Container(
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
            clipBehavior: Clip.antiAlias,
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: Column(
                children: [
                  for (final q in _faq)
                    ExpansionTile(
                      shape: const Border(),
                      collapsedShape: const Border(),
                      leading: IconTile(AppIcons.circleHelp),
                      title: Text(q[0],
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                      children: [
                        Text(q[1],
                            style: TextStyle(color: subtleText(context), height: 1.45)),
                      ],
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
