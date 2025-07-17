import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/traum.dart';

class TraumProvider with ChangeNotifier {
  List<Traum> _traeume = [];

  List<Traum> get traeume => _traeume;

  Future<void> loadTraeume() async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('traeume')
        .orderBy('timestamp', descending: true)
        .get();
    _traeume = snapshot.docs.map((doc) {
      final data = doc.data();
      return Traum(
        id: doc.id,
        text: data['text'] as String? ?? '',
        label: data['label'] as String? ?? 'Empfangen',
        isFavorit: data['isFavorit'] as bool? ?? false,
        timestamp: (data['timestamp'] as Timestamp).toDate(),
        filePath: data['audioUrl'] as String?,
        creatorName: data['creatorName'] as String?,
      );
    }).toList();
    notifyListeners();
  }

  Future<void> addTraum(Traum traum) async {
    final userId = FirebaseAuth.instance.currentUser!.uid;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('traeume')
        .doc(traum.id)
        .set(traum.toJson());
    _traeume.insert(0, traum);
    notifyListeners();
  }

  void updateTraumStatus(String id, ProcessingStatus status) {
    final index = _traeume.indexWhere((t) => t.id == id);
    if (index != -1) {
      _traeume[index] = _traeume[index].copyWith(status: status);
      notifyListeners();
      // Update status in Firestore as well
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('traeume')
          .doc(id)
          .update({'status': status.toString()});
    }
  }
}
