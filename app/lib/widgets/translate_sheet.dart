import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../theme.dart';
import 'ui.dart';

/// Языки для перевода (код → название).
const Map<String, String> kTranslateLangs = {
  'ru': 'Русский',
  'en': 'English',
  'de': 'Deutsch',
  'fr': 'Français',
  'es': 'Español',
  'it': 'Italiano',
  'tr': 'Türkçe',
  'uk': 'Українська',
  'kk': 'Қазақша',
  'uz': 'Oʻzbek',
  'az': 'Azərbaycan',
  'hy': 'Հայերեն',
  'ka': 'ქართული',
  'zh': '中文',
  'ja': '日本語',
  'ko': '한국어',
  'ar': 'العربية',
  'pl': 'Polski',
};

bool _looksRussian(String t) {
  final cyr = RegExp(r'[а-яё]', caseSensitive: false).allMatches(t).length;
  final lat = RegExp(r'[a-z]', caseSensitive: false).allMatches(t).length;
  return cyr >= lat;
}

/// Перевод сообщения: русский текст — на английский, остальное — на русский;
/// язык можно сменить чипами.
Future<void> showTranslateSheet(BuildContext context, String text) {
  return showAppSheet(context, scrollable: true, builder: (_) => _TranslateSheet(text: text));
}

class _TranslateSheet extends StatefulWidget {
  final String text;
  const _TranslateSheet({required this.text});
  @override
  State<_TranslateSheet> createState() => _TranslateSheetState();
}

class _TranslateSheetState extends State<_TranslateSheet> {
  late String _to = _looksRussian(widget.text) ? 'en' : 'ru';
  String? _result;
  String? _from;
  String? _error;
  bool _loading = true;
  int _req = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = ++_req;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await Api.translate(widget.text, _to);
      if (!mounted || id != _req) return;
      setState(() {
        _result = r['text'] as String?;
        _from = r['from'] as String?;
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

  @override
  Widget build(BuildContext context) {
    final sub = subtleText(context);
    final from = _from != null ? (kTranslateLangs[_from] ?? _from!) : null;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppIcons.languages, color: appState.accent, size: 22),
                const SizedBox(width: 10),
                const Text('Перевод', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const Spacer(),
                if (from != null && !_loading)
                  Text('$from → ${kTranslateLangs[_to] ?? _to}',
                      style: TextStyle(color: sub, fontSize: 12.5)),
              ],
            ),
            const SizedBox(height: 12),
            // оригинал (свёрнуто, если длинный)
            Text(widget.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: sub, fontSize: 13.5)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _loading
                    ? const Padding(
                        key: ValueKey('l'),
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Shimmer(height: 16),
                            SizedBox(height: 8),
                            Shimmer(height: 16, width: 220),
                          ],
                        ),
                      )
                    : _error != null
                        ? Row(
                            key: const ValueKey('e'),
                            children: [
                              Icon(AppIcons.wifiOff, color: sub, size: 18),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_error!, style: TextStyle(color: sub))),
                              TextButton(onPressed: _load, child: const Text('Ещё раз')),
                            ],
                          )
                        : SingleChildScrollView(
                            key: ValueKey('r$_to'),
                            child: SelectableText(_result ?? '',
                                style: const TextStyle(fontSize: 16.5, height: 1.35)),
                          ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 36,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final e in kTranslateLangs.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(e.value),
                        selected: _to == e.key,
                        onSelected: (_) {
                          if (_to == e.key) return;
                          setState(() => _to = e.key);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text('Текст отправляется в сервис перевода',
                      style: TextStyle(color: sub, fontSize: 11.5)),
                ),
                TextButton.icon(
                  onPressed: _result == null || _loading
                      ? null
                      : () {
                          Clipboard.setData(ClipboardData(text: _result!));
                          HapticFeedback.selectionClick();
                          toast(context, 'Перевод скопирован', icon: AppIcons.copy);
                        },
                  icon: const Icon(AppIcons.copy, size: 18),
                  label: const Text('Копировать'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
