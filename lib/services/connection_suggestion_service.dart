import 'dart:math';

import 'package:collection/collection.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prophetie_app/models/connection_item.dart';
import 'package:prophetie_app/models/connection_suggestion.dart';
import 'package:prophetie_app/services/connection_utils.dart';
import 'package:prophetie_app/services/feedback_service.dart';

class ConnectionSuggestionService {
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final FeedbackService _feedbackService = FeedbackService.instance;

  /// Main method to get a list of connection suggestions.
  Future<List<ConnectionSuggestion>> getSuggestions({
    int page = 0,
    int pageSize = 10,
    double scoreThreshold = 0.5,
  }) async {
    if (_uid == null) throw Exception("User not logged in.");

    // 1. Load all items, learning profile, and user's past decisions
    final (allItems, learningProfile, decidedIds, allEmbeddings) = await (
      _loadAllItems(),
      _feedbackService.getLearningProfile(),
      _feedbackService.getDecidedSuggestionIds(),
      ensureEmbeddings(_uid!, await _loadAllItems())
    ).wait;

    if (allItems.length < 2) return [];

    final weights = Map<String, double>.from(learningProfile['weights']);
    final coherence = Map<String, dynamic>.from(learningProfile['labelCoherence']);

    // 2. Generate candidate pairs
    final candidates = _generateCandidates(allItems, allEmbeddings);

    // 3. Score and filter candidates
    final scoredSuggestions = <ConnectionSuggestion>[];
    for (final pair in candidates) {
      final suggestionId = getPairKey(pair.a, pair.b);

      // Skip if user has already decided on this suggestion
      if (decidedIds.contains(suggestionId)) {
        continue;
      }

      final suggestion = _scoreSuggestion(
        pair.a,
        pair.b,
        weights,
        coherence,
        allEmbeddings,
      );

      if (suggestion.score >= scoreThreshold) {
        scoredSuggestions.add(suggestion);
      }
    }

    // 4. Sort by score and paginate
    scoredSuggestions.sort((a, b) => b.score.compareTo(a.score));

    final startIndex = page * pageSize;
    if (startIndex >= scoredSuggestions.length) return [];
    final endIndex = (startIndex + pageSize > scoredSuggestions.length)
        ? scoredSuggestions.length
        : startIndex + pageSize;

    return scoredSuggestions.sublist(startIndex, endIndex);
  }

  /// Loads all `ConnectionItem`s for the current user.
  Future<List<ConnectionItem>> _loadAllItems() async {
    if (_uid == null) return [];
    final dreams = await loadConnectionItems('traeume', ItemType.dream, _uid!);
    final prophecies = await loadConnectionItems('prophetien', ItemType.prophecy, _uid!);
    return [...dreams, ...prophecies];
  }

  /// Generates candidate pairs based on label overlap or a baseline text similarity.
  Set<({ConnectionItem a, ConnectionItem b})> _generateCandidates(
      List<ConnectionItem> items, Map<String, List<double>> embeddings) {
    final candidates = <({ConnectionItem a, ConnectionItem b})>{};
    final seenPairs = <String>{};

    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final itemA = items[i];
        final itemB = items[j];

        final pairKey = getPairKey(itemA, itemB);
        if (seenPairs.contains(pairKey)) continue;

        // Condition 1: Shared labels
        final labelsA = itemA.labels.toSet();
        final labelsB = itemB.labels.toSet();
        if (labelsA.intersection(labelsB).isNotEmpty) {
          candidates.add((a: itemA, b: itemB));
          seenPairs.add(pairKey);
          continue;
        }

        // Condition 2: Basic text similarity
        final vecA = embeddings[getItemKey(itemA)];
        final vecB = embeddings[getItemKey(itemB)];
        if (vecA != null && vecB != null) {
          final sim = cosineSimilarity(vecA, vecB);
          if (sim > 0.5) { // Low threshold for candidacy
            candidates.add((a: itemA, b: itemB));
            seenPairs.add(pairKey);
          }
        }
      }
    }
    return candidates;
  }

  /// Scores a single candidate pair based on multiple weighted features.
  ConnectionSuggestion _scoreSuggestion(
    ConnectionItem a,
    ConnectionItem b,
    Map<String, double> weights,
    Map<String, dynamic> coherence,
    Map<String, List<double>> embeddings,
  ) {
    final featureScores = <String, double>{};

    // Feature 1: Text Similarity
    final vecA = embeddings[getItemKey(a)];
    final vecB = embeddings[getItemKey(b)];
    featureScores['textSimilarity'] = (vecA != null && vecB != null) ? cosineSimilarity(vecA, vecB) : 0.0;

    // Feature 2: Label Overlap (Jaccard Index)
    final labelsA = a.labels.toSet();
    final labelsB = b.labels.toSet();
    final intersection = labelsA.intersection(labelsB).length;
    final union = labelsA.union(labelsB).length;
    featureScores['labelOverlap'] = (union == 0) ? 0.0 : intersection / union;

    // Feature 3: Label Coherence (from learning profile)
    double totalCoherence = 0;
    int coherenceCount = 0;
    for (final labelA in labelsA) {
      for (final labelB in labelsB) {
        if (labelA == labelB) continue;
        final key = [labelA, labelB]..sort();
        final coherenceKey = key.join('|');
        totalCoherence += (coherence[coherenceKey] as num? ?? 0.0).toDouble();
        coherenceCount++;
      }
    }
    featureScores['labelCoherence'] = (coherenceCount == 0) ? 0.0 : (totalCoherence / coherenceCount).clamp(-1.0, 1.0);
    // Remap from [-1, 1] to [0, 1] for scoring
    featureScores['labelCoherence'] = (featureScores['labelCoherence']! + 1) / 2;


    // Feature 4: Time Proximity
    final timeDiff = a.timestamp.difference(b.timestamp).inDays.abs();
    featureScores['timeProximity'] = exp(-0.01 * timeDiff); // Exponential decay

    // Calculate weighted final score
    double finalScore = 0;
    weights.forEach((feature, weight) {
      finalScore += (featureScores[feature] ?? 0.0) * weight;
    });

    // Generate explanation
    final explanation = _generateExplanation(featureScores);

    return ConnectionSuggestion(
      id: getPairKey(a, b),
      first: a,
      second: b,
      score: finalScore.clamp(0.0, 1.0),
      explanation: explanation,
      featureScores: featureScores,
    );
  }

  /// Creates a human-readable explanation for the suggestion.
  String _generateExplanation(Map<String, double> scores) {
    final sortedScores = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final primaryReason = sortedScores.first;
    String reasonStr = "";

    switch (primaryReason.key) {
      case 'textSimilarity':
        reasonStr = "Hohe Textähnlichkeit (${(primaryReason.value * 100).toInt()}%)";
        break;
      case 'labelOverlap':
         reasonStr = "Starke Label-Übereinstimmung";
        break;
      case 'labelCoherence':
         reasonStr = "Passende Label-Kombinationen";
        break;
      case 'timeProximity':
        reasonStr = "Zeitliche Nähe";
        break;
    }
    return reasonStr;
  }
}