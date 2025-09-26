import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Guard for concurrent transcription jobs
final Set<String> _inProgressTranscriptions = {};

/// Transkribiert eine lokale Audiodatei mit OpenAI Whisper und gibt das Transkript zurück.
Future<String?> transcribeAudioFile(String filePath) async {
  final file = File(filePath);
  if (!file.existsSync()) return null;
  final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
  final request = http.MultipartRequest('POST', uri);
  final apiKey = dotenv.env['OPENAI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    throw Exception('OpenAI API key fehlt.');
  }
  request.headers['Authorization'] = 'Bearer $apiKey';
  request.files.add(await http.MultipartFile.fromPath('file', file.path));
  request.fields['model'] = 'whisper-1';
  try {
    late http.StreamedResponse streamedResponse;
    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        streamedResponse = await request.send().timeout(Duration(seconds: 120));
        break;
      } on TimeoutException catch (e) {
        if (attempt == 3) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      } catch (e) {
        if (attempt == 3) rethrow;
        await Future.delayed(Duration(seconds: 2 * attempt));
      }
    }
    final response = await http.Response.fromStream(streamedResponse);
    if (response.statusCode == 200) {
      return jsonDecode(response.body)['text'] as String;
    } else {
      final errorBody = jsonDecode(response.body);
      final errorMessage = errorBody['error']?['message'] ?? response.body;
      print('Whisper error ${response.statusCode}: $errorMessage');
      return null;
    }
  } on TimeoutException catch (_) {
    print('⏰ Whisper-Anfrage überschritt das Zeitlimit von 120 Sekunden.');
    return null;
  } catch (e) {
    print('❌ Fehler bei Whisper-Anfrage: $e');
    return null;
  }
}

/// Transkribiert und bereitet eine Prophetie für Neu-Analyse vor.
Future<void> transcribeAndPrepareAnalysis({
  required String filePath,
  required String docId,
  required String collectionName,
  Future<void> Function()? onComplete,
  bool isRemoteUrl = false,
}) async {
  final userId = FirebaseAuth.instance.currentUser?.uid;
  if (userId == null) return;

  if (_inProgressTranscriptions.contains(docId)) {
    print('Transkription bereits in Arbeit für $docId');
    return;
  }
  _inProgressTranscriptions.add(docId);

  try {
    String? transcript;

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection(collectionName)
          .doc(docId)
          .set({'status': 'transcribing'}, SetOptions(merge: true));
    } catch (e) {
      print('Firestore-Update (transcribing) fehlgeschlagen: $e');
    }

    if (isRemoteUrl) {
      File? tempFile;
      try {
        final response = await http.get(Uri.parse(filePath));
        if (response.statusCode != 200) {
          throw Exception('Failed to download audio file');
        }
        final tempDir = Directory.systemTemp;
        tempFile = File('${tempDir.path}/${const Uuid().v4()}.m4a');
        await tempFile.writeAsBytes(response.bodyBytes);
        transcript = await transcribeAudioFile(tempFile.path);
      } finally {
        if (tempFile != null && await tempFile.exists()) {
          try {
            await tempFile.delete();
          } catch (_) {}
        }
      }
    } else {
      transcript = await transcribeAudioFile(filePath);
    }

    if (transcript != null && transcript.isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection(collectionName)
            .doc(docId)
            .set({
              'transcript': transcript,
              'status': 'done',
              'isAnalyzed': false,
            }, SetOptions(merge: true));
      } catch (e) {
        print('Firestore-Update (done) fehlgeschlagen: $e');
      }
    } else {
      throw Exception('Transcript is null or empty');
    }
  } catch (e) {
    print("❌ Transkription fehlgeschlagen: $e");
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection(collectionName)
          .doc(docId)
          .set({'status': 'failed'}, SetOptions(merge: true));
    } catch (e2) {
      print('Firestore-Update (failed) fehlgeschlagen: $e2');
    }
  } finally {
    _inProgressTranscriptions.remove(docId);
  }

  if (onComplete != null) {
    await onComplete();
  }
}
