import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';
import 'app_state.dart';

/// Сквозное шифрование личных чатов.
///
/// Как это работает:
/// * у каждого устройства своя пара ключей X25519; закрытый ключ никогда не
///   покидает телефон, на сервер уходит только открытый;
/// * текст сообщения шифруется случайным одноразовым ключом (AES-256-GCM);
/// * этот ключ «заворачивается» отдельно для каждого устройства собеседника и
///   своих устройств: общий секрет X25519 → HKDF-SHA256 → AES-256-GCM;
/// * сервер хранит только конверт {v, sp, c, k} и прочитать его не может.
///
/// Если у собеседника старая версия приложения (нет ключей), сообщение уходит
/// обычным способом — переписка не ломается.
class E2E {
  E2E._();

  static final _x = X25519();
  static final _aes = AesGcm.with256bits();
  static final _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static const _info = [99, 111, 110, 110, 101, 99, 116, 111, 45, 101, 50, 101, 45, 118, 49]; // connecto-e2e-v1

  static SimpleKeyPair? _kp;
  static String? _pub; // мой открытый ключ, base64
  static String? _keyId; // id моего ключа на сервере
  static String? _owner; // для какого аккаунта загружены ключи
  static Future<void>? _loading;

  /// Готовые ключи обёртки по открытому ключу собеседника — X25519 считаем один раз.
  static final Map<String, SecretKey> _wrap = {};

  /// Расшифрованные тексты: id сообщения → текст.
  static final Map<String, String> _plain = {};

  /// Расшифрованные превью для списка чатов: конверт → текст.
  static final Map<String, String> _byEnv = {};
  static String? cachedEnv(String env) => _byEnv[env];

  /// Ключи участников чата (кэш на 2 минуты).
  static final Map<String, _ChatKeys> _chatKeys = {};

  /// Готово ли шифрование для этого чата (для значка 🔒 в шапке).
  static bool enabledFor(String chatId) {
    final k = _chatKeys[chatId];
    return k != null && k.enabled && k.peerHasKeys;
  }

  // ─────────────────────────────── ключи устройства ───────────────────────────────

  /// Загрузить (или создать) ключ устройства для текущего аккаунта и отправить
  /// открытую часть на сервер. Можно вызывать сколько угодно раз.
  static Future<void> ensure() {
    final uid = appState.myUserId;
    if (uid == null) return Future.value();
    if (_owner == uid && _kp != null && _keyId != null) return Future.value();
    return _loading ??= _load(uid).whenComplete(() => _loading = null);
  }

  static Future<void> _load(String uid) async {
    if (_owner != uid) {
      _kp = null;
      _pub = null;
      _keyId = null;
      _wrap.clear();
      _chatKeys.clear();
    }
    final p = await SharedPreferences.getInstance();
    final seedKey = 'e2e_seed_$uid';
    var seed = p.getString(seedKey);
    if (seed == null) {
      final rnd = math.Random.secure();
      seed = base64Encode(List<int>.generate(32, (_) => rnd.nextInt(256)));
      await p.setString(seedKey, seed);
    }
    final kp = await _x.newKeyPairFromSeed(base64Decode(seed));
    final pub = base64Encode((await kp.extractPublicKey()).bytes);
    _kp = kp;
    _pub = pub;
    _owner = uid;
    // регистрация открытого ключа (идемпотентно — тот же ключ вернёт тот же id)
    final cached = p.getString('e2e_kid_$uid');
    final cachedPub = p.getString('e2e_kpub_$uid');
    if (cached != null && cachedPub == pub) _keyId = cached;
    try {
      final r = await Api.registerKey(appState.deviceId, pub);
      final id = r['key_id'] as String?;
      if (id != null) {
        _keyId = id;
        await p.setString('e2e_kid_$uid', id);
        await p.setString('e2e_kpub_$uid', pub);
      }
    } catch (_) {
      // нет сети — попробуем в следующий раз, а расшифровать сможем по сохранённому id
    }
  }

  static Future<SecretKey> _wrapKey(String theirPubB64) async {
    final cached = _wrap[theirPubB64];
    if (cached != null) return cached;
    final shared = await _x.sharedSecretKey(
      keyPair: _kp!,
      remotePublicKey: SimplePublicKey(base64Decode(theirPubB64), type: KeyPairType.x25519),
    );
    final k = await _hkdf.deriveKey(secretKey: shared, info: _info);
    _wrap[theirPubB64] = k;
    return k;
  }

  static Future<_ChatKeys> _keysOf(String chatId) async {
    final c = _chatKeys[chatId];
    if (c != null && DateTime.now().difference(c.at).inMinutes < 2) return c;
    try {
      final r = await Api.chatKeys(chatId);
      final keys = ((r['keys'] as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
      final me = appState.myUserId;
      final k = _ChatKeys(
        enabled: r['enabled'] == true,
        keys: {
          for (final e in keys) e['key_id'] as String: e['public_key'] as String,
        },
        peerHasKeys: keys.any((e) => e['user_id'] != me),
        at: DateTime.now(),
      );
      _chatKeys[chatId] = k;
      return k;
    } catch (_) {
      // не получилось (нет сети) — запомним «без шифрования» ненадолго, чтобы не долбить сервер
      return _chatKeys[chatId] = c ??
          _ChatKeys(enabled: false, keys: const {}, peerHasKeys: false, at: DateTime.now());
    }
  }

  /// Проверить заранее (для значка в чате): включено ли шифрование.
  static Future<bool> check(String chatId) async {
    await ensure();
    final k = await _keysOf(chatId);
    return k.enabled && k.peerHasKeys;
  }

  // ─────────────────────────────── шифрование ───────────────────────────────

  /// Зашифровать текст для чата. Возвращает (текст для сервера, конверт или null).
  static Future<(String, String?)> seal(String chatId, String text) async {
    if (text.isEmpty) return (text, null);
    try {
      await ensure();
      if (_kp == null || _pub == null) return (text, null);
      final ck = await _keysOf(chatId);
      if (!ck.enabled || !ck.peerHasKeys) return (text, null);
      final targets = Map<String, String>.from(ck.keys);
      if (_keyId != null) targets[_keyId!] = _pub!;
      final msgKey = await _aes.newSecretKey();
      final msgKeyBytes = await msgKey.extractBytes();
      final body = await _aes.encrypt(utf8.encode(text), secretKey: msgKey);
      final wrapped = <String, String>{};
      for (final e in targets.entries) {
        final wk = await _wrapKey(e.value);
        final box = await _aes.encrypt(msgKeyBytes, secretKey: wk);
        wrapped[e.key] = base64Encode(box.concatenation());
      }
      final env = jsonEncode({
        'v': 1,
        'sp': _pub,
        'c': base64Encode(body.concatenation()),
        'k': wrapped,
      });
      return ('', env);
    } catch (_) {
      return (text, null); // что-то пошло не так — не теряем сообщение
    }
  }

  /// Запомнить свой только что отправленный текст (чтобы не расшифровывать заново).
  static void remember(String? msgId, String text, [String? env]) {
    if (text.isEmpty) return;
    if (msgId != null) _plain[msgId] = text;
    if (env != null) _byEnv[env] = text;
  }

  /// Уже расшифрованный текст (без ожидания).
  static String? cached(String? msgId) => msgId == null ? null : _plain[msgId];

  /// Расшифровать конверт. null — это сообщение не для этого устройства или повреждено.
  static Future<String?> open(String env, {String? id}) async {
    final c = _byEnv[env];
    if (c != null) return c;
    try {
      await ensure();
      final kid = _keyId;
      if (_kp == null || kid == null) return null;
      final m = jsonDecode(env) as Map<String, dynamic>;
      final keys = (m['k'] as Map).cast<String, dynamic>();
      final mine = keys[kid] as String?;
      if (mine == null) return null;
      final wk = await _wrapKey(m['sp'] as String);
      final kb = await _aes.decrypt(
          SecretBox.fromConcatenation(base64Decode(mine), nonceLength: 12, macLength: 16),
          secretKey: wk);
      final body = await _aes.decrypt(
          SecretBox.fromConcatenation(base64Decode(m['c'] as String),
              nonceLength: 12, macLength: 16),
          secretKey: SecretKey(kb));
      final text = utf8.decode(body);
      if (id != null) _plain[id] = text;
      if (_byEnv.length > 500) _byEnv.clear();
      _byEnv[env] = text;
      return text;
    } catch (_) {
      return null;
    }
  }

  /// Текст-заглушка, пока сообщение расшифровывается или если не получилось.
  static const pending = '🔒 …';
  static const unavailable = '🔒 Сообщение недоступно на этом устройстве';
}

class _ChatKeys {
  final bool enabled;
  final Map<String, String> keys; // key_id → открытый ключ
  final bool peerHasKeys;
  final DateTime at;
  _ChatKeys({required this.enabled, required this.keys, required this.peerHasKeys, required this.at});
}
