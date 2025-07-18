import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Qwen-AI Analyse-Aufruf
Future<Map<String, dynamic>?> analyzeContentWithQwenAI(
  String transcript,
) async {
  final prompt =
      '''
Analysiere die folgende Prophetie und gib deine Antwort nur als JSON-Objekt zurück. Verwende keine Erklärungen, keine zusätzlichen Texte, keine Markdown-Formatierung. Gib ausschließlich ein valides JSON-Objekt mit folgendem Aufbau zurück. **Jedes Feld MUSS immer befüllt sein** :

{
  "title": "Titel der Prophetie (maximal 4 Wörter, verwende NICHT das Wort 'Prophetie')",
  "mainPoints": "Die wichtigsten Kernpunkte der Prophetie als kommagetrennte Liste ohne führende Bindestriche",
  "summary": "Zusammenfassung der Prophetie (max. 4 Sätze)",
  "storiesExamplesCitations": "Nur narrative biblische Geschichten oder Zitate ohne konkrete Versangaben, wenn es keine Biblischen Geschichten gibt die dazu passen dann schreibe: \"Keine Passenden Biblische Geschichten oder Zitate gefunden\"",
  "followUpQuestions": "Fragen zur persönlichen Reflexion, die ich mir stellen kann um die Prophetie besser zu verstehen, kommasepariert ohne weitere Erklärungen",
  "actionItems": "Konkrete Handlungsschritte",
  "supportingScriptures": "Nur konkrete Bibelstellen (Kapitel und Versangaben), kommasepariert ohne weiteren Text",
  "relatedTopics": "Ähnliche geistliche Themen",
  "transcript": "$transcript"
}

Hier ist das Transkript:
$transcript
''';

  final response = await http.post(
    Uri.parse(
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/embeddings',
    ),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['QWEN_API_KEY']}',
    },
    body: jsonEncode({
      'model': 'qwen-turbo',
      'messages': [
        {
          'role': 'system',
          'content':
              'Du bist ein Assistent der Prophetien analysiert, Hilfestellungen gibt und ein christlicher Professor bist, der an Geistesgaben glaubt.',
        },
        {'role': 'user', 'content': prompt},
      ],
    }),
  );
  if (response.statusCode != 200) return null;
  final content =
      jsonDecode(response.body)['choices'][0]['message']['content'] as String;
  final jsonStart = content.indexOf('{');
  final jsonEnd = content.lastIndexOf('}');
  if (jsonStart == -1 || jsonEnd == -1 || jsonEnd <= jsonStart) return null;
  final jsonString = content.substring(jsonStart, jsonEnd + 1);
  try {
    return jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (e) {
    print('JSON parse error: $e');
    print('Raw AI response: $content');
    return null;
  }
}

// Firestore-Dokument mit den KI-Ergebnissen updaten
Future<void> updateAnalysisInFirestore(
  String docId,
  Map<String, dynamic> ai,
) async {
  print('🧪 updateAnalysisInFirestore called for $docId');
  String _asString(dynamic value) {
    if (value is List) return value.join('\n');
    return value?.toString() ?? '';
  }

  final userId = FirebaseAuth.instance.currentUser!.uid;
  try {
    print('🔁 Writing AI results including isAnalyzed=true');
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('prophetien')
        .doc(docId)
        .set({
          'title': _asString(ai['title']),
          'mainPoints': _asString(ai['mainPoints']),
          'summary': _asString(ai['summary']),
          'storiesExamplesCitations': _asString(ai['storiesExamplesCitations']),
          'questions': _asString(ai['followUpQuestions']),
          'actionItems': _asString(ai['actionItems']),
          'verses': _asString(ai['supportingScriptures']),
          'relatedTopics': _asString(ai['relatedTopics']),
          'isAnalyzed': true,
        }, SetOptions(merge: true));
    print('✅ Firestore update with isAnalyzed complete');
    print('Prophetie analysis written for docId=$docId');
  } catch (e) {
    print('Error writing prophetie analysis for docId=$docId: $e');
  }
}

// Komplettes Analyse- und Speichern-Workflow für einen Prophetie-Text
Future<void> analyzeAndSaveProphetie({
  required String transcript,
  required String firestoreDocId,
  Future<void> Function()? onReload,
}) async {
  final ai = await analyzeContentWithQwenAI(transcript);
  if (ai != null) {
    await updateAnalysisInFirestore(firestoreDocId, ai);
    if (onReload != null) await onReload();
  }
}
