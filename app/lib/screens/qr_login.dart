import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_flow.dart';

// ─────────────────────────────────────────────────────────────
// Компьютер: QR-код для входа (как в Telegram Desktop)
// ─────────────────────────────────────────────────────────────

class QrLoginPanel extends StatefulWidget {
  const QrLoginPanel({super.key});
  @override
  State<QrLoginPanel> createState() => _QrLoginPanelState();
}

class _QrLoginPanelState extends State<QrLoginPanel> {
  String? _token;
  String? _code;
  String? _qr;
  String _status = 'loading'; // loading | pending | scanned | error
  Timer? _poll;
  DateTime _startedAt = DateTime.now();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    _poll?.cancel();
    setState(() => _status = 'loading');
    try {
      final r = await Api.qrStart(appState.deviceId, appState.platform);
      if (!mounted) return;
      setState(() {
        _token = r['token'] as String?;
        _code = r['code'] as String?;
        _qr = r['qr'] as String?;
        _status = 'pending';
        _startedAt = DateTime.now();
      });
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
    } catch (_) {
      if (mounted) setState(() => _status = 'error');
    }
  }

  Future<void> _check() async {
    final t = _token;
    if (t == null || _done) return;
    // код живёт 2 минуты — чуть раньше обновляем сами
    if (DateTime.now().difference(_startedAt).inSeconds > 110) {
      _start();
      return;
    }
    try {
      final r = await Api.qrPoll(t);
      if (!mounted || _done) return;
      final st = r['status'] as String? ?? 'pending';
      if (st == 'expired') {
        _start();
      } else if (st == 'approved') {
        _done = true;
        _poll?.cancel();
        await continueLogin(context, r, login: '', password: '');
      } else if (st != _status) {
        setState(() => _status = st);
      }
    } catch (_) {}
  }

  String get _prettyCode {
    final c = _code ?? '';
    return c.length == 8 ? '${c.substring(0, 4)}-${c.substring(4)}' : c;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    Widget qrBox;
    if (_status == 'error') {
      qrBox = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(AppIcons.wifiOff, size: 40, color: subtleText(context)),
          const SizedBox(height: 10),
          const Text('Нет связи с сервером'),
          TextButton(onPressed: _start, child: const Text('Повторить')),
        ],
      );
    } else if (_qr == null) {
      qrBox = const SizedBox(width: 36, height: 36, child: CircularProgressIndicator());
    } else {
      qrBox = AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Container(
          key: ValueKey(_qr),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
          ),
          child: QrImageView(
            data: _qr!,
            version: QrVersions.auto,
            size: 200,
            backgroundColor: Colors.white,
            eyeStyle: QrEyeStyle(eyeShape: QrEyeShape.circle, color: appState.accent),
            dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF111318)),
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
      decoration: BoxDecoration(
        color: cardColor(context),
        borderRadius: BorderRadius.circular(kRadiusL),
        border: Border.all(color: hairline(context)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Вход по QR-коду',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          SizedBox(height: 226, child: Center(child: qrBox)),
          const SizedBox(height: 14),
          if (_status == 'scanned')
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(AppIcons.smartphone, size: 18, color: kSuccess),
                const SizedBox(width: 6),
                Text('Подтверди вход на телефоне',
                    style: TextStyle(color: dark ? const Color(0xFF86EFAC) : kSuccess,
                        fontWeight: FontWeight.w700)),
              ],
            )
          else ...[
            _step(context, '1', 'Открой Connecto на телефоне'),
            _step(context, '2', 'Настройки → Устройства → Подключить компьютер'),
            _step(context, '3', 'Наведи камеру на этот код'),
          ],
          if (_code != null) ...[
            const SizedBox(height: 12),
            Text('Нет камеры? Введи код на телефоне:',
                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
            const SizedBox(height: 4),
            SelectableText(_prettyCode,
                style: TextStyle(
                    fontSize: 22,
                    letterSpacing: 3,
                    fontWeight: FontWeight.w800,
                    color: appState.accent)),
          ],
        ],
      ),
    );
  }

  Widget _step(BuildContext context, String n, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: appState.accent.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Text(n,
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w800, color: appState.accent)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5))),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────
// Телефон: отсканировать QR с компьютера и разрешить вход
// ─────────────────────────────────────────────────────────────

/// Разбор того, что отсканировали или ввели: токен из QR или короткий код.
({String? token, String? code})? _parseQr(String raw) {
  final v = raw.trim();
  if (v.startsWith('connecto-login:')) return (token: v.substring(15), code: null);
  final code = v.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (code.length == 8) return (token: null, code: code);
  return null;
}

/// Спросить подтверждение и впустить компьютер. true — вход разрешён.
Future<bool> approveQrLogin(BuildContext context, String raw) async {
  final ref = _parseQr(raw);
  if (ref == null) {
    toast(context, 'Это не код входа Connecto', error: true);
    return false;
  }
  try {
    final info = await Api.qrInspect(token: ref.token, code: ref.code);
    if (!context.mounted) return false;
    final plat = (info['platform'] as String?) ?? 'Компьютер';
    final city = (info['city'] as String?) ?? '';
    final ip = (info['ip'] as String?) ?? '';
    final where = [if (city.isNotEmpty) city, if (ip.isNotEmpty) ip].join(' · ');
    final ok = await confirm(context,
        title: 'Войти на $plat?',
        body: '${where.isNotEmpty ? '$where\n\n' : ''}'
            'Там откроются все твои чаты. Подтверждай, только если это твой компьютер '
            'и ты сам(а) сейчас видишь этот QR-код.',
        action: 'Войти');
    if (!ok || !context.mounted) return false;
    await Api.qrApprove(token: ref.token, code: ref.code);
    if (context.mounted) {
      HapticFeedback.mediumImpact();
      toast(context, 'Готово — вход на $plat выполнен', icon: AppIcons.monitorSmartphone);
    }
    return true;
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
    return false;
  }
}

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});
  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _ctrl = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _handle(String raw) async {
    if (_busy) return;
    _busy = true;
    await _ctrl.stop();
    if (!mounted) return;
    final ok = await approveQrLogin(context, raw);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      _busy = false;
      await _ctrl.start();
    }
  }

  Future<void> _manual() async {
    final code = await askText(context,
        title: 'Код с компьютера',
        hint: 'ABCD-1234',
        action: 'Войти',
        maxLength: 12);
    if (code == null || code.trim().isEmpty || !mounted) return;
    await _handle(code);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Подключить компьютер'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _ctrl,
            onDetect: (capture) {
              for (final b in capture.barcodes) {
                final v = b.rawValue;
                if (v != null && v.isNotEmpty) {
                  _handle(v);
                  break;
                }
              }
            },
          ),
          // рамка прицела
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 40,
            child: Column(
              children: [
                const Text(
                  'Открой Connecto на компьютере и наведи камеру на QR-код',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  onPressed: _manual,
                  icon: const Icon(AppIcons.keyboard),
                  label: const Text('Ввести код вручную'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
