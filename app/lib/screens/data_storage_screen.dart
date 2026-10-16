import 'dart:io';

import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:path_provider/path_provider.dart';

import '../app_state.dart';
import '../cache.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Данные и память: реальный размер кэша, очистка, автозагрузка, качество.
class DataStorageScreen extends StatefulWidget {
  const DataStorageScreen({super.key});
  @override
  State<DataStorageScreen> createState() => _DataStorageScreenState();
}

class _DataStorageScreenState extends State<DataStorageScreen> {
  int? _textBytes;
  int? _fileBytes;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  Future<int> _dirSize(Directory d) async {
    var total = 0;
    try {
      if (!await d.exists()) return 0;
      await for (final e in d.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    return total;
  }

  Future<void> _measure() async {
    final t = await Cache.sizeBytes();
    var f = 0;
    try {
      f = await _dirSize(await getTemporaryDirectory());
    } catch (_) {}
    if (mounted) {
      setState(() {
        _textBytes = t;
        _fileBytes = f + PaintingBinding.instance.imageCache.currentSizeBytes;
      });
    }
  }

  String _fmt(int? b) {
    if (b == null) return '…';
    if (b < 1024) return '$b Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} КБ';
    if (b < 1024 * 1024 * 1024) return '${(b / 1024 / 1024).toStringAsFixed(1)} МБ';
    return '${(b / 1024 / 1024 / 1024).toStringAsFixed(2)} ГБ';
  }

  Future<void> _clear() async {
    final ok = await confirm(context,
        title: 'Очистить кэш?',
        body: 'Сохранённые копии чатов, фото и временные файлы удалятся с устройства. '
            'Сообщения останутся на сервере и загрузятся снова.',
        action: 'Очистить',
        danger: true);
    if (!ok) return;
    setState(() => _clearing = true);
    await Cache.clearAll();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    try {
      final tmp = await getTemporaryDirectory();
      await for (final e in tmp.list(followLinks: false)) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
    await _measure();
    if (!mounted) return;
    setState(() => _clearing = false);
    toast(context, 'Кэш очищен', icon: AppIcons.sparkles);
  }

  @override
  Widget build(BuildContext context) {
    final total = (_textBytes ?? 0) + (_fileBytes ?? 0);
    final ready = _textBytes != null && _fileBytes != null;
    final share = ready && total > 0 ? (_textBytes! / total) : 0.0;
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Данные и память')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Занято на устройстве',
                        style: TextStyle(color: subtleText(context))),
                    const SizedBox(height: 4),
                    Text(ready ? _fmt(total) : '…',
                        style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        height: 10,
                        child: Row(
                          children: [
                            Expanded(
                                flex: _flex(share),
                                child: Container(color: appState.accent)),
                            Expanded(
                                flex: _flex(1 - share),
                                child: Container(color: kPremium)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _legend(appState.accent, 'Сообщения и чаты', _fmt(_textBytes)),
                    const SizedBox(height: 6),
                    _legend(kPremium, 'Фото, видео и файлы', _fmt(_fileBytes)),
                    const SizedBox(height: 16),
                    PrimaryButton(
                        label: 'Очистить кэш',
                        icon: AppIcons.trash2,
                        loading: _clearing,
                        onTap: _clear),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            const SectionLabel('Автозагрузка'),
            SectionCard(children: [
              SwitchTile(
                icon: AppIcons.image,
                title: 'Загружать фото автоматически',
                subtitle: 'Иначе — по нажатию, экономит трафик',
                value: appState.autoDownloadPhotos,
                onChanged: (v) => appState.setDeviceSettings(autoDownloadPhotos: v),
              ),
              SwitchTile(
                icon: AppIcons.circlePlay,
                title: 'Автовоспроизведение видео',
                subtitle: 'Видео начинает играть сразу при открытии',
                value: appState.autoplayVideo,
                onChanged: (v) => appState.setDeviceSettings(autoplayVideo: v),
              ),
            ]),
            const SizedBox(height: 18),
            const SectionLabel('Качество отправляемых фото'),
            SectionCard(children: [
              _quality('high', 'Высокое', 'Почти без сжатия'),
              _quality('auto', 'Стандартное', 'Баланс качества и размера'),
              _quality('economy', 'Экономия', 'Меньше трафика, до 1280 px'),
            ]),
          ],
        ),
      ),
    );
  }

  int _flex(double v) {
    final n = (v * 1000).round();
    return n < 1 ? 1 : (n > 999 ? 999 : n);
  }

  Widget _legend(Color c, String label, String value) => Row(
        children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
          Text(value, style: TextStyle(color: subtleText(context))),
        ],
      );

  Widget _quality(String key, String title, String sub) {
    final sel = appState.uploadQuality == key;
    return ListTile(
      onTap: () => appState.setDeviceSettings(uploadQuality: key),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(sub, style: TextStyle(color: subtleText(context), fontSize: 13)),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? appState.accent : subtleText(context), width: sel ? 7 : 2),
        ),
      ),
    );
  }
}
