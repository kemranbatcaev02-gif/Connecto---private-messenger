import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../theme.dart';
import 'ui.dart';

/// Поиск музыки для истории (iTunes / Deezer, отрывки по 30 с).
/// Возвращает выбранный трек: {title, artist, cover, preview, duration}.
Future<Map<String, dynamic>?> showMusicSearch(BuildContext context) {
  return showAppSheet<Map<String, dynamic>>(context,
      scrollable: true, builder: (_) => const _MusicSearch());
}

class _MusicSearch extends StatefulWidget {
  const _MusicSearch();
  @override
  State<_MusicSearch> createState() => _MusicSearchState();
}

class _MusicSearchState extends State<_MusicSearch> {
  final _q = TextEditingController();
  final _player = AudioPlayer();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;
  String? _error;
  String? _playing;
  Timer? _debounce;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = null);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _player.dispose();
    _q.dispose();
    super.dispose();
  }

  void _changed(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _search);
  }

  Future<void> _search() async {
    final q = _q.text.trim();
    final id = ++_req;
    if (q.isEmpty) {
      setState(() {
        _items = [];
        _error = null;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.musicSearch(q);
      if (!mounted || id != _req) return;
      setState(() {
        _items = r.map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || id != _req) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  Future<void> _toggle(Map<String, dynamic> t) async {
    final id = t['id'] as String?;
    try {
      if (_playing == id) {
        await _player.stop();
        if (mounted) setState(() => _playing = null);
        return;
      }
      await _player.stop();
      if (!mounted) return;
      await _player.play(UrlSource(t['preview'] as String), volume: 0.9);
      if (!mounted) return;
      setState(() => _playing = id);
    } catch (_) {
      if (mounted) toast(context, 'Не удалось включить отрывок', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = subtleText(context);
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: TextField(
              controller: _q,
              autofocus: true,
              onChanged: _changed,
              onSubmitted: (_) => _search(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Исполнитель или песня',
                prefixIcon: const Icon(AppIcons.search),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: _loading && _items.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: TextStyle(color: sub)))
                    : _items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                  _q.text.trim().isEmpty
                                      ? 'Найди трек — в истории заиграет отрывок на 30 секунд'
                                      : 'Ничего не нашлось',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: sub)),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _items.length,
                            itemBuilder: (_, i) {
                              final t = _items[i];
                              final cover = t['cover'] as String?;
                              final on = _playing == t['id'];
                              return ListTile(
                                leading: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: SizedBox(
                                    width: 48,
                                    height: 48,
                                    child: cover != null
                                        ? Image.network(cover,
                                            fit: BoxFit.cover,
                                            cacheWidth: 144,
                                            webHtmlElementStrategy:
                                                WebHtmlElementStrategy.fallback,
                                            errorBuilder: (_, _, _) =>
                                                Container(color: Colors.black12))
                                        : Container(
                                            color: appState.accent.withValues(alpha: 0.2),
                                            child: Icon(AppIcons.headphones,
                                                color: appState.accent)),
                                  ),
                                ),
                                title: Text(t['title'] as String? ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                subtitle: Text(t['artist'] as String? ?? '',
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: on ? 'Стоп' : 'Послушать',
                                      icon: Icon(on ? AppIcons.pause : AppIcons.play,
                                          color: appState.accent),
                                      onPressed: () => _toggle(t),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        HapticFeedback.selectionClick();
                                        Navigator.pop(context, t);
                                      },
                                      child: const Text('Выбрать'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Text('Отрывки — iTunes / Deezer',
                style: TextStyle(color: sub, fontSize: 11.5)),
          ),
        ],
      ),
    );
  }
}
