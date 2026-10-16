import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'e2e.dart';
import 'io/local_files.dart';
import 'notifications.dart';

/// Время с сервера → местное. Строка без пояса («2026-09-30T10:00:00») — это UTC
/// (старый сервер и кэш так отдавали), иначе время съезжало на 3 часа.
DateTime? parseServerTime(String? iso) {
  if (iso == null || iso.isEmpty) return null;
  var s = iso.trim();
  if (s.contains('T') && !RegExp(r'(Z|[+-]\d\d:?\d\d)$').hasMatch(s)) s = '${s}Z';
  return DateTime.tryParse(s)?.toLocal();
}

/// Адрес сервера для приложений (телефон, компьютер). Защищенный HTTPS.
const String kServerUrl = 'https://connectomes.duckdns.org/api';

/// Для отладки веба: flutter run -d chrome --dart-define=API_URL=https://сайт/api
const String _apiOverride = String.fromEnvironment('API_URL');

/// Адрес API. Веб-версия живёт на том же сайте (https://…/api) — так браузер не
/// ругается на «небезопасное» содержимое и работают микрофон и камера.
String get kBaseUrl {
  if (_apiOverride.isNotEmpty) return _apiOverride;
  if (kIsWeb) return '${Uri.base.origin}/api';
  return kServerUrl;
}

String get kWsUrl {
  final base = kBaseUrl;
  final ws = base.startsWith('https://')
      ? 'wss://${base.substring(8)}'
      : 'ws://${base.replaceFirst(RegExp(r'^http://'), '')}';
  return '$ws/ws';
}

/// Номер сборки этого приложения. build_all.ps1 передаёт его из pubspec.yaml
/// (version: 1.3.0+11 → 11) через --dart-define=APP_BUILD, руками менять не нужно.
const int kAppBuild = int.fromEnvironment('APP_BUILD', defaultValue: 16);

class ApiException implements Exception {
  final String message;
  final int status;
  ApiException(this.message, [this.status = 0]);
  bool get isAuth => status == 401;
  @override
  String toString() => message;
}

/// Понятный текст ошибки для пользователя.
String friendlyError(Object e) {
  if (e is ApiException) return e.message;
  if (e is SocketException || e is http.ClientException) {
    return 'Нет соединения с сервером';
  }
  if (e is TimeoutException) return 'Сервер долго не отвечает, попробуй ещё раз';
  return 'Что-то пошло не так';
}

class Api {
  static final http.Client _client = http.Client();
  static http.Client get client => _client;

  static String? token;
  static String? refreshToken;

  /// AppState подписывается: сохранить новые токены / сеанс завершён.
  static void Function(String access, String refresh)? onTokensRefreshed;
  static void Function()? onSessionEnded;

  static Future<bool>? _refreshing;

  static Map<String, String> _headers({bool auth = false}) {
    final h = {'Content-Type': 'application/json'};
    if (auth && token != null) h['Authorization'] = 'Bearer $token';
    return h;
  }

  static dynamic _json(http.Response r) {
    if (r.bodyBytes.isEmpty) return null;
    return jsonDecode(utf8.decode(r.bodyBytes));
  }

  static Future<http.Response> _raw(String method, String path,
      {Object? body,
      Map<String, String>? query,
      bool auth = true,
      Duration timeout = const Duration(seconds: 20)}) async {
    var uri = Uri.parse('$kBaseUrl$path');
    if (query != null) uri = uri.replace(queryParameters: query);
    Future<http.Response> go() {
      final h = _headers(auth: auth);
      final b = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'POST':
          return _client.post(uri, headers: h, body: b).timeout(timeout);
        case 'PUT':
          return _client.put(uri, headers: h, body: b).timeout(timeout);
        case 'PATCH':
          return _client.patch(uri, headers: h, body: b).timeout(timeout);
        case 'DELETE':
          return _client.delete(uri, headers: h, body: b).timeout(timeout);
        default:
          return _client.get(uri, headers: h).timeout(timeout);
      }
    }

    var r = await go();
    if (r.statusCode == 401 && auth && token != null) {
      if (await _tryRefresh()) {
        r = await go();
      }
      if (r.statusCode == 401) onSessionEnded?.call();
    }
    return r;
  }

  /// Запрос с разбором JSON. ok — допустимые коды ответа.
  static Future<dynamic> _call(String method, String path,
      {Object? body,
      Map<String, String>? query,
      bool auth = true,
      List<int> ok = const [200, 201, 204],
      Duration timeout = const Duration(seconds: 20)}) async {
    final r = await _raw(method, path,
        body: body, query: query, auth: auth, timeout: timeout);
    if (ok.contains(r.statusCode)) return _json(r);
    throw ApiException(_err(r), r.statusCode);
  }

  static Future<bool> _tryRefresh() {
    final rt = refreshToken;
    if (rt == null) return Future.value(false);
    final pending = _refreshing;
    if (pending != null) return pending;
    final f = (() async {
      try {
        final r = await _client
            .post(Uri.parse('$kBaseUrl/auth/refresh'),
                headers: _headers(), body: jsonEncode({'refresh_token': rt}))
            .timeout(const Duration(seconds: 15));
        if (r.statusCode != 200) return false;
        final d = _json(r) as Map<String, dynamic>;
        token = d['access_token'] as String;
        refreshToken = d['refresh_token'] as String? ?? rt;
        onTokensRefreshed?.call(token!, refreshToken!);
        return true;
      } catch (_) {
        return false;
      } finally {
        _refreshing = null;
      }
    })();
    _refreshing = f;
    return f;
  }

  /// Обновить токены заранее (при старте). true — сеанс жив.
  static Future<bool> refreshNow() => _tryRefresh();

  static Map<String, dynamic> _map(dynamic v) =>
      (v as Map).cast<String, dynamic>();
  static List<dynamic> _list(dynamic v) => (v as List?) ?? const [];

  // ── вход и регистрация ──

  /// Регистрация. Возвращает {access_token, refresh_token, user} — сразу вход.
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    required String displayName,
    String? code,
    String? deviceId,
    String? platform,
  }) async =>
      _map(await _call('POST', '/auth/register', auth: false, body: {
        'username': username,
        'email': email,
        'password': password,
        'display_name': displayName,
        if (code != null) 'code': code,
        'device_id': deviceId,
        'platform': platform,
      }));

  /// Шаг 1 регистрации: проверка логина/почты и код на почту.
  /// {sent, required, email_masked}. required=false — сервер без почты, код не нужен.
  static Future<Map<String, dynamic>> registerCode(String email, String username) async =>
      _map(await _call('POST', '/auth/register/code',
          auth: false, body: {'email': email, 'username': username}));

  /// Шаг 1 входа: {access_token,...} | {needs_code} | {needs_password, ticket, hint}.
  static Future<Map<String, dynamic>> login({
    required String login,
    required String password,
    String? deviceId,
    String? platform,
  }) async =>
      _map(await _call('POST', '/auth/login', auth: false, body: {
        'login': login,
        'password': password,
        'device_id': deviceId,
        'platform': platform,
      }));

  /// Шаг 2 — код с почты.
  static Future<Map<String, dynamic>> loginVerify({
    required String login,
    required String password,
    required String code,
    String? deviceId,
    String? platform,
  }) async =>
      _map(await _call('POST', '/auth/login/verify', auth: false, body: {
        'login': login,
        'password': password,
        'code': code,
        'device_id': deviceId,
        'platform': platform,
      }));

  /// Отправить код на почту (по запросу с экрана подтверждения)
  static Future<Map<String, dynamic>> loginSendEmail({
    required String login,
    required String password,
    String? deviceId,
    String? platform,
  }) async =>
      _map(await _call('POST', '/auth/login/send-email', auth: false, body: {
        'login': login,
        'password': password,
        'device_id': deviceId,
        'platform': platform,
      }));

  /// Войти с помощью облачного пароля в обход одноразового кода
  static Future<Map<String, dynamic>> loginWithCloudPassword({
    required String login,
    required String password,
    required String cloudPassword,
    String? deviceId,
    String? platform,
  }) async =>
      _map(await _call('POST', '/auth/login/cloud-password', auth: false, body: {
        'login': login,
        'password': password,
        'cloud_password': cloudPassword,
        'device_id': deviceId,
        'platform': platform,
      }));

  /// Шаг 3 — облачный пароль.
  static Future<Map<String, dynamic>> login2fa(
          String ticket, String password) async =>
      _map(await _call('POST', '/auth/login/2fa',
          auth: false, body: {'ticket': ticket, 'password': password}));

  static Future<Map<String, dynamic>> login2faForgot(String ticket) async =>
      _map(await _call('POST', '/auth/login/2fa/forgot',
          auth: false, body: {'ticket': ticket}));

  static Future<Map<String, dynamic>> login2faReset(
          String ticket, String code) async =>
      _map(await _call('POST', '/auth/login/2fa/reset',
          auth: false, body: {'ticket': ticket, 'code': code}));

  static Future<void> passwordForgot(String email) async =>
      _call('POST', '/auth/password/forgot', auth: false, body: {'email': email});

  static Future<void> passwordReset(
          String email, String code, String newPassword) async =>
      _call('POST', '/auth/password/reset', auth: false, body: {
        'email': email,
        'code': code,
        'new_password': newPassword,
      });

  /// Старый токен без сеанса → получить сеанс и refresh-токен.
  static Future<Map<String, dynamic>> upgradeSession(
          String deviceId, String platform) async =>
      _map(await _call('POST', '/auth/session',
          body: {'device_id': deviceId, 'platform': platform}));

  static Future<void> logoutServer() async {
    try {
      await _raw('POST', '/auth/logout', timeout: const Duration(seconds: 6));
    } catch (_) {}
  }

  static Future<List<dynamic>> loginEvents() async =>
      _list(await _call('GET', '/auth/login_events'));

  // ── служебное ──

  static Future<void> registerPushToken(String t) async {
    try {
      await _raw('POST', '/push/token', body: {'token': t});
    } catch (_) {}
  }

  static Future<void> dropPushToken(String t) async {
    try {
      await _raw('DELETE', '/push/token', body: {'token': t});
    } catch (_) {}
  }

  /// Проверка обновлений. Возвращает данные, если на сервере сборка новее.
  static Future<Map<String, dynamic>?> checkUpdate() async {
    if (kIsWeb) return null; // сайт обновляется сам
    try {
      final r = await http
          .get(Uri.parse('$kBaseUrl/app_version'))
          .timeout(const Duration(seconds: 6));
      if (r.statusCode != 200) return null;
      var d = _map(_json(r));
      if (Platform.isWindows) {
        // у Windows-версии свой блок в app_version.json: {"windows": {build, version, url, notes}}
        final w = d['windows'];
        if (w is! Map) return null;
        d = w.cast<String, dynamic>();
        d['url_direct'] = d['url'] ?? d['url_direct'];
      }
      final build = (d['build'] as num?)?.toInt() ?? 0;
      return build > kAppBuild ? d : null;
    } catch (_) {
      return null;
    }
  }

  static Future<bool> ping() async {
    try {
      final r = await http
          .get(Uri.parse('$kBaseUrl/'))
          .timeout(const Duration(seconds: 6));
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ── я ──

  static Future<Map<String, dynamic>> me() async =>
      _map(await _call('GET', '/me'));

  static Future<Map<String, dynamic>> updateMe(Map<String, dynamic> data) async =>
      _map(await _call('PATCH', '/me', body: data));

  static Future<Map<String, dynamic>> setPrivacy(
          {Map<String, String>? values, bool? readReceipts}) async =>
      _map(await _call('PUT', '/me/privacy', body: {
        'values': values ?? <String, String>{},
        if (readReceipts != null) 'read_receipts': readReceipts,
      }));

  static Future<Map<String, dynamic>> setNotify(Map<String, bool> data) async =>
      _map(await _call('PUT', '/me/notify', body: data));

  /// Смена почты, шаг 1: {sent, email_masked} или {changed, user} (если почта не настроена).
  static Future<Map<String, dynamic>> changeEmailStart(String newEmail, String password) async =>
      _map(await _call('POST', '/me/email',
          body: {'new_email': newEmail, 'password': password}));

  static Future<Map<String, dynamic>> changeEmailConfirm(String newEmail, String code) async =>
      _map(await _call('POST', '/me/email/confirm',
          body: {'new_email': newEmail, 'code': code}));

  static Future<void> changePassword(String oldPw, String newPw) async =>
      _call('POST', '/me/password',
          body: {'old_password': oldPw, 'new_password': newPw});

  /// new == null → выключить облачный пароль.
  static Future<Map<String, dynamic>> setCloudPassword(
          {String? current, String? newPassword, String? hint}) async =>
      _map(await _call('PUT', '/me/cloud_password', body: {
        'current': current,
        'new': newPassword,
        'hint': hint,
      }));

  static Future<List<dynamic>> sessions() async =>
      _list(await _call('GET', '/sessions'));

  static Future<void> terminateSession(String id) async =>
      _call('DELETE', '/sessions/$id');

  static Future<void> terminateOtherSessions() async =>
      _call('DELETE', '/sessions');

  static Future<void> deleteMe() async => _call('DELETE', '/me');

  static Future<Map<String, dynamic>> setHandle(String handle) async =>
      _map(await _call('POST', '/users/handle', body: {'handle': handle}));

  // ── люди ──

  static Future<List<dynamic>> searchUsers(String q) async =>
      _list(await _call('GET', '/users/search', query: {'q': q}));

  static Future<Map<String, dynamic>> userProfile(String userId) async =>
      _map(await _call('GET', '/users/$userId'));

  static Future<void> blockUser(String userId) async =>
      _call('POST', '/users/$userId/block');

  static Future<void> unblockUser(String userId) async =>
      _call('DELETE', '/users/$userId/block');

  static Future<List<dynamic>> blockedUsers() async =>
      _list(await _call('GET', '/users/blocks'));

  static Future<bool> blockStatus(String userId) async {
    try {
      final d = await _call('GET', '/users/$userId/block');
      return (d as Map)['blocked'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> report(
      {String? targetId, String? chatId, String? reason}) async {
    try {
      await _call('POST', '/report', body: {
        'target_id': targetId,
        'chat_id': chatId,
        'reason': reason,
      });
    } catch (_) {}
  }

  // ── чаты ──

  static Future<List<dynamic>> chats() async =>
      _list(await _call('GET', '/chats'));

  static Future<Map<String, dynamic>> chatInfo(String chatId) async =>
      _map(await _call('GET', '/chats/$chatId'));

  static Future<Map<String, dynamic>> createChat({
    required String type,
    String? title,
    String? description,
    String? handle,
    String? avatarUrl,
    List<String> memberIds = const [],
  }) async =>
      _map(await _call('POST', '/chats', body: {
        'type': type,
        'title': title,
        'description': description,
        'handle': handle,
        'avatar_url': avatarUrl,
        'member_ids': memberIds,
      }));

  static Future<Map<String, dynamic>> editChat(
          String chatId, Map<String, dynamic> data) async =>
      _map(await _call('PATCH', '/chats/$chatId', body: data));

  static Future<Map<String, dynamic>> regenerateInvite(String chatId) async =>
      _map(await _call('POST', '/chats/$chatId/invite'));

  static Future<List<dynamic>> members(String chatId, {String q = ''}) async =>
      _list(await _call('GET', '/chats/$chatId/members', query: {'q': q}));

  static Future<Map<String, dynamic>> addMembers(
          String chatId, List<String> userIds) async =>
      _map(await _call('POST', '/chats/$chatId/members',
          body: {'user_ids': userIds}));

  static Future<void> kickMember(String chatId, String userId) async =>
      _call('DELETE', '/chats/$chatId/members/$userId');

  static Future<void> setMemberRole(
          String chatId, String userId, String role) async =>
      _call('PATCH', '/chats/$chatId/members/$userId', body: {'role': role});

  static Future<void> transferOwnership(String chatId, String userId) async =>
      _call('POST', '/chats/$chatId/transfer', body: {'user_id': userId});

  static Future<List<dynamic>> chatBans(String chatId) async =>
      _list(await _call('GET', '/chats/$chatId/bans'));

  static Future<void> unbanMember(String chatId, String userId) async =>
      _call('DELETE', '/chats/$chatId/bans/$userId');

  static Future<void> leaveChat(String chatId) async =>
      _call('POST', '/chats/$chatId/leave');

  static Future<List<dynamic>> searchPublicChats(String q) async =>
      _list(await _call('GET', '/chats/public/search', query: {'q': q}));

  static Future<Map<String, dynamic>> joinPublic(String chatId) async =>
      _map(await _call('POST', '/chats/$chatId/join'));

  static Future<Map<String, dynamic>> invitePreview(String code) async =>
      _map(await _call('GET', '/join/$code'));

  static Future<Map<String, dynamic>> joinByInvite(String code) async =>
      _map(await _call('POST', '/join/$code'));

  /// Вытащить код приглашения из ссылки (…/j/CODE или …/join/CODE) или вернуть null.
  static String? inviteCodeOf(String text) {
    final m = RegExp(r'/(?:j|join)/([A-Za-z0-9_\-]{6,})').firstMatch(text.trim());
    return m?.group(1);
  }

  static Future<void> setMute(String chatId, int until) async {
    try {
      await _call('PUT', '/chats/$chatId/mute', body: {'until': until});
    } catch (_) {}
  }

  static Future<List<dynamic>> messages(String chatId, {int limit = 400}) async =>
      _list(await _call('GET', '/chats/$chatId/messages',
          query: {'limit': '$limit'}));

  /// Пометить чат прочитанным (для галочек ✓✓ у собеседника).
  static Future<void> markRead(String chatId) async {
    try {
      Notif.cancelChat(chatId);
      await _raw('POST', '/chats/$chatId/read');
    } catch (_) {}
  }

  /// Статус и карточка собеседника в личном чате.
  static Future<Map<String, dynamic>?> peerInfo(String chatId) async {
    try {
      return _map(await _call('GET', '/chats/$chatId/peer',
          timeout: const Duration(seconds: 8)));
    } catch (_) {
      return null;
    }
  }

  /// Удалить чат. both=false — только у себя / выйти; both=true — у всех.
  static Future<void> deleteChat(String chatId, {bool both = false}) async =>
      _call('DELETE', '/chats/$chatId', query: {'scope': both ? 'both' : 'me'});

  /// Очистить историю чата. forAll=false — только у себя.
  static Future<void> clearHistory(String chatId, {bool forAll = true}) async =>
      _call('DELETE', '/chats/$chatId/messages',
          query: {'scope': forAll ? 'all' : 'me'});

  static Future<Map<String, dynamic>> sendMessage(
    String chatId, {
    String text = '',
    String kind = 'text',
    String? mediaUrl,
    String? fileName,
    String? replyToId,
    String? forwardedFrom,
    String? effect,
    bool silent = false,
    DateTime? openAt,
    String? storyId,
  }) async {
    // личные чаты шифруются сквозным шифрованием (если у собеседника есть ключи)
    final (plain, enc) = await E2E.seal(chatId, text);
    final r = _map(await _call('POST', '/chats/$chatId/messages', body: {
      'text': plain,
      'kind': kind,
      'media_url': mediaUrl,
      'file_name': fileName,
      'reply_to_id': replyToId,
      'forwarded_from': forwardedFrom,
      if (effect != null) 'effect': effect,
      if (silent) 'silent': true,
      if (openAt != null) 'open_at': openAt.millisecondsSinceEpoch,
      if (storyId != null) 'story_id': storyId,
      if (enc != null) 'enc': enc,
    }));
    if (enc != null) E2E.remember(r['id'] as String?, text, enc);
    return r;
  }

  /// Открытый ключ устройства для сквозного шифрования.
  static Future<Map<String, dynamic>> registerKey(String deviceId, String publicKey) async =>
      _map(await _call('PUT', '/keys', body: {'device_id': deviceId, 'public_key': publicKey}));

  /// Ключи устройств участников личного чата.
  // ── вход по QR-коду ──

  /// Компьютер: получить QR и короткий код для входа.
  static Future<Map<String, dynamic>> qrStart(String deviceId, String platform) async =>
      _map(await _call('POST', '/auth/qr/start',
          auth: false, body: {'device_id': deviceId, 'platform': platform}));

  /// Компьютер: подтвердили ли вход на телефоне.
  static Future<Map<String, dynamic>> qrPoll(String token) async =>
      _map(await _call('GET', '/auth/qr/$token', auth: false,
          timeout: const Duration(seconds: 10)));

  /// Телефон: куда будет вход (платформа, город).
  static Future<Map<String, dynamic>> qrInspect({String? token, String? code}) async =>
      _map(await _call('POST', '/auth/qr/inspect', body: {'token': token, 'code': code}));

  /// Телефон: разрешить вход.
  static Future<Map<String, dynamic>> qrApprove({String? token, String? code}) async =>
      _map(await _call('POST', '/auth/qr/approve', body: {'token': token, 'code': code}));

  /// Перед звонком: можно ли звонить, ICE/TURN-серверы, режим «только через сервер».
  static Future<Map<String, dynamic>> callPrepare(String chatId) async =>
      _map(await _call('GET', '/calls/prepare',
          query: {'chat_id': chatId}, timeout: const Duration(seconds: 12)));

  static Future<Map<String, dynamic>> chatKeys(String chatId) async =>
      _map(await _call('GET', '/chats/$chatId/keys'));

  /// Автоудаление сообщений в чате (0 — выкл).
  static Future<Map<String, dynamic>> setChatTtl(String chatId, int seconds) async =>
      _map(await _call('PUT', '/chats/$chatId/ttl', body: {'seconds': seconds}));

  /// Редактировать своё текстовое сообщение.
  static Future<Map<String, dynamic>> editMessage(
      String chatId, String msgId, String text) async {
    final (plain, enc) = await E2E.seal(chatId, text);
    final r = _map(await _call('PATCH', '/chats/$chatId/messages/$msgId',
        body: {'text': plain, if (enc != null) 'enc': enc}));
    if (enc != null) E2E.remember(msgId, text, enc);
    return r;
  }

  /// Удалить сообщение у всех (автор или админ).
  static Future<void> deleteMessage(String chatId, String msgId) async =>
      _call('DELETE', '/chats/$chatId/messages/$msgId');

  /// Закрепить / открепить сообщение.
  static Future<void> pinMessage(
          String chatId, String msgId, bool pinned) async =>
      _call('POST', '/chats/$chatId/messages/$msgId/pin',
          body: {'pinned': pinned});

  /// Поставить / снять реакцию. Возвращает актуальный список реакций.
  static Future<List<dynamic>> react(
      String chatId, String msgId, String emoji) async {
    final d = _map(await _call('POST', '/chats/$chatId/messages/$msgId/react',
        body: {'emoji': emoji}));
    return _list(d['reactions']);
  }

  /// Загрузка файла (фото/видео/файл/голосовое). Возвращает {url, file_name}.
  /// В браузере path — blob:-ссылка; тогда читаем байты и нужен [fileName] с расширением.
  static Future<Map<String, dynamic>> uploadPath(String path, {String? fileName}) async {
    final bytes = kIsWeb ? await readLocalBytes(path) : null;
    Future<http.StreamedResponse> go() async {
      final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/upload'));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      if (bytes != null) {
        req.files.add(http.MultipartFile.fromBytes('file', bytes,
            filename: fileName ?? _guessName(bytes)));
      } else {
        req.files.add(await http.MultipartFile.fromPath('file', path));
      }
      return _client.send(req);
    }

    var resp = await go();
    if (resp.statusCode == 401 && await _tryRefresh()) resp = await go();
    final body = await resp.stream.bytesToString();
    if (resp.statusCode == 200) {
      return (jsonDecode(body) as Map).cast<String, dynamic>();
    }
    String msg = 'Ошибка загрузки (${resp.statusCode})';
    try {
      final d = jsonDecode(body);
      if (d is Map && d['detail'] is String) msg = d['detail'] as String;
    } catch (_) {}
    throw ApiException(msg, resp.statusCode);
  }

  /// Имя файла по первым байтам (для загрузки из браузера без имени).
  static String _guessName(List<int> b) {
    bool starts(List<int> sig, [int at = 0]) =>
        b.length >= at + sig.length &&
        List.generate(sig.length, (i) => b[at + i] == sig[i]).every((x) => x);
    if (starts([0x89, 0x50, 0x4E, 0x47])) return 'image.png';
    if (starts([0xFF, 0xD8, 0xFF])) return 'image.jpg';
    if (starts([0x47, 0x49, 0x46])) return 'image.gif';
    if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x45, 0x42, 0x50], 8)) {
      return 'image.webp';
    }
    if (starts([0x52, 0x49, 0x46, 0x46]) && starts([0x57, 0x41, 0x56, 0x45], 8)) {
      return 'audio.wav';
    }
    if (starts([0x1A, 0x45, 0xDF, 0xA3])) return 'media.webm';
    if (starts([0x66, 0x74, 0x79, 0x70], 4)) return 'video.mp4';
    if (starts([0x49, 0x44, 0x33]) || starts([0xFF, 0xFB])) return 'audio.mp3';
    if (starts([0x4F, 0x67, 0x67, 0x53])) return 'audio.ogg';
    if (starts([0x25, 0x50, 0x44, 0x46])) return 'file.pdf';
    return 'file.bin';
  }

  // ── премиум ──

  static Future<Map<String, dynamic>> premiumStatus() async =>
      _map(await _call('GET', '/premium'));

  static Future<Map<String, dynamic>> redeemPromo(String code) async =>
      _map(await _call('POST', '/premium/redeem', body: {'code': code}));

  // ── истории ──

  static Future<Map<String, dynamic>> storiesFeed() async =>
      _map(await _call('GET', '/stories'));

  static Future<Map<String, dynamic>> storyLimits() async =>
      _map(await _call('GET', '/stories/limits'));

  static Future<Map<String, dynamic>> userStories(String userId) async =>
      _map(await _call('GET', '/stories/user/$userId'));

  static Future<List<dynamic>> userPosts(String userId) async =>
      _list(await _call('GET', '/users/$userId/posts'));

  static Future<List<dynamic>> storyArchive() async =>
      _list(await _call('GET', '/stories/archive'));

  static Future<Map<String, dynamic>> createStory({
    required String mediaUrl,
    String kind = 'image',
    String caption = '',
    String audience = 'all',
    bool pinned = false,
    int hours = 24,
    List<Map<String, dynamic>> overlays = const [],
    String? musicUrl,
    String? musicTitle,
  }) async =>
      _map(await _call('POST', '/stories', body: {
        'media_url': mediaUrl,
        'kind': kind,
        'caption': caption,
        'audience': audience,
        'pinned': pinned,
        'hours': hours,
        if (overlays.isNotEmpty) 'overlays': overlays,
        if (musicUrl != null) 'music_url': musicUrl,
        if (musicTitle != null) 'music_title': musicTitle,
      }));

  /// Погода для стикера: {temp, emoji, text, city}.
  // ── бесплатные внешние API (через наш сервер) ──

  /// GIF: поиск (пустой запрос — популярные). {provider, items, next, categories}
  static Future<Map<String, dynamic>> gifs(String q, {int offset = 0}) async =>
      _map(await _call('GET', '/ext/gifs', query: {'q': q, 'offset': '$offset'}));

  /// Забрать GIF к нам на сервер → {url}
  static Future<Map<String, dynamic>> gifImport(String url) async =>
      _map(await _call('POST', '/ext/gifs/import',
          body: {'url': url}, timeout: const Duration(seconds: 40)));

  /// Перевод текста → {text, from, to}
  static Future<Map<String, dynamic>> translate(String text, String to) async =>
      _map(await _call('POST', '/ext/translate', body: {'text': text, 'to': to}));

  /// Музыка для историй: [{id, title, artist, cover, preview, duration}]
  static Future<List<dynamic>> musicSearch(String q) async =>
      _list(await _call('GET', '/ext/music', query: {'q': q}));

  /// Отрывок трека → к нам на сервер → {url}
  static Future<Map<String, dynamic>> musicImport(String url) async =>
      _map(await _call('POST', '/ext/music/import',
          body: {'url': url}, timeout: const Duration(seconds: 40)));

  /// Встроенные полезные боты (погода, курсы, факты, переводчик)
  static Future<List<dynamic>> builtinBots() async => _list(await _call('GET', '/ext/bots'));

  static Future<Map<String, dynamic>> weather({double? lat, double? lon}) async =>
      _map(await _call('GET', '/stories/weather',
          query: lat != null && lon != null ? {'lat': '$lat', 'lon': '$lon'} : null));

  static Future<void> deleteStory(String id) async => _call('DELETE', '/stories/$id');

  static Future<Map<String, dynamic>> pinStory(String id, bool pinned) async =>
      _map(await _call('PUT', '/stories/$id/pin', body: {'pinned': pinned}));

  static Future<void> viewStory(String id, {bool stealth = false}) async {
    try {
      await _call('POST', '/stories/$id/view',
          query: stealth ? {'stealth': 'true'} : null);
    } catch (_) {}
  }

  static Future<void> reactStory(String id, String? emoji) async =>
      _call('POST', '/stories/$id/react', body: {'emoji': emoji});

  static Future<List<dynamic>> storyViewers(String id) async =>
      _list(await _call('GET', '/stories/$id/viewers'));

  // ── коины ──

  static Future<Map<String, dynamic>> wallet() async => _map(await _call('GET', '/coins'));
  static Future<Map<String, dynamic>> shop() async => _map(await _call('GET', '/coins/shop'));

  static Future<List<dynamic>> coinHistory() async =>
      _list(await _call('GET', '/coins/history'));

  static Future<Map<String, dynamic>> claimDaily() async =>
      _map(await _call('POST', '/coins/daily'));

  static Future<Map<String, dynamic>> buyCoins(String packageId) async =>
      _map(await _call('POST', '/coins/buy', body: {'package_id': packageId}));

  static Future<Map<String, dynamic>> paymentStatus(String id) async =>
      _map(await _call('GET', '/coins/payments/$id'));

  static Future<Map<String, dynamic>> buyPremiumWithCoins(String planId,
          {String? toUserId}) async =>
      _map(await _call('POST', '/coins/premium',
          body: {'plan_id': planId, if (toUserId != null) 'to_user_id': toUserId}));

  // ── подарки ──

  static Future<Map<String, dynamic>> giftCatalog() async =>
      _map(await _call('GET', '/gifts/catalog'));

  static Future<Map<String, dynamic>> sendGift(String toUserId, String giftId,
          {String text = '', bool anonymous = false}) async =>
      _map(await _call('POST', '/gifts/send', body: {
        'to_user_id': toUserId,
        'gift_id': giftId,
        'text': text,
        'anonymous': anonymous,
      }));

  static Future<Map<String, dynamic>> userGifts(String userId) async =>
      _map(await _call('GET', '/users/$userId/gifts'));

  static Future<Map<String, dynamic>> hideGift(String id, bool hidden) async =>
      _map(await _call('PUT', '/gifts/$id/hide', body: {'hidden': hidden}));

  static Future<Map<String, dynamic>> convertGift(String id) async =>
      _map(await _call('POST', '/gifts/$id/convert'));

  static Future<Map<String, dynamic>> pinGift(String id, bool pinned) async =>
      _map(await _call('PUT', '/gifts/$id/pin', body: {'pinned': pinned}));

  /// Улучшить до уникального: {gift, balance}.
  static Future<Map<String, dynamic>> upgradeGift(String id) async =>
      _map(await _call('POST', '/gifts/$id/upgrade'));

  static Future<Map<String, dynamic>> giftUpgradeInfo() async =>
      _map(await _call('GET', '/gifts/upgrade_info'));

  // ── боты ──

  static Future<List<dynamic>> myBots() async => _list(await _call('GET', '/bots'));

  static Future<Map<String, dynamic>> createBot(
          String name, String username) async =>
      _map(await _call('POST', '/bots',
          body: {'name': name, 'username': username}));

  static Future<Map<String, dynamic>> editBot(
          String botId, Map<String, dynamic> data) async =>
      _map(await _call('PATCH', '/bots/$botId', body: data));

  static Future<Map<String, dynamic>> regenerateBotToken(String botId) async =>
      _map(await _call('POST', '/bots/$botId/token'));

  static Future<void> deleteBot(String botId) async =>
      _call('DELETE', '/bots/$botId');

  // ── админка ──

  static Future<Map<String, dynamic>> adminStats() async =>
      _map(await _call('GET', '/admin/stats'));

  /// Список всех пользователей (только для админа). q — поиск.
  static Future<List<dynamic>> adminUsers(String q) async =>
      _list(await _call('GET', '/admin/users', query: {'q': q}));

  /// Забанить / разбанить пользователя.
  static Future<void> adminSetBan(String userId, bool banned) async =>
      _call('POST', '/admin/users/$userId/${banned ? 'ban' : 'unban'}');

  /// Удалить аккаунт пользователя навсегда.
  static Future<void> adminDeleteUser(String userId) async =>
      _call('DELETE', '/admin/users/$userId');

  static Future<Map<String, dynamic>> adminSetPremium(
          String userId, int days) async =>
      _map(await _call('POST', '/admin/users/$userId/premium',
          body: {'days': days}));

  static Future<List<dynamic>> adminPromos() async =>
      _list(await _call('GET', '/admin/promo'));

  static Future<Map<String, dynamic>> adminCreatePromo(int days, int uses,
          {String? code, int coins = 0}) async =>
      _map(await _call('POST', '/admin/promo',
          body: {'days': days, 'uses': uses, 'code': code, 'coins': coins}));

  static Future<Map<String, dynamic>> adminEconomy() async =>
      _map(await _call('GET', '/admin/economy'));

  static Future<List<dynamic>> adminUserCoins(String userId) async =>
      _list(await _call('GET', '/admin/users/$userId/coins'));

  static Future<Map<String, dynamic>> adminGift(String userId, String giftId,
          {String text = ''}) async =>
      _map(await _call('POST', '/admin/users/$userId/gift',
          body: {'gift_id': giftId, 'text': text}));

  // ── админка: магазин подарков ──

  static Future<List<dynamic>> adminGifts() async => _list(await _call('GET', '/admin/gifts'));

  static Future<Map<String, dynamic>> adminSaveGift(Map<String, dynamic> body,
          {String? id}) async =>
      _map(await _call(id == null ? 'POST' : 'PUT', id == null ? '/admin/gifts' : '/admin/gifts/$id',
          body: body));

  static Future<Map<String, dynamic>> adminDeleteGift(String id) async =>
      _map(await _call('DELETE', '/admin/gifts/$id'));

  /// Картинка подарка: сервер убирает белый фон и делает PNG 512×512.
  /// Либо новый файл (path / bytes), либо уже загруженный (src = /media/...).
  static Future<Map<String, dynamic>> adminGiftImage(
      {String? path, List<int>? bytes, String? fileName, String? src, bool removeBg = true}) async {
    Future<http.StreamedResponse> go() async {
      final req = http.MultipartRequest('POST', Uri.parse('$kBaseUrl/admin/gifts/image'));
      if (token != null) req.headers['Authorization'] = 'Bearer $token';
      req.fields['remove_bg'] = removeBg ? 'true' : 'false';
      if (src != null) req.fields['src'] = src;
      if (bytes != null) {
        req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName ?? 'gift.png'));
      } else if (path != null) {
        req.files.add(await http.MultipartFile.fromPath('file', path, filename: fileName));
      }
      return _client.send(req);
    }

    var resp = await go();
    if (resp.statusCode == 401 && await _tryRefresh()) resp = await go();
    final body = await resp.stream.bytesToString();
    if (resp.statusCode == 200) return (jsonDecode(body) as Map).cast<String, dynamic>();
    String msg = 'Ошибка загрузки (${resp.statusCode})';
    try {
      final d = jsonDecode(body);
      if (d is Map && d['detail'] is String) msg = d['detail'] as String;
    } catch (_) {}
    throw ApiException(msg, resp.statusCode);
  }

  /// Админ: проверка почты (SMTP) и тестовое письмо себе.
  static Future<Map<String, dynamic>> adminMailCheck({bool send = false}) async =>
      _map(await _call('GET', '/admin/mail_check', query: {'send': send ? 'true' : 'false'},
          timeout: const Duration(seconds: 40)));

  // ── магазин оформления ──

  static Future<Map<String, dynamic>> shopHome() async => _map(await _call('GET', '/shop'));

  static Future<Map<String, dynamic>> shopItems(
          {String q = '',
          String kind = '',
          String collection = '',
          String filter = '',
          String rarity = '',
          String sort = 'popular',
          int offset = 0,
          int limit = 60}) async =>
      _map(await _call('GET', '/shop/items', query: {
        if (q.isNotEmpty) 'q': q,
        if (kind.isNotEmpty) 'kind': kind,
        if (collection.isNotEmpty) 'collection': collection,
        if (filter.isNotEmpty) 'filter': filter,
        if (rarity.isNotEmpty) 'rarity': rarity,
        'sort': sort,
        'offset': '$offset',
        'limit': '$limit',
      }));

  static Future<Map<String, dynamic>> shopItem(String id) async =>
      _map(await _call('GET', '/shop/items/$id'));

  static Future<Map<String, dynamic>> shopInventory() async =>
      _map(await _call('GET', '/shop/inventory'));

  /// Купить себе или в подарок [toUserId].
  static Future<Map<String, dynamic>> shopBuy(String id, {String? toUserId, String text = ''}) async =>
      _map(await _call('POST', '/shop/items/$id/buy',
          body: {if (toUserId != null) 'to_user_id': toUserId, 'text': text}));

  static Future<Map<String, dynamic>> shopEquip(String id) async =>
      _map(await _call('POST', '/shop/items/$id/equip'));

  static Future<Map<String, dynamic>> shopUnequip(String kind) async =>
      _map(await _call('POST', '/shop/unequip', body: {'kind': kind}));

  // ── админка: магазин оформления ──

  static Future<List<dynamic>> adminShopItems() async =>
      _list(await _call('GET', '/admin/shop/items'));

  static Future<Map<String, dynamic>> adminSaveShopItem(Map<String, dynamic> body,
          {String? id}) async =>
      _map(await _call(id == null ? 'POST' : 'PUT',
          id == null ? '/admin/shop/items' : '/admin/shop/items/$id',
          body: body));

  static Future<Map<String, dynamic>> adminDeleteShopItem(String id) async =>
      _map(await _call('DELETE', '/admin/shop/items/$id'));

  static Future<List<dynamic>> adminShopCollections() async =>
      _list(await _call('GET', '/admin/shop/collections'));

  static Future<Map<String, dynamic>> adminSaveCollection(Map<String, dynamic> body,
          {String? id}) async =>
      _map(await _call(id == null ? 'POST' : 'PUT',
          id == null ? '/admin/shop/collections' : '/admin/shop/collections/$id',
          body: body));

  static Future<Map<String, dynamic>> adminDeleteCollection(String id) async =>
      _map(await _call('DELETE', '/admin/shop/collections/$id'));

  /// Загрузить картинку/видео товара → {url, kind, preview_url}.
  static Future<Map<String, dynamic>> adminShopMedia(
          {String? path, List<int>? bytes, String? fileName,
          void Function(double p)? onProgress}) async =>
      _sendFile('/admin/shop/media',
          path: path, bytes: bytes, fileName: fileName, onProgress: onProgress);

  /// Импорт пака (zip с shop.json и файлами) → {collections, items, gifts, files}.
  static Future<Map<String, dynamic>> adminShopImport(
          {String? path, List<int>? bytes, String? fileName,
          void Function(double p)? onProgress}) async =>
      _sendFile('/admin/shop/import',
          path: path, bytes: bytes, fileName: fileName ?? 'pack.zip', onProgress: onProgress);

  /// Отправка одного файла с полоской прогресса (для больших загрузок из админки).
  static Future<Map<String, dynamic>> _sendFile(String apiPath,
      {String? path,
      List<int>? bytes,
      String? fileName,
      Map<String, String> fields = const {},
      void Function(double p)? onProgress}) async {
    await adminRelease(); // заодно обновит токен (поток второй раз не отправить)
    final uri = Uri.parse('$kBaseUrl$apiPath');
    final req = http.MultipartRequest('POST', uri);
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    req.fields.addAll(fields);
    if (bytes != null) {
      req.files.add(http.MultipartFile.fromBytes('file', bytes, filename: fileName ?? 'file'));
    } else if (path != null) {
      req.files.add(await http.MultipartFile.fromPath('file', path, filename: fileName));
    }
    final total = req.contentLength;
    final body = req.finalize();
    final out = http.StreamedRequest('POST', uri)
      ..headers.addAll(req.headers)
      ..contentLength = total;
    var sent = 0;
    body.listen((chunk) {
      sent += chunk.length;
      if (total > 0) onProgress?.call(sent / total);
      out.sink.add(chunk);
    }, onDone: () => out.sink.close(), onError: out.sink.addError, cancelOnError: true);
    final resp = await _client.send(out);
    final text = await resp.stream.bytesToString();
    if (resp.statusCode == 200) return (jsonDecode(text) as Map).cast<String, dynamic>();
    String msg = 'Ошибка загрузки (${resp.statusCode})';
    try {
      final d = jsonDecode(text);
      if (d is Map && d['detail'] is String) msg = d['detail'] as String;
    } catch (_) {}
    throw ApiException(msg, resp.statusCode);
  }

  // ── админка: обновления приложения ──

  static Future<Map<String, dynamic>> adminRelease() async =>
      _map(await _call('GET', '/admin/release'));

  /// Выложить новую версию (APK или установщик). Без файла — только поправить текст.
  /// [path] — файл на телефоне/ПК, [bytes] — в браузере. onProgress: 0..1.
  static Future<Map<String, dynamic>> adminPublishRelease({
    required String platform,
    required String version,
    required int build,
    required String notes,
    bool mandatory = false,
    String? path,
    List<int>? bytes,
    String? fileName,
    void Function(double p)? onProgress,
  }) async =>
      _sendFile('/admin/release',
          path: path,
          bytes: bytes,
          fileName: fileName,
          fields: {
            'platform': platform,
            'version': version,
            'build': '$build',
            'notes': notes,
            'mandatory': mandatory ? 'true' : 'false',
          },
          onProgress: onProgress);

  static Future<List<dynamic>> adminStories() async =>
      _list(await _call('GET', '/admin/stories'));

  static Future<void> adminDeleteStory(String id) async =>
      _call('DELETE', '/admin/stories/$id');

  static Future<Map<String, dynamic>> adminGiveCoins(String userId, int amount,
          {String? note}) async =>
      _map(await _call('POST', '/admin/users/$userId/coins',
          body: {'amount': amount, if (note != null && note.isNotEmpty) 'note': note}));

  static Future<void> adminDeletePromo(String code) async =>
      _call('DELETE', '/admin/promo/$code');

  static Future<List<dynamic>> adminReports() async =>
      _list(await _call('GET', '/admin/reports'));

  static Future<List<dynamic>> adminSupport() async =>
      _list(await _call('GET', '/admin/support'));

  static Future<List<dynamic>> adminSupportMessages(String chatId) async =>
      _list(await _call('GET', '/admin/support/$chatId'));

  static Future<void> adminSupportReply(String chatId, String text) async =>
      _call('POST', '/admin/support/$chatId', body: {'text': text});

  static Future<int> adminBroadcast(String text,
      {String target = 'all', List<String>? userIds}) async {
    final d = _map(await _call('POST', '/admin/broadcast',
        body: {
          'text': text,
          'target': target,
          if (userIds != null && userIds.isNotEmpty) 'user_ids': userIds,
        },
        timeout: const Duration(seconds: 120)));
    return (d['sent'] as num?)?.toInt() ?? 0;
  }

  static Future<Map<String, dynamic>> adminUserDetail(String userId) async =>
      _map(await _call('GET', '/admin/users/$userId'));

  static Future<Map<String, dynamic>> adminVerify(String userId, bool value) async =>
      _map(await _call('POST', '/admin/users/$userId/verify', body: {'value': value}));

  static Future<int> adminLogoutUser(String userId) async {
    final d = _map(await _call('POST', '/admin/users/$userId/logout'));
    return (d['sessions'] as num?)?.toInt() ?? 0;
  }

  static Future<void> adminMessageUser(String userId, String text) async =>
      _call('POST', '/admin/users/$userId/message', body: {'text': text});

  static Future<List<dynamic>> adminPremiumUsers() async =>
      _list(await _call('GET', '/admin/premium'));

  static Future<List<dynamic>> adminChats(String q) async =>
      _list(await _call('GET', '/admin/chats', query: {'q': q}));

  static Future<Map<String, dynamic>> adminVerifyChat(String chatId, bool value) async =>
      _map(await _call('POST', '/admin/chats/$chatId/verify', body: {'value': value}));

  static Future<void> adminDeleteChat(String chatId) async =>
      _call('DELETE', '/admin/chats/$chatId');

  static String _err(http.Response r) {
    try {
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      final detail = d['detail'];
      if (detail is String) return detail;
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        if (first is Map) {
          final loc = (first['loc'] as List?)?.last?.toString() ?? '';
          final msg = first['msg']?.toString() ?? '';
          if (loc == 'password') return 'Пароль — минимум 8 символов';
          if (loc == 'username') {
            return 'Логин: 3–32 символа, латиница, цифры и _';
          }
          if (loc == 'email') return 'Проверь почту — похоже, опечатка';
          if (loc == 'handle') return 'Юзернейм: 3–32 символа, латиница, цифры и _';
          return msg.isEmpty ? 'Ошибка ${r.statusCode}' : msg;
        }
      }
    } catch (_) {}
    if (r.statusCode == 413) return 'Файл слишком большой';
    if (r.statusCode >= 500) return 'Сервер временно недоступен';
    return 'Ошибка ${r.statusCode}';
  }
}
