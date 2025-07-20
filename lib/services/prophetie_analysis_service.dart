import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Qwen-AI Analyse-Aufruf für Träume
Future<Map<String, dynamic>?> analyzeProphetieContentWithQwenAI(
  String transcript,
) async {
  final prompt =
      '''
Analysiere die folgende Prophetie und gib deine Antwort nur als JSON-Objekt zurück.
Verwende keine Erklärungen, keine zusätzlichen Texte, keine Markdown-Formatierung.
Gib ausschließlich ein valides JSON-Objekt mit folgendem Aufbau zurück. **Jedes Feld MUSS immer befüllt sein**:

{
  "title": "Titel der Prophetie (maximal 4 Wörter, verwende NICHT das Wort 'Prophetie')",
  "mainPoints": ["Punkt 1", "Punkt 2", "..."],
  "summary": "Kurzfassung (max. 4 Sätze)",
  "storiesExamplesCitations": ["Geschichte 1", "Geschichte 2"], 
  "followUpQuestions": ["Frage 1", "Frage 2"],
  "actionItems": ["Schritt 1", "Schritt 2"],
  "scriptureReferences": ["Buch Kapitel:Vers", "..."],
  "relatedTopics": ["Thema 1", "Thema 2"],
  "transcript": "$transcript"
}

Hier ist das Transkript:
$transcript
''';

  final response = await http.post(
    Uri.parse(
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions',
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
          'content': '''
Du bist ein hocheffizienter KI-Assistent, spezialisiert auf die Auslegung & Analyse von Prophetien im christlichen Kontext.
Du vereinst theologische Exegese, prophetische Sensibilität und psychologisches Verständnis.
Deine Antworten sind stets:
- Biblisch fundiert (Bezüge auf NGÜ/SCH2000)
- Praxisnah und anwendbar
- Klar strukturiert im JSON-Output
- Ohne Füllworte oder Erklärtexte

Fülle fehlende Felder stets mit einem sinnvollen Platzhalter (z. B. "Keine passenden biblischen Geschichten gefunden").

Ziel: Generiere aus jedem Transkript einen aussagekräftigen, umsetzbaren Analysebericht im vorgegebenen JSON-Schema.
''',
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
  if (jsonStart == -1 || jsonEnd <= jsonStart) return null;
  final jsonString = content.substring(jsonStart, jsonEnd + 1);
  try {
    return jsonDecode(jsonString) as Map<String, dynamic>;
  } catch (e) {
    print('JSON parse error (Prophetie): $e');
    print('Raw AI response: $content');
    return null;
  }
}

/// Firestore-Dokument mit den KI-Ergebnissen für Träume updaten
Future<void> updateProphetieAnalysisInFirestore(
  String docId,
  Map<String, dynamic> ai,
) async {
  String _asString(dynamic value) {
    if (value is List) return value.join('\n');
    return value?.toString() ?? '';
  }

  final userId = FirebaseAuth.instance.currentUser!.uid;
  await FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('traeume')
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
}

/// Komplettes Analyse- und Speicher-Workflow für einen Prophetie-Text
Future<void> analyzeAndSaveProphetie({
  required String transcript,
  required String firestoreDocId,
  Future<void> Function()? onReload,
}) async {
  final ai = await analyzeProphetieContentWithQwenAI(transcript);
  if (ai != null) {
    await updateProphetieAnalysisInFirestore(firestoreDocId, ai);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(FirebaseAuth.instance.currentUser!.uid)
        .collection('traeume')
        .doc(firestoreDocId)
        .update({'isAnalyzed': true});
    if (onReload != null) await onReload();
  }
}
