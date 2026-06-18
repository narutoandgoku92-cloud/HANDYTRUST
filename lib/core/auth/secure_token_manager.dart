import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A secure token manager for production-ready auth storage.
///
/// This class stores the auth token in platform secure storage and
/// keeps UI and widget code free of sensitive values.
class SecureTokenManager {
  static const String _tokenKey = 'auth_access_token';

  final FlutterSecureStorage _secureStorage;

  SecureTokenManager({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  Future<void> saveToken(String token) async {
    await _secureStorage.write(
      key: _tokenKey,
      value: token,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<String?> getToken() async {
    return await _secureStorage.read(
      key: _tokenKey,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  Future<bool> hasToken() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  Future<void> refreshToken(String newToken) async {
    await saveToken(newToken);
  }

  Future<void> clearToken() async {
    await _secureStorage.delete(
      key: _tokenKey,
      iOptions: _iosOptions,
      aOptions: _androidOptions,
    );
  }

  static const AndroidOptions _androidOptions = AndroidOptions(
    encryptedSharedPreferences: true,
  );

  static const IOSOptions _iosOptions = IOSOptions(
    accessibility: KeychainAccessibility.first_unlock,
  );
}
