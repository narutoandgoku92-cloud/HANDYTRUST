import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/demo_escrow_service.dart';

// ── Service provider ──────────────────────────────────────────────────────────

final demoEscrowServiceProvider = Provider<DemoEscrowService>(
  (ref) => DemoEscrowService(FirebaseFirestore.instance),
);

// ── State ─────────────────────────────────────────────────────────────────────

enum DemoPaymentStep { idle, processing, success, error }

class DemoPaymentState {
  final DemoPaymentStep step;
  final String? error;

  const DemoPaymentState({
    this.step = DemoPaymentStep.idle,
    this.error,
  });

  DemoPaymentState copyWith({DemoPaymentStep? step, String? error}) =>
      DemoPaymentState(
        step: step ?? this.step,
        error: error,
      );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

class DemoPaymentNotifier extends StateNotifier<DemoPaymentState> {
  final DemoEscrowService _service;
  final String _jobId;

  DemoPaymentNotifier(this._service, this._jobId)
      : super(const DemoPaymentState());

  Future<void> startPayment(String payerUid) async {
    // Guard: only start from idle state
    if (state.step != DemoPaymentStep.idle) return;
    state = const DemoPaymentState(step: DemoPaymentStep.processing);
    try {
      await _service.startDemoEscrowPayment(_jobId, payerUid: payerUid);
      state = const DemoPaymentState(step: DemoPaymentStep.success);
    } catch (e) {
      state = DemoPaymentState(
        step: DemoPaymentStep.error,
        error: e.toString(),
      );
    }
  }

  void reset() => state = const DemoPaymentState();
}

final demoPaymentNotifierProvider = StateNotifierProvider.family<
    DemoPaymentNotifier, DemoPaymentState, String>(
  (ref, jobId) =>
      DemoPaymentNotifier(ref.watch(demoEscrowServiceProvider), jobId),
);

// ── Real-time raw job stream ──────────────────────────────────────────────────
// Separate from jobStreamProvider (which returns JobModel) so the demo screen
// can read escrow.* and payment.* sub-fields that are not modelled in JobModel.

final jobRawStreamProvider =
    StreamProvider.family<DocumentSnapshot<Map<String, dynamic>>, String>(
  (ref, jobId) => ref.watch(demoEscrowServiceProvider).watchJobRaw(jobId),
);
