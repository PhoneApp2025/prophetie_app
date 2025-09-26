import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../widgets/main_navigation.dart';
import 'login_screen.dart';
import 'register_screen.dart' show kTermsVersion;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:prophetie_app/main.dart';

final googleSignIn = GoogleSignIn(
  scopes: [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive.appdata',
  ],
);

final Uri kLegalUrl = Uri.parse('https://www.notion.so/Terms-of-Use-Privacy-Notice-21c017fc7cf7802ba0a9e2b7680a8b4a?source=copy_link');

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Future<void> _initializeFirebase;

  @override
  void initState() {
    super.initState();
    _initializeFirebase = Firebase.initializeApp();
  }

  Future<void> _openLegal() async {
    try {
      final can = await canLaunchUrl(kLegalUrl);
      if (!can) {
        if (mounted) {
          showFlushbar('Konnte die Seite nicht öffnen.');
        }
        return;
      }
      await launchUrl(kLegalUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        showFlushbar('Fehler beim Öffnen der Seite.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _initializeFirebase,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return StreamBuilder<User?>(
          stream: FirebaseAuth.instance.authStateChanges(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            } else if (snapshot.hasData) {
              return FutureBuilder<bool>(
                future: _needsReconsent(snapshot.data!),
                builder: (context, reconsentSnapshot) {
                  if (reconsentSnapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  } else if (reconsentSnapshot.hasError) {
                    return Scaffold(
                      body: Center(child: Text('Fehler beim Überprüfen der Nutzungsbedingungen')),
                    );
                  } else if (reconsentSnapshot.data == true) {
                    // Show reconsent dialog
                    return Scaffold(
                      body: Center(
                        child: _showReconsentDialog(snapshot.data!),
                      ),
                    );
                  } else {
                    return const MainNavigation();
                  }
                },
              );
            } else {
              return const LoginScreen();
            }
          },
        );
      },
    );
  }

  Future<bool> _needsReconsent(User user) async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    final data = doc.data();
    if (data == null) return true;
    final termsVersion = data['termsVersion'];
    if (termsVersion == null) return true;
    if (termsVersion != kTermsVersion) return true;
    return false;
  }

  Widget _showReconsentDialog(User user) {
    return AlertDialog(
      title: const Text('Nutzungsbedingungen aktualisiert'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Die Nutzungsbedingungen wurden aktualisiert. Sie können die Informationen ansehen und müssen ihnen zustimmen, um die App weiter zu nutzen.',
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _openLegal,
            icon: const Icon(Icons.open_in_new),
            label: const Text('Terms of Use & Privacy Policy ansehen'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _openLegal,
          child: const Text('Ansehen'),
        ),
        TextButton(
          onPressed: () async {
            await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
              'termsAccepted': true,
              'termsVersion': kTermsVersion,
              'termsAcceptedAtServer': FieldValue.serverTimestamp(),
            });
            if (mounted) {
              Navigator.of(context).pop();
              setState(() {});
            }
          },
          child: const Text('Zustimmen'),
        ),
      ],
    );
  }
}