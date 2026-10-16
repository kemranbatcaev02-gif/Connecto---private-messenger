import 'package:flutter/material.dart';
import '../icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../screens/image_viewer.dart';
import '../screens/video_screen.dart';
import 'ui.dart';
import '../file_opener.dart';

/// Открыть ссылку с учётом настройки «встроенный браузер».
Future<void> openLink(String url) async {
  var u = url.trim();
  if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri == null) return;
  try {
    await launchUrl(uri,
        mode: appState.inAppBrowser
            ? LaunchMode.inAppBrowserView
            : LaunchMode.externalApplication);
  } catch (_) {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

String mediaUrl(String? path) {
  if (path == null || path.isEmpty) return '';
  return path.startsWith('http') ? path : '$kBaseUrl$path';
}

/// Карточка «Медиа · Голосовые · Файлы · Ссылки» для профиля чата.
class SharedMediaCard extends StatefulWidget {
  final String chatId;
  const SharedMediaCard({super.key, required this.chatId});
  @override
  State<SharedMediaCard> createState() => _SharedMediaCardState();
}

class _SharedMediaCardState extends State<SharedMediaCard> {
  final List<Map<String, dynamic>> _media = [];
  final List<Map<String, dynamic>> _files = [];
  final List<Map<String, dynamic>> _links = [];
  final List<Map<String, dynamic>> _voice = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await Api.messages(widget.chatId, limit: 1000);
      for (final raw in list.reversed) {
        final m = (raw as Map).cast<String, dynamic>();
        final kind = m['kind'] as String? ?? 'text';
        if (kind == 'image' || kind == 'video') {
          _media.add(m);
        } else if (kind == 'file') {
          _files.add(m);
        } else if (kind == 'voice') {
          _voice.add(m);
        } else if (kind == 'text') {
          final t = m['text'] as String? ?? '';
          if (RegExp(r'https?://').hasMatch(t)) _links.add(m);
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const SectionCard(children: [
        Padding(padding: EdgeInsets.all(16), child: Shimmer(height: 16)),
      ]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_media.isNotEmpty) ...[
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _media.length > 12 ? 12 : _media.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) => SizedBox(
                width: 92,
                child: MediaThumb(m: _media[i]),
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SectionCard(children: [
          _row(AppIcons.images, 'Фото и видео', _media, grid: true),
          _row(AppIcons.mic, 'Голосовые', _voice),
          _row(AppIcons.file, 'Файлы', _files),
          _row(AppIcons.link, 'Ссылки', _links),
        ]),
      ],
    );
  }

  Widget _row(IconData icon, String title, List<Map<String, dynamic>> items,
      {bool grid = false}) {
    return SettingsTile(
      icon: icon,
      title: title,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(items.isEmpty ? 'нет' : '${items.length}',
              style: TextStyle(color: subtleText(context))),
          const SizedBox(width: 4),
          Icon(AppIcons.chevronRight, color: subtleText(context), size: 20),
        ],
      ),
      onTap: items.isEmpty
          ? null
          : () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) =>
                      AttachmentsScreen(title: title, items: items, grid: grid))),
    );
  }
}

/// Миниатюра фото/видео.
class MediaThumb extends StatelessWidget {
  final Map<String, dynamic> m;
  const MediaThumb({super.key, required this.m});
  @override
  Widget build(BuildContext context) {
    final url = mediaUrl(m['media_url'] as String?);
    final isImage = m['kind'] == 'image';
    return GestureDetector(
      onTap: () => isImage ? openImageViewer(context, url: url) : openVideo(context, url: url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: isImage
            ? Image.network(url,
                fit: BoxFit.cover,
                cacheWidth: 300,
                errorBuilder: (_, __, ___) => Container(
                    color: Colors.black12, child: const Icon(AppIcons.imageOff)))
            : Container(
                decoration: BoxDecoration(gradient: accentGradient(appState.accent)),
                child: const Center(
                    child: Icon(AppIcons.play, color: Colors.white, size: 30))),
      ),
    );
  }
}

/// Экран со списком вложений одного типа.
class AttachmentsScreen extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> items;
  final bool grid;
  const AttachmentsScreen(
      {super.key, required this.title, required this.items, this.grid = false});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: grid
          ? GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3, mainAxisSpacing: 6, crossAxisSpacing: 6),
              itemCount: items.length,
              itemBuilder: (context, i) => MediaThumb(m: items[i]),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final m = items[i];
                final kind = m['kind'] as String? ?? 'text';
                final isLink = kind == 'text';
                final text = m['text'] as String? ?? '';
                final label = isLink
                    ? (RegExp(r'https?://\S+').firstMatch(text)?.group(0) ?? text)
                    : (m['file_name'] as String? ??
                        (kind == 'voice' ? 'Голосовое сообщение' : 'Файл'));
                final d = parseServerTime(m['created_at'] as String? ?? '');
                final sub = [
                  (m['sender_name'] as String?) ?? '',
                  if (d != null)
                    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}',
                ].where((x) => x.isNotEmpty).join(' · ');
                return ListTile(
                  leading: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                        color: appState.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(12)),
                    child: Icon(
                        kind == 'voice'
                            ? AppIcons.mic
                            : isLink
                                ? AppIcons.link
                                : AppIcons.fileText,
                        color: appState.accent),
                  ),
                  title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: sub.isEmpty
                      ? null
                      : Text(sub, style: TextStyle(color: subtleText(context))),
                  onTap: () => isLink
                      ? openLink(label)
                      : FileOpener.openOrDownload(
                          context,
                          url: mediaUrl(m['media_url'] as String?),
                          fileName: (m['file_name'] as String?) ?? label,
                        ),
                );
              },
            ),
    );
  }
}
