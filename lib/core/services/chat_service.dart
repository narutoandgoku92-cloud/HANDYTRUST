import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/message_model.dart';
import '../utils/safe_firestore.dart';

class ChatService {
  final FirebaseFirestore _db;

  ChatService(this._db);

  CollectionReference<Map<String, dynamic>> _messages(String jobId) =>
      _db.collection('jobs').doc(jobId).collection('messages');

  /// Real-time message stream for a job — ordered oldest-first
  Stream<List<MessageModel>> messagesStream(String jobId) => safeStream(
        _messages(jobId).orderBy('createdAt', descending: false),
        (d) => MessageModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'messages:$jobId',
      );

  Future<void> sendText({
    required String jobId,
    required String senderId,
    required String receiverId,
    required String text,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: senderId,
      receiverId: receiverId,
      text: text,
      type: MessageType.text,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> sendImage({
    required String jobId,
    required String senderId,
    required String receiverId,
    required String imageUrl,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: senderId,
      receiverId: receiverId,
      text: '📷 Image',
      type: MessageType.image,
      imageUrl: imageUrl,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> sendNegotiation({
    required String jobId,
    required String senderId,
    required String receiverId,
    required double proposedAmount,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: senderId,
      receiverId: receiverId,
      text: '💰 Price proposal: ₦${proposedAmount.toStringAsFixed(0)}',
      type: MessageType.negotiation,
      proposedAmount: proposedAmount,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> sendSystemMessage({
    required String jobId,
    required String text,
  }) async {
    final id = _messages(jobId).doc().id;
    final msg = MessageModel(
      id: id,
      jobId: jobId,
      senderId: 'system',
      receiverId: 'all',
      text: text,
      type: MessageType.system,
      createdAt: DateTime.now(),
    );
    await _messages(jobId).doc(id).set(msg.toJson());
  }

  Future<void> markAsRead(String jobId, String messageId) =>
      _messages(jobId).doc(messageId).update({'isRead': true});

  Future<int> unreadCount(String jobId, String userId) async {
    final snap = await _messages(jobId)
        .where('receiverId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .count()
        .get();
    return snap.count ?? 0;
  }
}
