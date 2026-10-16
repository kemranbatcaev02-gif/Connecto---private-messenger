import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../platform.dart';
import '../widgets/ui.dart';
import 'qr_login.dart';

/// Устройства: активные сеансы (можно завершить) и история входов.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});
  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _events = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([Api.sessions(), Api.loginEvents()]);
      if (!mounted) return;
      setState(() {
        _sessions = r[0].map((e) => (e as Map).cast<String, dynamic>()).toList();
        _events = r[1].map((e) => (e as Map).cast<String, dynamic>()).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  IconData _icon(String? platform) {
    final p = (platform ?? '').toLowerCase();
    if (p.contains('android') || p.contains('iphone') || p.contains('ios')) {
      return AppIcons.smartphone;
    }
    if (p.contains('windows') || p.contains('mac') || p.contains('linux')) {
      return AppIcons.monitor;
    }
    if (p.contains('bot')) return AppIcons.bot;
    return AppIcons.laptop;
  }

  String _when(String? iso) {
    final d = parseServerTime(iso ?? '');
    if (d == null) return '';
    final now = DateTime.now();
    final diff = now.difference(d);
    if (diff.inMinutes < 2) return 'только что';
    if (diff.inMinutes < 60) return '${diff.inMinutes} мин назад';
    final hhmm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 0 && now.day == d.day) return 'сегодня в $hhmm';
    if (diff.inDays <= 1 && now.day != d.day) return 'вчера в $hhmm';
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}, $hhmm';
  }

  Future<void> _terminate(Map<String, dynamic> s) async {
    final ok = await confirm(context,
        title: 'Завершить сеанс?',
        body: '${s['platform'] ?? 'Устройство'}${(s['city'] ?? '').toString().isNotEmpty ? ', ${s['city']}' : ''} '
            'выйдет из аккаунта. При следующем входе там понадобится код из письма.',
        action: 'Завершить',
        danger: true);
    if (!ok) return;
    try {
      await Api.terminateSession(s['id'] as String);
      if (!mounted) return;
      setState(() => _sessions.remove(s));
      toast(context, 'Сеанс завершён', icon: AppIcons.logOut);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _terminateOthers() async {
    final ok = await confirm(context,
        title: 'Завершить все другие сеансы?',
        body: 'Выход произойдёт на всех устройствах, кроме этого.',
        action: 'Завершить',
        danger: true);
    if (!ok) return;
    try {
      await Api.terminateOtherSessions();
      if (!mounted) return;
      setState(() => _sessions.removeWhere((s) => s['current'] != true));
      toast(context, 'Остальные сеансы завершены', icon: AppIcons.shieldCheck);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Widget _sessionTile(Map<String, dynamic> s) {
    final cur = s['current'] == true;
    final city = (s['city'] as String?) ?? '';
    final ip = (s['ip'] as String?) ?? '';
    final place = [if (city.isNotEmpty) city, if (ip.isNotEmpty) ip].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: (cur ? kSuccess : appState.accent).withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(_icon(s['platform'] as String?),
            color: cur ? kSuccess : appState.accent, size: 21),
      ),
      title: Text('Connecto · ${s['platform'] ?? 'Устройство'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
          [
            if (place.isNotEmpty) place,
            cur ? 'это устройство' : 'активность: ${_when(s['last_active'] as String?)}',
          ].join('\n'),
          style: TextStyle(
              color: cur ? kSuccess : subtleText(context), fontSize: 12.5, height: 1.35)),
      trailing: cur
          ? null
          : IconButton(
              tooltip: 'Завершить',
              icon: const Icon(AppIcons.logOut, color: kDanger, size: 20),
              onPressed: () => _terminate(s)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _sessions.where((s) => s['current'] == true).toList();
    final others = _sessions.where((s) => s['current'] != true).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Устройства')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? ListView(children: const [ListSkeleton(count: 5)])
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 80),
                    EmptyState(
                        icon: AppIcons.wifiOff,
              mascot: 'empty_no_internet',
                        title: 'Не удалось загрузить',
                        subtitle: _error,
                        action: TextButton(onPressed: _load, child: const Text('Повторить'))),
                  ])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                    children: [
                      if (!desktopUx) ...[
                        SectionCard(children: [
                          SettingsTile(
                            icon: AppIcons.monitor,
                            title: 'Подключить компьютер',
                            subtitle: 'Отсканируй QR-код в Connecto на компьютере или на сайте',
                            onTap: () async {
                              final ok = await Navigator.push<bool>(context,
                                  MaterialPageRoute(builder: (_) => const QrScanScreen()));
                              if (ok == true) _load();
                            },
                          ),
                        ]),
                        const SizedBox(height: 18),
                      ],
                      const SectionLabel('Это устройство'),
                      SectionCard(children: [
                        for (final s in current) _sessionTile(s),
                        if (others.isNotEmpty)
                          SettingsTile(
                              icon: AppIcons.hand,
                              title: 'Завершить все другие сеансы',
                              danger: true,
                              onTap: _terminateOthers,
                              chevron: false),
                      ]),
                      const SizedBox(height: 18),
                      SectionLabel('Активные сеансы · ${others.length}'),
                      if (others.isEmpty)
                        SectionCard(children: [
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Других активных устройств нет 👍',
                                style: TextStyle(color: subtleText(context))),
                          ),
                        ])
                      else
                        SectionCard(children: [for (final s in others) _sessionTile(s)]),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Text(
                            'Вход с нового устройства всегда подтверждается кодом из письма. '
                            'О каждом входе приходит уведомление в чат «Connecto».',
                            style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                      ),
                      const SizedBox(height: 18),
                      const SectionLabel('История входов'),
                      SectionCard(children: [
                        if (_events.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text('Пока пусто',
                                style: TextStyle(color: subtleText(context))),
                          ),
                        for (final e in _events)
                          ListTile(
                            dense: true,
                            leading: Icon(_icon(e['platform'] as String?),
                                color: subtleText(context), size: 20),
                            title: Text(
                                '${e['platform'] ?? 'Устройство'}${(e['city'] ?? '').toString().isNotEmpty ? ' · ${e['city']}' : ''}',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text(_when(e['created_at'] as String?),
                                style: TextStyle(color: subtleText(context))),
                          ),
                      ]),
                    ],
                  ),
      ),
    );
  }
}
