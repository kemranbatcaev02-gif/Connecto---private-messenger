import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_flow.dart';
import 'verify_code_screen.dart';

/// Сброс пароля: почта → код из письма → новый пароль.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  final _pw = TextEditingController();
  final _pw2 = TextEditingController();
  final _field = GlobalKey<CodeFieldState>();
  int _step = 0; // 0 — почта, 1 — код, 2 — новый пароль
  String _code = '';
  bool _loading = false;
  bool _obscure = true;

  @override
  void dispose() {
    _email.dispose();
    _pw.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _email.text.trim().toLowerCase();
    if (!email.contains('@')) {
      toast(context, 'Введи почту аккаунта', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await Api.passwordForgot(email);
      if (mounted) setState(() => _step = 1);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (_pw.text.length < 8) {
      toast(context, 'Пароль — минимум 8 символов', error: true);
      return;
    }
    if (_pw.text != _pw2.text) {
      toast(context, 'Пароли не совпадают', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await Api.passwordReset(_email.text.trim().toLowerCase(), _code, _pw.text);
      if (!mounted) return;
      toast(context, 'Пароль изменён. Войди с новым паролем');
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      toast(context, friendlyError(e), error: true);
      if (e is ApiException && e.status == 400) setState(() => _step = 1);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      Column(
        key: const ValueKey(0),
        children: [
          AppTextField(
              controller: _email,
              hint: 'Почта аккаунта',
              icon: AppIcons.mail,
              keyboard: TextInputType.emailAddress,
              autofocus: true,
              onSubmitted: (_) => _sendCode()),
          const SizedBox(height: 22),
          PrimaryButton(label: 'Прислать код', loading: _loading, onTap: _sendCode),
        ],
      ),
      Column(
        key: const ValueKey(1),
        children: [
          CodeField(
            key: _field,
            onCompleted: (c) => setState(() {
              _code = c;
              _step = 2;
            }),
          ),
          const SizedBox(height: 18),
          Text('Если аккаунт с такой почтой есть — код уже в письме.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(context), fontSize: 13)),
          TextButton(
              onPressed: () => setState(() => _step = 0),
              child: const Text('Изменить почту')),
        ],
      ),
      Column(
        key: const ValueKey(2),
        children: [
          AppTextField(
            controller: _pw,
            hint: 'Новый пароль',
            icon: AppIcons.lock,
            obscure: _obscure,
            autofocus: true,
            suffix: IconButton(
              icon: Icon(_obscure ? AppIcons.eyeOff : AppIcons.eye,
                  color: subtleText(context), size: 20),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 12),
          AppTextField(
              controller: _pw2,
              hint: 'Повтори пароль',
              icon: AppIcons.lockKeyhole,
              obscure: _obscure,
              onSubmitted: (_) => _save()),
          const SizedBox(height: 22),
          PrimaryButton(label: 'Сохранить пароль', loading: _loading, onTap: _save),
          const SizedBox(height: 10),
          Text('После сброса выполнится выход на всех устройствах.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(context), fontSize: 12.5)),
        ],
      ),
    ];
    const titles = ['Сброс пароля', 'Код из письма', 'Новый пароль'];
    const subs = [
      'Укажи почту, к которой привязан аккаунт',
      'Введи 6 цифр из письма',
      'Придумай новый пароль для входа',
    ];
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: AuthHeader(
              key: ValueKey('h$_step'),
              title: titles[_step],
              subtitle: subs[_step],
              icon: const [AppIcons.keyRound, AppIcons.mailCheck, AppIcons.lock][_step],
            ),
          ),
          const SizedBox(height: 30),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            transitionBuilder: (c, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(
                position: Tween(begin: const Offset(0.08, 0), end: Offset.zero).animate(a),
                child: c,
              ),
            ),
            child: steps[_step],
          ),
        ],
      ),
    );
  }
}
