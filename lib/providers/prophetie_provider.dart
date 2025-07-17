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
        .set(prophetie.toJson());
    _prophetien.insert(0, prophetie);
    notifyListeners();
  }

  void updateProphetieStatus(String id, ProcessingStatus status,
      {String? errorMessage}) {
    final index = _prophetien.indexWhere((p) => p.id == id);
    if (index != -1) {
      _prophetien[index] = _prophetien[index]
          .copyWith(status: status, lastErrorMessage: errorMessage);
      notifyListeners();
      // Update status in Firestore as well
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('prophetien')
          .doc(id)
          .update(
              {'status': status.toString(), 'lastErrorMessage': errorMessage});
    }
  }
}
