import '../models/prophetie.dart';
import '../models/traum.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/SentRecording.dart';

final List<SentRecording> sentRecordings = [];

final List<Prophetie> prophetien = [];
final List<Traum> traeume = [];

final List<String> prophetienLabels = [];
final List<String> traeumeLabels = [];

class LabelManager {
  LabelManager._privateConstructor();

  static final LabelManager instance = LabelManager._privateConstructor();

  List<String> labels = [];

  void listenToLabels(void Function(List<String>) onUpdate) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels')
        .snapshots()
        .listen((snapshot) {
          labels = snapshot.docs
              .map((doc) => doc.data()['label'] as String)
              .toList();
          onUpdate(labels);
        });
  }
}

// --- Premium-Funktionen / Plan-Abfrage ---

String userPlan = 'none'; // Default: kein Abo

Future<void> ladeUserPlan() async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  final doc = await FirebaseFirestore.instance
      .collection('users')
      .doc(uid)
      .get();
  userPlan = doc.data()?['plan'] ?? 'none';
}

// Shortcut für Beta-Test: solange true, sind alle Premium-Funktionen freigeschaltet
bool betaTest = true;

// Hilfsfunktion für Premium-Check überall nutzbar
bool get hatPremium =>
    betaTest || userPlan == 'monthly' || userPlan == 'yearly';
