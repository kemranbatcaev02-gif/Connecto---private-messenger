import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'cache.dart';
import 'customization.dart';
import 'launcher_icon.dart';
import 'media_cache.dart';
import 'push_service.dart';
import 'realtime.dart';
import 'theme.dart';

/// Лимиты бесплатной версии и Premium (сервер проверяет свои, клиент — свои).
const int kFreeAccounts = 3;
const int kPremiumAccounts = 6;
const int kFreePinned = 5;
const int kPremiumPinned = 10;


/// Настройки звонков по умолчанию (ключ → значение).
const Map<String, bool> kCallPrefDefaults = {
  'noise': true, // шумоподавление
  'echo': true, // эхоподавление
  'agc': true, // автогромкость микрофона
  'hd': true, // видео 720p (иначе 480p)
  'saver': false, // экономия трафика: 360p, 15 кадров
  'speaker': true, // видеозвонок — сразу на громкую связь
  'ring': true, // мелодия входящего
  'vibrate': true, // вибрация входящего
  'mirror': true, // зеркалить своё видео с фронтальной камеры
  'pip': true, // картинка в картинке при сворачивании
  'proximity': true, // гасить экран у уха
  'roundAutoplay': true, // видеосообщения крутятся в чате без звука
};

class AppState extends ChangeNotifier {
  // ── Оформление ──
  ThemeMode themeMode = ThemeMode.dark;
  Color _accent = const Color(0xFF7C6CFF);

  /// Акцент с учётом Premium: эксклюзивные и свои цвета — только с Premium.
  Color get accent {
    if (isPremium) return _accent;
    final v = _accent.toARGB32();
    return kAccentPresets.any((c) => c.toARGB32() == v) ? _accent : kAccentPresets.first;
  }

  Color get rawAccent => _accent;

  void setThemeMode(ThemeMode m) { themeMode = m; notifyListeners(); _persist(); }
  void setAccent(Color c) { _accent = c; notifyListeners(); _persist(); }

  // ── Кастомизация (Premium-варианты откатываются к стандартным без подписки) ──
  String themeStyle = 'default';
  String bubbleStyle = 'classic';
  String fontFamily = 'Manrope';
  String transition = 'slide';
  String navStyle = 'glass';
  String avatarRing = 'accent';
  String iconStyle = 'color';
  int liveWallpaper = -1;       // индекс kLiveWallpapers, -1 — выкл
  String chatFrame = 'none';    // рамки чатов в списке (kChatFrames)
  String bubbleFrame = 'none';  // обводка сообщений (kBubbleFrames)
  FrameCustom chatFrameCustom = const FrameCustom();
  FrameCustom bubbleFrameCustom = const FrameCustom(width: 1.6, glow: 0.3);

  String _eff(List<Opt> list, String v) {
    final o = optOf(list, v);
    if (o.id != v) return list.first.id;
    return (o.premium && !isPremium) ? list.first.id : v;
  }

  String get themeStyleEff => _eff(kThemeStyles, themeStyle);
  String get bubbleStyleEff => _eff(kBubbleStyles, bubbleStyle);
  String get fontEff => _eff(kFonts, fontFamily);
  String get transitionEff => _eff(kTransitions, transition);
  String get navStyleEff => _eff(kNavStyles, navStyle);
  String get avatarRingEff => _eff(kAvatarRings, avatarRing);
  String get iconStyleEff => _eff(kIconStyles, iconStyle);
  String get chatFrameEff => _eff(kChatFrames, chatFrame);
  String get bubbleFrameEff => _eff(kBubbleFrames, bubbleFrame);

  void setFrames({String? chat, String? bubble, FrameCustom? chatCustom,
      FrameCustom? bubbleCustom}) {
    if (chat != null) chatFrame = chat;
    if (bubble != null) bubbleFrame = bubble;
    if (chatCustom != null) chatFrameCustom = chatCustom;
    if (bubbleCustom != null) bubbleFrameCustom = bubbleCustom;
    notifyListeners();
    _persist();
  }
  int get liveWallpaperEff =>
      (isPremium && liveWallpaper >= 0 && liveWallpaper < kLiveWallpapers.length)
          ? liveWallpaper
          : -1;

  void setCustom({String? theme, String? bubble, String? font, String? trans,
      String? nav, String? ring, int? live, String? icons}) {
    if (icons != null) iconStyle = icons;
    if (theme != null) themeStyle = theme;
    if (bubble != null) bubbleStyle = bubble;
    if (font != null) fontFamily = font;
    if (trans != null) transition = trans;
    if (nav != null) navStyle = nav;
    if (ring != null) avatarRing = ring;
    if (live != null) {
      liveWallpaper = live;
      if (live >= 0) shopWallpaperUrl = null;
    }
    notifyListeners();
    _persist();
    if (ring != null && token != null) {
      Api.updateMe({'avatar_ring': ring}).catchError((_) => <String, dynamic>{});
    }
  }

  void resetCustom() {
    themeStyle = 'default';
    bubbleStyle = 'classic';
    fontFamily = 'Manrope';
    transition = 'slide';
    navStyle = 'glass';
    avatarRing = 'accent';
    iconStyle = 'color';
    liveWallpaper = -1;
    chatFrame = 'none';
    bubbleFrame = 'none';
    chatFrameCustom = const FrameCustom();
    bubbleFrameCustom = const FrameCustom(width: 1.6, glow: 0.3);
    _accent = kAccentPresets.first;
    chatWallpaper = -1;
    shopWallpaperUrl = null;
    nameColor = null;
    notifyListeners();
    _persist();
    if (token != null) {
      Api.updateMe({'avatar_ring': 'accent'}).catchError((_) => <String, dynamic>{});
    }
  }

  /// Непрочитанные (для значка на вкладке «Чаты»).
  final ValueNotifier<int> unreadTotal = ValueNotifier(0);

  // ── Голосовые ──
  double voiceSpeed = 1.0;
  final Set<String> playedVoices = {};
  bool isVoicePlayed(String id) => playedVoices.contains(id);
  void markVoicePlayed(String id) {
    if (playedVoices.add(id)) _persistAccountPrefs();
  }

  void setVoiceSpeed(double v) { voiceSpeed = v; _persist(); }

  // ── Настройки чатов ──
  double messageTextScale = 1.0;
  double bubbleRadius = 18;
  int chatWallpaper = -1;
  // обои из магазина (картинка или видео); если заданы — главнее обычных обоев
  String? shopWallpaperUrl;
  String? shopWallpaperKind;
  String? shopWallpaperId;
  Color? nameColor;
  bool inAppBrowser = true;
  bool animations = true;

  // ── Устройство / данные ──
  bool energySaving = false;       // режим энергосбережения: меньше анимаций и опросов
  bool autoplayVideo = true;
  bool autoDownloadPhotos = true;
  String uploadQuality = 'auto';   // auto | high | economy

  /// Анимации с учётом энергосбережения.
  bool get motion => animations && !energySaving;
  int get imageQuality => switch (uploadQuality) {
        'high' => 95,
        'economy' => 55,
        _ => 80,
      };

  // ── Уведомления (локально) ──
  bool muteAll = false;
  bool notifySound = true;
  bool notifyVibrate = true;
  bool notifyInChat = false;
  // серверные: private/groups/channels/preview/reactions
  Map<String, bool> notify = {
    'private': true, 'groups': true, 'channels': true,
    'preview': true, 'reactions': true,
  };

  // ── Профиль / аккаунт (зеркало сервера) ──
  String? token;
  String? refresh;
  String? myUserId;
  String? currentOpenChatId;
  String userId = '—';
  String username = '';
  String? handle;
  String email = '';
  String displayName = '';
  String lastName = '';
  String phone = '';
  String bio = '';
  String? avatarUrl;
  String lastseenPrivacy = 'all';
  bool isAdmin = false;
  bool isPremium = false;
  DateTime? premiumUntil;
  bool hasCloudPassword = false;
  String? cloudPasswordHint;
  bool readReceipts = true;
  Map<String, String> privacy = {};
  DateTime? birthday;
  bool showId = false;
  bool isVerified = false;
  String? emojiStatus;
  String? coverUrl;
  String? coverKind;
  int coins = 0;
  // ── надетое из магазина (видят все): рамка аватара и анимация профиля {id, url, kind}
  Map<String, dynamic>? wornFrame;
  Map<String, dynamic>? profileFx;
  String? coverItem;

  // ── Устройство и мультиаккаунт ──
  String deviceId = '';
  String platform = 'Android';
  List<Map<String, dynamic>> accounts = [];

  int get accountLimit => isPremium ? kPremiumAccounts : kFreeAccounts;
  int get pinLimit => isPremium ? kPremiumPinned : kFreePinned;

  // ── Код-пароль (блокировка приложения) ──
  String? passcodeHash;
  int autoLockMinutes = 1;         // 0 — сразу, иначе через N минут в фоне
  bool locked = false;
  DateTime? _pausedAt;
  bool get passcodeOn => passcodeHash != null;

  /// Вызывается, когда сервер завершил сеанс (выход на другом устройстве, бан…).
  VoidCallback? onSessionEndedUi;

  // ── загрузка и сохранение ──

  Future<void> loadPrefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      final tm = p.getInt('themeMode');
      if (tm != null && tm >= 0 && tm < ThemeMode.values.length) {
        themeMode = ThemeMode.values[tm];
      }
      final ac = p.getInt('accent');
      if (ac != null) _accent = Color(ac);
      themeStyle = p.getString('themeStyle') ?? themeStyle;
      bubbleStyle = p.getString('bubbleStyle') ?? bubbleStyle;
      fontFamily = p.getString('fontFamily') ?? fontFamily;
      transition = p.getString('transition') ?? transition;
      navStyle = p.getString('navStyle') ?? navStyle;
      avatarRing = p.getString('avatarRing') ?? avatarRing;
      iconStyle = p.getString('iconStyle') ?? iconStyle;
      liveWallpaper = p.getInt('liveWallpaper') ?? liveWallpaper;
      chatFrame = p.getString('chatFrame') ?? chatFrame;
      onboardingDone = p.getBool('onboardingDone') ?? false;
      archiveHidden = p.getBool('archiveHidden') ?? false;
      ghostTyping = p.getBool('ghostTyping') ?? false;
      roundMode = p.getBool('roundMode') ?? false;
      for (final k in kCallPrefDefaults.keys) {
        final v = p.getBool('call_$k');
        if (v != null) _callPrefs[k] = v;
      }
      bubbleFrame = p.getString('bubbleFrame') ?? bubbleFrame;
      try {
        final cf = p.getString('chatFrameCustom');
        if (cf != null) chatFrameCustom = FrameCustom.fromJson(jsonDecode(cf) as Map<String, dynamic>);
        final bf = p.getString('bubbleFrameCustom');
        if (bf != null) bubbleFrameCustom = FrameCustom.fromJson(jsonDecode(bf) as Map<String, dynamic>);
      } catch (_) {}
      voiceSpeed = p.getDouble('voiceSpeed') ?? voiceSpeed;
      messageTextScale = p.getDouble('textScale') ?? messageTextScale;
      bubbleRadius = p.getDouble('bubbleRadius') ?? bubbleRadius;
      chatWallpaper = p.getInt('wallpaper') ?? chatWallpaper;
      shopWallpaperUrl = p.getString('shopWallpaperUrl');
      shopWallpaperKind = p.getString('shopWallpaperKind');
      shopWallpaperId = p.getString('shopWallpaperId');
      final nc = p.getInt('nameColor');
      nameColor = (nc == null || nc == -1) ? null : Color(nc);
      inAppBrowser = p.getBool('inAppBrowser') ?? inAppBrowser;
      animations = p.getBool('animations') ?? animations;
      energySaving = p.getBool('energySaving') ?? energySaving;
      autoplayVideo = p.getBool('autoplayVideo') ?? autoplayVideo;
      autoDownloadPhotos = p.getBool('autoDownloadPhotos') ?? autoDownloadPhotos;
      uploadQuality = p.getString('uploadQuality') ?? uploadQuality;
      showId = p.getBool('showId') ?? showId;
      muteAll = p.getBool('muteAll') ?? muteAll;
      notifySound = p.getBool('notifySound') ?? notifySound;
      notifyVibrate = p.getBool('notifyVibrate') ?? notifyVibrate;
      notifyInChat = p.getBool('notifyInChat') ?? notifyInChat;
      passcodeHash = p.getString('passcode');
      autoLockMinutes = p.getInt('autoLock') ?? autoLockMinutes;
      locked = passcodeHash != null;   // при запуске — всегда заблокировано
      deviceId = p.getString('device_id') ?? '';
      if (deviceId.isEmpty) {
        deviceId =
            'dev_${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}';
        await p.setString('device_id', deviceId);
      }
      platform = _platformName();
      final accJson = p.getString('accounts');
      if (accJson != null) {
        accounts = (jsonDecode(accJson) as List)
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
      }
      // Сохранённый профиль — ДО первого кадра: Premium-цвет, шрифт и тема
      // сразу такие, как у пользователя (без «перекрашивания» после входа).
      final t0 = p.getString('token');
      if (t0 != null) {
        final acc = accounts.where((a) => a['token'] == t0).toList();
        final id = acc.isNotEmpty ? acc.first['id'] as String? : null;
        if (id != null) {
          await _loadCachedProfile(id);
          // Premium мог закончиться, пока приложение было закрыто
          final pu = premiumUntil;
          if (pu != null && pu.isBefore(DateTime.now())) isPremium = false;
        }
      }
    } catch (_) {}
    Api.onTokensRefreshed = _onTokensRefreshed;
    Api.onSessionEnded = _onSessionEnded;
    notifyListeners();
  }

  String _platformName() {
    if (kIsWeb) {
      return switch (defaultTargetPlatform) {
        TargetPlatform.iOS => 'Браузер (iPhone)',
        TargetPlatform.android => 'Браузер (Android)',
        TargetPlatform.macOS => 'Браузер (Mac)',
        _ => 'Браузер (ПК)',
      };
    }
    try {
      if (Platform.isAndroid) return 'Android';
      if (Platform.isIOS) return 'iPhone';
      if (Platform.isWindows) return 'Windows';
      if (Platform.isMacOS) return 'macOS';
      if (Platform.isLinux) return 'Linux';
    } catch (_) {}
    return 'Устройство';
  }

  Future<void> _persist() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt('themeMode', themeMode.index);
      await p.setInt('accent', _accent.toARGB32());
      await p.setString('themeStyle', themeStyle);
      await p.setString('bubbleStyle', bubbleStyle);
      await p.setString('fontFamily', fontFamily);
      await p.setString('transition', transition);
      await p.setString('navStyle', navStyle);
      await p.setString('avatarRing', avatarRing);
      await p.setString('iconStyle', iconStyle);
      await p.setInt('liveWallpaper', liveWallpaper);
      await p.setString('chatFrame', chatFrame);
      await p.setString('bubbleFrame', bubbleFrame);
      await p.setString('chatFrameCustom', jsonEncode(chatFrameCustom.toJson()));
      await p.setString('bubbleFrameCustom', jsonEncode(bubbleFrameCustom.toJson()));
      await p.setDouble('voiceSpeed', voiceSpeed);
      await p.setDouble('textScale', messageTextScale);
      await p.setDouble('bubbleRadius', bubbleRadius);
      await p.setInt('wallpaper', chatWallpaper);
      if (shopWallpaperUrl == null) {
        await p.remove('shopWallpaperUrl');
        await p.remove('shopWallpaperKind');
        await p.remove('shopWallpaperId');
      } else {
        await p.setString('shopWallpaperUrl', shopWallpaperUrl!);
        await p.setString('shopWallpaperKind', shopWallpaperKind ?? 'image');
        await p.setString('shopWallpaperId', shopWallpaperId ?? '');
      }
      await p.setInt('nameColor', nameColor?.toARGB32() ?? -1);
      await p.setBool('inAppBrowser', inAppBrowser);
      await p.setBool('animations', animations);
      await p.setBool('energySaving', energySaving);
      await p.setBool('autoplayVideo', autoplayVideo);
      await p.setBool('autoDownloadPhotos', autoDownloadPhotos);
      await p.setString('uploadQuality', uploadQuality);
      await p.setBool('showId', showId);
      await p.setBool('muteAll', muteAll);
      await p.setBool('notifySound', notifySound);
      await p.setBool('notifyVibrate', notifyVibrate);
      await p.setBool('notifyInChat', notifyInChat);
      await p.setInt('autoLock', autoLockMinutes);
      if (passcodeHash == null) {
        await p.remove('passcode');
      } else {
        await p.setString('passcode', passcodeHash!);
      }
    } catch (_) {}
  }

  // ── настройки на аккаунт (архив, закрепы, скрытые, звук) ──

  String _k(String name) => 'acc_${myUserId ?? 'none'}_$name';

  Future<void> _loadAccountPrefs() async {
    archivedChats.clear();
    pinnedChats.clear();
    hiddenMessages.clear();
    mutedUntil.clear();
    playedVoices.clear();
    revealedGifts.clear();
    try {
      final p = await SharedPreferences.getInstance();
      archivedChats.addAll(p.getStringList(_k('archived')) ??
          p.getStringList('archivedChats') ?? const []);
      pinnedChats.addAll(p.getStringList(_k('pinned')) ?? const []);
      playedVoices.addAll(p.getStringList(_k('voices')) ?? const []);
      revealedGifts.addAll(p.getStringList(_k('gifts_seen')) ?? const []);
      hiddenMessages.addAll(p.getStringList(_k('hidden')) ??
          p.getStringList('hiddenMessages') ?? const []);
      for (final s in (p.getStringList(_k('muted')) ??
          p.getStringList('mutedUntil') ?? const [])) {
        final i = s.lastIndexOf(':');
        if (i > 0) {
          final v = int.tryParse(s.substring(i + 1));
          if (v != null) mutedUntil[s.substring(0, i)] = v;
        }
      }
    } catch (_) {}
  }

  Future<void> _persistAccountPrefs() async {
    if (myUserId == null) return;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setStringList(_k('archived'), archivedChats.toList());
      await p.setStringList(_k('pinned'), pinnedChats);
      final pv = playedVoices.toList();
      await p.setStringList(_k('voices'), pv.length > 3000 ? pv.sublist(pv.length - 3000) : pv);
      await p.setStringList(_k('hidden'), hiddenMessages.toList());
      final rg = revealedGifts.toList();
      await p.setStringList(_k('gifts_seen'), rg.length > 500 ? rg.sublist(rg.length - 500) : rg);
      await p.setStringList(_k('muted'),
          mutedUntil.entries.map((e) => '${e.key}:${e.value}').toList());
    } catch (_) {}
  }

  // ── пользователь ──

  void _applyUser(Map<String, dynamic> u) {
    myUserId = u['id'] as String?;
    userId = u['id'] as String? ?? '—';
    username = u['username'] as String? ?? username;
    handle = u['handle'] as String?;
    email = u['email'] as String? ?? email;
    final dn = u['display_name'] as String?;
    displayName = (dn != null && dn.isNotEmpty) ? dn : username;
    lastName = u['last_name'] as String? ?? '';
    phone = u['phone'] as String? ?? '';
    bio = u['bio'] as String? ?? '';
    avatarUrl = u['avatar_url'] as String?;
    lastseenPrivacy = u['lastseen_privacy'] as String? ?? 'all';
    isAdmin = u['is_admin'] == true;
    isPremium = u['is_premium'] == true;
    final pu = u['premium_until'] as String?;
    premiumUntil = pu != null ? parseServerTime(pu) : null;
    hasCloudPassword = u['has_cloud_password'] == true;
    cloudPasswordHint = u['cloud_password_hint'] as String?;
    if (u.containsKey('read_receipts')) readReceipts = u['read_receipts'] != false;
    final pv = u['privacy'];
    if (pv is Map) {
      privacy = pv.map((k, v) => MapEntry(k.toString(), v.toString()));
    }
    final nt = u['notify'];
    if (nt is Map) {
      notify = nt.map((k, v) => MapEntry(k.toString(), v == true));
    }
    isVerified = u['is_verified'] == true;
    emojiStatus = u['emoji_status'] as String?;
    coverUrl = u['cover_url'] as String?;
    coverKind = u['cover_kind'] as String?;
    if (u['coins'] is num) coins = (u['coins'] as num).toInt();
    wornFrame = (u['frame'] is Map) ? (u['frame'] as Map).cast<String, dynamic>() : null;
    profileFx =
        (u['profile_fx'] is Map) ? (u['profile_fx'] as Map).cast<String, dynamic>() : null;
    coverItem = u['cover_item'] as String?;
    // рамка аватара хранится на сервере — её видят все
    final ring = u['avatar_ring'] as String?;
    if (ring != null && ring.isNotEmpty) avatarRing = ring;
    final b = u['birthday'] as String?;
    birthday = (b != null && b.isNotEmpty) ? DateTime.tryParse(b) : null;
    Cache.scope = myUserId ?? '';
  }

  Map<String, dynamic> _userSnapshot() => {
        'id': myUserId, 'username': username, 'handle': handle,
        'email': email, 'display_name': displayName, 'last_name': lastName,
        'phone': phone, 'bio': bio, 'avatar_url': avatarUrl,
        'lastseen_privacy': lastseenPrivacy, 'is_admin': isAdmin,
        'is_premium': isPremium,
        'premium_until': premiumUntil?.toUtc().toIso8601String(),
        'has_cloud_password': hasCloudPassword,
        'cloud_password_hint': cloudPasswordHint,
        'read_receipts': readReceipts, 'privacy': privacy, 'notify': notify,
        'birthday': birthday?.toIso8601String(),
        'is_verified': isVerified, 'emoji_status': emojiStatus,
        'cover_url': coverUrl, 'cover_kind': coverKind, 'coins': coins,
        'frame': wornFrame, 'profile_fx': profileFx, 'cover_item': coverItem,
      };

  Future<void> _cacheProfile() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_k('profile'), jsonEncode(_userSnapshot()));
    } catch (_) {}
  }

  Future<bool> _loadCachedProfile(String? id) async {
    try {
      final p = await SharedPreferences.getInstance();
      final s = p.getString('acc_${id ?? 'none'}_profile') ?? p.getString('cache_user');
      if (s != null) {
        _applyUser((jsonDecode(s) as Map).cast<String, dynamic>());
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Обновить локальные поля из свежего ответа сервера.
  void applyServerUser(Map<String, dynamic> u) {
    _applyUser(u);
    // рамка выбрана до того, как её стали хранить на сервере — отправим один раз
    if (u.containsKey('avatar_ring') && u['avatar_ring'] == null && avatarRing != 'accent') {
      Api.updateMe({'avatar_ring': avatarRing}).catchError((_) => <String, dynamic>{});
    }
    _cacheProfile();
    _upsertAccount();
    if (coverUrl != null && coverUrl!.isNotEmpty && !kIsWeb) {
      final full = coverUrl!.startsWith('http') ? coverUrl! : '$kBaseUrl$coverUrl';
      MediaCache.file(full).catchError((_) => null);
    }
    notifyListeners();
    // Premium закончился — премиум-иконку приложения меняем на обычную
    if (!isPremium) LauncherIcon.enforcePremium();
  }

  Future<void> refreshMe() async {
    try {
      applyServerUser(await Api.me());
    } catch (_) {}
  }

  // ── вход / выход / аккаунты ──

  Future<void> _saveTokens() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (token == null) {
        await p.remove('token');
        await p.remove('refresh');
      } else {
        await p.setString('token', token!);
        if (refresh != null) await p.setString('refresh', refresh!);
      }
    } catch (_) {}
  }

  void _onTokensRefreshed(String access, String rt) {
    token = access;
    refresh = rt;
    _saveTokens();
    _upsertAccount();
  }

  bool _endingSession = false;

  void _onSessionEnded() {
    if (_endingSession || token == null) return;
    _endingSession = true;
    final dead = myUserId;
    Future(() async {
      accounts.removeWhere((a) => a['id'] == dead);
      await _persistAccounts();
      await _clearCurrent();
      _endingSession = false;
      onSessionEndedUi?.call();
    });
  }

  /// tok — access, refresh — refresh-токен, user — профиль с сервера.
  Future<void> saveAuth(String tok, Map<String, dynamic> user,
      {String? refreshToken}) async {
    token = tok;
    refresh = refreshToken ?? refresh;
    Api.token = tok;
    Api.refreshToken = refresh;
    _applyUser(user);
    await _loadAccountPrefs();
    await _saveTokens();
    await _upsertAccount();
    _cacheProfile();
    Realtime.disconnect();
    Realtime.connect();
    Push.register();
    notifyListeners();
  }

  /// Удобный вход из ответа сервера {access_token, refresh_token, user}.
  Future<void> saveAuthResponse(Map<String, dynamic> r) => saveAuth(
      r['access_token'] as String,
      (r['user'] as Map).cast<String, dynamic>(),
      refreshToken: r['refresh_token'] as String?);

  /// true — вошли (возможно офлайн), false — нужен экран входа.
  Future<bool> tryAutoLogin() async {
    String? t;
    String? rt;
    try {
      final p = await SharedPreferences.getInstance();
      t = p.getString('token');
      rt = p.getString('refresh');
    } catch (_) {}
    if (t == null) return false;
    token = t;
    refresh = rt;
    Api.token = t;
    Api.refreshToken = rt;
    // id текущего аккаунта — из списка аккаунтов по токену
    final acc = accounts.where((a) => a['token'] == t).toList();
    final knownId = acc.isNotEmpty ? acc.first['id'] as String? : null;
    try {
      if (rt == null) {
        // старый токен (до обновления) → получить сеанс и refresh
        final up = await Api.upgradeSession(deviceId, platform);
        token = up['access_token'] as String;
        refresh = up['refresh_token'] as String?;
        Api.token = token;
        Api.refreshToken = refresh;
        _applyUser((up['user'] as Map).cast<String, dynamic>());
      } else {
        await Api.refreshNow();
        _applyUser(await Api.me());
      }
      await _loadAccountPrefs();
      await _saveTokens();
      await _upsertAccount();
      _cacheProfile();
      Push.register();
    } catch (e) {
      if (e is ApiException && (e.status == 401 || e.status == 403)) {
        // сеанс завершён или аккаунт заблокирован
        accounts.removeWhere((a) => a['token'] == t);
        await _persistAccounts();
        await _clearCurrent();
        return false;
      }
      // нет сети — входим офлайн по кэшу
      if (!await _loadCachedProfile(knownId)) {
        if (knownId != null) myUserId = knownId;
      }
      await _loadAccountPrefs();
    }
    Realtime.connect();
    notifyListeners();
    return true;
  }

  Future<void> _persistAccounts() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('accounts', jsonEncode(accounts));
    } catch (_) {}
  }

  Future<void> _upsertAccount() async {
    if (myUserId == null || token == null) return;
    final idx = accounts.indexWhere((a) => a['id'] == myUserId);
    final entry = <String, dynamic>{
      'id': myUserId,
      'token': token,
      'refresh': refresh,
      'username': username,
      'display_name': displayName,
      'avatar_url': avatarUrl,
      'email': email,
      'is_premium': isPremium,
    };
    if (idx >= 0) {
      accounts[idx] = entry;
    } else {
      accounts.insert(0, entry);
    }
    await _persistAccounts();
  }

  /// Можно ли добавить ещё один аккаунт.
  bool get canAddAccount => accounts.length < accountLimit;

  /// Переключиться на сохранённый аккаунт. Возвращает текст ошибки или null.
  Future<String?> switchAccount(Map<String, dynamic> acc) async {
    final tok = acc['token'] as String?;
    if (tok == null || acc['id'] == myUserId) return null;
    final prevToken = token, prevRefresh = refresh;
    token = tok;
    refresh = acc['refresh'] as String?;
    Api.token = token;
    Api.refreshToken = refresh;
    Realtime.disconnect();
    try {
      if (refresh != null) await Api.refreshNow();
      _applyUser(await Api.me());
      await _loadAccountPrefs();
      await _saveTokens();
      await _upsertAccount();
      _cacheProfile();
      Push.register();
    } catch (e) {
      if (e is ApiException && e.status == 401) {
        // этот аккаунт вышел — убираем и возвращаемся назад
        accounts.removeWhere((a) => a['id'] == acc['id']);
        await _persistAccounts();
        token = prevToken;
        refresh = prevRefresh;
        Api.token = token;
        Api.refreshToken = refresh;
        Realtime.connect();
        notifyListeners();
        return 'Сеанс этого аккаунта завершён — войди в него заново';
      }
      // офлайн — показываем сохранённое
      myUserId = acc['id'] as String?;
      await _loadCachedProfile(myUserId);
      await _loadAccountPrefs();
      await _saveTokens();
    }
    Realtime.connect();
    notifyListeners();
    return null;
  }

  Future<void> removeAccount(String id) async {
    accounts.removeWhere((a) => a['id'] == id);
    await _persistAccounts();
    notifyListeners();
  }

  Future<void> _clearCurrent() async {
    token = null;
    refresh = null;
    Api.token = null;
    Api.refreshToken = null;
    myUserId = null;
    isAdmin = false;
    isPremium = false;
    Realtime.disconnect();
    await _saveTokens();
    notifyListeners();
  }

  /// Выйти из текущего аккаунта. true — переключились на другой сохранённый.
  Future<bool> logout() async {
    await Push.unregister();
    await Api.logoutServer();
    final me = myUserId;
    accounts.removeWhere((a) => a['id'] == me);
    await _persistAccounts();
    await _clearCurrent();
    if (accounts.isNotEmpty) {
      final err = await switchAccount(accounts.first);
      if (err == null && token != null) return true;
    }
    return false;
  }

  void setHandleLocal(String? h) { handle = h; notifyListeners(); }

  // ── приватность и уведомления (сервер) ──

  String privacyOf(String key) =>
      key == 'lastseen' ? lastseenPrivacy : (privacy[key] ?? 'all');

  Future<void> setPrivacyValue(String key, String value) async {
    final u = await Api.setPrivacy(values: {key: value});
    applyServerUser(u);
  }

  Future<void> setReadReceipts(bool v) async {
    readReceipts = v;
    notifyListeners();
    final u = await Api.setPrivacy(readReceipts: v);
    applyServerUser(u);
  }

  Future<void> setNotifyServer(String key, bool v) async {
    notify[key] = v;
    notifyListeners();
    try {
      final d = await Api.setNotify({key: v});
      notify = d.map((k, val) => MapEntry(k, val == true));
      notifyListeners();
    } catch (_) {}
  }

  void setLocalNotify({bool? sound, bool? vibrate, bool? inChat}) {
    if (sound != null) notifySound = sound;
    if (vibrate != null) notifyVibrate = vibrate;
    if (inChat != null) notifyInChat = inChat;
    notifyListeners();
    _persist();
  }

  void setMuteAll(bool v) { muteAll = v; notifyListeners(); _persist(); }

  // ── звук чатов (синхронизируется с сервером — для пушей) ──
  final Map<String, int> mutedUntil = {};   // 0 = навсегда (локально)

  bool isMuted(String chatId) {
    if (!mutedUntil.containsKey(chatId)) return false;
    final until = mutedUntil[chatId]!;
    if (until == 0) return true;
    if (DateTime.now().millisecondsSinceEpoch < until) return true;
    mutedUntil.remove(chatId);
    _persistAccountPrefs();
    return false;
  }

  void muteFor(String chatId, Duration? dur) {
    final until = dur == null ? 0 : DateTime.now().add(dur).millisecondsSinceEpoch;
    mutedUntil[chatId] = until;
    notifyListeners();
    _persistAccountPrefs();
    Api.setMute(chatId, until == 0 ? -1 : until);
  }

  void unmute(String chatId) {
    mutedUntil.remove(chatId);
    notifyListeners();
    _persistAccountPrefs();
    Api.setMute(chatId, 0);
  }

  void toggleMute(String chatId) {
    if (isMuted(chatId)) {
      unmute(chatId);
    } else {
      muteFor(chatId, null);
    }
  }

  /// Подтянуть заглушённые чаты с сервера (синхронизация между устройствами).
  void syncMutes(List<dynamic> chats) {
    var changed = false;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final raw in chats) {
      final c = raw as Map<String, dynamic>;
      final id = c['id'] as String?;
      if (id == null) continue;
      final srv = (c['muted_until'] as num?)?.toInt() ?? 0;
      final local = srv == -1 ? 0 : (srv > now ? srv : null);
      if (local == null) {
        if (mutedUntil.remove(id) != null) changed = true;
      } else if (mutedUntil[id] != local) {
        mutedUntil[id] = local;
        changed = true;
      }
    }
    if (changed) {
      _persistAccountPrefs();
      notifyListeners();
    }
  }

  // ── подарки: какие уже показали на весь экран (показываем при входе в чат) ──
  final Set<String> revealedGifts = {};
  bool isGiftRevealed(String msgId) => revealedGifts.contains(msgId);
  void markGiftRevealed(String msgId) {
    if (revealedGifts.add(msgId)) _persistAccountPrefs();
  }

  // ── «Невидимка» (Premium): не показывать собеседникам «печатает…» ──
  bool ghostTyping = false;
  Future<void> setGhostTyping(bool v) async {
    ghostTyping = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('ghostTyping', v);
    } catch (_) {}
  }

  // ── звонки: настройки на этом устройстве ──
  final Map<String, bool> _callPrefs = Map.of(kCallPrefDefaults);
  bool callPref(String key) => _callPrefs[key] ?? kCallPrefDefaults[key] ?? false;
  Future<void> setCallPref(String key, bool v) async {
    _callPrefs[key] = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('call_$key', v);
    } catch (_) {}
  }

  // ── кнопка записи: голосовое или видеосообщение (запоминаем, как в Telegram) ──
  bool roundMode = false;
  Future<void> setRoundMode(bool v) async {
    roundMode = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('roundMode', v);
    } catch (_) {}
  }

  // ── архив можно спрятать: открывается долгим нажатием на заголовок «Connecto» ──
  bool archiveHidden = false;
  Future<void> setArchiveHidden(bool v) async {
    archiveHidden = v;
    notifyListeners();
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('archiveHidden', v);
    } catch (_) {}
  }

  // ── онбординг (один раз на устройстве) ──
  bool onboardingDone = false;
  Future<void> setOnboardingDone() async {
    onboardingDone = true;
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('onboardingDone', true);
    } catch (_) {}
  }

  // ── скрытые сообщения («удалить у себя») ──
  final Set<String> hiddenMessages = {};
  bool isMsgHidden(String id) => hiddenMessages.contains(id);
  void hideMessage(String id) {
    hiddenMessages.add(id);
    notifyListeners();
    _persistAccountPrefs();
  }

  // ── архив ──
  final Set<String> archivedChats = {};
  bool isArchived(String chatId) => archivedChats.contains(chatId);
  void setArchived(String chatId, bool v) {
    if (v) {
      archivedChats.add(chatId);
      pinnedChats.remove(chatId);
    } else {
      archivedChats.remove(chatId);
    }
    notifyListeners();
    _persistAccountPrefs();
  }

  // ── закреплённые чаты ──
  final List<String> pinnedChats = [];
  bool isPinned(String chatId) => pinnedChats.contains(chatId);

  /// false — упёрлись в лимит.
  bool togglePin(String chatId) {
    if (pinnedChats.contains(chatId)) {
      pinnedChats.remove(chatId);
    } else {
      if (pinnedChats.length >= pinLimit) return false;
      pinnedChats.insert(0, chatId);
      archivedChats.remove(chatId);
    }
    notifyListeners();
    _persistAccountPrefs();
    return true;
  }

  // ── оформление чатов ──
  void setNameColor(Color? c) { nameColor = c; notifyListeners(); _persist(); }
  void setWallpaper(int i) {
    chatWallpaper = i;
    shopWallpaperUrl = null;
    shopWallpaperKind = null;
    shopWallpaperId = null;
    notifyListeners();
    _persist();
  }

  /// Обои из магазина; null — снять.
  void setShopWallpaper(String? id, String? url, String? kind) {
    shopWallpaperId = id;
    shopWallpaperUrl = url;
    shopWallpaperKind = kind;
    if (url != null) liveWallpaper = -1;
    notifyListeners();
    _persist();
  }

  /// Обои с учётом Premium: премиум-обои без подписки не показываются.
  int get chatWallpaperEff {
    final w = chatWallpaper;
    final img = imageWallpaperOf(w);
    if (img != null) return (img.premium && !isPremium) ? -1 : w;
    if (w >= kFreeWallpapers && w < kWallpapers.length && !isPremium) return -1;
    return w;
  }

  void setChatSettings({double? textScale, double? bubbleRadius,
      bool? inAppBrowser, bool? animations}) {
    if (textScale != null) messageTextScale = textScale;
    if (bubbleRadius != null) this.bubbleRadius = bubbleRadius;
    if (inAppBrowser != null) this.inAppBrowser = inAppBrowser;
    if (animations != null) this.animations = animations;
    notifyListeners();
    _persist();
  }

  void setDeviceSettings({bool? energySaving, bool? autoplayVideo,
      bool? autoDownloadPhotos, String? uploadQuality}) {
    if (energySaving != null) this.energySaving = energySaving;
    if (autoplayVideo != null) this.autoplayVideo = autoplayVideo;
    if (autoDownloadPhotos != null) this.autoDownloadPhotos = autoDownloadPhotos;
    if (uploadQuality != null) this.uploadQuality = uploadQuality;
    notifyListeners();
    _persist();
  }

  // ── показывать ID (локально) ──
  void setPrivacy({bool? showId}) {
    if (showId != null) this.showId = showId;
    notifyListeners();
    _persist();
  }

  // ── код-пароль ──

  static String _hashPin(String pin) {
    // FNV-1a 64 × 2000 итераций с солью — для локальной блокировки достаточно
    var h = BigInt.parse('cbf29ce484222325', radix: 16);
    final prime = BigInt.parse('100000001b3', radix: 16);
    final mask = (BigInt.one << 64) - BigInt.one;
    final data = utf8.encode('connecto-lock:$pin');
    for (var round = 0; round < 2000; round++) {
      for (final b in data) {
        h = ((h ^ BigInt.from(b)) * prime) & mask;
      }
      h = (h ^ BigInt.from(round)) & mask;
    }
    return h.toRadixString(16);
  }

  void setPasscode(String pin) {
    passcodeHash = _hashPin(pin);
    locked = false;
    notifyListeners();
    _persist();
  }

  void clearPasscode() {
    passcodeHash = null;
    locked = false;
    notifyListeners();
    _persist();
  }

  bool checkPasscode(String pin) => passcodeHash != null && _hashPin(pin) == passcodeHash;

  void unlock(String pin) {
    if (checkPasscode(pin)) {
      locked = false;
      notifyListeners();
    }
  }

  void setAutoLock(int minutes) {
    autoLockMinutes = minutes;
    notifyListeners();
    _persist();
  }

  void lockNow() {
    if (passcodeOn) {
      locked = true;
      notifyListeners();
    }
  }

  void onPaused() => _pausedAt ??= DateTime.now();

  void onResumed() {
    final at = _pausedAt;
    _pausedAt = null;
    if (!passcodeOn || at == null || locked) return;
    if (DateTime.now().difference(at).inMinutes >= autoLockMinutes) {
      locked = true;
      notifyListeners();
    }
  }
}

final appState = AppState();
