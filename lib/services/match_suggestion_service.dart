import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/connection_item.dart';

/// Represents a potential connection identified by the system.
class MatchSuggestion {
  final ConnectionItem itemA;
  final ConnectionItem itemB;
  final String pairKey;
  final double confidence;
  final String rationale;
  final Map<String, dynamic> features;

  MatchSuggestion({
    required this.itemA,
    required this.itemB,
    required this.pairKey,
    required this.confidence,
    required this.rationale,
    required this.features,
  });

  /// Helper to convert to a map for JSON serialization if needed.
  Map<String, dynamic> toJson() => {
        'aId': '${describeEnum(itemA.type)}:${itemA.id}',
        'bId': '${describeEnum(itemB.type)}:${itemB.id}',
        'pairKey': pairKey,
        'confidence': confidence,
        'rationale': rationale,
        'features': features,
      };
}

/// Represents a user-defined rule to prevent certain types of matches.
class FeedbackRule {
  final String id; // Firestore document ID
  final String description; // e.g., "Don't match dreams with prophecies about politics"
  final Map<String, dynamic> pattern; // e.g., {'typeA': 'dream', 'typeB': 'prophecy', 'label': 'politics'}

  FeedbackRule({required this.id, required this.description, required this.pattern});
}

/// The final output of the suggestion generation process.
class SuggestionResult {
  final List<MatchSuggestion> matches;
  final List<FeedbackRule> newRules; // For rules proposed by the system

  SuggestionResult({this.matches = const [], this.newRules = const []});

  /// Helper to convert to a map for JSON serialization if needed.
  Map<String, dynamic> toJson() => {
        'matches': matches.map((m) => m.toJson()).toList(),
        'new_rules': newRules.map((r) => {'description': r.description, 'pattern': r.pattern}).toList(),
      };
}

/// Service to handle the logic of generating, managing, and storing match suggestions.
class MatchSuggestionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;

  static const double MIN_CONFIDENCE_THRESHOLD = 0.7;

  /// Generate a deterministic key for a pair of items.
  static String getPairKey(ConnectionItem a, ConnectionItem b) {
    final keyA = '${describeEnum(a.type)}:${a.id}'.trim().toLowerCase();
    final keyB = '${describeEnum(b.type)}:${b.id}'.trim().toLowerCase();
    return keyA.compareTo(keyB) < 0 ? '$keyA--$keyB' : '$keyB--$keyA';
  }

  /// Loads the set of pairKeys that the user has previously rejected.
  Future<Set<String>> loadBlocklist() async {
    if (_uid == null) return {};
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_uid)
          .collection('match_blocklist')
          .get();
      return snapshot.docs.map((doc) => doc.id).toSet();
    } catch (e) {
      if (kDebugMode) {
        print('Error loading blocklist: $e');
      }
      return {}; // Fail gracefully
    }
  }

  /// Accepts a suggestion, creating a permanent connection.
  Future<void> acceptSuggestion(MatchSuggestion suggestion) async {
    if (_uid == null) throw Exception('User not logged in.');

    final connectionDoc = {
      'firstId': suggestion.itemA.id,
      'secondId': suggestion.itemB.id,
      'firstType': describeEnum(suggestion.itemA.type),
      'secondType': describeEnum(suggestion.itemB.type),
      'firstTitle': suggestion.itemA.title,
      'secondTitle': suggestion.itemB.title,
      'firstTimestamp': suggestion.itemA.timestamp,
      'secondTimestamp': suggestion.itemB.timestamp,
      'similarity': suggestion.confidence,
      'similarityPct': (suggestion.confidence * 100).round(),
      'similarityText': suggestion.rationale,
      'pinned': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('connections')
        .doc(suggestion.pairKey)
        .set(connectionDoc, SetOptions(merge: true));
  }

  /// Rejects a suggestion, adding it to the blocklist to prevent it from being shown again.
  Future<void> rejectSuggestion(MatchSuggestion suggestion, {String? reason}) async {
    if (_uid == null) throw Exception('User not logged in.');

    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('match_blocklist')
        .doc(suggestion.pairKey)
        .set({
      'pairKey': suggestion.pairKey,
      'scope': 'exact',
      'createdAt': FieldValue.serverTimestamp(),
      'reason': reason ?? 'User rejected suggestion.',
    });
  }

  /// Removes an existing connection and adds it to the blocklist.
  Future<void> removeConnection(ConnectionItem itemA, ConnectionItem itemB) async {
    if (_uid == null) throw Exception('User not logged in.');
    final pairKey = getPairKey(itemA, itemB);

    // Add to blocklist
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('match_blocklist')
        .doc(pairKey)
        .set({
      'pairKey': pairKey,
      'scope': 'exact',
      'createdAt': FieldValue.serverTimestamp(),
      'reason': 'Connection removed by user.',
    });

    // Delete from connections
    await _firestore
        .collection('users')
        .doc(_uid)
        .collection('connections')
        .doc(pairKey)
        .delete();
  }

  /// Fetches all items (dreams, prophecies) for the current user.
  Future<List<ConnectionItem>> _fetchAllItems() async {
    if (_uid == null) return [];

    // Adapting _loadItems from ConnectionService
    Future<List<ConnectionItem>> load(String collection, ItemType type) async {
      final snap = await _firestore
          .collection('users')
          .doc(_uid)
          .collection(collection)
          .orderBy('timestamp', descending: true)
          .get();
      return snap.docs.map((d) {
        final data = d.data();
        final text = (data['text'] as String? ?? data['transcript'] as String? ?? '').trim();
        final title = (data['title'] as String?)?.trim() ?? (text.split('\n').first.trim());

        return ConnectionItem(
          id: d.id,
          title: title.isNotEmpty ? title : '[ohne Titel]',
          text: text,
          type: type,
          timestamp: (data['timestamp'] as Timestamp).toDate(),
          // Add other fields if necessary
        );
      }).toList();
    }

    final dreams = await load('traeume', ItemType.dream);
    final prophecies = await load('prophetien', ItemType.prophecy);

    return [...dreams, ...prophecies];
  }

  /// The main logic for generating new match suggestions.
  Future<SuggestionResult> generateSuggestions() async {
    if (_uid == null) return SuggestionResult();

    final allItems = await _fetchAllItems();
    if (allItems.length < 2) return SuggestionResult();

    final blocklist = await loadBlocklist();
    final existingConnectionsSnap = await _firestore.collection('users').doc(_uid).collection('connections').get();
    final existingConnectionKeys = existingConnectionsSnap.docs.map((d) => d.id).toSet();

    // Ensure all items have embeddings
    // final embeddings = await _ensureEmbeddings(allItems, force: false);

    final suggestions = <MatchSuggestion>[];

    // MOCK-UP: Simulate embeddings for demonstration
    final embeddings = {for (var item in allItems) _keyOf(item): List.generate(256, (i) => i.toDouble())};

    for (int i = 0; i < allItems.length; i++) {
      for (int j = i + 1; j < allItems.length; j++) {
        final itemA = allItems[i];
        final itemB = allItems[j];
        final pairKey = getPairKey(itemA, itemB);

        if (blocklist.contains(pairKey) || existingConnectionKeys.contains(pairKey)) {
          continue;
        }

        final embeddingA = embeddings[_keyOf(itemA)];
        final embeddingB = embeddings[_keyOf(itemB)];

        if (embeddingA != null && embeddingB != null) {
          final result = await _calculateConfidence(itemA, itemB, embeddingA, embeddingB);
          if (result['confidence'] >= MIN_CONFIDENCE_THRESHOLD) {
            suggestions.add(MatchSuggestion(
              itemA: itemA,
              itemB: itemB,
              pairKey: pairKey,
              confidence: result['confidence'],
              rationale: result['rationale'],
              features: result['features'],
            ));
          }
        }
      }
    }

    suggestions.sort((a, b) => b.confidence.compareTo(a.confidence));
    return SuggestionResult(matches: suggestions);
  }

  // NOTE: Embedding-related functions from ConnectionService would be pasted here.
  // For brevity, they are omitted, but would include:
  // - fetchQwenEmbeddings
  // - _ensureEmbeddings
  // - _cosineSimilarity
  // - _cleanForEmbedding
  // - _isSaneEmbedding
  // - _keyOf (helper)
  static String _keyOf(ConnectionItem it) => '${describeEnum(it.type)}:${it.id}';

  /// Fetches labels for a given item.
  Future<Set<String>> _getItemLabels(ConnectionItem item) async {
    if (_uid == null) return {};
    final collectionName = item.type == ItemType.dream ? 'traeume' : 'prophetien';
    try {
      final doc = await _firestore.collection('users').doc(_uid).collection(collectionName).doc(item.id).get();
      final data = doc.data();
      if (data != null && data.containsKey('labels') && data['labels'] is List) {
        return (data['labels'] as List).map((label) => label.toString().toLowerCase()).toSet();
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error fetching labels for ${item.id}: $e');
      }
    }
    return {};
  }

  /// Calculates a confidence score based on multiple features.
  Future<Map<String, dynamic>> _calculateConfidence(
    ConnectionItem itemA,
    ConnectionItem itemB,
    List<double> embeddingA,
    List<double> embeddingB,
  ) async {
    // 1. Semantic Similarity (heavy weight)
    final semanticSimilarity = 0.9; // Simulated: _cosineSimilarity(embeddingA, embeddingB);

    // 2. Label Overlap
    final labelsA = await _getItemLabels(itemA);
    final labelsB = await _getItemLabels(itemB);
    double labelOverlap = 0.0;
    if (labelsA.isNotEmpty || labelsB.isNotEmpty) {
      final intersection = labelsA.intersection(labelsB).length;
      final union = labelsA.union(labelsB).length;
      if (union > 0) {
        labelOverlap = intersection / union;
      }
    }

    // 3. Time Difference (lower weight)
    final timeDiffDays = itemA.timestamp.difference(itemB.timestamp).inDays.abs();
    final timeProximity = (1 - (timeDiffDays / 365)).clamp(0.0, 1.0); // Simple linear decay over a year

    // Weighted confidence score
    final confidence = (semanticSimilarity * 0.7) + (labelOverlap * 0.2) + (timeProximity * 0.1);

    // Generate rationale
    String rationale = 'Match based on high semantic similarity.';
    if (labelOverlap > 0.5) {
      rationale = 'Strong semantic and label overlap detected.';
    } else if (timeProximity > 0.9) {
      rationale += ' The events also occurred close in time.';
    }

    return {
      'confidence': confidence.clamp(0.0, 1.0),
      'rationale': rationale,
      'features': {
        'semantic_similarity': semanticSimilarity,
        'label_overlap': labelOverlap,
        'time_difference_days': timeDiffDays,
        'shared_labels': labelsA.intersection(labelsB).toList(),
      },
    };
  }
}