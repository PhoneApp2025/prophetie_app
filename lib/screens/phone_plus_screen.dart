import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // for kReleaseMode
import 'package:prophetie_app/screens/login_screen.dart';
import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prophetie_app/services/purchase_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math';
import 'package:confetti/confetti.dart';

const String _sharedSecret = '18dc02c00e9d4749b536f17223bdd554';

const pink = Color(0xFFFF2D55);

class PhonePlusScreen extends StatefulWidget {
  const PhonePlusScreen({Key? key}) : super(key: key);

  @override
  _PhonePlusScreenState createState() => _PhonePlusScreenState();
}

class _PhonePlusScreenState extends State<PhonePlusScreen> {
  StreamSubscription<User?>? _authListener;
  final ScrollController _sliderController = ScrollController();
  Timer? _autoScrollTimer;
  StreamSubscription<List<PurchaseDetails>>? _restoreSub;
  // Prevent duplicate delivery (StoreKit 2 duplicate callbacks)
  bool _hasDelivered = false;
  // Bildpfade für Marquee-Banner
  final List<String> imagePaths = [
    'assets/images/banner_14.png',
    'assets/images/banner_14.png',
    'assets/images/banner_14.png',
    'assets/images/banner_14.png',
    'assets/images/banner_14.png',
    'assets/images/banner_14.png',
    'assets/images/banner_14.png',
    'assets/images/banner_14.png',

    // weitere Bildpfade hier eintragen
  ];

  /// Server-side receipt verification via Cloud Function
  Future<Map<String, dynamic>> _verifyReceiptServer(String receiptData) async {
    final user = FirebaseAuth.instance.currentUser;
    final idToken = await user?.getIdToken();
    print("DEBUG: idToken = $idToken");
    final uri = Uri.parse(
      'https://us-central1-phone-6223e.cloudfunctions.net/verifyReceipt',
    );
    // Prepare headers for Apple receipt verification, including StoreKit 2
    final headers = {
      "Content-Type": "application/json",
      "Authorization": "Bearer $idToken",
    };
    // Always send as base64-encoded legacy receipt-data
    final payload = {"receipt-data": receiptData, "password": _sharedSecret};
    final payloadStr = json.encode(payload);
    print('DEBUG: Receipt data length: ${receiptData.length}');
    print(
      'DEBUG: Receipt data sample: ${receiptData.substring(0, min(20, receiptData.length))}',
    );
    print('DEBUG: Payload: $payloadStr');
    final resp = await http.post(uri, headers: headers, body: payloadStr);
    // Debug: log raw response
    print('DEBUG: verifyReceiptServer status=${resp.statusCode}');
    print('DEBUG: verifyReceiptServer body=${resp.body}');
    if (resp.statusCode != 200) {
      throw Exception('Receipt verification HTTP error: ${resp.statusCode}');
    }
    try {
      return json.decode(resp.body) as Map<String, dynamic>;
    } catch (e) {
      throw Exception('Failed to parse receipt verification response: $e');
    }
  }

  static const _kProductID = 'phone_plus_yearly';
  late final PurchaseService _purchaseService;
  late final ConfettiController _confettiController;
  bool _purchasePending = false;

  @override
  void initState() {
    super.initState();
    _purchaseService = PurchaseService();
    _purchaseService.init();
    _authListener = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user == null && mounted) {
        // User logged out: navigate back to login
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
    _startAutoScroll();
    _confettiController = ConfettiController(
      duration: const Duration(seconds: 1),
    );
  }

  @override
  void dispose() {
    _authListener?.cancel();
    _autoScrollTimer?.cancel();
    _sliderController.dispose();
    _confettiController.dispose();
    _purchaseService.dispose();
    super.dispose();
  }

  void _startAutoScroll() {
    const pixelsPerTick = 0.3; // Geschwindigkeit
    _autoScrollTimer = Timer.periodic(const Duration(milliseconds: 14), (_) {
      if (!_sliderController.hasClients) return;
      final maxScroll = _sliderController.position.maxScrollExtent;
      final current = _sliderController.offset;
      double next = current + pixelsPerTick;
      if (next >= maxScroll) {
        _sliderController.jumpTo(0);
      } else {
        _sliderController.jumpTo(next);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    // Debug prints for current user and email
    print('DEBUG: currentUser = ${FirebaseAuth.instance.currentUser}');
    print(
      'DEBUG: currentUser.email = ${FirebaseAuth.instance.currentUser?.email}',
    );
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
      });
      return const SizedBox();
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final bannerWidth = screenWidth * 0.9;
    final bannerHeight = bannerWidth * 0.4; // adjust ratio as needed
    return SafeArea(
      child: Stack(
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirection: -pi / 2, // shoot upwards
              emissionFrequency: 0.2,
              numberOfParticles: 30,
              maxBlastForce: 20,
              minBlastForce: 5,
              gravity: 0.3,
              shouldLoop: false,
              blastDirectionality: BlastDirectionality.explosive,
              colors: const [
                Color(0xFFFF2D55),
                Color(0xFF00C9A7),
                Color(0xFFFFD700),
              ],
            ),
          ),
          // Main Center Content without Card
          Align(
            alignment: Alignment.topCenter,
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Image.asset(
                          Theme.of(context).brightness == Brightness.dark
                              ? 'assets/images/logo_white.png'
                              : 'assets/images/logo.png',
                          height: 24,
                          width: 24,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'PHONĒ+',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.black,
                            letterSpacing: -1.2,
                          ),
                        ),
                      ],
                    ),
                    Container(
                      width: bannerWidth,
                      height: bannerHeight,
                      margin: const EdgeInsets.only(top: 19, bottom: 22),
                      decoration: BoxDecoration(
                        color: Color.fromARGB(255, 232, 232, 232),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        controller: _sliderController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 18,
                        ),
                        itemCount: imagePaths.length,
                        itemBuilder: (context, index) {
                          final imgPath = imagePaths[index % imagePaths.length];
                          return _CardImage(imgPath: imgPath);
                        },
                      ),
                    ),
                    // Hinweis: Du kannst die Bilddateien und Anzahl bei Bedarf anpassen.
                    const SizedBox(height: 18),
                    // Headline
                    RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: TextStyle(
                          color:
                              Theme.of(context).textTheme.bodyLarge?.color ??
                              Colors.black,
                          fontSize: 26,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          const TextSpan(text: 'Entdecke alles,'), // Komma
                          const TextSpan(text: '\n'), // neue Zeile
                          const TextSpan(text: 'was '), // "was "
                          TextSpan(
                            text: 'PHONĒ+',
                            style: const TextStyle(
                              color: Color(0xFFFF2C55),
                              fontSize: 26,
                              fontWeight: FontWeight.w600, // PHONĒ+ jetzt bold
                            ),
                          ),
                          const TextSpan(text: ' dir bietet'), // Rest
                          const TextSpan(text: '.'), // Punkt
                        ],
                      ),
                    ),
                    const SizedBox(height: 34),
                    // Bullet-Points
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        BulletPoint(
                          "Deine Prophetien und Träume dauerhaft speichern und KI-gestützt auswerten.",
                        ),
                        BulletPoint(
                          "Alle Aufnahmen und Notizen sicher an einem Ort.",
                        ),
                        BulletPoint(
                          "Erhalte automatische Erinnerungen an vergangene Eindrücke.",
                        ),
                        BulletPoint(
                          "Teste die App 14 Tage kostenlos und entdecke alle Funktionen.",
                        ),
                      ],
                    ),
                    const SizedBox(height: 30),
                    // Purchase or active subscription UI
                    FutureBuilder<String>(
                      future: _getUserPlanType(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const SizedBox();
                        }
                        if (snapshot.hasError) {
                          return Column(
                            children: [
                              Text(
                                'Fehler beim Laden des Abo-Status:\n${snapshot.error}',
                                style: const TextStyle(color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () {
                                  setState(
                                    () {},
                                  ); // Retry by rebuilding the FutureBuilder
                                },
                                child: const Text('Erneut versuchen'),
                              ),
                            ],
                          );
                        }
                        final plan = snapshot.data;
                        if (plan != null && plan != 'none') {
                          // Already has an active subscription
                          return Column(
                            children: [
                              Center(
                                child: ElevatedButton(
                                  onPressed: null,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.grey,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 14,
                                      horizontal: 24,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Text(
                                    plan == 'monthly'
                                        ? 'Abo aktiv: Monatlich'
                                        : 'Abo aktiv: Jährlich',
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                          );
                        } else {
                          // No active subscription: show purchase UI
                          return Padding(
                            padding: const EdgeInsets.only(top: 40),
                            child: Column(
                              children: [
                                Center(
                                  child: Text(
                                    '24,99 € / Jahr',
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: _purchasePending
                                      ? const CircularProgressIndicator()
                                      : ElevatedButton(
                                          onPressed: () {
                                            _purchaseService.buyYearly();
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: pink,
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 11,
                                              horizontal: 24,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            elevation: 0,
                                          ),
                                          child: const Text(
                                            'PHONĒ+ jetzt starten',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Abo verlängert sich automatisch für 24,99 €/Jahr,\nkündbar jederzeit in den Store-Einstellungen.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                TextButton(
                                  onPressed: () async {
                                    final uri = Uri.parse(
                                      'https://www.notion.so/Term-of-Use-222017fc7cf7800d9b1bddd0c8168cd5?source=copy_link',
                                    );
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    } else {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Konnte Link nicht öffnen',
                                          ),
                                        ),
                                      );
                                    }
                                  },
                                  child: const Text(
                                    'Nutzungsbedingungen anzeigen',
                                    style: TextStyle(
                                      decoration: TextDecoration.underline,
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                TextButton(
                                  onPressed: () {},
                                  child: const Text(
                                    'Käufe wiederherstellen',
                                    style: TextStyle(
                                      decoration: TextDecoration.underline,
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getUserPlanType() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return 'none';
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    final data = doc.data();
    if (data == null) return 'none';
    // Check if subscription has not expired
    final expiresTs = data['expiresAt'] as Timestamp?;
    if (expiresTs != null && expiresTs.toDate().isAfter(DateTime.now())) {
      return data['plan'] as String? ?? 'none';
    }
    // Subscription expired or missing
    return 'none';
  }

  // _checkExistingPlan() method removed
}

// Bullet Point Widget
class BulletPoint extends StatelessWidget {
  final String text;
  const BulletPoint(this.text, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_rounded, color: Color(0xFFFF2D55), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color:
                    Theme.of(context).textTheme.bodyLarge?.color ??
                    Colors.black87,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Card Image Widget ohne Hover/State
class _CardImage extends StatelessWidget {
  final String imgPath;
  const _CardImage({required this.imgPath});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 22,
            spreadRadius: 1,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(0),
        child: Container(
          color: Theme.of(context).cardColor,
          child: Image.asset(
            imgPath,
            width: 70,
            height: 120,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
