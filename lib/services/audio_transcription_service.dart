import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Transkribiert eine lokale Audiodatei mit OpenAI Whisper und gibt das Transkript zurück.
Future<String?> transcribeAudioFile(String filePath) async {
  final file = File(filePath);
  if (!file.existsSync()) return null;
  final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');
  final request = http.MultipartRequest('POST', uri)
    ..headers['Authorization'] = 'Bearer ${dotenv.env['OPENAI_API_KEY']}'
    ..files.add(await http.MultipartFile.fromPath('file', file.path))
    ..fields['model'] = 'whisper-1';
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  if (response.statusCode == 200) {
    return jsonDecode(response.body)['text'] as String;
  } else {
    print('Whisper error: ${response.body}');
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
  String? transcript;
  if (isRemoteUrl) {
    // Download remote file to temporary local file
    final response = await http.get(Uri.parse(filePath));
    if (response.statusCode == 200) {
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/${const Uuid().v4()}.m4a');
      await tempFile.writeAsBytes(response.bodyBytes);
      transcript = await transcribeAudioFile(tempFile.path);
      await tempFile.delete().catchError((_) {});
    } else {
      transcript = null;
    }
  } else {
    transcript = await transcribeAudioFile(filePath);
  }
  final userId = FirebaseAuth.instance.currentUser!.uid;
  if (transcript != null) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection(collectionName)
        .doc(docId)
        .set({'transcript': transcript}, SetOptions(merge: true));
  }
  if (onComplete != null) {
    await onComplete();
  }
}
