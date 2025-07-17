import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../widgets/main_navigation.dart';
import '../screens/profil_screen.dart';
import 'login_screen.dart';
import '../services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'phone_plus_screen.dart';

final googleSignIn = GoogleSignIn(
  scopes: [
    'https://www.googleapis.com/auth/drive.file',
    'https://www.googleapis.com/auth/drive.appdata',
  ],
);

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
              final user = FirebaseAuth.instance.currentUser!;
              // Standard-Labels initialisieren
              final labelsRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('labels');
              labelsRef.get().then((snap) {
                if (snap.docs.isEmpty) {
                  labelsRef.doc('Archiv').set({'label': 'Archiv'});
                  labelsRef.doc('Prüfen').set({'label': 'Prüfen'});
                }
              });
              return const MainNavigation();
            } else {
              return const LoginScreen();
            }
          },
        );
      },
    );
  }
}

Future<void> reAuthenticateWithGoogle() async {
  try {
    await googleSignIn.disconnect();
    await googleSignIn.signOut();
    final account = await googleSignIn.signIn();
    print("🔁 Reauthentifiziert als: ${account?.email}");
  } catch (e) {
    print("⚠️ Fehler bei Reauthentifizierung: $e");
  }
}
