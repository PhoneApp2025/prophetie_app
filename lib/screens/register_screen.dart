import 'dart:io';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:prophetie_app/screens/auth_gate.dart';
import 'package:prophetie_app/services/auth_service.dart';
import 'package:prophetie_app/main.dart';

import 'package:shared_preferences/shared_preferences.dart';

const String kTermsVersion = '2025-06-30';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  DateTime? _acceptedAt;
  bool _accepted = false;
  bool _isLoading = false;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  Future<void> _persistPreConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('preConsentAccepted', true);
    await prefs.setString('preConsentVersion', kTermsVersion);
    await prefs.setString('preConsentAcceptedAt', DateTime.now().toUtc().toIso8601String());
  }

  Future<void> _recordConsentToUser(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    final preAt = prefs.getString('preConsentAcceptedAt');
    final preVersion = prefs.getString('preConsentVersion');
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'termsAccepted': true,
      'termsVersion': preVersion ?? kTermsVersion,
      'termsAcceptedAtClient': preAt ?? _acceptedAt?.toUtc().toIso8601String(),
      'termsAcceptedAtServer': FieldValue.serverTimestamp(),
      'consentSource': 'register_screen',
    }, SetOptions(merge: true));
  }


  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showHinweise() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.black,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
          child: Text(
            'Hier stehen die Nutzungshinweise. Lies sie aufmerksam durch.',
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      ),
    );
  }

  void _showDatenschutz() async {
    final url = Uri.parse(
      'https://www.notion.so/Terms-of-Use-Privacy-Notice-21c017fc7cf7802ba0a9e2b7680a8b4a?source=copy_link',
    );
    await launchUrl(url, mode: LaunchMode.inAppWebView);
  }

  Future<void> _signInWithGoogle() async {
    if (!_accepted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isLoading = true;
    });
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        throw Exception('Google-Anmeldung abgebrochen.');
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final user = userCredential.user;
      if (user != null) {
        await _recordConsentToUser(user.uid);
        await AuthService().handlePostLogin();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/authGate');
      }
    } catch (e) {
      if (!mounted) return;
      showFlushbar('Google-Anmeldung fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _signInWithApple() async {
    if (!_accepted) return;
    HapticFeedback.selectionClick();
    setState(() {
      _isLoading = true;
    });
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      final oauthCredential = OAuthProvider("apple.com").credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        oauthCredential,
      );
      final user = userCredential.user;
      if (user != null) {
        await _recordConsentToUser(user.uid);
        await AuthService().handlePostLogin();
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/authGate');
      }
    } catch (e) {
      if (!mounted) return;
      showFlushbar('Apple-Anmeldung fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black),
          Container(color: Colors.black.withOpacity(0.5)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 36),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Nun beginnt Verwalterschaft",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: MediaQuery.of(context).size.width > 600 ? 28 : 22,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Erstelle einen Account, um Prophetien und Träume zu speichern. Bitte lese zunächst die Nutzungshinweise durch und akzeptiere sie, um fortzufahren.",
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: MediaQuery.of(context).size.width > 600 ? 18 : 14,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.left,
                    ),
                  ),
                  // Spacer/Expanded to push content down
                  Expanded(child: Container()),
                  Expanded(
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 22),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FadeTransition(
                              opacity: _fadeAnimation,
                              child: Column(
                                children: [
                                  ElevatedButton(
                                    onPressed: (_accepted && !_isLoading)
                                        ? _signInWithGoogle
                                        : null,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF232323),
                                      minimumSize: const Size(
                                        double.infinity,
                                        52,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(13),
                                      ),
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 0,
                                      ),
                                      alignment: Alignment.centerLeft,
                                    ),
                                    child: _isLoading
                                        ? const Center(
                                            child: SizedBox(
                                              height: 24,
                                              width: 24,
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                              ),
                                            ),
                                          )
                                        : Row(
                                            children: [
                                              const FaIcon(
                                                FontAwesomeIcons.google,
                                                color: Colors.white,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 15),
                                              Expanded(
                                                child: Text(
                                                  "Mit Google einloggen",
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  textAlign: TextAlign.center,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                  const SizedBox(height: 10),
                                  if (Platform.isIOS)
                                    ElevatedButton(
                                      onPressed: (_accepted && !_isLoading)
                                          ? _signInWithApple
                                          : null,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(
                                          0xFF232323,
                                        ),
                                        minimumSize: const Size(
                                          double.infinity,
                                          52,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            13,
                                          ),
                                        ),
                                        elevation: 0,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 0,
                                        ),
                                        alignment: Alignment.centerLeft,
                                      ),
                                      child: _isLoading
                                          ? const Center(
                                              child: SizedBox(
                                                height: 24,
                                                width: 24,
                                                child:
                                                    CircularProgressIndicator(
                                                      color: Colors.white,
                                                    ),
                                              ),
                                            )
                                          : Row(
                                              children: [
                                                const FaIcon(
                                                  FontAwesomeIcons.apple,
                                                  color: Colors.white,
                                                  size: 22,
                                                ),
                                                const SizedBox(width: 15),
                                                Expanded(
                                                  child: Text(
                                                    "Mit Apple einloggen",
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                ),
                                              ],
                                            ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 15),
                            // Checkbox
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF232323),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 7,
                              ),
                              margin: const EdgeInsets.only(bottom: 4),
                              child: Row(
                                children: [
                                  Checkbox(
                                    activeColor: Color(0xFFFF2D55),
                                    value: _accepted,
                                    onChanged: (val) async {
                                      final newVal = val ?? false;
                                      setState(() {
                                        _accepted = newVal;
                                        if (newVal) {
                                          _acceptedAt = DateTime.now();
                                        } else {
                                          _acceptedAt = null;
                                        }
                                      });
                                      if (newVal) {
                                        await _persistPreConsent();
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  const Flexible(
                                    child: Text(
                                      "Ich stimme den Bedingungen zu.",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Datenschutz Row (zentriert)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                TextButton(
                                  onPressed: _showDatenschutz,
                                  child: const Text(
                                    "Nutzungsbedingungen & Datenschutz",
                                    style: TextStyle(color: Colors.white60),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
