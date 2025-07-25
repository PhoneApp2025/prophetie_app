// lib/services/connection_service.dart
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/connection_item.dart';
import '../models/connection_pair.dart';

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
    body: jsonEncode({'model': 'text-embedding-v3', 'input': texts}),
  );
  print('Qwen request URL: ${response.request?.url}');
  print('Qwen response status: ${response.statusCode}');
  if (response.statusCode != 200) {
    print(
      'Qwen Embeddings Error (status ${response.statusCode}): ${response.body}',
    );
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

    final all =
        [...dreams, ...props]
            // entferne Platzhalter-Einträge ohne echten Text
            .where((i) => i.text.trim() != 'Wird analysiert...')
            .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (all.length < 2) {
      return [];
    }

    final texts = all.map((c) => c.text).toList();
    final embeddings = await fetchQwenEmbeddings(texts);

    if (embeddings == null) {
      return [];
    }

    final scoredPairs = <MapEntry<ConnectionPair, double>>[];
    for (var i = 0; i < embeddings.length; i++) {
      for (var j = i + 1; j < embeddings.length; j++) {
        final sim = _cosineSimilarity(embeddings[i], embeddings[j]);
        if (sim > 0.7) {
          scoredPairs.add(
            MapEntry(
              ConnectionPair(
                first: all[j],
                second: all[i],
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
      pairs.sort((a, b) => b.second.timestamp.compareTo(a.second.timestamp));
      return pairs.take(4).toList();
    }

    return [];
  }
}
