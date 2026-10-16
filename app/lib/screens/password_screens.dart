import 'package:flutter/material.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class _PwField extends StatefulWidget {
  final TextEditingController c;
  final String hint;
  final IconData icon;
  final bool autofocus;
  const _PwField(this.c, this.hint, {this.icon = AppIcons.lock, this.autofocus = false});
  @override
  State<_PwField> createState() => _PwFieldState();
}

class _PwFieldState extends State<_PwField> {
  bool _obscure = true;
  @override
  Widget build(BuildContext context) => AppTextField(
        controller: widget.c,
        hint: widget.hint,
        icon: widget.icon,
        obscure: _obscure,
        autofocus: widget.autofocus,
        suffix: IconButton(
          icon: Icon(_obscure ? AppIcons.eyeOff : AppIcons.eye,
              color: subtleText(context), size: 20),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      );
}

Widget _header(BuildContext context, IconData icon, String title, String sub) => FadeSlideIn(
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
                gradient: accentGradient(appState.accent), shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 38),
          ),
          const SizedBox(height: 16),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(context), height: 1.4)),
        ],
      ),
    );

/// Смена пароля для входа.
class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});
  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _old = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _old.dispose();
    _new.dispose();
    _new2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text.length < 8) {
      toast(context, 'Новый пароль — минимум 8 символов', error: true);
      return;
    }
    if (_new.text != _new2.text) {
      toast(context, 'Пароли не совпадают', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      await Api.changePassword(_old.text, _new.text);
      if (!mounted) return;
      toast(context, 'Пароль изменён. Другие устройства вышли из аккаунта',
          icon: AppIcons.shieldCheck);
      Navigator.pop(context);
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
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        children: [
          _header(context, AppIcons.keyRound, 'Смена пароля',
              'После смены на всех остальных устройствах произойдёт выход.'),
          const SizedBox(height: 26),
          _PwField(_old, 'Текущий пароль', autofocus: true),
          const SizedBox(height: 12),
          _PwField(_new, 'Новый пароль', icon: AppIcons.lockKeyhole),
          const SizedBox(height: 12),
          _PwField(_new2, 'Повтори новый пароль', icon: AppIcons.lockKeyhole),
          const SizedBox(height: 24),
          PrimaryButton(label: 'Сохранить', loading: _loading, onTap: _save),
        ],
      ),
    );
  }
}

/// Облачный пароль (двухэтапная проверка): включить, сменить, выключить.
class CloudPasswordScreen extends StatefulWidget {
  const CloudPasswordScreen({super.key});
  @override
  State<CloudPasswordScreen> createState() => _CloudPasswordScreenState();
}

class _CloudPasswordScreenState extends State<CloudPasswordScreen> {
  final _cur = TextEditingController();
  final _new = TextEditingController();
  final _new2 = TextEditingController();
  final _hint = TextEditingController();
  bool _loading = false;
  bool _editing = false;

  @override
  void dispose() {
    _cur.dispose();
    _new.dispose();
    _new2.dispose();
    _hint.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_new.text.length < 4) {
      toast(context, 'Облачный пароль — минимум 4 символа', error: true);
      return;
    }
    if (_new.text != _new2.text) {
      toast(context, 'Пароли не совпадают', error: true);
      return;
    }
    setState(() => _loading = true);
    try {
      final u = await Api.setCloudPassword(
          current: appState.hasCloudPassword ? _cur.text : null,
          newPassword: _new.text,
          hint: _hint.text.trim());
      appState.applyServerUser(u);
      if (!mounted) return;
      toast(context, 'Облачный пароль сохранён', icon: AppIcons.shieldCheck);
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _disable() async {
    final pw = await askText(context,
        title: 'Отключить облачный пароль',
        hint: 'Текущий облачный пароль',
        action: 'Отключить');
    if (pw == null || pw.isEmpty || !mounted) return;
    try {
      final u = await Api.setCloudPassword(current: pw);
      appState.applyServerUser(u);
      if (!mounted) return;
      toast(context, 'Облачный пароль отключён', icon: AppIcons.shieldOff);
      setState(() {});
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = appState.hasCloudPassword;
    final showForm = !on || _editing;
    return Scaffold(
      appBar: AppBar(),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
        children: [
          _header(
              context,
              on ? AppIcons.shieldCheck : AppIcons.shield,
              on ? 'Облачный пароль включён' : 'Облачный пароль',
              'При входе на новом устройстве, кроме кода из письма, '
                  'понадобится этот пароль. Даже если кто-то узнает твой основной пароль — войти не сможет.'),
          const SizedBox(height: 24),
          if (on && !_editing) ...[
            if ((appState.cloudPasswordHint ?? '').isNotEmpty)
              SectionCard(children: [
                SettingsTile(
                    icon: AppIcons.lightbulb,
                    title: appState.cloudPasswordHint!,
                    subtitle: 'Подсказка',
                    chevron: false),
              ]),
            const SizedBox(height: 12),
            SectionCard(children: [
              SettingsTile(
                  icon: AppIcons.pencil,
                  title: 'Сменить облачный пароль',
                  onTap: () => setState(() => _editing = true)),
              SettingsTile(
                  icon: AppIcons.shieldOff,
                  title: 'Отключить',
                  danger: true,
                  onTap: _disable,
                  chevron: false),
            ]),
          ],
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            child: showForm
                ? Column(
                    children: [
                      if (on) ...[
                        _PwField(_cur, 'Текущий облачный пароль', autofocus: true),
                        const SizedBox(height: 12),
                      ],
                      _PwField(_new, 'Новый облачный пароль',
                          icon: AppIcons.lockKeyhole, autofocus: !on),
                      const SizedBox(height: 12),
                      _PwField(_new2, 'Повтори пароль', icon: AppIcons.lockKeyhole),
                      const SizedBox(height: 12),
                      AppTextField(
                          controller: _hint,
                          hint: 'Подсказка (необязательно)',
                          icon: AppIcons.lightbulb,
                          maxLength: 64),
                      const SizedBox(height: 8),
                      Text(
                          'Если забудешь облачный пароль, его можно сбросить кодом из письма на ${appState.email}.',
                          style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                      const SizedBox(height: 22),
                      PrimaryButton(
                          label: on ? 'Сохранить новый пароль' : 'Включить',
                          loading: _loading,
                          onTap: _save),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}
