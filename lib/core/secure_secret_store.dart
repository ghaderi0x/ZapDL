import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../engine/http_support.dart';

/// Keeps download credentials (cookies, tokens) and proxy passwords in the
/// platform keystore: Keychain (iOS/macOS), Keystore (Android), DPAPI
/// (Windows), libsecret (Linux).
class SecureSecretStore implements SecretStore {
  SecureSecretStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  String _key(String id) => 'zapdl.secret.$id';

  @override
  Future<Map<String, String>> read(String id) async {
    final raw = await _s.read(key: _key(id));
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  @override
  Future<void> write(String id, Map<String, String> secrets) async {
    if (secrets.isEmpty) {
      await _s.delete(key: _key(id));
    } else {
      await _s.write(key: _key(id), value: jsonEncode(secrets));
    }
  }

  @override
  Future<void> delete(String id) => _s.delete(key: _key(id));
}
