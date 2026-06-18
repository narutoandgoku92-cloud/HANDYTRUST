import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/payment_service.dart';
import '../models/payment_model.dart';

final paymentServiceProvider = Provider<PaymentService>((ref) => PaymentService());

final paymentNotifierProvider = Provider((ref) => ref.watch(paymentServiceProvider));

// Example helper to perform payment simulation
final simulatePaymentProvider = FutureProvider.family<PaymentModel, Map<String, dynamic>>((ref, args) async {
  final service = ref.watch(paymentServiceProvider);
  return service.simulatePayment(
    jobId: args['jobId'] as String,
    payerId: args['payerId'] as String,
    artisanId: args['artisanId'] as String,
    amount: args['amount'] as double,
  );
});
