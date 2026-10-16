import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../icons.dart';

import '../api.dart';
import '../app_state.dart';
import '../theme.dart';
import '../widgets/effects.dart';
import '../widgets/ui.dart';
import 'appearance_screen.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _name = TextEditingController(text: appState.displayName);
  final _last = TextEditingController(text: appState.lastName);
  final _bio = TextEditingController(text: appState.bio);
  final _handle = TextEditingController(text: appState.handle ?? '');
  final _phone = TextEditingController(text: appState.phone);
  DateTime? _birthday = appState.birthday;
  String? _avatar = appState.avatarUrl;
  bool _uploading = false;
  bool _saving = false;
  String? _cover = appState.coverUrl;
  String? _coverKind = appState.coverKind;
  String? _coverLocal;
  bool _coverChanged = false;
  bool _coverUploading = false;

  int get _bioLimit => appState.isPremium ? 300 : 140;

  @override
  void dispose() {
    _name.dispose();
    _last.dispose();
    _bio.dispose();
    _handle.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    final src = await showAppSheet<ImageSource>(context, builder: (ctx) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        SheetItem(
            icon: AppIcons.images,
            title: 'Выбрать из галереи',
            onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        SheetItem(
            icon: AppIcons.camera,
            title: 'Сделать фото',
            onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        if (_avatar != null && _avatar!.isNotEmpty)
          SheetItem(
              icon: AppIcons.trash2,
              title: 'Удалить фото',
              danger: true,
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _avatar = '');
              }),
        const SizedBox(height: 6),
      ]);
    });
    if (src == null) return;
    try {
      final x = await ImagePicker()
          .pickImage(source: src, imageQuality: 88, maxWidth: 1080);
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

  Future<void> _pickCoverPhoto() async {
    try {
      final x = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 92, maxWidth: 1600);
      if (x == null || !mounted) return;
      setState(() => _coverUploading = true);
      final square = await cropSquare(x.path);
      final up = await Api.uploadPath(square);
      if (!mounted) return;
      setState(() {
        _cover = up['url'] as String?;
        _coverKind = 'image';
        _coverLocal = square;
        _coverChanged = true;
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _coverUploading = false);
    }
  }

  Future<void> _pickCoverVideo() async {
    if (!appState.isPremium) {
      premiumGate(context, 'Видео-обложка');
      return;
    }
    try {
      final x = await ImagePicker().pickVideo(
          source: ImageSource.gallery, maxDuration: const Duration(seconds: 15));
      if (x == null) return;
      final d = await videoDuration(x.path);
      if (d == null || d.inMilliseconds > 15500) {
        if (mounted) {
          toast(context, 'Видео должно быть не длиннее 15 секунд', error: true);
        }
        return;
      }
      setState(() => _coverUploading = true);
      final up = await Api.uploadPath(x.path);
      if (!mounted) return;
      setState(() {
        _cover = up['url'] as String?;
        _coverKind = 'video';
        _coverLocal = x.path;
        _coverChanged = true;
      });
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _coverUploading = false);
    }
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1920),
      lastDate: now,
      helpText: 'День рождения',
    );
    if (picked != null) setState(() => _birthday = picked);
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      toast(context, 'Имя не может быть пустым', error: true);
      return;
    }
    if (_bio.text.length > _bioLimit) {
      toast(context, 'О себе — до $_bioLimit символов', error: true);
      return;
    }
    final handle = _handle.text.trim().replaceFirst('@', '');
    if (handle.isNotEmpty && !RegExp(r'^[a-zA-Z0-9_]{3,32}$').hasMatch(handle)) {
      toast(context, 'Юзернейм: 3–32 символа, латиница, цифры и _', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      if (handle.isNotEmpty && handle != (appState.handle ?? '')) {
        appState.applyServerUser(await Api.setHandle(handle));
      }
      final u = await Api.updateMe({
        'display_name': name,
        'last_name': _last.text.trim(),
        'bio': _bio.text.trim(),
        'phone': _phone.text.trim(),
        'birthday': _birthday != null ? _birthday!.toIso8601String().split('T').first : '',
        'avatar_url': _avatar ?? '',
        if (_coverChanged) 'cover_url': _cover ?? '',
        if (_coverChanged && _cover != null) 'cover_kind': _coverKind ?? 'image',
      });
      appState.applyServerUser(u);
      if (!mounted) return;
      toast(context, 'Профиль сохранён');
      Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, friendlyError(e), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _coverBtn(IconData icon, String label, VoidCallback onTap,
      {bool premium = false, bool danger = false}) {
    final color = danger ? kDanger : Theme.of(context).colorScheme.onSurface;
    return Pressable(
      onTap: _coverUploading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
        decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: hairline(context))),
        child: Row(
          children: [
            IconTile(icon, size: 28, danger: danger),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700)),
            ),
            if (premium) const Icon(AppIcons.star, color: kPremium, size: 16),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final b = _birthday;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Профиль'),
        actions: [
          TextButton(
              onPressed: _saving ? null : _save,
              child: const Text('Готово', style: TextStyle(fontWeight: FontWeight.w800))),
          const SizedBox(width: 6),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          Center(
            child: Pressable(
              onTap: _uploading ? null : _pickAvatar,
              child: Stack(
                children: [
                  Avatar(name: _name.text, url: _avatar, size: 110, useAccent: true),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: appState.accent,
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Theme.of(context).scaffoldBackgroundColor, width: 3),
                      ),
                      child: _uploading
                          ? const Padding(
                              padding: EdgeInsets.all(7),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(AppIcons.camera, color: Colors.white, size: 17),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          const SectionLabel('Обложка профиля · 1:1'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: cardColor(context), borderRadius: BorderRadius.circular(kRadiusL)),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: 104,
                    height: 104,
                    child: _coverUploading
                        ? const Center(child: CircularProgressIndicator())
                        : (_cover != null && _cover!.isNotEmpty)
                            ? CoverView(url: _cover!, kind: _coverKind, localPath: _coverLocal)
                            : Container(
                                decoration: BoxDecoration(
                                    gradient: accentGradient(appState.accent)),
                                child: const Icon(AppIcons.cover, color: Colors.white, size: 34),
                              ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _coverBtn(AppIcons.image, 'Фото', _pickCoverPhoto),
                      const SizedBox(height: 6),
                      _coverBtn(AppIcons.video, 'Видео до 15 с', _pickCoverVideo,
                          premium: true),
                      if (_cover != null && _cover!.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _coverBtn(AppIcons.trash2, 'Убрать', () => setState(() {
                              _cover = null;
                              _coverKind = null;
                              _coverLocal = null;
                              _coverChanged = true;
                            }), danger: true),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text('Фото обрежется по центру в квадрат. Видео-обложка — с Premium.',
                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Имя'),
          AppTextField(
              controller: _name,
              hint: 'Имя',
              icon: AppIcons.user,
              maxLength: 64,
              onChanged: (_) => setState(() {})),
          const SizedBox(height: 10),
          AppTextField(
              controller: _last,
              hint: 'Фамилия (необязательно)',
              icon: AppIcons.user,
              maxLength: 64),
          const SizedBox(height: 20),
          const SectionLabel('О себе'),
          AppTextField(
              controller: _bio,
              hint: 'Пара слов о себе',
              icon: AppIcons.info,
              maxLines: 3,
              onChanged: (_) => setState(() {})),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text(
                '${_bio.text.length}/$_bioLimit${appState.isPremium ? '' : ' · с Premium — до 300'}',
                style: TextStyle(
                    color: _bio.text.length > _bioLimit ? kDanger : subtleText(context),
                    fontSize: 12.5)),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Юзернейм'),
          AppTextField(
              controller: _handle,
              hint: 'юзернейм',
              prefixText: '@',
              icon: AppIcons.atSign,
              maxLength: 32),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: Text('По юзернейму тебя найдут в поиске, не зная номера и почты.',
                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
          ),
          const SizedBox(height: 20),
          const SectionLabel('Контакты'),
          AppTextField(
              controller: _phone,
              hint: 'Телефон (необязательно)',
              icon: AppIcons.phone,
              keyboard: TextInputType.phone,
              maxLength: 32),
          const SizedBox(height: 10),
          SectionCard(children: [
            SettingsTile(
              icon: AppIcons.cake,
              title: b == null
                  ? 'День рождения'
                  : '${b.day.toString().padLeft(2, '0')}.${b.month.toString().padLeft(2, '0')}.${b.year}',
              subtitle: b == null ? 'Не указан' : 'День рождения',
              onTap: _pickBirthday,
              trailing: b == null
                  ? null
                  : IconButton(
                      icon: Icon(AppIcons.x, color: subtleText(context), size: 18),
                      onPressed: () => setState(() => _birthday = null)),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Text('Кто видит телефон, фото, описание и день рождения — '
                'настраивается в «Конфиденциальности».',
                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
          ),
          const SizedBox(height: 26),
          PrimaryButton(label: 'Сохранить', loading: _saving, onTap: _save),
        ],
      ),
    );
  }
}
