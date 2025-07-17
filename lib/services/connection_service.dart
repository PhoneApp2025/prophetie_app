// lib/services/connection_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/connection_item.dart';
import '../models/connection_pair.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // for Timestamp

/// Holt Embeddings per Qwen AI
Future<List<List<double>>?> fetchQwenEmbeddings(List<String> texts) async {
  final response = await http.post(
    Uri.parse(
      'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/embeddings',
    ),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${dotenv.env['QWEN_API_KEY']}',
    },
    body: jsonEncode({'model': 'qwen-embedding-1', 'input': texts}),
  );
  if (response.statusCode != 200) {
    print('Qwen Embeddings Error: ${response.body}');
    return null;
  }
  final data = jsonDecode(response.body);
  return (data['data'] as List).map<List<double>>((e) {
    final list = e['embedding'] as List;
    return list.map((v) => (v as num).toDouble()).toList();
  }).toList();
}

/// Kosinus-Ähnlichkeit
double _cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (sqrt(normA) * sqrt(normB) + 1e-8);
}

class ConnectionService {
  static Future<List<ConnectionItem>> _loadItems(
    String collection,
    ItemType type,
    String uid,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(collection)
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      final ts = data['timestamp'] is Timestamp
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.parse(data['timestamp'] as String);
      final textValue =
          (data['text'] as String?) ??
          (data['transcript'] as String?) ??
          (data['summary'] as String?) ??
          '';
      final titleValue =
          data['title'] as String? ?? textValue.split('\n').first;
      return ConnectionItem(
        id: d.id,
        title: titleValue,
        text: textValue,
        type: type,
        timestamp: ts,
        filePath: data['audioUrl'] as String?,
      );
    }).toList();
  }

  static Future<List<ConnectionPair>> fetchConnections() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final firestore = FirebaseFirestore.instance;

    final dreams = await _loadItems('traeume', ItemType.dream, uid);
    final props = await _loadItems('prophetien', ItemType.prophecy, uid);

    // Direkter lokaler Fallback, wenn keine Träume, aber mindestens zwei Prophetien
    if (dreams.isEmpty && props.length >= 2) {
      final List<ConnectionPair> directPairs = [];
      for (var i = 0; i < props.length; i++) {
        for (var j = i + 1; j < props.length; j++) {
          final aWords = props[i].text
              .toLowerCase()
              .split(RegExp(r'\W+'))
              .where((w) => w.length > 3)
              .toSet();
          final bWords = props[j].text
              .toLowerCase()
              .split(RegExp(r'\W+'))
              .where((w) => w.length > 3)
              .toSet();
          final common = aWords.intersection(bWords).toList();
          if (common.isNotEmpty) {
            directPairs.add(
              ConnectionPair(
                first: props[j],
                second: props[i],
                relationSummary:
                    'Gemeinsame Begriffe: ${common.take(5).join(', ')}',
              ),
            );
            if (directPairs.length >= 4) break;
          }
        }
        if (directPairs.length >= 4) break;
      }
      if (directPairs.isNotEmpty) {
        directPairs.sort(
          (a, b) => b.second.timestamp.compareTo(a.second.timestamp),
        );
        return directPairs.take(4).toList();
      }
    }
    final all =
        [...dreams, ...props]
            // entferne Platzhalter-Einträge ohne echten Text
            .where((i) => i.text.trim() != 'Wird analysiert...')
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // 2) KI-Prompt vorbereiten: suche Paare unter den Top 20 jüngsten Items
    final candidates = all.take(20).toList();

    // 3) KI-Abfrage mit Fehlerbehandlung
    bool useFallback = false;
    List<dynamic> parsed = [];
    try {
      http.Response resp = await http
          .post(
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
                {'role': 'system', 'content': 'Du bist ein Assistent.'},
                {
                  'role': 'user',
                  'content':
                      '''
Du bekommst eine Liste von Eindrücken (Traum oder Prophetie).  
Finde Paare, bei denen das spätere den früheren bestätigt, ergänzt oder weiterführt.  
Gib **maximal vier Paare** zurück.  
Antworte als JSON-Liste folgender Form:
[
  {
    "firstId": "<ID des älteren Items>",
    "secondId": "<ID des neueren Items>",
    "summary": "Kurze Beschreibung der Verbindung"
  },
  …
]
Prophetien/Träume:
${candidates.map((i) {
                        final t = i.type == ItemType.dream ? 'Traum' : 'Prophetie';
                        final snippet = i.text.length > 200 ? '${i.text.substring(0, 200)}…' : i.text;
                        return '- [$t] $snippet (${i.timestamp.toIso8601String()})';
                      }).join('\n')}
''',
                },
              ],
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final content =
            jsonDecode(resp.body)['choices'][0]['message']['content'] as String;
        try {
          parsed = jsonDecode(content) as List<dynamic>;
        } catch (e) {
          useFallback = true;
        }
      } else {
        useFallback = true;
      }
    } catch (e) {
      useFallback = true;
    }

    // 4) Auswertung oder Fallback
    if (!useFallback && parsed.isNotEmpty) {
      final pairs = parsed.map((m) {
        final first = candidates.firstWhere((i) => i.id == m['firstId']);
        final second = candidates.firstWhere((i) => i.id == m['secondId']);
        return ConnectionPair(
          first: first,
          second: second,
          relationSummary: m['summary'] as String,
        );
      }).toList();
      // Sort by recency of the second item and take latest 4
      pairs.sort((a, b) => b.second.timestamp.compareTo(a.second.timestamp));
      return pairs.take(4).toList();
    }

    // --- Qwen Embeddings-Fallback ---
    {
      final texts = candidates.map((c) => c.text).toList();
      final embeddings = await fetchQwenEmbeddings(texts);
      if (embeddings != null) {
        final scoredPairs = <MapEntry<ConnectionPair, double>>[];
        for (var i = 0; i < embeddings.length; i++) {
          for (var j = i + 1; j < embeddings.length; j++) {
            final sim = _cosineSimilarity(embeddings[i], embeddings[j]);
            if (sim > 0.75) {
              scoredPairs.add(
                MapEntry(
                  ConnectionPair(
                    first: candidates[j],
                    second: candidates[i],
                    relationSummary:
                        'Semantische Ähnlichkeit ${(sim * 100).toStringAsFixed(0)}%',
                  ),
                  sim,
                ),
              );
            }
          }
        }
        scoredPairs.sort((a, b) => b.value.compareTo(a.value));
        if (scoredPairs.isNotEmpty) {
          final pairs = scoredPairs.map((e) => e.key).toList();
          pairs.sort(
            (a, b) => b.second.timestamp.compareTo(a.second.timestamp),
          );
          return pairs.take(4).toList();
        }
      }
    }

    // Fallback: nur anzeigen, wenn es wirklich Gemeinsamkeiten gibt
    if (candidates.length >= 2) {
      final aWords = candidates[1].text
          .toLowerCase()
          .split(RegExp(r'\W+'))
          .where((w) => w.length > 3)
          .toSet();
      final bWords = candidates[0].text
          .toLowerCase()
          .split(RegExp(r'\W+'))
          .where((w) => w.length > 3)
          .toSet();
      // Direkter Übereinstimmung
      final directCommon = aWords.intersection(bWords).toSet();
      // Fuzzy-Übereinstimmung für morphologische Varianten
      final fuzzyCommon = <String>{};
      for (var w in aWords) {
        for (var bw in bWords) {
          if (w.contains(bw) || bw.contains(w)) {
            fuzzyCommon.add(bw);
          }
        }
      }
      // Gemeinsame Begriffe insgesamt
      final common = {...directCommon, ...fuzzyCommon}.toList();
      if (common.isNotEmpty) {
        final summary = common.length == 1
            ? 'Beide behandeln das Thema "${common.first}".'
            : 'Gemeinsame Begriffe: ${common.join(', ')}';
        return [
          ConnectionPair(
            first: candidates[1],
            second: candidates[0],
            relationSummary: summary,
          ),
        ];
      }
    }
    return [];
  }
}
