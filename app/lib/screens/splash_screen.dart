import 'dart:async';
import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import 'home_shell.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<double> _scale;
  late final Animation<double> _logoFade;
  late final Animation<double> _textFade;
  String _status = 'Подключение…';
  bool _offline = false; // нет сети, но есть сохранённый вход

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1600));
    _scale = Tween(begin: 0.82, end: 1.0)
        .animate(CurvedAnimation(parent: _c, curve: const Interval(0.0, 0.5, curve: Curves.easeOutBack)));
    _logoFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.0, 0.35, curve: Curves.easeIn));
    _textFade = CurvedAnimation(
        parent: _c, curve: const Interval(0.45, 1.0, curve: Curves.easeIn));
    _c.forward();
    _start();
  }

  Future<void> _start() async {
    final connected = await Api.ping();
    if (mounted) {
      setState(() => _status = connected ? 'Подключено' : 'Не подключено');
    }
    final ok = await appState.tryAutoLogin();
    if (!connected && ok) {
      // нет сети, но есть сохранённый вход — предлагаем зайти офлайн
      if (mounted) setState(() => _offline = true);
      return;
    }
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    _go(ok ? const HomeShell() : const LoginScreen());
  }

  void _go(Widget page) {
    Navigator.of(context).pushReplacement(PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) =>
          FadeTransition(opacity: a, child: child),
    ));
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connected = _status == 'Подключено';
    final failed = _status == 'Сервер недоступен';
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _c,
              builder: (_, __) => Opacity(
                opacity: _logoFade.value,
                child: Transform.scale(
                    scale: _scale.value, child: _logo(appState.accent)),
              ),
            ),
            const SizedBox(height: 30),
            FadeTransition(
              opacity: _textFade,
              child: Column(
                children: [
                  const Text('Connecto',
                      style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1)),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!connected && !failed)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: appState.accent),
                        )
                      else
                        Icon(
                            connected ? AppIcons.circleCheck : AppIcons.circleAlert,
                            size: 15,
                            color: connected
                                ? const Color(0xFF10B981)
                                : const Color(0xFFF43F5E)),
                      const SizedBox(width: 8),
                      Text(_status,
                          style: TextStyle(
                              fontSize: 13,
                              color: subtleText(context),
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                  if (_offline) ...[
                    const SizedBox(height: 22),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                          'Нет соединения с сервером. Можно зайти офлайн — посмотреть загруженные чаты и фото.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 13, color: subtleText(context))),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: appState.accent,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 12)),
                      onPressed: () => _go(const HomeShell()),
                      child: const Text('Зайти офлайн'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _logo(Color accent) => AppLogo(size: 116, accent: accent);
}
