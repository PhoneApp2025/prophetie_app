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
      final rawTs = data['timestamp'];
      DateTime dateTime;
      if (rawTs is Timestamp) {
        dateTime = rawTs.toDate();
      } else if (rawTs is String) {
        dateTime = DateTime.parse(rawTs);
      } else {
        dateTime = DateTime.now();
      }
      return Prophetie(
        id: doc.id,
        transcript: data['transkript'] as String? ?? '',
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

  void updateProphetieStatus(
    String id,
    ProcessingStatus status, {
    String? errorMessage,
  }) {
    final index = _prophetien.indexWhere((p) => p.id == id);
    if (index != -1) {
      _prophetien[index] = _prophetien[index].copyWith(
        status: status,
        lastErrorMessage: errorMessage,
      );
      notifyListeners();
      // Update status in Firestore as well
      FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('prophetien')
          .doc(id)
          .update({
            'status': status.toString(),
            'lastErrorMessage': errorMessage,
          });
    }
  }

  /// Removes a Prophetie by ID and notifies listeners
  void removeProphetie(String id) {
    _prophetien.removeWhere((p) => p.id == id);
    notifyListeners();
  }

  Future<void> handleNewProphetie({
    required String id,
    String? localFilePath,
    String? transcriptText,
    required String label,
    String? creatorName,
  }) async {
    // This method should encapsulate the logic from the screen
    // For now, we'll just add the prophetie and notify listeners
    final newProphetie = Prophetie(
      id: id,
      transcript: transcriptText ?? "Wird transkribiert...",
      label: label,
      isFavorit: false,
      timestamp: DateTime.now(),
      creatorName: creatorName,
      status: transcriptText == null
          ? ProcessingStatus.transcribing
          : ProcessingStatus.analyzing,
    );
    await addProphetie(newProphetie);
  }
}
