import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_flow.dart';
import 'verify_code_screen.dart';

String maskEmail(String email) {
  final at = email.indexOf('@');
  if (at <= 0) return email;
  final name = email.substring(0, at);
  final dom = email.substring(at);
  if (name.length <= 2) return '${name[0]}*$dom';
  return '${name[0]}${'*' * (name.length - 2)}${name[name.length - 1]}$dom';
}

/// Смена почты: пароль → код на новую почту → готово.
class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});
  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim().toLowerCase();
    if (!_emailRe.hasMatch(email)) {
      toast(context, 'Введи корректную почту', error: true);
      return;
    }
    if (email == appState.email.toLowerCase()) {
      toast(context, 'Это и так твоя почта', error: true);
      return;
    }
    if (_password.text.isEmpty) {
      toast(context, 'Введи пароль от аккаунта', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final password = _password.text;
    try {
      final r = await Api.changeEmailStart(email, password);
      if (!mounted) return;
      if (r['changed'] == true) {
        appState.applyServerUser((r['user'] as Map).cast<String, dynamic>());
        Navigator.pop(context);
        toast(context, 'Почта изменена', icon: AppIcons.mailCheck);
        return;
      }
      setState(() => _loading = false);
      final nav = Navigator.of(context);
      await nav.push(MaterialPageRoute(
        builder: (_) => EmailCodeScreen(
          title: 'Код с новой почты',
          subtitle: 'Мы отправили код на\n${r['email_masked'] ?? email}',
          onVerify: (ctx, code) async {
            final u = await Api.changeEmailConfirm(email, code);
            appState.applyServerUser(u);
            if (!ctx.mounted) return;
            Navigator.of(ctx)
              ..pop()
              ..pop();
            toast(ctx, 'Почта изменена на ${maskEmail(email)}', icon: AppIcons.mailCheck);
          },
          onResend: () async {
            await Api.changeEmailStart(email, password);
          },
        ),
      ));
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          FadeSlideIn(
            child: AuthHeader(
              title: 'Смена почты',
              subtitle: 'Сейчас: ${maskEmail(appState.email)}\n'
                  'На новую почту придёт код подтверждения',
              icon: AppIcons.mail,
            ),
          ),
          const SizedBox(height: 28),
          FadeSlideIn(
            delayMs: 60,
            child: AppTextField(
                controller: _email,
                hint: 'Новая почта',
                icon: AppIcons.atSign,
                keyboard: TextInputType.emailAddress),
          ),
          const SizedBox(height: 12),
          FadeSlideIn(
            delayMs: 120,
            child: AppTextField(
              controller: _password,
              hint: 'Пароль от аккаунта',
              icon: AppIcons.lock,
              obscure: _obscure,
              onSubmitted: (_) => _submit(),
              suffix: IconButton(
                icon: Icon(_obscure ? AppIcons.eyeOff : AppIcons.eye,
                    color: subtleText(context), size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          const SizedBox(height: 22),
          FadeSlideIn(
            delayMs: 180,
            child: PrimaryButton(label: 'Получить код', loading: _loading, onTap: _submit),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(kRadius)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const IconTile(AppIcons.shieldCheck, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                      'Почту видишь только ты: она нужна для входа, кодов и восстановления пароля. '
                      'На старую почту придёт уведомление о смене.',
                      style: TextStyle(color: subtleText(context), fontSize: 13, height: 1.35)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
