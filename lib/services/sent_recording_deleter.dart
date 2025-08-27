import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class SentRecordingDeleter {
  Future<void> deleteRecording(String docId, String? url) async {
    if (url != null && url.isNotEmpty) {
      try {
        print('Attempting to delete URL: $url');
        try {
          final ref = FirebaseStorage.instance.refFromURL(url);
          print('Reference obtained: ${ref.fullPath}');
          await ref.delete();
          print('File deleted successfully from storage: $url');
        } catch (e) {
          print('Error deleting from storage: $e');
        }
      } catch (e) {
        print('Fehler beim Löschen von $url: $e');
        // Even if file deletion fails, proceed to delete Firestore entry.
      }
    } else {
      print('URL ist null oder leer, Firestore-Dokument wird gelöscht.');
    }
    await _deleteFirestoreDocument(docId);
  }

  Future<void> _deleteFirestoreDocument(String docId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .collection('gesendet')
        .doc(docId)
        .delete();
  }
}
