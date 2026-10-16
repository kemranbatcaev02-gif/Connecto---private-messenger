import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_flow.dart';
import 'legal_screen.dart';
import 'verify_code_screen.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _nick = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  static final _nickRe = RegExp(r'^[a-zA-Z0-9_]{3,32}$');
  static final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _nick.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _name.text.trim();
    final nick = _nick.text.trim();
    final email = _email.text.trim().toLowerCase();
    String? err;
    if (name.isEmpty) {
      err = 'Как тебя зовут?';
    } else if (!_emailRe.hasMatch(email)) {
      err = 'Введи корректную почту — на неё придёт код при входе';
    } else if (!_nickRe.hasMatch(nick)) {
      err = 'Логин: 3–32 символа, латиница, цифры и _';
    } else if (_password.text.length < 8) {
      err = 'Пароль — минимум 8 символов';
    } else if (_password.text != _confirm.text) {
      err = 'Пароли не совпадают';
    }
    if (err != null) {
      toast(context, err, error: true);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);
    final password = _password.text;
    Future<Map<String, dynamic>> create(String? code) => Api.register(
          username: nick,
          email: email,
          password: password,
          displayName: name,
          code: code,
          deviceId: appState.deviceId,
          platform: appState.platform,
        );
    try {
      // шаг 1: логин и почта свободны? — код на почту
      final c = await Api.registerCode(email, nick);
      if (!mounted) return;
      if (c['required'] != true) {
        final r = await create(null);
        if (!mounted) return;
        await finishLogin(context, r, isNewUser: true);
        return;
      }
      setState(() => _loading = false);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => EmailCodeScreen(
            title: 'Подтверди почту',
            subtitle: 'Мы отправили код из 6 цифр на\n${c['email_masked'] ?? email}',
            onVerify: (ctx, code) async {
              final r = await create(code);
              if (!ctx.mounted) return;
              await finishLogin(ctx, r, isNewUser: true);
            },
            onResend: () async {
              await Api.registerCode(email, nick);
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fields = <Widget>[
      AppTextField(controller: _name, hint: 'Имя', icon: AppIcons.smile, maxLength: 64),
      AppTextField(
          controller: _email,
          hint: 'Почта',
          icon: AppIcons.mail,
          keyboard: TextInputType.emailAddress),
      AppTextField(
          controller: _nick,
          hint: 'Логин для входа (латиница)',
          icon: AppIcons.atSign,
          maxLength: 32),
      AppTextField(
        controller: _password,
        hint: 'Пароль (от 8 символов)',
        icon: AppIcons.lock,
        obscure: _obscure,
        suffix: IconButton(
          icon: Icon(_obscure ? AppIcons.eyeOff : AppIcons.eye,
              color: subtleText(context), size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      AppTextField(
          controller: _confirm,
          hint: 'Повтори пароль',
          icon: AppIcons.lockKeyhole,
          obscure: _obscure,
          onSubmitted: (_) => _submit()),
    ];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          const FadeSlideIn(
            child: AuthHeader(
              title: 'Новый аккаунт',
              subtitle: 'На почту придёт код подтверждения.\nПотом он же будет защищать вход с новых устройств',
              icon: AppIcons.userPlus,
            ),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < fields.length; i++) ...[
            FadeSlideIn(delayMs: 60 * (i + 1), child: fields[i]),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 14),
          FadeSlideIn(
            delayMs: 380,
            child: PrimaryButton(
                label: 'Создать аккаунт', loading: _loading, onTap: _submit),
          ),
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              Text('Создавая аккаунт, ты принимаешь ',
                  style: TextStyle(color: subtleText(context), fontSize: 12.5)),
              GestureDetector(
                onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const LegalScreen(
                            title: 'Условия использования', body: kTermsText))),
                child: Text('условия использования',
                    style: TextStyle(
                        color: appState.accent,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
