import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'app_state.dart';
import 'realtime.dart';

/// Одна история.
class StoryItem {
  final String id;
  final String userId;
  final String mediaUrl;
  final String kind; // image|video
  final String caption;
  final String audience;
  bool pinned;
  final bool active;
  final DateTime createdAt;
  final DateTime? expiresAt;
  bool seen;
  int viewsCount;
  int reactionsCount;
  String? myReaction;
  final List<Map<String, dynamic>> overlays;
  final String? musicUrl;
  final String? musicTitle;

  StoryItem({
    required this.id,
    required this.userId,
    required this.mediaUrl,
    required this.kind,
    required this.caption,
    required this.audience,
    required this.pinned,
    required this.active,
    required this.createdAt,
    required this.expiresAt,
    required this.seen,
    this.viewsCount = 0,
    this.reactionsCount = 0,
    this.myReaction,
    this.overlays = const [],
    this.musicUrl,
    this.musicTitle,
  });

  bool get isVideo => kind == 'video';
  bool get mine => userId == appState.myUserId;

  factory StoryItem.fromMap(Map<String, dynamic> m) => StoryItem(
        id: m['id'] as String,
        userId: m['user_id'] as String? ?? '',
        mediaUrl: m['media_url'] as String? ?? '',
        kind: m['kind'] as String? ?? 'image',
        caption: m['caption'] as String? ?? '',
        audience: m['audience'] as String? ?? 'all',
        pinned: m['pinned'] == true,
        active: m['active'] != false,
        createdAt: parseServerTime(m['created_at'] as String? ?? '') ??
            DateTime.now(),
        expiresAt: parseServerTime(m['expires_at'] as String? ?? ''),
        seen: m['seen'] == true,
        viewsCount: (m['views_count'] as num?)?.toInt() ?? 0,
        reactionsCount: (m['reactions_count'] as num?)?.toInt() ?? 0,
        myReaction: m['my_reaction'] as String?,
        overlays: ((m['overlays'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList(),
        musicUrl: m['music_url'] as String?,
        musicTitle: m['music_title'] as String?,
      );
}

/// Истории одного человека (кружок).
class StoryGroup {
  final String userId;
  final String name;
  final String? avatarUrl;
  final bool premium;
  final bool verified;
  final bool isMe;
  final List<StoryItem> stories;

  StoryGroup({
    required this.userId,
    required this.name,
    required this.avatarUrl,
    required this.premium,
    required this.verified,
    required this.isMe,
    required this.stories,
  });

  bool get hasUnseen => stories.any((s) => !s.seen);

  /// С какой истории начинать: первая непросмотренная.
  int get startIndex {
    final i = stories.indexWhere((s) => !s.seen);
    return i < 0 ? 0 : i;
  }

  factory StoryGroup.fromMap(Map<String, dynamic> g) {
    final u = (g['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return StoryGroup(
      userId: u['id'] as String? ?? '',
      name: u['display_name'] as String? ?? '',
      avatarUrl: u['avatar_url'] as String?,
      premium: u['is_premium'] == true,
      verified: u['is_verified'] == true,
      isMe: g['is_me'] == true,
      stories: ((g['stories'] as List?) ?? const [])
          .map((e) => StoryItem.fromMap((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

/// Лента историй над чатами. Обновляется по WebSocket.
class StoriesStore extends ChangeNotifier {
  List<StoryGroup> groups = [];
  Map<String, dynamic> limits = const {};
  bool loaded = false;
  /// Режим инкогнито (Premium): просмотры не видны авторам.
  bool stealth = false;
  bool _listening = false;
  Timer? _deb;
  String? _owner;

  StoryGroup? get mine {
    for (final g in groups) {
      if (g.isMe) return g;
    }
    return null;
  }

  List<StoryGroup> get others => groups.where((g) => !g.isMe).toList();

  StoryGroup? groupOf(String userId) {
    for (final g in groups) {
      if (g.userId == userId) return g;
    }
    return null;
  }

  bool hasActive(String? userId) => userId != null && groupOf(userId) != null;
  bool hasUnseen(String? userId) => groupOf(userId ?? '')?.hasUnseen ?? false;

  int get left => (limits['left'] as num?)?.toInt() ?? 0;

  void _listen() {
    if (_listening) return;
    _listening = true;
    Realtime.addListener((m) {
      final t = m['type'];
      if (t == 'story_new' || t == 'story_deleted') refreshSoon();
    });
  }

  void refreshSoon() {
    _deb?.cancel();
    _deb = Timer(const Duration(milliseconds: 400), refresh);
  }

  Future<void> refresh() async {
    _listen();
    if (appState.myUserId == null) return;
    if (_owner != appState.myUserId) {
      // сменили аккаунт — чистим чужую ленту
      _owner = appState.myUserId;
      groups = [];
      loaded = false;
      notifyListeners();
    }
    try {
      final d = await Api.storiesFeed();
      groups = ((d['groups'] as List?) ?? const [])
          .map((e) => StoryGroup.fromMap((e as Map).cast<String, dynamic>()))
          .toList();
      limits = (d['limits'] as Map?)?.cast<String, dynamic>() ?? const {};
      loaded = true;
      notifyListeners();
    } catch (_) {}
  }

  void markSeen(String storyId) {
    for (final g in groups) {
      for (final s in g.stories) {
        if (s.id == storyId && !s.seen) {
          s.seen = true;
          notifyListeners();
          return;
        }
      }
    }
  }

  /// После просмотра — непросмотренные вперёд.
  void resort() {
    final me = groups.where((g) => g.isMe).toList();
    final unseen = groups.where((g) => !g.isMe && g.hasUnseen).toList();
    final seen = groups.where((g) => !g.isMe && !g.hasUnseen).toList();
    groups = [...me, ...unseen, ...seen];
    notifyListeners();
  }
}

final stories = StoriesStore();
