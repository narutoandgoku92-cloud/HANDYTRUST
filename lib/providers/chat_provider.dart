import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/chat_service.dart';
import '../core/services/job_service.dart';
import '../core/services/storage_service.dart';
import '../models/audit_log_model.dart';
import '../models/job_mutation_context.dart';
import '../models/message_model.dart';
import 'job_service_provider.dart';

final chatServiceProvider = Provider<ChatService>(
  (ref) => ChatService(FirebaseFirestore.instance),
);

/// Real-time message stream for a job.
final messagesStreamProvider =
    StreamProvider.family<List<MessageModel>, String>((ref, jobId) {
  return ref.watch(chatServiceProvider).messagesStream(jobId);
});

/// Send-state notifier — tracks in-flight send operations.
///
/// [sendNegotiation] routes through [JobService], which writes the negotiation
/// message AND updates job.agreedAmount atomically in a single Firestore
/// transaction. No split-write race condition is possible.
class ChatNotifier extends StateNotifier<AsyncValue<void>> {
  final ChatService _chat;
  final StorageService _storage;
  final JobService _jobService;
  final String jobId;
  final String senderId;
  final String receiverId;
  final ActorRole senderRole;

  ChatNotifier({
    required ChatService chat,
    required StorageService storage,
    required JobService jobService,
    required this.jobId,
    required this.senderId,
    required this.receiverId,
    required this.senderRole,
  })  : _chat = chat,
        _storage = storage,
        _jobService = jobService,
        super(const AsyncData(null));

  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _chat.sendText(
          jobId: jobId,
          senderId: senderId,
          receiverId: receiverId,
          text: text.trim(),
        ));
  }

  Future<void> sendImageBytes(Uint8List bytes) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final url = await _storage.uploadJobImageBytes(
        jobId: jobId,
        userId: senderId,
        index: DateTime.now().millisecondsSinceEpoch,
        bytes: bytes,
      );
      await _chat.sendImage(
        jobId: jobId,
        senderId: senderId,
        receiverId: receiverId,
        imageUrl: url,
      );
    });
  }

  /// Atomically sends a negotiation message and records [amount] on the job.
  /// Delegates entirely to [JobService.sendNegotiation] — one transaction,
  /// all three writes (message, agreedAmount, audit log) commit together or
  /// are all rolled back.
  Future<void> sendNegotiation(double amount) async {
    state = const AsyncLoading();
    final ctx = JobMutationContext(
      actorId: senderId,
      actorRole: senderRole,
      actionType: JobActionType.negotiationProposal,
    );
    state = await AsyncValue.guard(
        () => _jobService.sendNegotiation(ctx, jobId, receiverId, amount));
  }
}

final storageServiceProvider = Provider<StorageService>(
  (_) => StorageService(),
);

final chatNotifierProvider = StateNotifierProvider.family<ChatNotifier,
    AsyncValue<void>, ChatNotifierParams>((ref, params) {
  return ChatNotifier(
    chat: ref.watch(chatServiceProvider),
    storage: ref.watch(storageServiceProvider),
    jobService: ref.watch(jobServiceProvider),
    jobId: params.jobId,
    senderId: params.senderId,
    receiverId: params.receiverId,
    senderRole: params.senderRole,
  );
});

class ChatNotifierParams {
  final String jobId;
  final String senderId;
  final String receiverId;
  final ActorRole senderRole;

  const ChatNotifierParams({
    required this.jobId,
    required this.senderId,
    required this.receiverId,
    required this.senderRole,
  });

  @override
  bool operator ==(Object other) =>
      other is ChatNotifierParams &&
      other.jobId == jobId &&
      other.senderId == senderId &&
      other.receiverId == receiverId &&
      other.senderRole == senderRole;

  @override
  int get hashCode => Object.hash(jobId, senderId, receiverId, senderRole);
}
