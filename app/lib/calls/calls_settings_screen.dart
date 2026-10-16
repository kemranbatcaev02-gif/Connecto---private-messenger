import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets/ui.dart';

const _labels = {'all': 'Все', 'contacts': 'Мои контакты', 'none': 'Никто'};

/// Настройки звонков и видеосообщений.
class CallsSettingsScreen extends StatefulWidget {
  const CallsSettingsScreen({super.key});
  @override
  State<CallsSettingsScreen> createState() => _CallsSettingsScreenState();
}

class _CallsSettingsScreenState extends State<CallsSettingsScreen> {
  @override
  void initState() {
    super.initState();
    appState.refreshMe();
  }

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
              trailing: e.key == cur ? Icon(AppIcons.circleCheck, color: appState.accent) : null,
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

  Widget _sw(IconData icon, String key, String title, [String? subtitle]) => SwitchTile(
        icon: icon,
        title: title,
        subtitle: subtitle,
        value: appState.callPref(key),
        onChanged: (v) => appState.setCallPref(key, v),
      );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Звонки')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  appState.accent.withValues(alpha: 0.22),
                  appState.accent.withValues(alpha: 0.06),
                ]),
                borderRadius: BorderRadius.circular(kRadiusL),
              ),
              child: Row(
                children: [
                  Icon(AppIcons.lockKeyhole, color: appState.accent, size: 30),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Звонки защищены сквозным шифрованием. Во время разговора сверьте '
                      'четыре эмодзи вверху экрана — если они совпадают, вас никто не слышит.',
                      style: TextStyle(fontSize: 13.5, color: Theme.of(context).colorScheme.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('Конфиденциальность'),
            SectionCard(children: [
              SettingsTile(
                icon: AppIcons.phone,
                title: 'Кто может мне звонить',
                subtitle: _labels[appState.privacyOf('calls')] ?? 'Все',
                onTap: () => _pick('calls', 'Кто может звонить',
                    'Остальные увидят «Пользователь ограничил звонки».'),
              ),
              SettingsTile(
                icon: AppIcons.shield,
                title: 'Прямое соединение (P2P)',
                subtitle: _labels[appState.privacyOf('p2p')] ?? 'Все',
                onTap: () => _pick('p2p', 'Прямое соединение',
                    'С остальными звонок пойдёт через сервер Connecto — они не узнают твой IP-адрес. '
                        'Качество может быть чуть ниже.'),
              ),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Звук'),
            SectionCard(children: [
              _sw(AppIcons.waves, 'noise', 'Шумоподавление', 'Убирает шум улицы и вентилятора'),
              _sw(AppIcons.headphones, 'echo', 'Эхоподавление', 'Собеседник не слышит себя'),
              _sw(AppIcons.mic, 'agc', 'Автогромкость микрофона'),
              // телефонные штуки: громкая связь и датчик у уха
              if (isNativeMobile) ...[
                _sw(AppIcons.volume2, 'speaker', 'Видеозвонки — на громкую связь'),
                _sw(AppIcons.smartphone, 'proximity', 'Гасить экран у уха',
                    'Во время аудиозвонка без громкой связи'),
              ],
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Видео'),
            SectionCard(children: [
              _sw(AppIcons.video, 'hd', 'HD-видео (720p)', 'Выключи, если связь слабая'),
              _sw(AppIcons.wifiOff, 'saver', 'Экономия трафика', '360p и 15 кадров в секунду'),
              _sw(AppIcons.swap, 'mirror', 'Зеркалить своё видео',
                  'Только на твоём экране, собеседник видит как есть'),
              if (isAndroid)
                _sw(AppIcons.layers, 'pip', 'Картинка в картинке',
                    'Видеозвонок остаётся в окошке, когда выходишь из приложения'),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Входящие'),
            SectionCard(children: [
              _sw(AppIcons.bellRing, 'ring', 'Мелодия звонка',
                  isNativeMobile ? 'Системная мелодия телефона' : 'Мелодия Connecto'),
              if (isNativeMobile) _sw(AppIcons.vibrate, 'vibrate', 'Вибрация'),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Видеосообщения'),
            SectionCard(children: [
              _sw(AppIcons.circlePlay, 'roundAutoplay', 'Автовоспроизведение без звука',
                  'Кружочки в чате оживают сами'),
            ]),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                'Нажми на значок микрофона в чате, чтобы переключиться на видеосообщение, '
                'и удерживай, чтобы записать. Смахни вверх — запись без рук.',
                style: TextStyle(color: subtleText(context), fontSize: 12.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
