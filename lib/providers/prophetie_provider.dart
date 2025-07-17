import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/prophetie.dart';

class ProphetieProvider with ChangeNotifier {
  List<Prophetie> _prophetien = [];

  List<Prophetie> get prophetien => _prophetien;

  Future<void> loadProphetien() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('prophetien')
        .orderBy('timestamp', descending: true)
        .get();
    _prophetien = snapshot.docs.map((doc) {
      final data = doc.data();
      return Prophetie(
        id: doc.id,
        text: data['text'] as String? ?? '',
        label: data['label'] as String? ?? 'NEU',
        isFavorit: data['isFavorit'] as bool? ?? false,
        timestamp: (data['timestamp'] as Timestamp).toDate(),
        filePath: data['audioUrl'] as String?,
        creatorName: data['creatorName'] as String?,
      );
    }).toList();
    notifyListeners();
  }

  Future<void> addProphetie(Prophetie prophetie) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('prophetien')
        .doc(prophetie.id)
        .set({
      'text': prophetie.text,
      'label': prophetie.label,
      'isFavorit': prophetie.isFavorit,
      'timestamp': prophetie.timestamp,
      'audioUrl': prophetie.filePath,
      'creatorName': prophetie.creatorName,
    });
    _prophetien.insert(0, prophetie);
    notifyListeners();
  }
}
