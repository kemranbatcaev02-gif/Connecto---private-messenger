import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../desktop_pane.dart';
import '../app_state.dart';
import '../calls/calls_settings_screen.dart';
import '../theme.dart';
import '../stories.dart';
import '../widgets/effects.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/story_widgets.dart';
import '../widgets/ui.dart';
import 'about_screen.dart';
import 'account_screen.dart';
import 'admin_screen.dart';
import 'appearance_screen.dart';
import 'bots_screen.dart';
import 'chat_settings_screen.dart';
import 'data_storage_screen.dart';
import 'device_screen.dart';
import 'help_screen.dart';
import 'language_screen.dart';
import 'notifications_screen.dart';
import 'premium_screen.dart';
import 'privacy_screen.dart';
import 'security_screen.dart';
import 'story_create_screen.dart';
import 'wallet_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  // в широком окне раздел открывается справа, на телефоне — отдельным экраном
  void _push(BuildContext c, Widget s) => openSection(c, s);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: [
            const SliverAppBar(pinned: true, title: Text('Настройки')),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 120),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  FadeSlideIn(
                      child: _ProfileCard(
                          onTap: () => _push(context, const AccountScreen()))),
                  const SizedBox(height: 14),
                  FadeSlideIn(
                    delayMs: 40,
                    child: _PremiumBanner(
                        onTap: () => _push(context, const PremiumScreen())),
                  ),
                  const SizedBox(height: 12),
                  FadeSlideIn(
                    delayMs: 70,
                    child: SectionCard(children: [
                      SettingsTile(
                          icon: AppIcons.coin,
                          title: 'Кристаллы',
                          subtitle: 'Баланс кристаллов, бонусы, подарки',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CoinAmount(appState.coins, size: 14),
                              const SizedBox(width: 4),
                              Icon(AppIcons.chevronRight, color: subtleText(context), size: 20),
                            ],
                          ),
                          onTap: () => _push(context, const WalletScreen())),
                      SettingsTile(
                          icon: AppIcons.stories,
                          title: 'Мои истории',
                          subtitle: 'Опубликовать или посмотреть свои',
                          onTap: () {
                            if (stories.mine != null) {
                              openStoriesOf(context, appState.myUserId ?? '');
                            } else {
                              openStoryCreate(context);
                            }
                          }),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  if (appState.isAdmin) ...[
                    SectionCard(children: [
                      SettingsTile(
                          icon: AppIcons.shield,
                          iconColor: kWarning,
                          title: 'Админ-панель',
                          subtitle: 'Статистика, люди, поддержка, промокоды',
                          onTap: () => _push(context, const AdminScreen())),
                    ]),
                    const SizedBox(height: 18),
                  ],
                  SectionCard(children: [
                    SettingsTile(
                        icon: AppIcons.userRound,
                        title: 'Аккаунт',
                        subtitle: 'Профиль, аккаунты, пароль',
                        onTap: () => _push(context, const AccountScreen())),
                    SettingsTile(
                        icon: AppIcons.lock,
                        title: 'Конфиденциальность',
                        subtitle: 'Кто что видит, блокировка, код-пароль',
                        onTap: () => _push(context, const PrivacyScreen())),
                    SettingsTile(
                        icon: AppIcons.monitorSmartphone,
                        title: 'Устройства',
                        subtitle: 'Активные сеансы и история входов',
                        onTap: () => _push(context, const SecurityScreen())),
                  ]),
                  const SizedBox(height: 18),
                  SectionCard(children: [
                    SettingsTile(
                        icon: AppIcons.bell,
                        title: 'Уведомления и звуки',
                        onTap: () => _push(context, const NotificationsScreen())),
                    SettingsTile(
                        icon: AppIcons.phone,
                        title: 'Звонки',
                        subtitle: 'Кто звонит, звук, видео, видеосообщения',
                        onTap: () => _push(context, const CallsSettingsScreen())),
                    SettingsTile(
                        icon: AppIcons.messageCircle,
                        title: 'Настройки чатов',
                        subtitle: 'Текст, пузыри, обои, цвет имени',
                        onTap: () => _push(context, const ChatSettingsScreen())),
                    SettingsTile(
                        icon: AppIcons.palette,
                        title: 'Оформление',
                        subtitle: 'Темы, шрифты, стили, анимации, эффекты',
                        onTap: () => _push(context, const AppearanceScreen())),
                    SettingsTile(
                        icon: AppIcons.database,
                        title: 'Данные и память',
                        subtitle: 'Кэш, автозагрузка, качество',
                        onTap: () => _push(context, const DataStorageScreen())),
                    SettingsTile(
                        icon: AppIcons.batteryCharging,
                        title: 'Энергосбережение',
                        subtitle: appState.energySaving ? 'Включено' : 'Анимации и фон',
                        onTap: () => _push(context, const DeviceScreen())),
                    SettingsTile(
                        icon: AppIcons.languages,
                        title: 'Язык',
                        subtitle: 'Русский',
                        onTap: () => _push(context, const LanguageScreen())),
                  ]),
                  const SizedBox(height: 18),
                  SectionCard(children: [
                    SettingsTile(
                        icon: AppIcons.bot,
                        title: 'Мои боты',
                        subtitle: 'Создать бота и получить токен',
                        onTap: () => _push(context, const BotsScreen())),
                  ]),
                  const SizedBox(height: 18),
                  SectionCard(children: [
                    SettingsTile(
                        icon: AppIcons.download,
                        iconColor: appState.accent,
                        title: 'Скачать приложение',
                        subtitle: 'APK для Android и .exe для Windows',
                        onTap: () => _push(context, const AboutScreen())),
                    SettingsTile(
                        icon: AppIcons.circleHelp,
                        title: 'Помощь и поддержка',
                        onTap: () => _push(context, const HelpScreen())),
                    SettingsTile(
                        icon: AppIcons.info,
                        title: 'О приложении',
                        subtitle: 'Connecto · сборка $kAppBuild',
                        onTap: () => _push(context, const AboutScreen())),
                  ]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ProfileCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final name = [appState.displayName, appState.lastName]
        .where((x) => x.isNotEmpty)
        .join(' ');
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
        child: Row(
          children: [
            AvatarRing(
              width: 2.5,
              child: Avatar(name: name, url: appState.avatarUrl, size: 56, useAccent: true),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  NameBadges(name.isEmpty ? appState.username : name,
                      premium: appState.isPremium,
                      verified: appState.isVerified,
                      emoji: appState.emojiStatus,
                      style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: appState.nameColor)),
                  const SizedBox(height: 3),
                  Text(
                      appState.handle != null && appState.handle!.isNotEmpty
                          ? '@${appState.handle}'
                          : appState.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: subtleText(context), fontSize: 14)),
                ],
              ),
            ),
            Icon(AppIcons.chevronRight, color: subtleText(context)),
          ],
        ),
      ),
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _PremiumBanner({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final on = appState.isPremium;
    final until = appState.premiumUntil;
    return Pressable(
      onTap: onTap,
      scale: 0.98,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: kPremiumGradient,
          borderRadius: BorderRadius.circular(kRadiusL),
          boxShadow: [
            BoxShadow(
                color: kPremium.withValues(alpha: 0.35),
                blurRadius: 18,
                offset: const Offset(0, 8)),
          ],
        ),
        child: Row(
          children: [
            const Icon(AppIcons.star, color: Colors.white, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(on ? 'Connecto Premium активен' : 'Connecto Premium',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                  Text(
                      on && until != null
                          ? 'До ${until.day.toString().padLeft(2, '0')}.${until.month.toString().padLeft(2, '0')}.${until.year}'
                          : '3 реакции, 6 аккаунтов, файлы до 500 МБ и не только',
                      style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(AppIcons.chevronRight, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
