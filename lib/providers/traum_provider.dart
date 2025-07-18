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
        .collection('träume')
        .orderBy('timestamp', descending: true)
        .get();
    _traeume = snapshot.docs.map((doc) {
      final data = doc.data();
      final rawTs = data['timestamp'];
      DateTime dateTime;
      if (rawTs is Timestamp) {
        dateTime = rawTs.toDate();
      } else if (rawTs is String) {
        dateTime = DateTime.parse(rawTs);
      } else {
        dateTime = DateTime.now();
      }
      return Traum(
        id: doc.id,
        text: data['text'] as String? ?? '',
        title: data['title'] as String? ?? '',
        label: data['label'] as String? ?? 'NEU',
        isFavorit: data['isFavorit'] as bool? ?? false,
        timestamp: dateTime,
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
        .collection('träume')
        .doc(traum.id)
        .set(traum.toJson());
    _traeume.insert(0, traum);
    notifyListeners();
  }

  void updateTraumStatus(
    String id,
    ProcessingStatus status, {
    String? errorMessage,
  }) {
    final index = _traeume.indexWhere((p) => p.id == id);
    if (index != -1) {
      _traeume[index] = _traeume[index].copyWith(
        status: status,
        lastErrorMessage: errorMessage,
      );
      notifyListeners();
      // Update status in Firestore as well
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('träume')
          .doc(id)
          .update({
            'status': status.toString(),
            'lastErrorMessage': errorMessage,
          });
    }
  }

  /// Removes a Prophetie by ID and notifies listeners
  void removeTraum(String id) {
    _traeume.removeWhere((p) => p.id == id);
    notifyListeners();
  }
}
