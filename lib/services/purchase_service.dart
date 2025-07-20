import 'dart:async';
import 'dart:convert';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

class PurchaseService {
  final InAppPurchase _iap = InAppPurchase.instance;
  final String _yearlyProductId = 'phone_plus_yearly';
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  Future<void> init() async {
    final bool available = await _iap.isAvailable();
    if (available) {
      _subscription = _iap.purchaseStream.listen(
        (purchases) => _handlePurchaseUpdates(purchases),
        onDone: () => _subscription.cancel(),
        onError: (error) => print('Purchase Stream Error: $error'),
      );
    }
  }

  Future<void> buyYearly() async {
    final ProductDetailsResponse response =
        await _iap.queryProductDetails({_yearlyProductId});
    if (response.notFoundIDs.isNotEmpty) {
      throw Exception('Yearly product not found');
    }
    final PurchaseParam purchaseParam =
        PurchaseParam(productDetails: response.productDetails.first);
    await _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  void _handlePurchaseUpdates(List<PurchaseDetails> purchases) {
    purchases.forEach((purchase) async {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        if (purchase.productID == _yearlyProductId) {
          await _verifyAndGrantAccess(purchase);
        }
        if (purchase.pendingCompletePurchase) {
          await _iap.completePurchase(purchase);
        }
      }
    });
  }

  Future<void> _verifyAndGrantAccess(PurchaseDetails purchase) async {
    final String receipt = purchase.verificationData.serverVerificationData;
    final String sharedSecret = dotenv.env['SHARED_SECRET']!;

    final response = await http.post(
      Uri.parse('https://us-central1-phone-6223e.cloudfunctions.net/verifyReceipt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'receipt-data': receipt,
        'password': sharedSecret,
      }),
    );

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body);
      if (decoded['status'] == 0) {
        final uid = FirebaseAuth.instance.currentUser!.uid;
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'plan': 'yearly',
          'expiresAt': decoded['latest_receipt_info'][0]['expires_date_ms'],
        }, SetOptions(merge: true));
      }
    }
  }

  void dispose() {
    _subscription.cancel();
  }
}
