import 'dart:convert';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_dotenv/flutter_dotenv.dart';

// Guard for concurrent Prophetie-Analysen
final Set<String> _inProgressProphetienAnalyses = {};

/// Qwen-AI Analyse-Aufruf für Träume
Future<Map<String, dynamic>?> analyzeProphetieContentWithQwenAI(
  String transcript,
) async {
  final cleaned = transcript.trim().toLowerCase();

  if (cleaned.isEmpty ||
      cleaned.length < 10 ||
      RegExp(
        r'^(?:\b[a-zäöüß]+\b[\s]*){1,4}$',
        caseSensitive: false,
      ).hasMatch(cleaned)) {
    return {
      'title': 'Keine Analyse',
      'mainPoints': [],
      'summary':
          'Dein Text wirkt nicht wie eine Prophetie (zu kurz/unklar). Formuliere bitte etwas ausführlicher, damit ich dir persönlich weiterhelfen kann.',
      'storiesExamplesCitations': [],
      'followUpQuestions': [
        'Wer hat dir die Worte zugesprochen?',
        'Was war der Hauptgedanke?',
        'Welche Reaktion löste es in dir aus?',
      ],
      'actionItems': [
        'Halte die Kernaussagen in 5–10 Sätzen fest',
        'Notiere Datum, Ort und beteiligte Personen',
        'Bitte Gott um Bestätigung und Frieden',
      ],
      'scriptureReferences': [],
      'transcript': transcript,
    };
  }

  final prompt =
      '''
Bitte beziehe dich nur auf exakt die im Transkript enthaltenen Begriffe und Konzepte. Ergänze keine eigenen Interpretationen.
Analysiere die folgende Prophetie und gib deine Antwort nur als JSON-Objekt zurück.
Verwende keine Erklärungen, keine zusätzlichen Texte, keine Markdown-Formatierung.
Gib ausschließlich ein valides JSON-Objekt mit folgendem Aufbau zurück. **Jedes Feld MUSS immer befüllt sein**:

{
  "title": "Titel der Prophetie (maximal 4 Wörter, verwende NICHT das Wort 'Prophetie')",
  "mainPoints": ["Punkt 1", "Punkt 2", "..."],
  "summary": "Kurzfassung (max. 6 Sätze)",
  "storiesExamplesCitations": ["Kurze biblische Erzählung 1", "Kurze biblische Erzählung 2"],
  "followUpQuestions": ["Frage 1", "Frage 2"],
  "actionItems": ["Schritt 1", "Schritt 2"],
  "scriptureReferences": ["Buch Kapitel:Vers", "..."],
  "transcript": "$transcript"
}

Hier ist das Transkript:
$transcript
''';

  final apiKey = dotenv.env['QWEN_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    throw Exception('QWEN API key fehlt.');
  }

  late http.Response response;
  for (var attempt = 1; attempt <= 3; attempt++) {
    try {
      response = await http
          .post(
            Uri.parse(
              'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': 'qwen-turbo',
              'messages': [
                {
                  'role': 'system',
                  'content': '''
Du bist ein hocheffizienter KI-Assistent, spezialisiert auf die Auslegung & Analyse von Prophetien im christlichen Kontext.
Du vereinst theologische Exegese, prophetische Sensibilität und psychologisches Verständnis.

STIL- UND PERSPEKTIVREGELN (WICHTIG):
- Schreibe auf DEUTSCH in der **Du-Form** (zweite Person Singular). Sprich die empfangende Person direkt an ("du", "dein", "dir").
- Gehe davon aus, dass die Prophetie in der Regel **von einer anderen Person** an dich gerichtet wurde; formuliere daher die Aussagen als Zuspruch/Anwendung **für dich**.
- Keine Dritte-Person-Formulierungen wie „der Empfänger“, „der Prophetierende“, „man“.
- Positiv, seelsorgerlich, ermutigend, aber präzise und ohne Kitsch.
- Aktive Sprache, Gegenwartsform, kurze Sätze.
- In `actionItems`: 3–6 klare, umsetzbare Schritte, als Imperativ (z. B. „Prüfe diese Worte im Gebet“, „Suche Rat bei einer reifen Person in deiner Gemeinde“, „Notiere, was Gott in dir betont“).
- In `summary` und `mainPoints`: direkte Ansprache (z. B. „Du wirst ermutigt…“, „Gott lädt dich ein…“).
- Biblisch fundiert (Bezüge auf NGÜ/SCH2000, keine langen Zitatblöcke außer in `scriptureReferences`).
- Interpretiere **ausschließlich** das, was im Transkript steht. Erfinde nichts hinzu.
- Klare Struktur, **ausschließlich JSON-Output**, keine Erklärtexte, kein Markdown.
- **WICHTIG: NOTIZEN EINBEZIEHEN**: Wenn im Transkript ein Abschnitt "[NOTIZEN FÜR DIE ANALYSE]" vorhanden ist, behandle diese Notizen als zusätzliche Kontextinformationen des Nutzers. Beziehe sie in deine Deutung ein und wenn relevant, spiegele sie **knapp** in `mainPoints` und/oder `summary` (z. B. als Beobachtung, Hinweis oder Kontext). Ignoriere die Notizen nicht.

Unter "storiesExamplesCitations" bitte jeweils zwei **kurze** narrative biblische Beispiele (keine reinen Verslisten).
Fehlende Felder stets sinnvoll füllen (z. B. "Keine passenden biblischen Geschichten gefunden").
Ziel: Erzeuge aus jeder Prophetie einen hilfreichen, persönlichen, anwendbaren Analysebericht im vorgegebenen JSON-Schema.
''',
                },
                {'role': 'user', 'content': prompt},
              ],
            }),
          )
          .timeout(Duration(seconds: 120));
      break;
    } catch (e) {
      if (attempt == 3) rethrow;
      await Future.delayed(Duration(seconds: 2 * attempt));
    }
  }
  if (response.statusCode != 200) {
    String errorMessage;
    try {
      final errorBody = jsonDecode(response.body);
      errorMessage = errorBody['error']?['message'] ?? response.body;
    } catch (_) {
      errorMessage = response.body;
    }
    print('QWEN error ${response.statusCode}: $errorMessage');
    return {
      'title': 'Keine Analyse möglich',
      'mainPoints': [],
      'summary':
          'Der Analysedienst ist gerade nicht erreichbar. Deine Prophetie bleibt erhalten, versuche es später erneut.',
      'storiesExamplesCitations': [],
      'followUpQuestions': [
        'Möchtest du noch Details ergänzen (Kontext, beteiligte Personen)?',
      ],
      'actionItems': [
        'Später erneut analysieren',
        'Prüfe die Worte im Gebet und halte Eindrücke fest',
      ],
      'scriptureReferences': [],
      'transcript': transcript,
    };
  }
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
  try {
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
          'verses': _asString(ai['scriptureReferences']),
          'isAnalyzed': true,
        }, SetOptions(merge: true));
  } catch (e) {
    print('Firestore-Update (Prophetie-Analyse) fehlgeschlagen: $e');
  }
}

/// Komplettes Analyse- und Speicher-Workflow für einen Prophetie-Text
Future<void> analyzeAndSaveProphetie({
  required String transcript,
  required String firestoreDocId,
  Future<void> Function()? onReload,
}) async {
  if (_inProgressProphetienAnalyses.contains(firestoreDocId)) {
    print('Analyse bereits in Arbeit für $firestoreDocId');
    return;
  }
  _inProgressProphetienAnalyses.add(firestoreDocId);
  try {
    // Load potential notes and the include flag to augment transcript
    final userId = FirebaseAuth.instance.currentUser!.uid;
    String effectiveTranscript = transcript;
    bool notesWereIncluded = false;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prophetien')
          .doc(firestoreDocId)
          .get();
      final data = snap.data();
      final includeNotes = (data?['notesIncludeInAnalysis'] as bool?) ?? false;
      final notes = (data?['notes'] as String?)?.trim() ?? '';
      if (includeNotes && notes.isNotEmpty) {
        notesWereIncluded = true;
        // Append notes with a clear marker so the model can treat them as context
        effectiveTranscript = (
          transcript.trim().isEmpty
              ? notes
              : transcript.trim() + "\n\n[NOTIZEN FÜR DIE ANALYSE]\n" + notes
        );
      }
    } catch (e) {
      // If fetching notes fails, continue with the original transcript
      print('Hinweis: Notes konnten nicht geladen werden: $e');
    }

    final ai = await analyzeProphetieContentWithQwenAI(effectiveTranscript);
    if (ai != null) {
      await updateProphetieAnalysisInFirestore(firestoreDocId, ai);
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('prophetien')
          .doc(firestoreDocId)
          .update({'isAnalyzed': true});
      await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('prophetien')
          .doc(firestoreDocId)
          .set({
            'notesIncludedInLastAnalysis': notesWereIncluded,
            'lastAnalyzedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
      if (onReload != null) await onReload();
    }
  } finally {
    _inProgressProphetienAnalyses.remove(firestoreDocId);
  }
}
