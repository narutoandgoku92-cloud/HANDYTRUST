import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import '../../core/services/paystack_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/escrow_provider.dart';
import '../../models/job_model.dart';
import '../../theme/app_theme.dart';

final _paystackServiceProvider = Provider<PaystackService>(
  (ref) => PaystackService(Dio(), FirebaseFirestore.instance),
);

class PaymentScreen extends ConsumerStatefulWidget {
  final String jobId;

  const PaymentScreen({super.key, required this.jobId});

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  final _amountController = TextEditingController();
  bool _loading = false;
  bool _amountInitialized = false;
  String? _error;

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final jobAsync = ref.watch(jobStreamProvider(widget.jobId));

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Escrow Payment')),
      body: jobAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (job) {
          if (job == null) return const Center(child: Text('Job not found'));
          return _buildBody(context, job);
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, JobModel job) {
    if (!_amountInitialized) {
      _amountInitialized = true;
      _amountController.text = job.agreedAmount?.toStringAsFixed(0) ?? '';
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _escrowInfoCard(),
          const SizedBox(height: 24),
          const Text('Payment Amount',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                fontFamily: 'Inter',
              )),
          const SizedBox(height: 8),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              prefixText: '₦ ',
              hintText: 'Enter amount',
              errorText: _error,
            ),
          ),
          const SizedBox(height: 12),
          _feeBreakdown(),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _loading ? null : () => _initiatePayment(job),
            child: _loading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : const Text('Lock Funds in Escrow'),
          ),
          const SizedBox(height: 16),
          const _EscrowGuaranteeRow(),
        ],
      ),
    );
  }

  Widget _escrowInfoCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.colors.accentSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: context.colors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: context.colors.accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.lock_outline_rounded,
                  color: context.colors.accent, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Escrow Protected',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: context.colors.textPrimary,
                        fontFamily: 'Inter',
                      )),
                  SizedBox(height: 4),
                  Text(
                    'Your money is held safely. Released only when you confirm the work is done.',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                      fontFamily: 'Inter',
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _feeBreakdown() {
    final amount = double.tryParse(_amountController.text) ?? 0;
    final platformFee = amount * 0.05;
    final total = amount + platformFee;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.colors.surfaceVariant,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _feeRow('Service amount', '₦${amount.toStringAsFixed(0)}'),
          const SizedBox(height: 6),
          _feeRow('Platform fee (5%)', '₦${platformFee.toStringAsFixed(0)}'),
          const Divider(height: 16),
          _feeRow('Total charged', '₦${total.toStringAsFixed(0)}',
              bold: true),
        ],
      ),
    );
  }

  Widget _feeRow(String label, String value, {bool bold = false}) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: 13,
                color: bold ? context.colors.textPrimary : context.colors.textSecondary,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
                fontFamily: 'Inter',
              )),
          Text(value,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: context.colors.textPrimary,
                fontFamily: 'Inter',
              )),
        ],
      );

  Future<void> _initiatePayment(JobModel job) async {
    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount < 100) {
      setState(() => _error = 'Minimum payment is ₦100');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final payerId = ref.read(authStateChangesProvider).value?.uid ?? '';
      if (payerId.isEmpty) throw Exception('Not signed in');

      // Transition job → paymentPending
      await ref.read(escrowNotifierProvider.notifier).initPayment(job.id, amount);

      // Try real Paystack; fall back to demo simulation if not configured
      try {
        final user = ref.read(currentUserProvider).asData?.value;
        final email = user?.email ?? 'demo@handytrust.ng';
        final paystack = ref.read(_paystackServiceProvider);
        final payment = await paystack.initializeTransaction(
          jobId: job.id,
          payerId: payerId,
          artisanId: job.artisanId,
          amountNaira: amount,
          customerEmail: email,
        );
        if (!mounted) return;
        if (payment.authorizationUrl != null) {
          context.push('/payment/${job.id}/webview', extra: {
            'url': payment.authorizationUrl!,
            'reference': payment.paystackReference!,
          });
        }
      } catch (_) {
        // Paystack not configured — demo simulation
        if (!mounted) return;
        await _simulatePaymentAndProceed(job.id);
      }
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _simulatePaymentAndProceed(String jobId) async {
    if (!mounted) return;
    // Hand off to DemoEscrowScreen for the full animated payment experience
    context.push('/demo-payment/$jobId', extra: {'autoStart': true});
  }
}

class _EscrowGuaranteeRow extends StatelessWidget {
  const _EscrowGuaranteeRow();

  @override
  Widget build(BuildContext context) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.security_rounded, size: 14, color: context.colors.textTertiary),
          SizedBox(width: 6),
          Text(
            'Secured by Paystack · Escrow by HandyTrust',
            style: TextStyle(
              fontSize: 11,
              color: context.colors.textTertiary,
              fontFamily: 'Inter',
            ),
          ),
        ],
      );
}
