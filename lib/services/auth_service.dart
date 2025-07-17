import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  Future<void> handlePostLogin() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final labelRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels');

    final snapshot = await labelRef.get();

    if (snapshot.docs.isEmpty) {
      await labelRef.doc('Archiv').set({'label': 'Archiv'});
      await labelRef.doc('Prüfen').set({'label': 'Prüfen'});
      print("📌 Standard-Labels wurden hinzugefügt");
    } else {
      print("🔁 Labels bereits vorhanden, kein Setup nötig");
    }
  }

  /// Lädt den aktuellen Abo-Plan des Benutzers
  Future<String> getUserPlan() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'none';
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    final data = doc.data();
    return (data != null && data.containsKey('plan'))
        ? data['plan'] as String
        : 'none';
  }

  /// Meldet den Benutzer mit E-Mail und Passwort an und führt danach Post-Login-Setup aus
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await FirebaseAuth.instance.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    await handlePostLogin(); // Standard-Labels und Setup
    return credential;
  }

  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    await handlePostLogin(); // Standard-Labels und Setup
    return credential;
  }
}
