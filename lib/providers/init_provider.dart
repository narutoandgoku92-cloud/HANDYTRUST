import 'dart:async';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/firebase/firebase_initializer.dart';

final firebaseInitializationProvider = FutureProvider<void>((ref) async {
  debugPrint('[init_provider] starting Firebase initialization');
  try {
    await initializeFirebase().timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        throw TimeoutException('Firebase initialization timed out after 30 seconds');
      },
    );
    debugPrint('[init_provider] Firebase initialization completed successfully');
  } catch (e, st) {
    debugPrint('[init_provider] Firebase initialization failed: $e');
    debugPrint(st.toString());
    rethrow;
  }
});
