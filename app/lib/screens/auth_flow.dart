import 'package:flutter/material.dart';

import '../app_state.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'two_factor_screen.dart';
import 'verify_code_screen.dart';

/// Разбирает ответ входа и ведёт дальше: код с почты → облачный пароль → чаты.
Future<void> continueLogin(BuildContext context, Map<String, dynamic> r,
    {required String login, required String password}) async {
  if (r['needs_code'] == true) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerifyCodeScreen(
          login: login,
          password: password,
          emailMasked: (r['email_masked'] as String?) ?? '',
          toChat: r['sent_to_chat'] == true,
          toEmail: r['sent_to_email'] == true,
          hasCloudPassword: r['has_cloud_password'] == true,
          cloudPasswordHint: (r['cloud_password_hint'] as String?) ?? '',
        ),
      ),
    );
    return;
  }
  if (r['needs_password'] == true) {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TwoFactorScreen(
          ticket: r['ticket'] as String,
          hint: (r['hint'] as String?) ?? '',
        ),
      ),
    );
    return;
  }
  await finishLogin(context, r);
}

/// Токены получены — сохраняем и открываем чаты.
Future<void> finishLogin(BuildContext context, Map<String, dynamic> r,
    {bool isNewUser = false}) async {
  if (!isNewUser) {
    await appState.setOnboardingDone();
  }
  await appState.saveAuthResponse(r);
  if (!context.mounted) return;
  Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => const HomeShell()),
    (_) => false,
  );
}

/// Шапка экранов входа: логотип с мягким «парением».
class AuthHeader extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData? icon;
  const AuthHeader({super.key, required this.title, required this.subtitle, this.icon});

  @override
  State<AuthHeader> createState() => _AuthHeaderState();
}

class _AuthHeaderState extends State<AuthHeader> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2400));

  @override
  void initState() {
    super.initState();
    if (appState.motion) _c.repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = appState.accent;
    final hsl = HSLColor.fromColor(accent);
    final light = hsl.withLightness((hsl.lightness + 0.13).clamp(0.0, 1.0)).toColor();
    return Column(
      children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final t = Curves.easeInOut.transform(_c.value);
            return Transform.translate(
              offset: Offset(0, -6 * t),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                      colors: [accent, light],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.30 + 0.15 * t),
                      blurRadius: 30 + 10 * t,
                      offset: Offset(0, 14 - 4 * t),
                    ),
                  ],
                ),
                child: child,
              ),
            );
          },
          child: Center(
            child: widget.icon != null
                ? Icon(widget.icon, color: Colors.white, size: 40)
                : SizedBox.expand(child: CustomPaint(painter: LogoCPainter())),
          ),
        ),
        const SizedBox(height: 22),
        Text(widget.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.5)),
        const SizedBox(height: 6),
        Text(widget.subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF8A8F9C)
                : const Color(0xFF6B7280), height: 1.4)),
      ],
    );
  }
}
