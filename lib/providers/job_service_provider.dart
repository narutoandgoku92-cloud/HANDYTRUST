import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/job_service.dart';

/// Single Riverpod provider for [JobService].
///
/// Imported by both escrow_provider.dart and chat_provider.dart so they share
/// the same instance and there is no ambiguity about which write layer is active.
final jobServiceProvider = Provider<JobService>(
  (ref) => JobService(FirebaseFirestore.instance),
);
