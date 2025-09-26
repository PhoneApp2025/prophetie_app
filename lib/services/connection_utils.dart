import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:prophetie_app/models/connection_item.dart';

// SHARED UTILITY FUNCTIONS FOR CONNECTION SERVICES

/// Generates a unique, namespaced key for a ConnectionItem.
String getItemKey(ConnectionItem it) => '${describeEnum(it.type)}:${it.id}';

/// Generates a canonical, order-independent key for a pair of ConnectionItems.
String getPairKey(ConnectionItem a, ConnectionItem b) {
  final ka = getItemKey(a);
  final kb = getItemKey(b);
  return ka.compareTo(kb) <= 0 ? '${ka}__${kb}' : '${kb}__${ka}';
}

/// Calculates the cosine similarity between two vectors.
double cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (sqrt(normA) * sqrt(normB) + 1e-8);
}

// Robustly parses a timestamp from various legacy data formats.
DateTime parseTimestamp(dynamic raw) {
  if (raw is Timestamp) return raw.toDate();
  if (raw is DateTime) return raw;
  if (raw is int) {
    if (raw > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(raw);
    return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
  }
  if (raw is String) {
    final s = raw.trim();
    if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
    try {
      return DateTime.parse(s);
    } catch (_) {
      final ms = int.tryParse(s);
      if (ms != null) {
        if (ms > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(ms);
        return DateTime.fromMillisecondsSinceEpoch(ms * 1000);
      }
    }
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// Loads all items (e.g., dreams, prophecies) from a specific Firestore collection for a user.
Future<List<ConnectionItem>> loadConnectionItems(
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
    final ts = parseTimestamp(data['timestamp']);

    final textValue = (data['text'] as String? ??
            data['transcript'] as String? ??
            data['summary'] as String? ??
            data['content'] as String? ??
            data['description'] as String? ??
            data['body'] as String? ??
            '')
        .trim();
    final titleValue = (data['title'] as String?)?.trim().isNotEmpty == true
        ? (data['title'] as String).trim()
        : (textValue.split('\n').firstWhere(
              (e) => e.trim().isNotEmpty,
              orElse: () => '',
            ).trim());

    final rawLabels = data['labels'];
    List<String> labels = [];
    if (rawLabels is List) {
      labels = rawLabels.map((l) => l.toString()).toList();
    } else if (data['label'] is String) {
      labels = [data['label'] as String];
    }

    return ConnectionItem(
      id: d.id,
      title: titleValue.isNotEmpty ? titleValue : '[ohne Titel]',
      text: textValue,
      type: type,
      timestamp: ts,
      labels: labels,
      filePath: data['audioUrl'] as String?,
    );
  }).toList();
}

/// Checks if an embedding vector is well-formed.
bool isSaneEmbedding(List<double> v) {
  if (v.isEmpty) return false;
  if (v.length < 64) return false;
  double norm = 0;
  for (final x in v) {
    if (x.isNaN || x.isInfinite) return false;
    norm += x * x;
  }
  norm = sqrt(norm);
  return norm > 0.1 && norm < 1000;
}

String _cleanForEmbedding(String s) {
  final trimmed = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  return trimmed.length > 4000 ? trimmed.substring(0, 4000) : trimmed;
}

/// Fetches text embeddings from the Qwen AI API with retry logic.
Future<List<List<double>>?> fetchQwenEmbeddings(List<String> texts) async {
  final apiKey = dotenv.env['QWEN_API_KEY'];
  if (apiKey == null || apiKey.trim().isEmpty) {
    debugPrint('Qwen Embeddings Error: QWEN_API_KEY fehlt.');
    return null;
  }

  final payload = {
    'model': 'text-embedding-v3',
    'input': texts.map(_cleanForEmbedding).toList(),
  };

  const maxAttempts = 4;
  Duration backoff(int attempt) => Duration(milliseconds: 300 * (1 << attempt));

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final response = await http
          .post(
            Uri.parse(
              'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/embeddings',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'];
        if (list is List) {
          try {
            return list.map<List<double>>((e) {
              final emb = e['embedding'] as List;
              return emb.map((v) => (v as num).toDouble()).toList();
            }).toList();
          } catch (e) {
            debugPrint('Qwen Embeddings Parse Error: $e');
            return null;
          }
        } else {
          debugPrint('Qwen Embeddings Error: Unerwartete Antwortstruktur.');
          return null;
        }
      }

      final body = response.body;
      final retryable = response.statusCode == 429 ||
          response.statusCode >= 500 ||
          (response.statusCode == 400 && body.contains('Internal server error'));

      debugPrint(
          'Qwen Embeddings Error (status ${response.statusCode}): ${response.body} | attempt=${attempt + 1}/$maxAttempts');

      if (!retryable || attempt == maxAttempts - 1) {
        return null;
      }

      await Future.delayed(backoff(attempt));
    } catch (e) {
      debugPrint('Qwen Embeddings Transport Error: $e | attempt=${attempt + 1}/$maxAttempts');
      if (attempt == maxAttempts - 1) return null;
      await Future.delayed(backoff(attempt));
    }
  }

  return null;
}

/// Ensures all provided items have embeddings, fetching any that are missing or invalid.
Future<Map<String, List<double>>> ensureEmbeddings(
  String uid,
  List<ConnectionItem> items, {
  bool force = false,
}) async {
  final existing = <String, List<double>>{};

  String typeKeyForCollection(String c) {
    final v = c.toLowerCase();
    if (v.contains('traeum')) return 'dream';
    if (v.contains('prophet')) return 'prophecy';
    return v;
  }

  Future<void> loadEmbeddings(String collection) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(collection)
        .get();
    for (final d in snap.docs) {
      final data = d.data();
      final emb = data['embedding'];
      if (emb is List) {
        final vec = emb.map((e) => (e as num).toDouble()).toList();
        final typeKey = typeKeyForCollection(collection);
        existing['$typeKey:${d.id}'] = vec;
      }
    }
  }

  await Future.wait([
    loadEmbeddings('traeume'),
    loadEmbeddings('prophetien'),
  ]);

  final missing = <ConnectionItem>[];
  for (final it in items) {
    final k = getItemKey(it);
    final vec = existing[k];
    if (force || vec == null || !isSaneEmbedding(vec)) {
      missing.add(it);
    }
  }
  if (missing.isEmpty) return existing;

  String collOf(ConnectionItem it) =>
      it.type == ItemType.dream ? 'traeume' : 'prophetien';

  const batchSize = 16;
  for (var i = 0; i < missing.length; i += batchSize) {
    final slice = missing.sublist(
      i,
      i + batchSize > missing.length ? missing.length : i + batchSize,
    );
    final texts = slice.map((e) => _cleanForEmbedding(e.text)).toList();
    final vecs = await fetchQwenEmbeddings(texts);
    if (vecs == null || vecs.length != slice.length) {
      debugPrint(
          'Qwen Embeddings Warn: Vecs null oder Längen-Mismatch. Überspringe Batch.');
      continue;
    }

    final batch = FirebaseFirestore.instance.batch();
    for (var k = 0; k < slice.length; k++) {
      final it = slice[k];
      final v = vecs[k];
      existing[getItemKey(it)] = v;
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collOf(it))
          .doc(it.id);
      batch.set(docRef, {
        'embedding': v,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  return existing;
}