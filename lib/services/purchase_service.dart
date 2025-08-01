import 'dart:async';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:flutter/services.dart';

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

  Future<bool> purchaseDefaultPackage() async {
    try {
      final offerings = await this.getOfferings();
      if (offerings.isEmpty) return false;

      final offering = offerings.firstWhere(
        (o) => o.identifier == 'default',
        orElse: () => offerings.first,
      );

      final package = offering.availablePackages.first;

      final customerInfo = await Purchases.purchasePackage(package);

      // Überprüfe, ob das Abo wirklich aktiv ist
      return customerInfo.entitlements.active['phone_plus']?.isActive ?? false;
    } on PlatformException catch (e) {
      if (e.code == 'purchase_cancelled') {
        print('Kauf wurde vom Nutzer abgebrochen');
        return false;
      } else {
        print('PlatformException: ${e.code}');
        return false;
      }
    } catch (e) {
      print('Kauf fehlgeschlagen: $e');
      return false;
    }
  }
}
