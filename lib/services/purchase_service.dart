import 'dart:async';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PurchaseService {
  PurchaseService._internal();
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;

  // Use your public SDK key here (appl_... or goog_...)
  static const _apiKey = 'appl_BmgohkROLRDaEyXUtsncvUcsCxN';

  static const _entitlementId =
      'PHONĒ+'; // exakt wie im RevenueCat-Entitlement (Achtung: Unicode-E)
  final ValueNotifier<bool> isSubscribedNotifier = ValueNotifier(false);

  // Callback to let the app (e.g. a Provider) know about premium status changes
  void Function(bool isPremium)? onPremiumChanged;

  /// Optional: Mirror Entitlement-Status nach Firestore (users/{uid}).
  bool enableFirestoreSync = true;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  void _updateSubscriptionFrom(CustomerInfo info) {
    final active = info.entitlements.active.containsKey(_entitlementId);
    isSubscribedNotifier.value = active;

    // Notify external listeners (e.g., PremiumProvider via a bound callback)
    try {
      final cb = onPremiumChanged;
      if (cb != null) cb(active);
    } catch (_) {}

    if (!enableFirestoreSync) return;

    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return; // nicht eingeloggt → nichts zu spiegeln

      final ent = info.entitlements.active[_entitlementId];
      final data = <String, dynamic>{
        'premium': {
          'isActive': ent != null,
          'productId': ent?.productIdentifier,
          'expiresAt': (() {
            final dynamic exp = ent?.expirationDate;
            if (exp == null) return null;
            if (exp is DateTime) return exp.toIso8601String();
            if (exp is String) return exp; // bereits ISO-String
            return exp.toString(); // Fallback
          })(),
          'updatedAt': FieldValue.serverTimestamp(),
          'source': 'revenuecat',
        },
      };
      _db.collection('users').doc(uid).set(data, SetOptions(merge: true));
    } catch (_) {
      // still fail-safe, UI bleibt korrekt über isSubscribedNotifier
    }
  }

  /// Initialize the SDK without external listener but keep internal updates.
  Future<void> init() async {
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(_apiKey));

    // Seed current state
    try {
      final info = await Purchases.getCustomerInfo();
      _updateSubscriptionFrom(info);
    } catch (_) {}

    // Internal listener keeps UI in sync
    Purchases.addCustomerInfoUpdateListener((info) {
      _updateSubscriptionFrom(info);
    });
  }

  /// Initialize the SDK and register a customer info update listener.
  Future<void> initWithListener(
    void Function(CustomerInfo) onCustomerInfoUpdated,
  ) async {
    await Purchases.setLogLevel(LogLevel.debug);
    await Purchases.configure(PurchasesConfiguration(_apiKey));

    // Seed current state
    try {
      final info = await Purchases.getCustomerInfo();
      _updateSubscriptionFrom(info);
      onCustomerInfoUpdated(info);
    } catch (_) {}

    Purchases.addCustomerInfoUpdateListener((info) {
      _updateSubscriptionFrom(info);
      onCustomerInfoUpdated(info);
    });
  }

  /// Fetch all offerings from RevenueCat.
  Future<Offerings> getOfferings() async {
    return await Purchases.getOfferings();
  }

  /// Fetches the latest CustomerInfo from RevenueCat.
  Future<CustomerInfo> getCustomerInfo() async {
    return await Purchases.getCustomerInfo();
  }

  /// Present the UI paywall for the given offering ID.
  /// Throws if the offering is not found.
  Future<void> presentPaywall({required String offeringId}) async {
    final offerings = await getOfferings();
    final offering = offerings.all[offeringId] ?? offerings.current;
    if (offering != null) {
      await RevenueCatUI.presentPaywall(offering: offering);
      // Nach Paywall den Status sicher aktualisieren
      try {
        final info = await Purchases.getCustomerInfo();
        _updateSubscriptionFrom(info);
      } catch (_) {}
    } else {
      throw Exception('Offering "$offeringId" not found');
    }
  }

  /// Purchase a specific package and return the updated CustomerInfo.
  Future<CustomerInfo> purchasePackage(Package package) async {
    try {
      final customerInfo = await Purchases.purchasePackage(package);
      _updateSubscriptionFrom(customerInfo);
      return customerInfo;
    } catch (e) {
      debugPrint('Error purchasing package: $e');
      rethrow;
    }
  }

  /// Restore previous purchases.
  Future<void> restorePurchases() async {
    try {
      await Purchases.restorePurchases();
      try {
        final info = await Purchases.getCustomerInfo();
        _updateSubscriptionFrom(info);
      } catch (_) {}
    } catch (e) {
      debugPrint('Error restoring purchases: $e');
    }
  }

  /// Check if the entitlement is active. Also updates the notifier.
  Future<bool> isSubscribed() async {
    final info = await Purchases.getCustomerInfo();
    _updateSubscriptionFrom(info);
    return info.entitlements.active.containsKey(_entitlementId);
  }

  /// Dispose any resources if needed.
  void dispose() {
    // No-op for now.
  }
}
