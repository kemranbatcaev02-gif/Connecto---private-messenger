import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_flow.dart';
import 'verify_code_screen.dart';

/// Шаг входа: облачный пароль (двухэтапная проверка).
class TwoFactorScreen extends StatefulWidget {
  final String ticket;
  final String hint;
  const TwoFactorScreen({super.key, required this.ticket, this.hint = ''});

  @override
  State<TwoFactorScreen> createState() => _TwoFactorScreenState();
}

class _TwoFactorScreenState extends State<TwoFactorScreen> {
  final _pw = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_pw.text.isEmpty) return;
    setState(() => _loading = true);
    try {
      final r = await Api.login2fa(widget.ticket, _pw.text);
      if (!mounted) return;
      await finishLogin(context, r);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgot() async {
    final ok = await confirm(context,
        title: 'Сбросить облачный пароль?',
        body: 'На почту придёт код. После ввода облачный пароль будет отключён, '
            'и ты войдёшь в аккаунт.',
        action: 'Прислать код');
    if (!ok || !mounted) return;
    try {
      final d = await Api.login2faForgot(widget.ticket);
      if (!mounted) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => _ResetTwoFactor(
                  ticket: widget.ticket,
                  emailMasked: (d['email_masked'] as String?) ?? '')));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          const FadeSlideIn(
            child: AuthHeader(
              title: 'Облачный пароль',
              subtitle: 'Аккаунт защищён двухэтапной проверкой.\nВведи облачный пароль.',
              icon: AppIcons.keyRound,
            ),
          ),
          const SizedBox(height: 30),
          FadeSlideIn(
            delayMs: 80,
            child: AppTextField(
              controller: _pw,
              hint: 'Облачный пароль',
              icon: AppIcons.lock,
              obscure: _obscure,
              autofocus: true,
              onSubmitted: (_) => _submit(),
              suffix: IconButton(
                icon: Icon(_obscure ? AppIcons.eyeOff : AppIcons.eye,
                    color: subtleText(context), size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (widget.hint.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(AppIcons.lightbulb, size: 16, color: subtleText(context)),
                const SizedBox(width: 8),
                Text('Подсказка: ${widget.hint}',
                    style: TextStyle(color: subtleText(context))),
              ],
            ),
          ],
          const SizedBox(height: 24),
          PrimaryButton(label: 'Войти', loading: _loading, onTap: _submit),
          const SizedBox(height: 10),
          Center(
            child: TextButton(onPressed: _forgot, child: const Text('Забыли облачный пароль?')),
          ),
        ],
      ),
    );
  }
}

class _ResetTwoFactor extends StatefulWidget {
  final String ticket;
  final String emailMasked;
  const _ResetTwoFactor({required this.ticket, required this.emailMasked});
  @override
  State<_ResetTwoFactor> createState() => _ResetTwoFactorState();
}

class _ResetTwoFactorState extends State<_ResetTwoFactor> {
  final _field = GlobalKey<CodeFieldState>();
  bool _loading = false;

  Future<void> _go(String code) async {
    setState(() => _loading = true);
    try {
      final r = await Api.login2faReset(widget.ticket, code);
      if (!mounted) return;
      await finishLogin(context, r);
    } catch (e) {
      if (mounted) {
        toast(context, friendlyError(e), error: true);
        _field.currentState?.clear();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          FadeSlideIn(
            child: AuthHeader(
              title: 'Код из письма',
              subtitle: 'Отправили на ${widget.emailMasked}',
              icon: AppIcons.mailCheck,
            ),
          ),
          const SizedBox(height: 30),
          CodeField(key: _field, onCompleted: _go),
          const SizedBox(height: 24),
          if (_loading) const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
