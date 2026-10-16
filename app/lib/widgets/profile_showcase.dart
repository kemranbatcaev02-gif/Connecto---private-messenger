
import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../stories.dart';
import '../theme.dart';
import '../screens/story_create_screen.dart';
import 'gift_widgets.dart';
import 'story_widgets.dart';
import 'ui.dart';
import '../screens/appearance_screen.dart' show premiumGate;

/// Вкладки в профиле (как в Telegram): «Публикации» и «Подарки».
class ProfileShowcase extends StatefulWidget {
  final String userId;
  final String name;
  final String? avatarUrl;
  /// Кнопка «Подарить» (в чужом профиле).
  final VoidCallback? onGift;
  const ProfileShowcase({
    super.key,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.onGift,
  });

  @override
  State<ProfileShowcase> createState() => ProfileShowcaseState();
}

class ProfileShowcaseState extends State<ProfileShowcase> {
  int _tab = 0;
  List<StoryItem>? _posts;
  List<Map<String, dynamic>>? _gifts;
  int _giftCount = 0;
  int _giftValue = 0;
  bool _giftsHidden = false;

  bool get _mine => widget.userId == appState.myUserId;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    await Future.wait([_loadPosts(), _loadGifts()]);
  }

  Future<void> _loadPosts() async {
    try {
      final l = await Api.userPosts(widget.userId);
      if (!mounted) return;
      setState(() => _posts =
          l.map((e) => StoryItem.fromMap((e as Map).cast<String, dynamic>())).toList());
    } catch (_) {
      if (mounted) setState(() => _posts ??= []);
    }
  }

  Future<void> _loadGifts() async {
    try {
      final d = await Api.userGifts(widget.userId);
      if (!mounted) return;
      setState(() {
        _gifts = ((d['gifts'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _giftCount = (d['count'] as num?)?.toInt() ?? _gifts!.length;
        _giftValue = (d['value'] as num?)?.toInt() ?? 0;
        _giftsHidden = d['hidden_by_privacy'] == true;
      });
    } catch (_) {
      if (mounted) setState(() => _gifts ??= []);
    }
  }

  Widget _tabBtn(int i, IconData icon, String label, int? count) {
    final on = _tab == i;
    return Expanded(
      child: Pressable(
        onTap: () => setState(() => _tab = i),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: on ? appState.accent.withValues(alpha: 0.14) : Colors.transparent,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: on ? appState.accent : subtleText(context)),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: on ? appState.accent : subtleText(context))),
              if (count != null && count > 0) ...[
                const SizedBox(width: 5),
                Text('$count',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                        color: (on ? appState.accent : subtleText(context))
                            .withValues(alpha: 0.75))),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _empty(IconData icon, String title, String sub, {Widget? action, String? mascot}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        children: [
          if (mascot != null) MascotArt(mascot, size: 130) else IconTile(icon, size: 52),
          const SizedBox(height: 10),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
          const SizedBox(height: 4),
          Text(sub,
              textAlign: TextAlign.center,
              style: TextStyle(color: subtleText(context), fontSize: 13, height: 1.35)),
          if (action != null) ...[const SizedBox(height: 12), action],
        ],
      ),
    );
  }

  Widget _postsTab() {
    final posts = _posts;
    if (posts == null) {
      return const Padding(padding: EdgeInsets.all(16), child: Shimmer(height: 120, radius: 14));
    }
    if (posts.isEmpty) {
      return _empty(
        AppIcons.stories,
        'Публикаций пока нет',
        _mine
            ? 'Закрепи историю в профиле — она останется здесь даже после 24 часов'
            : 'Здесь появятся истории, которые ${widget.name} закрепит в профиле',
        action: _mine
            ? FilledButton.icon(
                onPressed: () => openStoryCreate(context).then((_) => _loadPosts()),
                icon: const Icon(AppIcons.plus, size: 18),
                label: const Text('Новая история'))
            : null,
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: PostsGrid(
        posts: posts,
        userId: widget.userId,
        name: widget.name,
        avatarUrl: widget.avatarUrl,
        onChanged: _loadPosts,
      ),
    );
  }

  Future<void> _buySelf() async {
    if (!appState.isPremium) {
      premiumGate(context, 'Подарки самому себе');
      return;
    }
    final ok = await showGiftShop(context, toUserId: appState.myUserId ?? '', toName: 'себя');
    if (ok) _loadGifts();
  }

  Widget _giftsTab() {
    final gifts = _gifts;
    if (gifts == null) {
      return const Padding(padding: EdgeInsets.all(16), child: Shimmer(height: 120, radius: 14));
    }
    if (_giftsHidden) {
      return _empty(AppIcons.eyeOff, 'Подарки скрыты', '${widget.name} скрыл(а) подарки настройками');
    }
    if (gifts.isEmpty) {
      return _empty(
        AppIcons.gift,
        mascot: 'onboarding_3_gifts',
        'Подарков пока нет',
        _mine
            ? 'Когда тебе что-то подарят, подарки появятся здесь. С Premium можно купить подарок себе'
            : 'Стань первым, кто подарит ${widget.name} подарок',
        action: _mine
            ? FilledButton.icon(
                onPressed: _buySelf,
                icon: const Icon(AppIcons.gift, size: 18),
                label: const Text('Купить себе'))
            : (widget.onGift == null
                ? null
                : FilledButton.icon(
                    onPressed: widget.onGift,
                    icon: const Icon(AppIcons.gift, size: 18),
                    label: const Text('Подарить'))),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
          child: Row(
            children: [
              Flexible(
                child: Text('${plural(_giftCount, 'подарок', 'подарка', 'подарков')} · ценность ',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: subtleText(context), fontSize: 13)),
              ),
              CoinAmount(_giftValue, size: 13, color: subtleText(context)),
              const Spacer(),
              if (widget.onGift != null)
                TextButton.icon(
                    onPressed: widget.onGift,
                    icon: const Icon(AppIcons.gift, size: 17),
                    label: const Text('Подарить'))
              else if (_mine)
                TextButton.icon(
                    onPressed: _buySelf,
                    icon: const Icon(AppIcons.plus, size: 17),
                    label: const Text('Себе')),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 2),
          child: GiftWall(
            gifts: gifts,
            onTap: (ug) async {
              final changed = await showGiftDetails(context, ug);
              if (changed) _loadGifts();
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return SectionCard(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Row(
          children: [
            _tabBtn(0, AppIcons.stories, 'Публикации', _posts?.length),
            const SizedBox(width: 6),
            _tabBtn(1, AppIcons.gift, 'Подарки', _giftCount),
          ],
        ),
      ),
      AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          transitionBuilder: (c, a) => FadeTransition(opacity: a, child: c),
          child: KeyedSubtree(
            key: ValueKey(_tab),
            child: _tab == 0 ? _postsTab() : _giftsTab(),
          ),
        ),
      ),
    ]);
  }
}
