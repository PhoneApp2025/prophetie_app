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
        .set({
      'text': traum.text,
      'label': traum.label,
      'isFavorit': traum.isFavorit,
      'timestamp': traum.timestamp,
      'audioUrl': traum.filePath,
      'creatorName': traum.creatorName,
    });
    _traeume.insert(0, traum);
    notifyListeners();
  }
}
