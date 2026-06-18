import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import '../../models/payment_model.dart';

/// Integrates with Paystack REST API directly (no native SDK needed).
/// Fund flow: Customer pays → escrow held in Paystack balance →
///   Cloud Function releases to artisan after confirmed completion.
class PaystackService {
  final Dio _dio;
  final FirebaseFirestore _db;

  // Store key in env or Firebase Remote Config — never in source
  static const _baseUrl = 'https://api.paystack.co';

  PaystackService(this._dio, this._db);

  /// Step 1: Initialize transaction → get authorization URL for WebView
  Future<PaymentModel> initializeTransaction({
    required String jobId,
    required String payerId,
    required String artisanId,
    required double amountNaira,
    required String customerEmail,
  }) async {
    final secretKey = await _getSecretKey();
    final amountKobo = (amountNaira * 100).toInt();
    final paymentId = _db.collection('payments').doc().id;

    final response = await _dio.post(
      '$_baseUrl/transaction/initialize',
      data: {
        'email': customerEmail,
        'amount': amountKobo,
        'currency': 'NGN',
        'reference': paymentId,
        'metadata': {
          'jobId': jobId,
          'payerId': payerId,
          'artisanId': artisanId,
          'custom_fields': [
            {
              'display_name': 'Job ID',
              'variable_name': 'job_id',
              'value': jobId,
            }
          ],
        },
        'channels': ['card', 'bank', 'ussd', 'bank_transfer'],
      },
      options: Options(headers: {'Authorization': 'Bearer $secretKey'}),
    );

    final data = response.data['data'] as Map<String, dynamic>;
    final payment = PaymentModel(
      id: paymentId,
      jobId: jobId,
      payerId: payerId,
      artisanId: artisanId,
      amount: amountNaira,
      status: PaymentStatus.pending,
      paystackReference: data['reference'] as String,
      paystackAccessCode: data['access_code'] as String,
      authorizationUrl: data['authorization_url'] as String,
      createdAt: DateTime.now(),
    );

    await _db.collection('payments').doc(paymentId).set(payment.toJson());
    return payment;
  }

  /// Step 2: Verify transaction after WebView callback
  Future<bool> verifyTransaction(String reference) async {
    final secretKey = await _getSecretKey();

    final response = await _dio.get(
      '$_baseUrl/transaction/verify/$reference',
      options: Options(headers: {'Authorization': 'Bearer $secretKey'}),
    );

    final data = response.data['data'] as Map<String, dynamic>;
    final status = data['status'] as String;
    return status == 'success';
  }

  Future<String> _getSecretKey() async {
    final doc = await _db.collection('config').doc('paystack').get();
    final key = doc.data()?['secretKey'] as String?;
    if (key == null || key.isEmpty) {
      throw Exception('Paystack secret key not configured in Firestore config/paystack');
    }
    return key;
  }
}
