import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../api.dart';
import '../app_state.dart';
import '../icons.dart';
import '../stories.dart';
import '../theme.dart';
import '../screens/story_create_screen.dart';
import '../screens/story_viewer_screen.dart';
import 'shared_media.dart';
import 'ui.dart';

/// Кольцо истории вокруг аватара: цветное — есть новые, серое — всё просмотрено.
class StoryRing extends StatefulWidget {
  final Widget child;
  final bool active;   // есть истории
  final bool unseen;   // есть непросмотренные
  final double width;
  final double gap;
  const StoryRing({
    super.key,
    required this.child,
    required this.active,
    required this.unseen,
    this.width = 2.6,
    this.gap = 2.4,
  });

  @override
  State<StoryRing> createState() => _StoryRingState();
}

class _StoryRingState extends State<StoryRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant StoryRing old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final spin = widget.active && widget.unseen && appState.motion;
    if (spin && !_c.isAnimating) _c.repeat();
    if (!spin && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final a = appState.accent;
    final h = HSLColor.fromColor(a);
    final colors = widget.unseen
        ? [
            a,
            h.withHue((h.hue + 40) % 360).withLightness(0.62).toColor(),
            const Color(0xFFFF7AB6),
            const Color(0xFFFFB347),
            a,
          ]
        : [subtleText(context).withValues(alpha: 0.35), subtleText(context).withValues(alpha: 0.35)];
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) => Container(
        padding: EdgeInsets.all(widget.width),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: colors,
            transform: GradientRotation(_c.value * 2 * math.pi),
          ),
        ),
        child: Container(
          padding: EdgeInsets.all(widget.gap),
          decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}

/// Открыть истории человека (если они есть в ленте — вместе с остальными).
Future<void> openStoriesOf(BuildContext context, String userId) async {
  final groups = stories.groups;
  final i = groups.indexWhere((g) => g.userId == userId);
  if (i >= 0) {
    await openStoryViewer(context, groups, i);
    return;
  }
  try {
    final d = await Api.userStories(userId);
    final list = ((d['stories'] as List?) ?? const [])
        .map((e) => StoryItem.fromMap((e as Map).cast<String, dynamic>()))
        .toList();
    if (list.isEmpty) {
      if (context.mounted) toast(context, 'Активных историй нет', icon: AppIcons.stories);
      return;
    }
    final u = (d['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    final g = StoryGroup(
      userId: userId,
      name: u['display_name'] as String? ?? '',
      avatarUrl: u['avatar_url'] as String?,
      premium: u['is_premium'] == true,
      verified: u['is_verified'] == true,
      isMe: userId == appState.myUserId,
      stories: list,
    );
    if (context.mounted) await openStoryViewer(context, [g], 0);
  } catch (e) {
    if (context.mounted) toast(context, friendlyError(e), error: true);
  }
}

/// Лента кружков над списком чатов.
class StoriesBar extends StatelessWidget {
  const StoriesBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: stories,
      builder: (context, _) {
        final mine = stories.mine;
        final others = stories.others;
        return SizedBox(
          height: 104,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: 1 + others.length,
            itemBuilder: (context, i) {
              if (i == 0) {
                return _Bubble(
                  key: const ValueKey('me'),
                  index: 0,
                  name: 'Моя история',
                  avatarUrl: appState.avatarUrl,
                  avatarName: appState.displayName,
                  active: mine != null,
                  unseen: false,
                  plus: true,
                  onTap: () {
                    if (mine != null) {
                      final idx = stories.groups.indexOf(mine);
                      openStoryViewer(context, stories.groups, idx < 0 ? 0 : idx);
                    } else {
                      openStoryCreate(context);
                    }
                  },
                  onLongPress: () => openStoryCreate(context),
                );
              }
              final g = others[i - 1];
              return _Bubble(
                key: ValueKey(g.userId),
                index: i,
                name: g.name,
                avatarUrl: g.avatarUrl,
                avatarName: g.name,
                active: true,
                unseen: g.hasUnseen,
                premium: g.premium,
                onTap: () {
                  final idx = stories.groups.indexOf(g);
                  openStoryViewer(context, stories.groups, idx < 0 ? 0 : idx);
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _Bubble extends StatelessWidget {
  final int index;
  final String name;
  final String? avatarUrl;
  final String avatarName;
  final bool active;
  final bool unseen;
  final bool plus;
  final bool premium;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  const _Bubble({
    super.key,
    required this.index,
    required this.name,
    required this.avatarUrl,
    required this.avatarName,
    required this.active,
    required this.unseen,
    required this.onTap,
    this.plus = false,
    this.premium = false,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final first = name.trim().split(' ').first;
    return FadeSlideIn(
      delayMs: 40 * math.min(index, 8),
      child: Pressable(
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              const SizedBox(height: 6),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  StoryRing(
                    active: active,
                    unseen: unseen || (plus && active),
                    child: Avatar(
                        name: avatarName,
                        url: avatarUrl,
                        size: active ? 56 : 66,
                        useAccent: plus),
                  ),
                  if (plus)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          gradient: accentGradient(appState.accent),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).scaffoldBackgroundColor, width: 2.4),
                        ),
                        child: const Icon(AppIcons.plus, size: 14, color: Colors.white),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(first.isEmpty ? '…' : first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: unseen ? FontWeight.w700 : FontWeight.w500,
                      color: unseen ? null : subtleText(context))),
            ],
          ),
        ),
      ),
    );
  }
}

/// Превью истории (для сетки публикаций и ответов).
class StoryThumb extends StatelessWidget {
  final String mediaUrl;
  final bool video;
  final double radius;
  const StoryThumb({super.key, required this.mediaUrl, required this.video, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    final a = appState.accent;
    final placeholder = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [a.withValues(alpha: 0.85), const Color(0xFF1F1B3A)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35), shape: BoxShape.circle),
          child: const Icon(AppIcons.play, color: Colors.white, size: 24),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: video
          ? placeholder
          : Image.network(
              mediaUrl.startsWith('http') ? mediaUrl : '$kBaseUrl$mediaUrl',
              fit: BoxFit.cover,
              gaplessPlayback: true,
              cacheWidth: 360,
              frameBuilder: (c, child, frame, sync) => AnimatedOpacity(
                opacity: frame == null && !sync ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: child,
              ),
              errorBuilder: (_, __, ___) => Container(color: a.withValues(alpha: 0.25)),
            ),
    );
  }
}

/// «Публикации» в профиле: закреплённые истории сеткой 3×N.
class PostsGrid extends StatelessWidget {
  final List<StoryItem> posts;
  final String userId;
  final String name;
  final String? avatarUrl;
  final VoidCallback? onChanged;
  const PostsGrid({
    super.key,
    required this.posts,
    required this.userId,
    required this.name,
    this.avatarUrl,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4, childAspectRatio: 0.72),
      itemCount: posts.length,
      itemBuilder: (context, i) {
        final p = posts[i];
        return FadeSlideIn(
          delayMs: 30 * math.min(i, 12),
          child: Pressable(
            scale: 0.95,
            onTap: () async {
              final g = StoryGroup(
                userId: userId,
                name: name,
                avatarUrl: avatarUrl,
                premium: false,
                verified: false,
                isMe: userId == appState.myUserId,
                stories: posts,
              );
              await openStoryViewer(context, [g], 0, startAt: i, markViews: true);
              onChanged?.call();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                StoryThumb(mediaUrl: mediaUrl(p.mediaUrl), video: p.isVideo, radius: 12),
                Positioned(
                  left: 6,
                  bottom: 6,
                  right: 6,
                  child: Row(
                    children: [
                      if (p.mine) ...[
                        const Icon(AppIcons.eye, size: 13, color: Colors.white),
                        const SizedBox(width: 3),
                        Text('${p.viewsCount}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                shadows: [Shadow(blurRadius: 6)])),
                      ],
                      const Spacer(),
                      if (p.active)
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                              color: appState.accent,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 1.4)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
