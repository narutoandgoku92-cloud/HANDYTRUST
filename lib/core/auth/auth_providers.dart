import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'secure_token_manager.dart';
import '../network/api_client.dart';

final secureTokenManagerProvider = Provider<SecureTokenManager>((ref) {
  return SecureTokenManager();
});

final apiClientProvider = Provider<ApiClient>((ref) {
  final tokenManager = ref.read(secureTokenManagerProvider);
  return ApiClient(tokenManager);
});
