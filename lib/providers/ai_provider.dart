import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class JobAiSuggestion {
  final String suggestedCategory;
  final double confidence;
  final String enhancedDescription;

  const JobAiSuggestion({
    required this.suggestedCategory,
    required this.confidence,
    required this.enhancedDescription,
  });

  Map<String, dynamic> toJson() => {
        'category': suggestedCategory,
        'confidence': confidence,
        'enhancedDescription': enhancedDescription,
      };
}

/// Thrown by [AiService.analyzeJob] with an already-user-friendly message —
/// callers can show `e.toString()` (or just `'$e'`) directly without
/// needing to interpret Firebase error codes themselves.
class AiServiceException implements Exception {
  final String message;
  final String? code;

  const AiServiceException(this.message, {this.code});

  @override
  String toString() => message;
}

class AiService {
  final FirebaseFunctions _functions;

  AiService(this._functions);

  /// Calls the analyzeJob Cloud Function. Images are sent as raw base64
  /// bytes — job photos aren't uploaded to Storage until the job is
  /// actually submitted, so there's no imageUrl to pass at preview time.
  ///
  /// Never throws a raw FirebaseFunctionsException or lets a malformed
  /// response crash the caller — always throws AiServiceException with a
  /// message that's safe to show directly in the UI.
  Future<JobAiSuggestion> analyzeJob({
    required String description,
    List<String> imagesBase64 = const [],
  }) async {
    final callable = _functions.httpsCallable(
      'analyzeJob',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
    );

    final HttpsCallableResult result;
    try {
      result = await callable.call({
        'description': description,
        'images': imagesBase64,
      });
    } on FirebaseFunctionsException catch (e) {
      throw AiServiceException(_messageForCode(e.code), code: e.code);
    } catch (e) {
      throw const AiServiceException('AI analysis failed. Please try again.');
    }

    try {
      final data = Map<String, dynamic>.from(result.data as Map);
      return JobAiSuggestion(
        suggestedCategory: data['suggestedCategory'] as String,
        confidence: (data['confidence'] as num).toDouble(),
        enhancedDescription: data['enhancedDescription'] as String,
      );
    } catch (_) {
      // The function responded but with an unexpected shape — don't crash
      // the UI on a malformed/empty response.
      throw const AiServiceException('AI analysis returned an unexpected response.');
    }
  }

  String _messageForCode(String? code) {
    switch (code) {
      case 'not-found':
        // The callable endpoint doesn't exist on the deployed project —
        // almost always means the function hasn't been deployed yet.
        return 'AI is currently unavailable. You can still post your job manually.';
      case 'unavailable':
      case 'deadline-exceeded':
        return 'AI service is temporarily unavailable. Please try again, or post your job manually.';
      case 'unauthenticated':
        return 'Please sign in again to use AI analysis.';
      case 'internal':
        return 'AI analysis failed. You can still post your job without it.';
      default:
        return 'AI analysis failed. Please try again.';
    }
  }
}

final aiServiceProvider =
    Provider<AiService>((ref) => AiService(FirebaseFunctions.instance));
