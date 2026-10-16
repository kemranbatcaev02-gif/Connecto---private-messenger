import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'security_screen.dart';

/// Энергосбережение и поведение на этом устройстве.
class DeviceScreen extends StatelessWidget {
  const DeviceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Энергосбережение')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            FadeSlideIn(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: appState.energySaving
                      ? const LinearGradient(colors: [Color(0xFF16A34A), Color(0xFF4ADE80)])
                      : accentGradient(appState.accent),
                  borderRadius: BorderRadius.circular(kRadiusL),
                ),
                child: Row(
                  children: [
                    Icon(
                        appState.energySaving
                            ? AppIcons.batteryFull
                            : AppIcons.batteryMedium,
                        color: Colors.white,
                        size: 34),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              appState.energySaving
                                  ? 'Энергосбережение включено'
                                  : 'Обычный режим',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16)),
                          const SizedBox(height: 2),
                          Text(
                              appState.energySaving
                                  ? 'Анимации выключены, чаты обновляются реже'
                                  : 'Все анимации и мгновенные обновления',
                              style: const TextStyle(color: Colors.white, fontSize: 12.5)),
                        ],
                      ),
                    ),
                    Switch(
                      value: appState.energySaving,
                      onChanged: (v) => appState.setDeviceSettings(energySaving: v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('Что экономить'),
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: appState.energySaving ? 0.5 : 1,
              child: IgnorePointer(
                ignoring: appState.energySaving,
                child: SectionCard(children: [
                  SwitchTile(
                    icon: AppIcons.sparkles,
                    title: 'Анимации интерфейса',
                    subtitle: 'Переходы, появление сообщений, эффекты',
                    value: appState.animations,
                    onChanged: (v) => appState.setChatSettings(animations: v),
                  ),
                  SwitchTile(
                    icon: AppIcons.circlePlay,
                    title: 'Автовоспроизведение видео',
                    value: appState.autoplayVideo,
                    onChanged: (v) => appState.setDeviceSettings(autoplayVideo: v),
                  ),
                  SwitchTile(
                    icon: AppIcons.image,
                    title: 'Автозагрузка фото',
                    value: appState.autoDownloadPhotos,
                    onChanged: (v) => appState.setDeviceSettings(autoDownloadPhotos: v),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            SectionCard(children: [
              SettingsTile(
                icon: AppIcons.monitorSmartphone,
                title: 'Устройства и сеансы',
                subtitle: 'Где выполнен вход в аккаунт',
                onTap: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => const SecurityScreen())),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
