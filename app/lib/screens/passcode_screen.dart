import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../icons.dart';

import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

const int kPinLength = 4;

/// Цифровая клавиатура + точки. onDone получает введённый PIN.
class PinPad extends StatefulWidget {
  final String title;
  final String? subtitle;
  final Future<bool> Function(String pin) onDone; // false → ошибка (тряска)
  final Widget? footer;
  const PinPad(
      {super.key, required this.title, this.subtitle, required this.onDone, this.footer});

  @override
  State<PinPad> createState() => PinPadState();
}

class PinPadState extends State<PinPad> with SingleTickerProviderStateMixin {
  String _pin = '';
  bool _busy = false;
  late final AnimationController _shake = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 420));

  void reset() => setState(() => _pin = '');

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  Future<void> _tap(String d) async {
    if (_busy || _pin.length >= kPinLength) return;
    HapticFeedback.selectionClick();
    setState(() => _pin += d);
    if (_pin.length == kPinLength) {
      _busy = true;
      await Future.delayed(const Duration(milliseconds: 120));
      final ok = await widget.onDone(_pin);
      _busy = false;
      if (!mounted) return;
      if (!ok) {
        HapticFeedback.heavyImpact();
        _shake.forward(from: 0);
      }
      setState(() => _pin = '');
    }
  }

  void _back() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
              gradient: accentGradient(appState.accent),
              borderRadius: BorderRadius.circular(24)),
          child: const Icon(AppIcons.lock, color: Colors.white, size: 32),
        ),
        const SizedBox(height: 20),
        Text(widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 6),
          Text(widget.subtitle!,
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(context))),
        ],
        const SizedBox(height: 26),
        AnimatedBuilder(
          animation: _shake,
          builder: (_, child) => Transform.translate(
            offset: Offset(math.sin(_shake.value * math.pi * 6) * 12 * (1 - _shake.value), 0),
            child: child,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < kPinLength; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  margin: const EdgeInsets.symmetric(horizontal: 9),
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _pin.length ? appState.accent : Colors.transparent,
                    border: Border.all(
                        color: i < _pin.length ? appState.accent : subtleText(context),
                        width: 2),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 34),
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['', '0', '<'],
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final k in row)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: k.isEmpty
                        ? const SizedBox(width: 72, height: 72)
                        : _key(k),
                  ),
              ],
            ),
          ),
        if (widget.footer != null) ...[const SizedBox(height: 10), widget.footer!],
      ],
    );
  }

  Widget _key(String k) {
    final isBack = k == '<';
    return Material(
      color: isBack ? Colors.transparent : cardColor(context),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () => isBack ? _back() : _tap(k),
        child: SizedBox(
          width: 72,
          height: 72,
          child: Center(
            child: isBack
                ? Icon(AppIcons.delete, color: subtleText(context))
                : Text(k,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
          ),
        ),
      ),
    );
  }
}

/// Экран блокировки поверх приложения.
class LockOverlay extends StatelessWidget {
  const LockOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: PinPad(
              title: 'Введите код-пароль',
              subtitle: 'Connecto заблокирован',
              onDone: (pin) async {
                final ok = appState.checkPasscode(pin);
                if (ok) appState.unlock(pin);
                return ok;
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Настройки код-пароля.
class PasscodeSettingsScreen extends StatefulWidget {
  const PasscodeSettingsScreen({super.key});
  @override
  State<PasscodeSettingsScreen> createState() => _PasscodeSettingsScreenState();
}

class _PasscodeSettingsScreenState extends State<PasscodeSettingsScreen> {
  Future<void> _set() async {
    final ok = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const _PasscodeSetup()));
    if (ok == true && mounted) {
      setState(() {});
      toast(context, 'Код-пароль включён');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) => Scaffold(
        appBar: AppBar(title: const Text('Код-пароль')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FadeSlideIn(
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                    color: appState.accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(kRadiusL)),
                child: Row(
                  children: [
                    Icon(AppIcons.shieldCheck, color: appState.accent),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                          'Код из 4 цифр для входа в приложение на этом устройстве. '
                          'Если забудешь — придётся выйти из аккаунтов и войти заново.',
                          style: TextStyle(color: subtleText(context), height: 1.4)),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (!appState.passcodeOn)
              PrimaryButton(label: 'Включить код-пароль', icon: AppIcons.lock, onTap: _set)
            else ...[
              SectionCard(children: [
                SettingsTile(
                    icon: AppIcons.keyRound,
                    title: 'Сменить код-пароль',
                    onTap: _set),
                SettingsTile(
                  icon: AppIcons.timer,
                  title: 'Автоблокировка',
                  subtitle: _lockLabel(appState.autoLockMinutes),
                  onTap: _pickAutoLock,
                ),
                SettingsTile(
                    icon: AppIcons.lock,
                    title: 'Заблокировать сейчас',
                    onTap: () {
                      appState.lockNow();
                      Navigator.pop(context);
                    }),
              ]),
              const SizedBox(height: 16),
              SectionCard(children: [
                SettingsTile(
                  icon: AppIcons.lockOpen,
                  title: 'Выключить код-пароль',
                  danger: true,
                  onTap: () async {
                    if (await confirm(context,
                        title: 'Выключить код-пароль?',
                        action: 'Выключить',
                        danger: true)) {
                      appState.clearPasscode();
                      if (context.mounted) toast(context, 'Код-пароль выключен');
                    }
                  },
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  String _lockLabel(int m) => switch (m) {
        0 => 'Сразу',
        1 => 'Через 1 минуту',
        5 => 'Через 5 минут',
        60 => 'Через час',
        _ => 'Через $m мин',
      };

  void _pickAutoLock() {
    showAppSheet(context, builder: (ctx) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final m in const [0, 1, 5, 60])
            ListTile(
              title: Text(_lockLabel(m)),
              trailing: appState.autoLockMinutes == m
                  ? Icon(AppIcons.check, color: appState.accent)
                  : null,
              onTap: () {
                appState.setAutoLock(m);
                Navigator.pop(ctx);
              },
            ),
          const SizedBox(height: 8),
        ],
      );
    });
  }
}

class _PasscodeSetup extends StatefulWidget {
  const _PasscodeSetup();
  @override
  State<_PasscodeSetup> createState() => _PasscodeSetupState();
}

class _PasscodeSetupState extends State<_PasscodeSetup> {
  String? _first;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Center(
        child: SingleChildScrollView(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: PinPad(
              key: ValueKey(_first == null),
              title: _first == null ? 'Придумай код-пароль' : 'Повтори код-пароль',
              subtitle: _first == null ? '4 цифры' : 'Чтобы не ошибиться',
              onDone: (pin) async {
                if (_first == null) {
                  setState(() => _first = pin);
                  return true;
                }
                if (pin != _first) {
                  setState(() => _first = null);
                  toast(context, 'Коды не совпали — попробуй снова', error: true);
                  return false;
                }
                appState.setPasscode(pin);
                if (mounted) Navigator.pop(context, true);
                return true;
              },
            ),
          ),
        ),
      ),
    );
  }
}
