import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import '../models/connection_item.dart';
import '../models/match_models.dart';

class MatchService {
  final String userId;

  MatchService({required this.userId});

  static final _firestore = FirebaseFirestore.instance;

  // Firestore collections
  CollectionReference get _blocklistRef =>
      _firestore.collection('users').doc(userId).collection('blocklist');

  CollectionReference get _feedbackRulesRef =>
      _firestore.collection('users').doc(userId).collection('feedback_rules');

  CollectionReference get _rejectionsRef =>
      _firestore.collection('users').doc(userId).collection('rejections');

  /// Adds a pair to the blocklist to prevent it from being suggested again.
  Future<void> addToBlocklist(String pairKey) async {
    await _blocklistRef.doc(pairKey).set({'blockedAt': FieldValue.serverTimestamp()});
  }

  /// Removes a pair from the blocklist.
  Future<void> removeFromBlocklist(String pairKey) async {
    await _blocklistRef.doc(pairKey).delete();
  }

  /// Retrieves the entire blocklist.
  Future<Set<String>> getBlocklist() async {
    final snapshot = await _blocklistRef.get();
    return snapshot.docs.map((doc) => doc.id).toSet();
  }

  /// Adds a new feedback rule to Firestore.
  Future<void> addFeedbackRule(FeedbackRule rule) async {
    await _feedbackRulesRef.add(rule.toJson());
  }

  /// Retrieves all feedback rules from Firestore.
  Future<List<FeedbackRule>> getFeedbackRules() async {
    final snapshot = await _feedbackRulesRef.get();
    return snapshot.docs.map((doc) {
      final data = doc.data() as Map<String, dynamic>;
      return FeedbackRule(
        reason: data['reason'],
        condition: data['condition'],
      );
    }).toList();
  }

  /// Logs a rejected match for future analysis.
  Future<void> logRejection(Match match, ConnectionItem itemA, ConnectionItem itemB) async {
    await _rejectionsRef.add({
      'pairKey': match.pairKey,
      'features': match.features.toJson(),
      'rejectedAt': FieldValue.serverTimestamp(),
      'labelsA': itemA.labels,
      'labelsB': itemB.labels,
    });
  }

  /// Analyzes all connections and returns a list of matches.
  Future<AnalysisResult> analyzeConnections({
    double minConfidence = 0.7,
    bool forceRebuild = false,
  }) async {
    final dreams = await _loadItems('traeume', ItemType.dream);
    final prophecies = await _loadItems('prophetien', ItemType.prophecy);
    final allItems = [...dreams, ...prophecies];

    if (allItems.length < 2) {
      return AnalysisResult(matches: [], newRules: []);
    }

    final blocklist = await getBlocklist();
    final embeddings = await _ensureEmbeddings(allItems, force: forceRebuild);

    final List<Match> potentialMatches = [];

    for (var i = 0; i < allItems.length; i++) {
      for (var j = i + 1; j < allItems.length; j++) {
        final itemA = allItems[i];
        final itemB = allItems[j];
        final pairKey = _pairKey(itemA, itemB);

        if (blocklist.contains(pairKey)) continue;

        final embeddingA = embeddings[_keyOf(itemA)];
        final embeddingB = embeddings[_keyOf(itemB)];

        if (embeddingA == null || embeddingB == null) continue;

        final semanticSimilarity = _cosineSimilarity(embeddingA, embeddingB);

        if (semanticSimilarity < minConfidence) continue;

        final timeDifference =
            itemA.timestamp.difference(itemB.timestamp).inDays.abs();

        final labelsA = itemA.labels.toSet();
        final labelsB = itemB.labels.toSet();
        final intersection = labelsA.intersection(labelsB).length;
        final union = labelsA.union(labelsB).length;
        final labelOverlap = union > 0 ? intersection / union : 0.0;

        final features = MatchFeatures(
          semanticSimilarity: semanticSimilarity,
          labelOverlapScore: labelOverlap,
          timeDifferenceDays: timeDifference,
        );

        // Simple confidence score (can be improved)
        final confidence = semanticSimilarity;

        final rationale =
            'Semantic similarity of ${(semanticSimilarity * 100).toStringAsFixed(0)}% '
            'with a time difference of $timeDifference days. '
            'Shared labels: ${intersection > 0 ? labelsA.intersection(labelsB).join(', ') : 'none'}.';

        potentialMatches.add(
          Match(
            aId: itemA.id,
            bId: itemB.id,
            pairKey: pairKey,
            confidence: confidence,
            rationale: rationale,
            features: features,
          ),
        );
      }
    }

    potentialMatches.sort((a, b) => b.confidence.compareTo(a.confidence));

    final newRules = await _suggestNewRules();

    return AnalysisResult(matches: potentialMatches, newRules: newRules);
  }

  // Suggests new feedback rules based on rejection patterns.
  Future<List<FeedbackRule>> _suggestNewRules({
    int rejectionThreshold = 3,
  }) async {
    final snapshot = await _rejectionsRef.get();
    if (snapshot.docs.length < rejectionThreshold) {
      return [];
    }

    final labelPairCounts = <String, int>{};

    for (final doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final labelsA = List<String>.from(data['labelsA'] ?? []);
      final labelsB = List<String>.from(data['labelsB'] ?? []);

      for (final labelA in labelsA) {
        for (final labelB in labelsB) {
          final pair = [labelA, labelB]..sort();
          final key = pair.join('__');
          labelPairCounts[key] = (labelPairCounts[key] ?? 0) + 1;
        }
      }
    }

    final newRules = <FeedbackRule>[];
    final existingRules = await getFeedbackRules();
    final existingRuleConditions =
        existingRules.map((r) => jsonEncode(r.condition)).toSet();

    labelPairCounts.forEach((key, count) {
      if (count >= rejectionThreshold) {
        final labels = key.split('__');
        final condition = {
          'type': 'label_combination',
          'labels': labels,
        };

        if (!existingRuleConditions.contains(jsonEncode(condition))) {
          newRules.add(
            FeedbackRule(
              reason:
                  'You have frequently rejected matches between items with the labels: ${labels.join(', ')}.',
              condition: condition,
            ),
          );
        }
      }
    });

    return newRules;
  }

  // Generates a deterministic key for a single item.
  String _keyOf(ConnectionItem it) =>
      '${describeEnum(it.type)}:${it.id}'.toLowerCase().trim();

  // Generates a deterministic, order-independent key for a pair of items.
  String _pairKey(ConnectionItem a, ConnectionItem b) {
    final ka = _keyOf(a);
    final kb = _keyOf(b);
    return ka.compareTo(kb) <= 0 ? '${ka}__${kb}' : '${kb}__${ka}';
  }

  // Helper to load all items from a collection.
  Future<List<ConnectionItem>> _loadItems(
      String collection, ItemType type) async {
    final snap = await _firestore
        .collection('users')
        .doc(userId)
        .collection(collection)
        .orderBy('timestamp', descending: true)
        .get();

    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      final ts = _parseTimestamp(data['timestamp']);

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

      List<String> labels = [];
      if (data['labels'] is List) {
        labels = List<String>.from(data['labels']);
      } else if (data['label'] is String) {
        labels = [data['label']];
      }

      return ConnectionItem(
        id: d.id,
        title: titleValue.isNotEmpty ? titleValue : '[ohne Titel]',
        text: textValue,
        type: type,
        timestamp: ts,
        filePath: data['audioUrl'] as String?,
        labels: labels,
      );
    }).toList();
  }

  // Robust timestamp parser for legacy data.
  static DateTime _parseTimestamp(dynamic raw) {
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

  // Sanity check for legacy embeddings.
  static bool _isSaneEmbedding(List<double> v) {
    if (v.isEmpty || v.length < 64) return false;
    double norm = 0;
    for (final x in v) {
      if (x.isNaN || x.isInfinite) return false;
      norm += x * x;
    }
    norm = sqrt(norm);
    return norm > 0.1 && norm < 1000;
  }

  // Cleans and shortens text for embeddings to avoid API errors.
  String _cleanForEmbedding(String s) {
    final trimmed = s.replaceAll(RegExp(r'\\s+'), ' ').trim();
    return trimmed.length > 4000 ? trimmed.substring(0, 4000) : trimmed;
  }

  /// Fetches embeddings via Qwen AI with retry and timeout.
  Future<List<List<double>>?> fetchQwenEmbeddings(List<String> texts) async {
    final apiKey = dotenv.env['QWEN_API_KEY'];
    if (apiKey == null || apiKey.trim().isEmpty) {
      debugPrint('Qwen Embeddings Error: QWEN_API_KEY is missing.');
      return null;
    }

    List<String> preparedTexts = texts
        .map((s) => s.replaceAll(RegExp(r'\\s+'), ' ').trim())
        .map((s) => s.length > 4000 ? s.substring(0, 4000) : s)
        .toList();

    final payload = {'model': 'text-embedding-v2', 'input': preparedTexts};

    const maxAttempts = 4;
    Duration backoff(int attempt) =>
        Duration(milliseconds: 300 * (1 << attempt));

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        final response = await http
            .post(
              Uri.parse(
                  'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/embeddings'),
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
            debugPrint('Qwen Embeddings Error: Unexpected response structure.');
            return null;
          }
        }

        final body = response.body;
        final retryable = response.statusCode == 429 ||
            response.statusCode >= 500 ||
            (response.statusCode == 400 &&
                body.contains('Internal server error'));

        debugPrint(
            'Qwen Embeddings Error (status ${response.statusCode}): ${response.body} | attempt=${attempt + 1}/$maxAttempts');

        if (!retryable || attempt == maxAttempts - 1) return null;
        await Future.delayed(backoff(attempt));
      } catch (e) {
        debugPrint(
            'Qwen Embeddings Transport Error: $e | attempt=${attempt + 1}/$maxAttempts');
        if (attempt == maxAttempts - 1) return null;
        await Future.delayed(backoff(attempt));
      }
    }
    return null;
  }

  /// Cosine similarity between two vectors.
  double _cosineSimilarity(List<double> a, List<double> b) {
    double dot = 0, normA = 0, normB = 0;
    final len = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < len; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    return dot / (sqrt(normA) * sqrt(normB) + 1e-8);
  }

  /// Ensures all items have embeddings, fetching missing ones.
  Future<Map<String, List<double>>> _ensureEmbeddings(
    List<ConnectionItem> items, {
    bool force = false,
  }) async {
    final existing = <String, List<double>>{};
    final firestore = FirebaseFirestore.instance;
    final userDoc = firestore.collection('users').doc(userId);

    String typeKeyForCollection(String c) {
      final v = c.toLowerCase();
      if (v.contains('traeum')) return 'dream';
      if (v.contains('prophet')) return 'prophecy';
      return v;
    }

    Future<void> loadEmbeddings(String collection) async {
      final snap = await userDoc.collection(collection).get();
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
      final k = _keyOf(it);
      final vec = existing[k];
      final needs = force || vec == null || !_isSaneEmbedding(vec);
      if (needs) missing.add(it);
    }
    if (missing.isEmpty) return existing;

    String collOf(ConnectionItem it) =>
        it.type == ItemType.dream ? 'traeume' : 'prophetien';

    const batchSize = 16;
    for (var i = 0; i < missing.length; i += batchSize) {
      final slice = missing.sublist(
          i, i + batchSize > missing.length ? missing.length : i + batchSize);
      final texts = slice.map((e) => _cleanForEmbedding(e.text)).toList();
      final vecs = await fetchQwenEmbeddings(texts);
      if (vecs == null || vecs.length != slice.length) {
        debugPrint(
            'Qwen Embeddings Warn: Vecs null or length mismatch. Skipping batch.');
        continue;
      }

      final batch = firestore.batch();
      for (var k = 0; k < slice.length; k++) {
        final it = slice[k];
        final v = vecs[k];
        existing[_keyOf(it)] = v;
        final docRef = userDoc.collection(collOf(it)).doc(it.id);
        batch.set(docRef, {'embedding': v}, SetOptions(merge: true));
      }
      await batch.commit();
    }

    return existing;
  }
}