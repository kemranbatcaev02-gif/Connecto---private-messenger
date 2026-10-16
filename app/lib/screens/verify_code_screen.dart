import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'auth_flow.dart';

/// Поле кода из 6 цифр: отдельные «ячейки» с анимацией.
class CodeField extends StatefulWidget {
  final ValueChanged<String> onCompleted;
  final int length;
  const CodeField({super.key, required this.onCompleted, this.length = 6});
  @override
  State<CodeField> createState() => CodeFieldState();
}

class CodeFieldState extends State<CodeField> {
  final _c = TextEditingController();
  final _f = FocusNode();

  void clear() {
    _c.clear();
    setState(() {});
    _f.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _f.requestFocus();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    _f.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _c.text;
    return SizedBox(
      height: 58,
      child: Stack(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < widget.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: 44,
                  height: 58,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: cardColor(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: i == text.length && _f.hasFocus
                          ? appState.accent
                          : (i < text.length
                              ? appState.accent.withValues(alpha: 0.45)
                              : Colors.transparent),
                      width: 1.8,
                    ),
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 160),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                    child: Text(
                      i < text.length ? text[i] : '',
                      key: ValueKey('$i${i < text.length ? text[i] : ''}'),
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
            ],
          ),
          // прозрачное поле поверх ячеек принимает ввод и вставку из буфера
          Positioned.fill(
            child: TextField(
              controller: _c,
              focusNode: _f,
              keyboardType: TextInputType.number,
              maxLength: widget.length,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              showCursor: false,
              enableInteractiveSelection: false,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              decoration: const InputDecoration(
                counterText: '',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                setState(() {});
                if (v.length == widget.length) widget.onCompleted(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Экран подтверждения входа кодом (устройство, почта, облачный пароль).
class VerifyCodeScreen extends StatefulWidget {
  final String login;
  final String password;
  final String emailMasked;
  final bool toChat; // код отправлен в чат «Connecto» на активном устройстве
  final bool toEmail;
  final bool hasCloudPassword;
  final String cloudPasswordHint;
  const VerifyCodeScreen({
    super.key,
    required this.login,
    required this.password,
    required this.emailMasked,
    this.toChat = false,
    this.toEmail = true,
    this.hasCloudPassword = false,
    this.cloudPasswordHint = '',
  });

  @override
  State<VerifyCodeScreen> createState() => _VerifyCodeScreenState();
}

class _VerifyCodeScreenState extends State<VerifyCodeScreen> {
  final _field = GlobalKey<CodeFieldState>();
  bool _loading = false;
  int _resendIn = 60;
  Timer? _timer;
  late bool _toChat = widget.toChat;
  late bool _toEmail = widget.toEmail;
  late String _emailMasked = widget.emailMasked;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _resendIn = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendIn <= 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify(String code) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final r = await Api.loginVerify(
        login: widget.login,
        password: widget.password,
        code: code,
        deviceId: appState.deviceId,
        platform: appState.platform,
      );
      if (!mounted) return;
      await continueLogin(context, r, login: widget.login, password: widget.password);
    } catch (e) {
      if (mounted) {
        toast(context, friendlyError(e), error: true);
        _field.currentState?.clear();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      if (_toEmail) {
        await _sendToEmail(showToast: false);
      } else {
        await Api.login(
          login: widget.login,
          password: widget.password,
          deviceId: appState.deviceId,
          platform: appState.platform,
        );
        if (!mounted) return;
        toast(context, 'Код отправлен ещё раз в чат Connecto', icon: AppIcons.smartphone);
      }
      _startTimer();
      setState(() {});
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  Future<void> _sendToEmail({bool showToast = true}) async {
    setState(() => _loading = true);
    try {
      final r = await Api.loginSendEmail(
        login: widget.login,
        password: widget.password,
        deviceId: appState.deviceId,
        platform: appState.platform,
      );
      if (!mounted) return;
      setState(() {
        _toEmail = true;
        _toChat = false;
        if (r['email_masked'] != null) _emailMasked = r['email_masked'] as String;
      });
      _startTimer();
      if (showToast) {
        toast(context, 'Код отправлен на почту $_emailMasked', icon: AppIcons.mail);
      }
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openCloudPasswordDialog() async {
    final ctrl = TextEditingController();
    var obscure = true;
    final submitted = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          title: const Text('Облачный пароль'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.cloudPasswordHint.isNotEmpty
                    ? 'Подсказка: «${widget.cloudPasswordHint}»'
                    : 'Введите ваш 2-этапный облачный пароль для входа.',
                style: const TextStyle(fontSize: 13.5),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                obscureText: obscure,
                decoration: InputDecoration(
                  labelText: 'Облачный пароль',
                  prefixIcon: const Icon(AppIcons.lock),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? AppIcons.eye : AppIcons.eyeOff),
                    onPressed: () => setDState(() => obscure = !obscure),
                  ),
                ),
                onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Войти'),
            ),
          ],
        ),
      ),
    );

    if (submitted == null || submitted.isEmpty) return;
    setState(() => _loading = true);
    try {
      final r = await Api.loginWithCloudPassword(
        login: widget.login,
        password: widget.password,
        cloudPassword: submitted,
        deviceId: appState.deviceId,
        platform: appState.platform,
      );
      if (!mounted) return;
      await finishLogin(context, r);
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        children: [
          FadeSlideIn(
            child: AuthHeader(
              title: 'Это вы?',
              subtitle: _toChat
                  ? 'Код подтверждения отправлен в чат «Connecto» на устройстве, где вы уже вошли.'
                  : 'Код подтверждения отправлен на почту\n$_emailMasked',
              icon: _toChat ? AppIcons.shieldCheck : AppIcons.mail,
            ),
          ),
          const SizedBox(height: 32),
          FadeSlideIn(delayMs: 100, child: CodeField(key: _field, onCompleted: _verify)),
          const SizedBox(height: 26),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _loading
                ? const Center(
                    key: ValueKey('l'),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ))
                : Center(
                    key: const ValueKey('r'),
                    child: _resendIn > 0
                        ? Text('Отправить код ещё раз можно через $_resendIn с',
                            style: TextStyle(color: subtleText(context), fontSize: 13))
                        : TextButton.icon(
                            onPressed: _resend,
                            icon: const Icon(AppIcons.refreshCw, size: 18),
                            label: const Text('Отправить код ещё раз')),
                  ),
          ),
          const SizedBox(height: 20),

          // Альтернативные способы входа
          if (_toChat) ...[
            Center(
              child: TextButton.icon(
                onPressed: _sendToEmail,
                icon: const Icon(AppIcons.mail, size: 18),
                label: const Text('Отправить код на почту'),
              ),
            ),
          ],
          if (widget.hasCloudPassword) ...[
            Center(
              child: TextButton.icon(
                onPressed: _openCloudPasswordDialog,
                icon: const Icon(AppIcons.lock, size: 18),
                label: const Text('Войти с помощью облачного пароля'),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(kRadius)),
            child: Row(
              children: [
                Icon(AppIcons.info, size: 18, color: subtleText(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    _toChat
                        ? 'Откройте приложение Connecto на другом телефоне или ПК — код ждёт вас в чате.'
                        : 'Письмо не пришло? Проверьте «Спам» и «Промоакции».',
                    style: TextStyle(color: subtleText(context), fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Универсальный экран «введи код из письма» (регистрация, смена почты).
class EmailCodeScreen extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  /// Проверить код. Бросает исключение — поле очищается и показывается ошибка.
  final Future<void> Function(BuildContext context, String code) onVerify;
  /// Отправить код ещё раз.
  final Future<void> Function() onResend;
  const EmailCodeScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onVerify,
    required this.onResend,
    this.icon = AppIcons.mailCheck,
  });

  @override
  State<EmailCodeScreen> createState() => _EmailCodeScreenState();
}

class _EmailCodeScreenState extends State<EmailCodeScreen> {
  final _field = GlobalKey<CodeFieldState>();
  bool _loading = false;
  int _resendIn = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _resendIn = 60;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendIn <= 0) {
        t.cancel();
      } else {
        setState(() => _resendIn--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _verify(String code) async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await widget.onVerify(context, code);
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        toast(context, friendlyError(e), error: true);
        _field.currentState?.clear();
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    try {
      await widget.onResend();
      if (!mounted) return;
      toast(context, 'Код отправлен ещё раз', icon: AppIcons.mail);
      _startTimer();
      setState(() {});
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
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
            child: AuthHeader(title: widget.title, subtitle: widget.subtitle, icon: widget.icon),
          ),
          const SizedBox(height: 32),
          FadeSlideIn(delayMs: 100, child: CodeField(key: _field, onCompleted: _verify)),
          const SizedBox(height: 26),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _loading
                ? const Center(
                    key: ValueKey('l'),
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ))
                : Center(
                    key: const ValueKey('r'),
                    child: _resendIn > 0
                        ? Text('Отправить код ещё раз можно через $_resendIn с',
                            style: TextStyle(color: subtleText(context), fontSize: 13))
                        : TextButton.icon(
                            onPressed: _resend,
                            icon: const Icon(AppIcons.refreshCw, size: 18),
                            label: const Text('Отправить код ещё раз')),
                  ),
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(kRadius)),
            child: Row(
              children: [
                Icon(AppIcons.info, size: 18, color: subtleText(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Письмо не пришло? Проверь «Спам» и «Промоакции». '
                      'Код действует 10 минут.',
                      style: TextStyle(color: subtleText(context), fontSize: 13)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
