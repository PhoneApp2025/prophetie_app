import '../models/prophetie.dart';
import '../models/traum.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

abstract class CloudStorageService {
  Future<void> saveProphetien(List<Prophetie> prophetien);
  Future<List<Prophetie>> loadProphetien();
  Future<void> saveTraeume(List<Traum> traeume);
  Future<List<Traum>> loadTraeume();
}

class FirebaseCloudStorageService implements CloudStorageService {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  @override
  Future<void> saveProphetien(List<Prophetie> prophetien) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final prophetienData = prophetien.map((p) => p.toJson()).toList();
    await _firestore.collection('users').doc(uid).set({
      'prophetien': prophetienData,
    }, SetOptions(merge: true));
  }

  @override
  Future<List<Prophetie>> loadProphetien() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || !data.containsKey('prophetien')) return [];

    return (data['prophetien'] as List)
        .map((json) => Prophetie.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }

  @override
  Future<void> saveTraeume(List<Traum> traeume) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final traeumeData = traeume.map((t) => t.toJson()).toList();
    await _firestore.collection('users').doc(uid).set({
      'traeume': traeumeData,
    }, SetOptions(merge: true));
  }

  @override
  Future<List<Traum>> loadTraeume() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return [];

    final doc = await _firestore.collection('users').doc(uid).get();
    final data = doc.data();
    if (data == null || !data.containsKey('traeume')) return [];

    return (data['traeume'] as List)
        .map((json) => Traum.fromJson(Map<String, dynamic>.from(json)))
        .toList();
  }
}
