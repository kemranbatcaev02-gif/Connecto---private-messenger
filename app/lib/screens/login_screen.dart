import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_flow.dart';
import '../platform.dart';
import 'forgot_password_screen.dart';
import 'qr_login.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  /// true — добавляем ещё один аккаунт (текущий остаётся в списке).
  final bool addAccount;
  const LoginScreen({super.key, this.addAccount = false});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final login = _login.text.trim();
    final password = _password.text;
    if (login.isEmpty || password.isEmpty) {
      toast(context, 'Заполни почту/логин и пароль', error: true);
      return;
    }
    if (widget.addAccount &&
        appState.accounts.any((a) =>
            (a['username'] as String?)?.toLowerCase() == login.toLowerCase() ||
            (a['email'] as String?)?.toLowerCase() == login.toLowerCase())) {
      toast(context, 'Этот аккаунт уже добавлен', error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    try {
      final r = await Api.login(
        login: login,
        password: password,
        deviceId: appState.deviceId,
        platform: appState.platform,
      );
      if (!mounted) return;
      await continueLogin(context, r, login: login, password: password);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final form = _form(context);
    return Scaffold(
      appBar: widget.addAccount
          ? AppBar(title: const Text('Добавить аккаунт'))
          : null,
      body: SafeArea(
        child: !desktopUx
            ? form
            : LayoutBuilder(builder: (context, box) {
                // компьютер: слева QR-код (войти телефоном), справа обычный вход
                if (box.maxWidth >= 820) {
                  return Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 900),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const SizedBox(width: 360, child: QrLoginPanel()),
                            const SizedBox(width: 40),
                            Expanded(child: SizedBox(height: 620, child: form)),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                  children: [
                    Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: const QrLoginPanel()),
                    ),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: SizedBox(height: 600, child: form),
                      ),
                    ),
                  ],
                );
              }),
      ),
    );
  }

  Widget _form(BuildContext context) {
    return ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          children: [
            SizedBox(height: widget.addAccount ? 8 : 40),
            FadeSlideIn(
              child: AuthHeader(
                title: widget.addAccount ? 'Ещё один аккаунт' : 'С возвращением',
                subtitle: widget.addAccount
                    ? 'Войди — и переключайся между аккаунтами в профиле'
                    : 'Войди в свой аккаунт Connecto',
              ),
            ),
            const SizedBox(height: 34),
            FadeSlideIn(
              delayMs: 80,
              child: AppTextField(
                  controller: _login,
                  hint: 'Почта, логин или @юзернейм',
                  icon: AppIcons.user,
                  keyboard: TextInputType.emailAddress),
            ),
            const SizedBox(height: 14),
            FadeSlideIn(
              delayMs: 140,
              child: AppTextField(
                controller: _password,
                hint: 'Пароль',
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
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const ForgotPasswordScreen())),
                child: const Text('Забыли пароль?'),
              ),
            ),
            const SizedBox(height: 8),
            FadeSlideIn(
              delayMs: 200,
              child: PrimaryButton(label: 'Войти', loading: _loading, onTap: _submit),
            ),
            const SizedBox(height: 22),
            FadeSlideIn(
              delayMs: 260,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Нет аккаунта? ', style: TextStyle(color: subtleText(context))),
                  GestureDetector(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const RegisterScreen())),
                    child: Text('Зарегистрироваться',
                        style: TextStyle(
                            color: appState.accent, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
          ],
    );
  }
}

/// Совместимость со старыми экранами: поле ввода входа/регистрации.
Widget authField(BuildContext context, TextEditingController c, String hint,
        IconData icon,
        {bool obscure = false, Widget? suffix}) =>
    AppTextField(controller: c, hint: hint, icon: icon, obscure: obscure, suffix: suffix);
