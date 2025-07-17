import 'package:in_app_purchase/in_app_purchase.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class InAppPurchaseService {
  bool _isInTrial = false;
  bool get isInTrial => _isInTrial;
  static final InAppPurchaseService _instance =
      InAppPurchaseService._internal();
  factory InAppPurchaseService() => _instance;
  InAppPurchaseService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  final String _yearlyProductId = 'phone_plus_yearly';
  final String _monthlyProductId = 'phone_plus_monthly';
  late StreamSubscription<List<PurchaseDetails>> _subscription;

  bool isAvailable = false;
  bool hasPremium = false;
  List<ProductDetails> products = [];

  Future<void> init() async {
    isAvailable = await _iap.isAvailable();
    if (!isAvailable) return;

    await _getProducts();

    _subscription = _iap.purchaseStream.listen(
      (purchases) {
        _handlePurchaseUpdates(purchases);
      },
      onDone: () {
        _subscription.cancel();
      },
      onError: (error) {
        print('Purchase Stream Error: $error');
      },
    );
  }

  Future<void> _getProducts() async {
    final response = await _iap.queryProductDetails({
      _yearlyProductId,
      _monthlyProductId,
    });
    products = response.productDetails;
  }

  void buyPremium({bool yearly = true}) {
    final id = yearly ? _yearlyProductId : _monthlyProductId;
    final product = products.firstWhere(
      (p) => p.id == id,
      orElse: () => throw Exception('Produkt nicht gefunden'),
    );
    final purchaseParam = PurchaseParam(productDetails: product);
    _iap.buyNonConsumable(purchaseParam: purchaseParam);
  }

  void _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    for (final purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        if (purchase.productID == _yearlyProductId ||
            purchase.productID == _monthlyProductId) {
          hasPremium = true;
          final user = FirebaseAuth.instance.currentUser;
          if (user != null) {
            final userDoc = FirebaseFirestore.instance
                .collection('users')
                .doc(user.uid);
            final docSnapshot = await userDoc.get();
            final data = docSnapshot.data();
            DateTime? trialStart;
            if (data != null && data.containsKey('trialStart')) {
              trialStart = DateTime.tryParse(data['trialStart']);
            }
            if (trialStart == null) {
              trialStart = DateTime.now();
              await userDoc.set({
                'trialStart': trialStart.toIso8601String(),
              }, SetOptions(merge: true));
            }
            _isInTrial = DateTime.now().difference(trialStart).inDays < 14;
          } else {
            _isInTrial = true;
          }
          _iap.completePurchase(purchase);
        }
      }
    }
  }

  void dispose() {
    _subscription.cancel();
  }

  Future<void> checkTrialStatus() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      if (data != null && data.containsKey('trialStart')) {
        final start = DateTime.tryParse(data['trialStart']);
        if (start != null) {
          _isInTrial = DateTime.now().difference(start).inDays < 14;
        }
      }
    }
  }
}
