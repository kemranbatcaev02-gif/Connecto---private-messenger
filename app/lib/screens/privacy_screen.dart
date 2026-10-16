import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'appearance_screen.dart' show premiumGate;
import 'blocklist_screen.dart';
import 'change_email_screen.dart';
import 'passcode_screen.dart';
import 'password_screens.dart';
import 'security_screen.dart';

const _labels = {'all': 'Все', 'contacts': 'Мои контакты', 'none': 'Никто'};

/// Конфиденциальность: всё хранится на сервере и реально применяется к другим.
class PrivacyScreen extends StatefulWidget {
  const PrivacyScreen({super.key});
  @override
  State<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends State<PrivacyScreen> {
  int? _blocked;

  @override
  void initState() {
    super.initState();
    appState.refreshMe();
    _loadBlocked();
  }

  Future<void> _loadBlocked() async {
    try {
      final l = await Api.blockedUsers();
      if (mounted) setState(() => _blocked = l.length);
    } catch (_) {}
  }

  void _push(Widget s) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => s)).then((_) {
        _loadBlocked();
        if (mounted) setState(() {});
      });

  Future<void> _pick(String key, String title, String hint) async {
    final cur = appState.privacyOf(key);
    final v = await showAppSheet<String>(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(title,
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(hint, style: TextStyle(color: subtleText(ctx), fontSize: 13)),
          ),
          for (final e in _labels.entries)
            ListTile(
              onTap: () => Navigator.pop(ctx, e.key),
              leading: Icon(
                  switch (e.key) {
                    'all' => AppIcons.globe,
                    'contacts' => AppIcons.users,
                    _ => AppIcons.eyeOff,
                  },
                  color: e.key == cur ? appState.accent : subtleText(ctx)),
              title: Text(e.value, style: const TextStyle(fontWeight: FontWeight.w600)),
              trailing: e.key == cur
                  ? Icon(AppIcons.circleCheck, color: appState.accent)
                  : null,
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Text('«Мои контакты» — люди, с которыми у тебя есть личная переписка.',
                style: TextStyle(color: subtleText(ctx), fontSize: 12)),
          ),
        ],
      );
    });
    if (v == null || v == cur || !mounted) return;
    try {
      await appState.setPrivacyValue(key, v);
      if (mounted) toast(context, 'Сохранено');
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Widget _row(IconData icon, String key, String title, String hint) {
    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: _labels[appState.privacyOf(key)] ?? 'Все',
      onTap: () => _pick(key, title, hint),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Конфиденциальность')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            const SectionLabel('Безопасность'),
            SectionCard(children: [
              SettingsTile(
                  icon: AppIcons.userX,
                  title: 'Чёрный список',
                  subtitle: _blocked == null
                      ? null
                      : (_blocked == 0
                          ? 'Никого'
                          : plural(_blocked!, 'пользователь', 'пользователя',
                              'пользователей')),
                  onTap: () => _push(const BlocklistScreen())),
              SettingsTile(
                  icon: AppIcons.lockKeyhole,
                  title: 'Код-пароль',
                  subtitle: appState.passcodeOn ? 'Включён' : 'Выключен',
                  onTap: () => _push(const PasscodeSettingsScreen())),
              SettingsTile(
                  icon: AppIcons.shieldCheck,
                  title: 'Облачный пароль',
                  subtitle: appState.hasCloudPassword ? 'Включён' : 'Выключен',
                  onTap: () => _push(const CloudPasswordScreen())),
              SettingsTile(
                  icon: AppIcons.monitorSmartphone,
                  title: 'Устройства',
                  subtitle: 'Где выполнен вход',
                  onTap: () => _push(const SecurityScreen())),
              SettingsTile(
                  icon: AppIcons.mail,
                  title: 'Почта',
                  subtitle: '${maskEmail(appState.email)} · видишь только ты',
                  onTap: () => _push(const ChangeEmailScreen())),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Кто видит'),
            SectionCard(children: [
              _row(AppIcons.clock, 'lastseen', 'Время захода и «в сети»',
                  'Остальные увидят «был(а) недавно».'),
              _row(AppIcons.image, 'avatar', 'Фото профиля',
                  'Остальные увидят букву вместо фото.'),
              _row(AppIcons.info, 'bio', 'О себе', 'Описание в профиле.'),
              _row(AppIcons.phone, 'phone', 'Номер телефона', 'Номер в профиле.'),
              _row(AppIcons.cake, 'birthday', 'День рождения', 'Дата в профиле.'),
              _row(AppIcons.stories, 'stories', 'Истории',
                  'Остальные не увидят твои истории и публикации.'),
              _row(AppIcons.gift, 'gifts', 'Подарки в профиле',
                  'Остальные не увидят, какие подарки тебе дарили.'),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Кто может'),
            SectionCard(children: [
              _row(AppIcons.users, 'invites', 'Приглашать в группы',
                  'Остальным придётся отправить тебе ссылку-приглашение.'),
              _row(AppIcons.phone, 'calls', 'Звонить мне',
                  'Остальные увидят «Пользователь ограничил звонки».'),
              _row(AppIcons.mic, 'voice', 'Отправлять голосовые и кружочки',
                  'Остальные не смогут записать тебе голосовое или видеосообщение.'),
              _row(AppIcons.forward, 'forwards', 'Ссылаться на меня при пересылке',
                  'Вместо имени будет «Скрытый пользователь».'),
            ]),
            const SizedBox(height: 18),
            SectionCard(children: [
              SwitchTile(
                icon: AppIcons.checkCheck,
                title: 'Отчёты о прочтении',
                subtitle: 'Если выключить — ты тоже не увидишь, что прочитали тебя',
                value: appState.readReceipts,
                onChanged: (v) async {
                  try {
                    await appState.setReadReceipts(v);
                  } catch (e) {
                    appState.readReceipts = !v;
                    appState.refreshMe();
                    if (context.mounted) toast(context, friendlyError(e), error: true);
                  }
                },
              ),
              SwitchTile(
                icon: AppIcons.incognito,
                title: 'Невидимка${appState.isPremium ? '' : ' ⭐'}',
                subtitle: 'Собеседники не видят «печатает…» и «записывает голосовое»',
                value: appState.ghostTyping && appState.isPremium,
                onChanged: (v) {
                  if (!appState.isPremium) {
                    premiumGate(context, 'Невидимка');
                    return;
                  }
                  appState.setGhostTyping(v);
                },
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
