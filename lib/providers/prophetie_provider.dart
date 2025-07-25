import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/prophetie.dart';
import '../services/audio_transcription_service.dart';
import '../services/prophetie_analysis_service.dart';

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
      return Prophetie.fromJson(data);
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
    required List<String> labels,
    String? creatorName,
  }) async {
    final newProphetie = Prophetie(
      id: id,
      transcript: transcriptText ?? "Wird transkribiert...",
      labels: labels,
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
    await addProphetie(newProphetie);

    try {
      if (localFilePath != null) {
        // Audio-Workflow
        final storageRef = FirebaseStorage.instance.ref().child(
          'users/${FirebaseAuth.instance.currentUser!.uid}/prophetien/$id',
        );
        final uploadTask = await storageRef.putFile(File(localFilePath));
        final downloadUrl = await uploadTask.ref.getDownloadURL();

        // Update Firestore with the download URL
        await FirebaseFirestore.instance
            .collection('users')
            .doc(FirebaseAuth.instance.currentUser!.uid)
            .collection('prophetien')
            .doc(id)
            .update({'driveAudioId': downloadUrl, 'filePath': downloadUrl});

        await transcribeAndPrepareAnalysis(
          filePath: downloadUrl,
          docId: id,
          collectionName: 'prophetien',
          isRemoteUrl: true,
          onComplete: () async {
            final snapshot = await FirebaseFirestore.instance
                .collection('users')
                .doc(FirebaseAuth.instance.currentUser!.uid)
                .collection('prophetien')
                .doc(id)
                .get();
            final transcript = snapshot.data()?['transcript'] as String?;
            if (transcript != null && transcript.isNotEmpty) {
              updateProphetieStatus(id, ProcessingStatus.analyzing);
              await analyzeAndSaveProphetie(
                transcript: transcript,
                firestoreDocId: id,
                onReload: loadProphetien,
              );
              updateProphetieStatus(id, ProcessingStatus.complete);
            } else {
              updateProphetieStatus(
                id,
                ProcessingStatus.failed,
                errorMessage: "Transcription failed",
              );
            }
          },
        );
      } else if (transcriptText != null) {
        // Text-Workflow
        await analyzeAndSaveProphetie(
          transcript: transcriptText,
          firestoreDocId: id,
          onReload: loadProphetien,
        );
        updateProphetieStatus(id, ProcessingStatus.complete);
      }
    } catch (e) {
      updateProphetieStatus(
        id,
        ProcessingStatus.failed,
        errorMessage: e.toString(),
      );
    }
  }
}
