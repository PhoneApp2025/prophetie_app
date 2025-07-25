import 'dart:async';
import 'package:purchases_flutter/purchases_flutter.dart';

class PurchaseService {
  static const _apiKey = 'appl_BmgohkROLRDaEyXUtsncvUcsCxN';

  Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(_apiKey));
  }

  Future<List<Offering>> getOfferings() async {
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.all.values.toList();
    } catch (e) {
      print('Error getting offerings: $e');
      return [];
    }
  }

  Future<void> purchasePackage(Package package) async {
    try {
      await Purchases.purchasePackage(package);
    } catch (e) {
      print('Error purchasing package: $e');
    }
  }

  Future<void> restorePurchases() async {
    try {
      await Purchases.restorePurchases();
    } catch (e) {
      print('Error restoring purchases: $e');
    }
  }

  Future<bool> isSubscribed() async {
    final customerInfo = await Purchases.getCustomerInfo();
    return customerInfo.entitlements.active['phone_plus']?.isActive ?? false;
  }

  void dispose() {
    // No-op
  }
}
