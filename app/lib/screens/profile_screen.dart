import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../icons.dart';

import '../api.dart';
import '../desktop_pane.dart';
import '../app_state.dart';
import '../theme.dart';
import '../stories.dart';
import '../widgets/shop_media.dart';
import '../widgets/effects.dart';
import '../widgets/gift_widgets.dart';
import '../widgets/profile_showcase.dart';
import '../widgets/story_widgets.dart';
import '../widgets/ui.dart';
import 'account_screen.dart';
import 'bots_screen.dart';
import 'chat_screen.dart';
import 'create_channel_screen.dart';
import 'create_group_screen.dart';
import 'edit_profile_screen.dart';
import 'image_viewer.dart';
import 'premium_screen.dart';
import 'story_create_screen.dart';
import 'wallet_screen.dart';

/// Вкладка «Профиль»: карточка, мои группы и каналы, аккаунты.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Map<String, dynamic>> _mine = [];
  bool _loading = true;
  final _showcase = GlobalKey<ProfileShowcaseState>();

  @override
  void initState() {
    super.initState();
    _load();
    stories.addListener(_onStories);
  }

  @override
  void dispose() {
    stories.removeListener(_onStories);
    super.dispose();
  }

  void _onStories() {
    if (mounted) setState(() {});
  }

  void _share() {
    final h = appState.handle;
    if (h == null || h.isEmpty) {
      toast(context, 'Сначала задай юзернейм', icon: AppIcons.atSign);
      _push(const EditProfileScreen());
      return;
    }
    Clipboard.setData(ClipboardData(text: '@$h'));
    toast(context, 'Юзернейм @$h скопирован', icon: AppIcons.copy);
  }

  /// Мой аватар: есть истории — кольцо и просмотр, иначе фото / редактирование.
  Widget _myAvatar(Widget avatar, {required bool ring, double size = 62}) {
    final mine = stories.mine;
    // рамка из магазина заменяет обычную обводку
    if (mine == null && appState.wornFrame != null) {
      final url = appState.avatarUrl;
      return GestureDetector(
        onTap: url != null && url.isNotEmpty
            ? () => openImageViewer(context, url: '$kBaseUrl$url')
            : () => _push(const EditProfileScreen()),
        onLongPress: () => openStoryCreate(context),
        child: Padding(
          padding: EdgeInsets.all(size * 0.12),
          child: FramedAvatar(size: size, frame: appState.wornFrame, child: avatar),
        ),
      );
    }
    if (mine != null) {
      return GestureDetector(
        onTap: () => openStoriesOf(context, appState.myUserId ?? ''),
        onLongPress: () => openStoryCreate(context),
        child: StoryRing(active: true, unseen: true, width: 3, gap: 3, child: avatar),
      );
    }
    final url = appState.avatarUrl;
    return GestureDetector(
      onTap: url != null && url.isNotEmpty
          ? () => openImageViewer(context, url: '$kBaseUrl$url')
          : () => _push(const EditProfileScreen()),
      onLongPress: () => openStoryCreate(context),
      child: ring ? AvatarRing(width: 3, child: avatar) : AvatarRing(child: avatar),
    );
  }

  Future<void> _load() async {
    try {
      final list = await Api.chats();
      if (!mounted) return;
      setState(() {
        _mine = list
            .map((e) => (e as Map).cast<String, dynamic>())
            .where((c) =>
                c['type'] != 'direct' &&
                (c['my_role'] == 'owner' || c['my_role'] == 'admin'))
            .toList();
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _push(Widget s) => openSection(context, s);

  Future<void> _create(Widget page) async {
    final c = await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    _load();
    if (c is Map<String, dynamic> && mounted) openChatScreen(context, c).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: appState,
      builder: (context, _) {
        final name =
            [appState.displayName, appState.lastName].where((x) => x.isNotEmpty).join(' ');
        final b = appState.birthday;
        final others =
            appState.accounts.where((a) => a['id'] != appState.myUserId).toList();
        return Scaffold(
          backgroundColor: Colors.transparent,
          body: RefreshIndicator(
            onRefresh: () async {
              await Future.wait([
                appState.refreshMe(),
                _load(),
                stories.refresh(),
                _showcase.currentState?.reload() ?? Future.value(),
              ]);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar(
                  pinned: true,
                  title: const Text('Профиль'),
                  actions: [
                    _barBtn(context, AppIcons.share2, 'Поделиться', _share),
                    const SizedBox(width: 8),
                    _barBtn(context, AppIcons.pencil, 'Изменить',
                        () => _push(const EditProfileScreen())),
                    const SizedBox(width: 12),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 120),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      FadeSlideIn(child: _header(context, name)),
                      const SizedBox(height: 18),
                      FadeSlideIn(
                        delayMs: 50,
                        child: Row(
                          children: [
                            _quick(AppIcons.pencil, 'Изменить',
                                () => _push(const EditProfileScreen())),
                            _quick(AppIcons.stories, 'История',
                                () => openStoryCreate(context).then((_) {
                                      _showcase.currentState?.reload();
                                    })),
                            _quick(AppIcons.coin, fmtCoins(appState.coins),
                                () => _push(const WalletScreen()),
                                color: const Color(0xFF0EA5E9)),
                            _quick(AppIcons.star, 'Premium',
                                () => _push(const PremiumScreen()),
                                color: kPremium),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      if (appState.bio.isNotEmpty ||
                          appState.phone.isNotEmpty ||
                          b != null)
                        FadeSlideIn(
                          delayMs: 90,
                          child: SectionCard(children: [
                            if (appState.bio.isNotEmpty)
                              _info(AppIcons.info, appState.bio, 'О себе'),
                            if (appState.phone.isNotEmpty)
                              _info(AppIcons.phone, appState.phone, 'Телефон'),
                            if (b != null)
                              _info(
                                  AppIcons.cake,
                                  '${b.day.toString().padLeft(2, '0')}.${b.month.toString().padLeft(2, '0')}.${b.year}',
                                  'День рождения'),
                          ]),
                        ),
                      if (appState.bio.isEmpty && appState.phone.isEmpty && b == null)
                        SectionCard(children: [
                          SettingsTile(
                              icon: AppIcons.sparkles,
                              title: 'Расскажи о себе',
                              subtitle: 'Добавь описание, телефон и день рождения',
                              onTap: () => _push(const EditProfileScreen())),
                        ]),
                      const SizedBox(height: 16),
                      FadeSlideIn(
                        delayMs: 120,
                        child: ProfileShowcase(
                          key: _showcase,
                          userId: appState.myUserId ?? '',
                          name: title(name),
                          avatarUrl: appState.avatarUrl,
                        ),
                      ),
                      const SizedBox(height: 18),
                      const SectionLabel('Мои группы и каналы'),
                      SectionCard(children: [
                        if (_loading)
                          const Padding(
                              padding: EdgeInsets.all(16),
                              child: Shimmer(height: 36, radius: 12))
                        else
                          for (final c in _mine)
                            ListTile(
                              onTap: () => openChatScreen(context, c).then((_) => _load()),
                              leading: Avatar(
                                name: (c['title'] as String?) ?? '',
                                url: c['avatar_url'] as String?,
                                size: 42,
                                icon: c['type'] == 'channel'
                                    ? AppIcons.megaphone
                                    : AppIcons.users,
                              ),
                              title: Text((c['title'] as String?) ?? '',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w700)),
                              subtitle: Text(
                                  '${c['type'] == 'channel' ? 'канал' : 'группа'} · '
                                  '${c['my_role'] == 'owner' ? 'владелец' : 'админ'} · '
                                  '${(c['member_count'] as num?)?.toInt() ?? 0}',
                                  style: TextStyle(color: subtleText(context), fontSize: 13)),
                            ),
                        SettingsTile(
                            icon: AppIcons.users,
                            title: 'Создать группу',
                            onTap: () => _create(const CreateGroupScreen())),
                        SettingsTile(
                            icon: AppIcons.megaphone,
                            title: 'Создать канал',
                            onTap: () => _create(const CreateChannelScreen())),
                        SettingsTile(
                            icon: AppIcons.bot,
                            title: 'Мои боты',
                            onTap: () => _push(const BotsScreen())),
                      ]),
                      const SizedBox(height: 18),
                      SectionLabel('Аккаунты · ${appState.accounts.length}/${appState.accountLimit}'),
                      SectionCard(children: [
                        for (final a in others)
                          ListTile(
                            onTap: () => switchToAccount(context, a),
                            leading: Avatar(
                                name: (a['display_name'] as String?) ?? '?',
                                url: a['avatar_url'] as String?,
                                size: 40),
                            title: Text((a['display_name'] as String?) ?? '',
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('Переключиться',
                                style: TextStyle(color: subtleText(context), fontSize: 12.5)),
                            trailing: Icon(AppIcons.arrowRightLeft,
                                color: subtleText(context), size: 18),
                          ),
                        SettingsTile(
                            icon: AppIcons.userPlus,
                            title: 'Добавить аккаунт',
                            onTap: () => addAccount(context),
                            chevron: false),
                        SettingsTile(
                            icon: AppIcons.logOut,
                            title: 'Выйти',
                            danger: true,
                            onTap: () => logoutFlow(context),
                            chevron: false),
                      ]),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, String name) {
    final title = name.isEmpty ? appState.username : name;
    final status = appState.handle != null && appState.handle!.isNotEmpty
        ? '@${appState.handle} · в сети'
        : 'в сети';
    final cover = appState.coverUrl;
    if (cover != null && cover.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(kRadiusL),
        child: AspectRatio(
          aspectRatio: 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CoverView(url: cover, kind: appState.coverKind),
              Positioned.fill(child: ProfileFxOverlay(fx: appState.profileFx)),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.45, 1],
                    colors: [Colors.transparent, Color(0xCC000000)],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: _glassBtn(AppIcons.pencil, () => _push(const EditProfileScreen())),
              ),
              Positioned(
                left: 16,
                right: 16,
                bottom: 16,
                child: Row(
                  children: [
                    _myAvatar(
                        Avatar(
                            name: title,
                            url: appState.avatarUrl,
                            size: stories.mine != null ? 56 : 62,
                            useAccent: true),
                        ring: true,
                        size: stories.mine != null ? 56 : 62),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          NameBadges(title,
                              premium: appState.isPremium,
                              verified: appState.isVerified,
                              emoji: appState.emojiStatus,
                              maxLines: 2,
                              style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                  color: appState.nameColor ?? Colors.white)),
                          const SizedBox(height: 2),
                          Text(status,
                              style: const TextStyle(
                                  color: Colors.white70, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    final col = Column(
      children: [
        _myAvatar(
            Avatar(
                name: title,
                url: appState.avatarUrl,
                size: stories.mine != null ? 100 : 108,
                useAccent: true),
            ring: false,
            size: stories.mine != null ? 100 : 108),
        const SizedBox(height: 14),
        NameBadges(title,
            premium: appState.isPremium,
            verified: appState.isVerified,
            emoji: appState.emojiStatus,
            maxLines: 2,
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: appState.nameColor)),
        const SizedBox(height: 4),
        Text(status, style: const TextStyle(color: kSuccess, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        TextButton.icon(
          onPressed: () => _push(const EditProfileScreen()),
          icon: const Icon(AppIcons.cover, size: 18),
          label: const Text('Добавить обложку'),
        ),
      ],
    );
    if (appState.profileFx == null) return col;
    return Stack(children: [
      Positioned.fill(child: ProfileFxOverlay(fx: appState.profileFx)),
      col,
    ]);
  }

  /// Круглая кнопка в шапке (как поиск в списке чатов).
  Widget _barBtn(BuildContext context, IconData icon, String tip, VoidCallback onTap) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: tip,
      child: Pressable(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap();
        },
        scale: 0.90,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: cardColor(context).withValues(alpha: dark ? 0.75 : 0.88),
            shape: BoxShape.circle,
            border: Border.all(color: hairline(context)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: dark ? 0.18 : 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(icon, size: 20),
        ),
      ),
    );
  }

  /// Стеклянная кнопка поверх обложки.
  Widget _glassBtn(IconData icon, VoidCallback onTap) => Pressable(
        onTap: onTap,
        child: ClipOval(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
          ),
        ),
      );

  String title(String name) => name.isEmpty ? appState.username : name;

  Widget _quick(IconData icon, String label, VoidCallback onTap, {Color? color}) =>
      ProfileAction(icon: icon, label: label, onTap: onTap, color: color, showLabel: true);

  Widget _info(IconData icon, String value, String label) =>
      InfoTile(icon: icon, title: Text(value), label: label);
}
