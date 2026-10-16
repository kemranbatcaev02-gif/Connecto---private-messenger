import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/member_card.dart';
import '../widgets/ui.dart';
import '../widgets/user_picker.dart';

/// Общая форма создания группы/канала. Возвращает созданный чат (Map).
class CreateChannelScreen extends StatelessWidget {
  const CreateChannelScreen({super.key});
  @override
  Widget build(BuildContext context) => const CreateChatForm(channel: true);
}

class CreateChatForm extends StatefulWidget {
  final bool channel;
  const CreateChatForm({super.key, required this.channel});
  @override
  State<CreateChatForm> createState() => _CreateChatFormState();
}

class _CreateChatFormState extends State<CreateChatForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _handle = TextEditingController();
  bool _public = false;
  String? _avatar;
  bool _uploading = false;
  bool _saving = false;
  final List<Map<String, dynamic>> _members = [];

  bool get _ch => widget.channel;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1024);
      if (x == null || !mounted) return;
      setState(() => _uploading = true);
      final up = await Api.uploadPath(x.path);
      if (mounted) setState(() => _avatar = up['url'] as String?);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickMembers() async {
    final r = await pickUsers(context,
        title: _ch ? 'Пригласить подписчиков' : 'Участники группы',
        action: 'Готово',
        allowEmpty: true,
        exclude: _members.map((m) => m['id'] as String).toSet());
    if (r != null && mounted) setState(() => _members.addAll(r));
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      toast(context, _ch ? 'Придумай название канала' : 'Придумай название группы',
          error: true);
      return;
    }
    final handle = _public ? _handle.text.trim().replaceFirst('@', '') : null;
    if (_public && !RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{3,31}$').hasMatch(handle ?? '')) {
      toast(context, 'Ссылка: 4–32 символа, латиница, цифры и _, начинается с буквы',
          error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final chat = await Api.createChat(
        type: _ch ? 'channel' : 'group',
        title: title,
        description: _desc.text.trim(),
        handle: handle,
        avatarUrl: _avatar,
        memberIds: _members.map((m) => m['id'] as String).toList(),
      );
      if (!mounted) return;
      final skipped = ((chat['skipped'] as List?) ?? const [])
          .map((e) => (e as Map)['name'])
          .join(', ');
      toast(
          context,
          skipped.isEmpty
              ? (_ch ? 'Канал создан 🎉' : 'Группа создана 🎉')
              : 'Создано. $skipped запретил(и) приглашать себя — отправь им ссылку',
          icon: AppIcons.partyPopper);
      Navigator.pop(context, chat);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_ch ? 'Новый канал' : 'Новая группа')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          FadeSlideIn(
            child: Row(
              children: [
                Pressable(
                  onTap: _uploading ? null : _pickAvatar,
                  child: Stack(
                    children: [
                      Avatar(
                        name: _title.text.isEmpty ? '?' : _title.text,
                        url: _avatar,
                        size: 78,
                        useAccent: _avatar == null,
                        icon: _avatar == null
                            ? AppIcons.camera
                            : (_ch ? AppIcons.megaphone : AppIcons.users),
                      ),
                      if (_uploading)
                        const Positioned.fill(
                          child: Center(
                              child: CircularProgressIndicator(color: Colors.white)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: AppTextField(
                    controller: _title,
                    hint: _ch ? 'Название канала' : 'Название группы',
                    maxLength: 128,
                    autofocus: true,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          FadeSlideIn(
            delayMs: 50,
            child: AppTextField(
              controller: _desc,
              hint: 'Описание (необязательно)',
              icon: AppIcons.info,
              maxLines: 3,
              maxLength: 500,
            ),
          ),
          const SizedBox(height: 22),
          FadeSlideIn(
            delayMs: 100,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(_ch ? 'Тип канала' : 'Тип группы'),
                SectionCard(children: [_typeTile(false), _typeTile(true)]),
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: _public
                      ? Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: AppTextField(
                            controller: _handle,
                            hint: 'ссылка (напр. my_team)',
                            prefixText: '@',
                            icon: AppIcons.atSign,
                            maxLength: 32,
                          ),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          FadeSlideIn(
            delayMs: 150,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(_ch
                    ? 'Подписчики · ${_members.length}'
                    : 'Участники · ${_members.length + 1}'),
                SectionCard(children: [
                  SettingsTile(
                    icon: AppIcons.userPlus,
                    title: _ch ? 'Пригласить людей' : 'Добавить участников',
                    subtitle: _ch ? 'Можно позже — по ссылке' : null,
                    onTap: _pickMembers,
                    chevron: false,
                  ),
                ]),
                if (_members.isNotEmpty) const SizedBox(height: 8),
                for (final m in _members)
                  MemberCard(
                    member: m,
                    trailing: IconButton(
                      icon: const Icon(AppIcons.x, color: Colors.white70, size: 20),
                      onPressed: () => setState(() => _members.remove(m)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          PrimaryButton(
            label: _ch ? 'Создать канал' : 'Создать группу',
            icon: _ch ? AppIcons.megaphone : AppIcons.users,
            loading: _saving,
            onTap: _create,
          ),
        ],
      ),
    );
  }

  Widget _typeTile(bool pub) {
    final sel = _public == pub;
    return ListTile(
      onTap: () => setState(() => _public = pub),
      leading: Icon(pub ? AppIcons.globe : AppIcons.lock,
          color: sel ? appState.accent : subtleText(context)),
      title: Text(pub ? 'Публичный' : 'Частный',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(
          pub ? 'Найдут через поиск по @ссылке' : 'Вход только по ссылке-приглашению',
          style: TextStyle(color: subtleText(context))),
      trailing: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: sel ? appState.accent : subtleText(context), width: sel ? 7 : 2),
        ),
      ),
    );
  }
}

// ── Совместимость со старыми экранами ──

class AppField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData? icon;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboard;
  const AppField(
      {super.key,
      required this.controller,
      required this.hint,
      this.icon,
      this.maxLines = 1,
      this.maxLength,
      this.keyboard});

  @override
  Widget build(BuildContext context) => AppTextField(
      controller: controller,
      hint: hint,
      icon: icon,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboard: keyboard);
}

class BigButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;
  const BigButton(
      {super.key, required this.label, required this.onTap, this.loading = false});

  @override
  Widget build(BuildContext context) =>
      PrimaryButton(label: label, onTap: onTap, loading: loading);
}
