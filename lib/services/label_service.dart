import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LabelService {
  static final LabelService instance = LabelService._();

  LabelService._();

  List<String> labels = [];

  void init(void Function(List<String>) onUpdate) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels')
        .orderBy('order')
        .snapshots()
        .listen((snapshot) {
          labels = snapshot.docs
              .map((doc) => doc.data()['label'] as String)
              .toList();
          onUpdate(labels);
        });
  }

  Future<void> updateOrder(List<String> newLabels) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final batch = FirebaseFirestore.instance.batch();
    final labelsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels');

    for (int i = 0; i < newLabels.length; i++) {
      final docRef = labelsRef.doc(newLabels[i]);
      batch.set(docRef, {'label': newLabels[i], 'order': i});
    }

    await batch.commit();
  }

  Future<void> addLabel(String label) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final labelsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels');

    final exists = await labelsRef.doc(label).get();
    if (exists.exists) return;

    final order = labels.length;
    await labelsRef.doc(label).set({'label': label, 'order': order});
  }

  Future<void> renameLabel(String oldLabel, String newLabel) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final labelsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels');

    final oldDoc = await labelsRef.doc(oldLabel).get();
    if (!oldDoc.exists) return;

    final data = oldDoc.data();
    if (data == null) return;

    final order = data['order'] ?? labels.indexOf(oldLabel);

    await labelsRef.doc(newLabel).set({'label': newLabel, 'order': order});
    await labelsRef.doc(oldLabel).delete();
  }

  Future<void> deleteLabel(String label) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final labelsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels');

    await labelsRef.doc(label).delete();

    // Reihenfolge aktualisieren
    labels.remove(label);
    await updateOrder(labels);
  }

  Future<List<Map<String, dynamic>>> getAllLabels() async {
    return labels.map((label) => {'label': label}).toList();
  }
}
