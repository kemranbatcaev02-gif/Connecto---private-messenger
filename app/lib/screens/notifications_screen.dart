import 'package:flutter/material.dart';
import '../icons.dart';

import '../app_state.dart';
import '../calls/call_native.dart';
import '../notifications.dart';
import '../platform.dart';
import '../widgets/ui.dart';

/// Уведомления: серверные (что присылать пушем) + локальные (звук, вибрация).
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    appState.refreshMe();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final n = appState.notify;
        final off = appState.muteAll;
        return Scaffold(
          appBar: AppBar(title: const Text('Уведомления и звуки')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              SectionCard(children: [
                SwitchTile(
                  icon: off ? AppIcons.bellOff : AppIcons.bellRing,
                  title: 'Уведомления в приложении',
                  subtitle: off ? 'Выключены на этом устройстве' : 'Включены',
                  value: !off,
                  onChanged: (v) => appState.setMuteAll(!v),
                ),
              ]),
              const SizedBox(height: 18),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: off ? 0.45 : 1,
                child: IgnorePointer(
                  ignoring: off,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SectionLabel('Присылать'),
                      SectionCard(children: [
                        SwitchTile(
                          icon: AppIcons.user,
                          title: 'Личные чаты',
                          value: n['private'] != false,
                          onChanged: (v) => appState.setNotifyServer('private', v),
                        ),
                        SwitchTile(
                          icon: AppIcons.users,
                          title: 'Группы',
                          value: n['groups'] != false,
                          onChanged: (v) => appState.setNotifyServer('groups', v),
                        ),
                        SwitchTile(
                          icon: AppIcons.megaphone,
                          title: 'Каналы',
                          value: n['channels'] != false,
                          onChanged: (v) => appState.setNotifyServer('channels', v),
                        ),
                        SwitchTile(
                          icon: AppIcons.heart,
                          title: 'Реакции на мои сообщения',
                          value: n['reactions'] != false,
                          onChanged: (v) => appState.setNotifyServer('reactions', v),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      const SectionLabel('Вид'),
                      SectionCard(children: [
                        SwitchTile(
                          icon: AppIcons.eye,
                          title: 'Показывать текст',
                          subtitle: 'Иначе — просто «Новое сообщение»',
                          value: n['preview'] != false,
                          onChanged: (v) => appState.setNotifyServer('preview', v),
                        ),
                        SwitchTile(
                          icon: AppIcons.volume2,
                          title: 'Звук',
                          value: appState.notifySound,
                          onChanged: (v) => appState.setLocalNotify(sound: v),
                        ),
                        if (isNativeMobile)
                          SwitchTile(
                            icon: AppIcons.vibrate,
                            title: 'Вибрация',
                            value: appState.notifyVibrate,
                            onChanged: (v) => appState.setLocalNotify(vibrate: v),
                          ),
                        SwitchTile(
                          icon: AppIcons.messageSquareDot,
                          title: 'В открытом чате',
                          subtitle: 'Уведомлять, даже когда чат открыт',
                          value: appState.notifyInChat,
                          onChanged: (v) => appState.setLocalNotify(inChat: v),
                        ),
                      ]),
                      const SizedBox(height: 18),
                      SectionCard(children: [
                        SettingsTile(
                          icon: AppIcons.bellDot,
                          title: 'Проверить уведомление',
                          chevron: false,
                          onTap: () {
                            Notif.show('Connecto', 'Так будут выглядеть уведомления 👋');
                            toast(context, 'Отправили тестовое уведомление',
                                icon: AppIcons.bell);
                          },
                        ),
                        if (isAndroid)
                          SettingsTile(
                            icon: AppIcons.batteryCharging,
                            title: 'Работа в фоне',
                            subtitle: 'Отключить экономию заряда для мгновенных звонков',
                            chevron: false,
                            onTap: () {
                              CallNative.requestBatteryOptimizations();
                            },
                          ),
                      ]),
                      const SizedBox(height: 10),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                          'Звук отдельных чатов меняется в самом чате: меню ⋮ → «Отключить уведомления».',
                          style: TextStyle(fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
