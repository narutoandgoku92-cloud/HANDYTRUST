import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/support_ticket_service.dart';
import '../models/support_ticket_model.dart';

final supportTicketServiceProvider = Provider<SupportTicketService>(
  (ref) => SupportTicketService(FirebaseFirestore.instance),
);

final userTicketsProvider = StreamProvider.family<List<SupportTicketModel>, String>(
  (ref, userId) => ref.watch(supportTicketServiceProvider).watchUserTickets(userId),
);

/// All tickets — drives the admin Support tab.
final allTicketsProvider = StreamProvider<List<SupportTicketModel>>(
  (ref) => ref.watch(supportTicketServiceProvider).watchAllTickets(),
);
