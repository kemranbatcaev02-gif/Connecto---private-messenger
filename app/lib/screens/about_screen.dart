import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'help_screen.dart';
import 'legal_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});
  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _checking = false;

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final upd = await Api.checkUpdate();
    if (!mounted) return;
    setState(() => _checking = false);
    if (upd == null) {
      toast(context, 'У тебя последняя версия 👌', icon: AppIcons.circleCheck);
      return;
    }
    final direct = (upd['url_direct'] as String?) ?? '';
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Доступна версия ${upd['version'] ?? ''}'),
        content: Text((upd['notes'] as String?)?.isNotEmpty == true
            ? upd['notes'] as String
            : 'Вышло обновление Connecto.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Позже')),
          if (direct.isNotEmpty)
            TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  launchLink(direct);
                },
                child: const Text('Скачать',
                    style: TextStyle(fontWeight: FontWeight.w800))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          FadeSlideIn(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    gradient: accentGradient(appState.accent),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                          color: appState.accent.withValues(alpha: 0.4),
                          blurRadius: 24,
                          offset: const Offset(0, 10)),
                    ],
                  ),
                  child: const Icon(AppIcons.messageCircle, color: Colors.white, size: 48),
                ),
                const SizedBox(height: 16),
                const Text('Connecto',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text('Сборка $kAppBuild', style: TextStyle(color: subtleText(context))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
            child: Text(
              'Быстрый и красивый мессенджер: личные чаты, группы и каналы, боты с открытым API, '
              'голосовые, реакции, облачный пароль и гибкая конфиденциальность.',
              style: TextStyle(color: subtleText(context), height: 1.5),
            ),
          ),
          const SizedBox(height: 16),
          SectionCard(children: [
            SettingsTile(
                icon: AppIcons.refreshCw,
                title: 'Проверить обновления',
                trailing: _checking
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : null,
                onTap: _checking ? null : _checkUpdate,
                chevron: false),
            SettingsTile(
                icon: AppIcons.fileText,
                title: 'Условия использования',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(
                            title: 'Условия использования', body: kTermsText)))),
            SettingsTile(
                icon: AppIcons.shield,
                title: 'Политика конфиденциальности',
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(
                            title: 'Политика конфиденциальности', body: kPrivacyText)))),
            SettingsTile(
                icon: AppIcons.messageCircleHeart,
                title: 'Оставить отзыв',
                subtitle: 'Напиши нам — читаем всё',
                onTap: () => openSupportChat(context)),
          ]),
          const SizedBox(height: 24),
          Center(
            child: Text('Сделано с любовью · 2026',
                style: TextStyle(color: subtleText(context), fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
