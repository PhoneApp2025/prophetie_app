import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/traum.dart';
import '../services/audio_transcription_service.dart';
import '../services/traum_analysis_service.dart';

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
      final rawTs = data['timestamp'];
      DateTime dateTime;
      if (rawTs is Timestamp) {
        dateTime = rawTs.toDate();
      } else if (rawTs is String) {
        dateTime = DateTime.parse(rawTs);
      } else {
        dateTime = DateTime.now();
      }
      return Traum.fromJson(data);
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
          .collection('traeume')
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

  Future<void> handleNewTraum({
    required String id,
    String? localFilePath,
    String? transcriptText,
    required String label,
    String? creatorName,
  }) async {
    final newTraum = Traum(
      id: id,
      transcript: transcriptText ?? "Wird transkribiert...",
      label: label,
      isFavorit: false,
      timestamp: DateTime.now(),
      creatorName:
          creatorName ?? FirebaseAuth.instance.currentUser?.displayName,
      filePath: localFilePath,
      driveAudioId: null, // Wird nach dem Upload gesetzt
      status: transcriptText == null
          ? ProcessingStatus.transcribing
          : ProcessingStatus.analyzing,
    );
    await addTraum(newTraum);

    try {
      if (localFilePath != null) {
        // Audio-Workflow
        final storageRef = FirebaseStorage.instance.ref().child(
          'users/${FirebaseAuth.instance.currentUser!.uid}/traeume/$id',
        );
        final uploadTask = await storageRef.putFile(File(localFilePath));
        final downloadUrl = await uploadTask.ref.getDownloadURL();

        // Update Firestore with the download URL
        await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .collection('traeume')
            .doc(id)
            .update({'driveAudioId': downloadUrl, 'filePath': downloadUrl});

        await transcribeAndPrepareAnalysis(
          filePath: downloadUrl,
          docId: id,
          collectionName: 'traeume',
          isRemoteUrl: true,
          onComplete: () async {
            final snapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .collection('traeume')
                .doc(id)
                .get();
            final transcript = snapshot.data()?['transcript'] as String?;
            if (transcript != null && transcript.isNotEmpty) {
              updateTraumStatus(id, ProcessingStatus.analyzing);
              await analyzeAndSaveTraum(
                transcript: transcript,
                firestoreDocId: id,
                onReload: loadTraeume,
              );
              updateTraumStatus(id, ProcessingStatus.complete);
            } else {
              updateTraumStatus(
                id,
                ProcessingStatus.failed,
                errorMessage: "Transcription failed",
              );
            }
          },
        );
      } else if (transcriptText != null) {
        // Text-Workflow
        await analyzeAndSaveTraum(
          transcript: transcriptText,
          firestoreDocId: id,
          onReload: loadTraeume,
        );
        updateTraumStatus(id, ProcessingStatus.complete);
      }
    } catch (e) {
      updateTraumStatus(
        id,
        ProcessingStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }
}
