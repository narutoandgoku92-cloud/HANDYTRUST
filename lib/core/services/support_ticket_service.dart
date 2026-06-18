import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/support_ticket_model.dart';
import '../utils/safe_firestore.dart';

/// Write layer for /support_tickets — a self-contained collection unrelated
/// to job mutations, so it does not go through JobService (mirrors
/// PortfolioService / VerificationService, which each own their collection).
class SupportTicketService {
  final FirebaseFirestore _db;

  SupportTicketService(this._db);

  CollectionReference<Map<String, dynamic>> get _ticketsCol =>
      _db.collection('support_tickets');

  Future<void> createTicket({
    required String userId,
    required String userName,
    required String subject,
    required String message,
  }) async {
    await _ticketsCol.add({
      'userId': userId,
      'userName': userName,
      'subject': subject,
      'message': message,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Stream<List<SupportTicketModel>> watchUserTickets(String userId) => safeStream(
        _ticketsCol.where('userId', isEqualTo: userId),
        (d) => SupportTicketModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'userTickets:$userId',
      ).map((tickets) => tickets..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  /// All tickets, newest-first — drives the admin Support tab.
  Stream<List<SupportTicketModel>> watchAllTickets() => safeStream(
        _ticketsCol,
        (d) => SupportTicketModel.fromJson({...d.data(), 'id': d.id}),
        debugLabel: 'allTickets',
      ).map((tickets) => tickets..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

  Future<void> resolveTicket({
    required String ticketId,
    required String adminResponse,
  }) async {
    await _ticketsCol.doc(ticketId).update({
      'status': 'resolved',
      'adminResponse': adminResponse,
      'resolvedAt': FieldValue.serverTimestamp(),
    });
  }
}
