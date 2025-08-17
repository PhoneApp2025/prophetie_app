import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import '../models/SentRecording.dart';

class SentRecordingService {
  static final SentRecordingService _instance =
      SentRecordingService._internal();
  SentRecordingService._internal();

  factory SentRecordingService() => _instance;

  static SentRecordingService get instance => _instance;

  // Firestore-basiertes Lesen und Schreiben wird direkt im UI oder Repository gemacht.

  Future<void> markAsAccepted(String senderUid, String docId) async {
    final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable(
      'markSentRecordingAccepted',
    );
    try {
      await callable.call(<String, dynamic>{
        'senderUid': senderUid,
        'docId': docId,
      });
    } catch (e) {
      debugPrint("Cloud Function Fehler: $e");
      // Optional: weitere Fehlerbehandlung oder Benutzerbenachrichtigung
    }
  }
}
