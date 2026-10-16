import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'change_email_screen.dart';
import 'edit_profile_screen.dart';
import 'home_shell.dart';
import 'login_screen.dart';
import 'passcode_screen.dart';
import 'password_screens.dart';
import 'premium_screen.dart';

/// Переключиться на другой сохранённый аккаунт и перезапустить главный экран.
Future<void> switchToAccount(BuildContext context, Map<String, dynamic> acc) async {
  if (acc['id'] == appState.myUserId) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final err = await appState.switchAccount(acc);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  if (err != null) {
    toast(context, err, error: true);
    return;
  }
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()), (_) => false);
}

/// Добавить аккаунт (с учётом лимита бесплатной версии).
void addAccount(BuildContext context) {
  if (!appState.canAddAccount) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Достигнут лимит аккаунтов'),
        content: Text(appState.isPremium
            ? 'В одном приложении можно держать до $kPremiumAccounts аккаунтов.'
            : 'Без Premium можно добавить до $kFreeAccounts аккаунтов, с Premium — до $kPremiumAccounts.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Понятно')),
          if (!appState.isPremium)
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const PremiumScreen()));
                },
                child: const Text('Подробнее о Premium',
                    style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
    return;
  }
  Navigator.push(
      context, MaterialPageRoute(builder: (_) => const LoginScreen(addAccount: true)));
}

/// Выход из текущего аккаунта (с подтверждением).
Future<void> logoutFlow(BuildContext context) async {
  final others = appState.accounts.where((a) => a['id'] != appState.myUserId).length;
  final ok = await confirm(context,
      title: 'Выйти из аккаунта?',
      body: others > 0
          ? 'Вы переключитесь на другой сохранённый аккаунт.'
          : 'Чтобы вернуться, понадобится войти заново.',
      action: 'Выйти',
      danger: true);
  if (!ok || !context.mounted) return;
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  final switched = await appState.logout();
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pop();
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(
          builder: (_) => switched ? const HomeShell() : const LoginScreen()),
      (_) => false);
}

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  void _push(BuildContext c, Widget s) =>
      Navigator.push(c, MaterialPageRoute(builder: (_) => s));

  Future<void> _deleteAccount(BuildContext context) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Удалить аккаунт навсегда?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Удалятся профиль, сообщения, боты и участие в группах. Восстановить будет нельзя.\n\nНапиши УДАЛИТЬ, чтобы подтвердить:'),
              const SizedBox(height: 10),
              TextField(
                controller: c,
                autofocus: true,
                onChanged: (_) => setLocal(() {}),
                decoration: const InputDecoration(hintText: 'УДАЛИТЬ'),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text('Отмена', style: TextStyle(color: subtleText(ctx)))),
            TextButton(
                onPressed: c.text.trim().toUpperCase() == 'УДАЛИТЬ'
                    ? () => Navigator.pop(ctx, true)
                    : null,
                child: const Text('Удалить',
                    style: TextStyle(color: kDanger, fontWeight: FontWeight.w800))),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Api.deleteMe();
      final switched = await appState.logout();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(
              builder: (_) => switched ? const HomeShell() : const LoginScreen()),
          (_) => false);
    } catch (e) {
      if (context.mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final name =
            [appState.displayName, appState.lastName].where((x) => x.isNotEmpty).join(' ');
        return Scaffold(
          appBar: AppBar(title: const Text('Аккаунт')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              FadeSlideIn(
                child: Column(
                  children: [
                    Avatar(name: name, url: appState.avatarUrl, size: 96, useAccent: true),
                    const SizedBox(height: 12),
                    NameBadges(name.isEmpty ? appState.username : name,
                        premium: appState.isPremium,
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: appState.nameColor)),
                    const SizedBox(height: 4),
                    Text(appState.email, style: TextStyle(color: subtleText(context))),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SectionLabel('Аккаунты · ${appState.accounts.length}/${appState.accountLimit}'),
              SectionCard(children: [
                for (final a in appState.accounts)
                  ListTile(
                    onTap: () => switchToAccount(context, a),
                    leading: Avatar(
                        name: (a['display_name'] as String?) ?? '?',
                        url: a['avatar_url'] as String?,
                        size: 42),
                    title: NameBadges((a['display_name'] as String?) ?? '',
                        premium: a['is_premium'] == true,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    subtitle: Text((a['email'] as String?) ?? '',
                        style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                    trailing: a['id'] == appState.myUserId
                        ? Icon(AppIcons.circleCheck, color: appState.accent)
                        : IconButton(
                            tooltip: 'Убрать из списка',
                            icon: Icon(AppIcons.x, color: subtleText(context), size: 18),
                            onPressed: () async {
                              final ok = await confirm(context,
                                  title: 'Убрать аккаунт из списка?',
                                  body: 'Вы выйдете из него на этом устройстве.',
                                  action: 'Убрать',
                                  danger: true);
                              if (ok) appState.removeAccount(a['id'] as String);
                            }),
                  ),
                SettingsTile(
                    icon: AppIcons.userPlus,
                    title: 'Добавить аккаунт',
                    onTap: () => addAccount(context),
                    chevron: false),
              ]),
              const SizedBox(height: 18),
              const SectionLabel('Профиль'),
              SectionCard(children: [
                SettingsTile(
                    icon: AppIcons.pencil,
                    title: 'Изменить профиль',
                    subtitle: 'Имя, фото, о себе, юзернейм',
                    onTap: () => _push(context, const EditProfileScreen())),
                SettingsTile(
                    icon: AppIcons.atSign,
                    title: appState.handle != null && appState.handle!.isNotEmpty
                        ? '@${appState.handle}'
                        : 'Юзернейм не задан',
                    subtitle: 'По нему тебя находят в поиске',
                    onTap: appState.handle == null
                        ? () => _push(context, const EditProfileScreen())
                        : () {
                            Clipboard.setData(ClipboardData(text: '@${appState.handle}'));
                            toast(context, 'Юзернейм скопирован', icon: AppIcons.copy);
                          },
                    chevron: false),
                SettingsTile(
                    icon: AppIcons.mail,
                    title: appState.email,
                    subtitle: 'Почта для входа и кодов · нажми, чтобы сменить',
                    onTap: () => _push(context, const ChangeEmailScreen())),
                SettingsTile(
                    icon: AppIcons.fingerprint,
                    title: 'ID: ${appState.userId.length > 8 ? appState.userId.substring(0, 8) : appState.userId}…',
                    subtitle: 'Нажми, чтобы скопировать полностью',
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: appState.userId));
                      toast(context, 'ID скопирован', icon: AppIcons.copy);
                    },
                    chevron: false),
              ]),
              const SizedBox(height: 18),
              const SectionLabel('Безопасность'),
              SectionCard(children: [
                SettingsTile(
                    icon: AppIcons.keyRound,
                    title: 'Сменить пароль',
                    onTap: () => _push(context, const ChangePasswordScreen())),
                SettingsTile(
                    icon: AppIcons.shieldCheck,
                    title: 'Облачный пароль',
                    subtitle: appState.hasCloudPassword ? 'Включён' : 'Выключен',
                    onTap: () => _push(context, const CloudPasswordScreen())),
                SettingsTile(
                    icon: AppIcons.lockKeyhole,
                    title: 'Код-пароль',
                    subtitle: appState.passcodeOn ? 'Включён' : 'Выключен',
                    onTap: () => _push(context, const PasscodeSettingsScreen())),
              ]),
              const SizedBox(height: 18),
              SectionCard(children: [
                SettingsTile(
                    icon: AppIcons.logOut,
                    title: 'Выйти',
                    danger: true,
                    onTap: () => logoutFlow(context),
                    chevron: false),
                SettingsTile(
                    icon: AppIcons.trash2,
                    title: 'Удалить аккаунт',
                    danger: true,
                    onTap: () => _deleteAccount(context),
                    chevron: false),
              ]),
            ],
          ),
        );
      },
    );
  }
}
