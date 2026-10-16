import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/ui.dart';
import 'name_color_screen.dart';
import 'wallpaper_screen.dart';

/// Настройки чатов с живым предпросмотром.
class ChatSettingsScreen extends StatelessWidget {
  const ChatSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Настройки чатов')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            const _Preview(),
            const SizedBox(height: 18),
            const SectionLabel('Размер текста'),
            SectionCard(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Row(
                  children: [
                    Text('A', style: TextStyle(fontSize: 13, color: subtleText(context))),
                    Expanded(
                      child: Slider(
                        value: appState.messageTextScale.clamp(0.8, 1.4),
                        min: 0.8,
                        max: 1.4,
                        divisions: 6,
                        label: '${(appState.messageTextScale * 100).round()}%',
                        onChanged: (v) => appState.setChatSettings(textScale: v),
                      ),
                    ),
                    Text('A', style: TextStyle(fontSize: 22, color: subtleText(context))),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Скругление сообщений'),
            SectionCard(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
                child: Row(
                  children: [
                    Icon(AppIcons.square, size: 18, color: subtleText(context)),
                    Expanded(
                      child: Slider(
                        value: appState.bubbleRadius.clamp(6.0, 26.0),
                        min: 6,
                        max: 26,
                        divisions: 10,
                        label: '${appState.bubbleRadius.round()}',
                        onChanged: (v) => appState.setChatSettings(bubbleRadius: v),
                      ),
                    ),
                    Icon(AppIcons.circle, size: 18, color: subtleText(context)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 18),
            SectionCard(children: [
              SettingsTile(
                icon: AppIcons.wallpaper,
                title: 'Обои чатов',
                subtitle: appState.chatWallpaper < 0 ? 'Без обоев' : 'Выбраны',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const WallpaperScreen())),
              ),
              SettingsTile(
                icon: AppIcons.brush,
                title: 'Цвет имени в чатах',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                          color: appState.nameColor ?? appState.accent,
                          shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Icon(AppIcons.chevronRight, color: subtleText(context), size: 20),
                  ],
                ),
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const NameColorScreen())),
              ),
            ]),
            const SizedBox(height: 18),
            SectionCard(children: [
              SwitchTile(
                icon: AppIcons.globe,
                title: 'Встроенный браузер',
                subtitle: 'Открывать ссылки внутри приложения',
                value: appState.inAppBrowser,
                onChanged: (v) => appState.setChatSettings(inAppBrowser: v),
              ),
              SwitchTile(
                icon: AppIcons.sparkles,
                title: 'Анимации',
                subtitle: 'Плавное появление сообщений и переходы',
                value: appState.animations,
                onChanged: (v) => appState.setChatSettings(animations: v),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview();

  Widget _bubble(BuildContext context, String text, bool mine, String time) {
    final r = bubbleRadiusEff();
    final round = appState.bubbleStyleEff == 'round';
    final radius = BorderRadius.only(
      topLeft: Radius.circular(r),
      topRight: Radius.circular(r),
      bottomLeft: Radius.circular(mine || round ? r : 5),
      bottomRight: Radius.circular(!mine || round ? r : 5),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
        constraints: const BoxConstraints(maxWidth: 250),
        decoration: mine
            ? myBubbleDecoration(radius)
            : otherBubbleDecoration(context, radius),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: TextStyle(
                    color: mine ? Colors.white : null,
                    fontSize: 15.5 * appState.messageTextScale)),
            const SizedBox(height: 2),
            Text(time,
                style: TextStyle(
                    fontSize: 11,
                    color: mine ? Colors.white70 : subtleText(context))),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(kRadiusL),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(kRadiusL),
          border: Border.all(color: hairline(context)),
        ),
        child: ChatBackground(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _bubble(context, 'Привет! Как тебе новое оформление? 🙂', false, '12:30'),
                _bubble(context, 'Выглядит круто, пузыри теперь ровно как я хотел', true, '12:31'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
