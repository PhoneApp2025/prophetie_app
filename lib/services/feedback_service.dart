import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prophetie_app/models/connection_suggestion.dart';
import 'package:prophetie_app/models/feedback_log.dart';

class FeedbackService {
  FeedbackService._();
  static final instance = FeedbackService._();

  final _db = FirebaseFirestore.instance;
  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  DocumentReference get _learningProfileRef =>
      _db.collection('users').doc(_uid).collection('connections').doc('learning_profile');

  /// Records a user's decision on a suggestion and updates the learning model.
  Future<void> recordDecision({
    required ConnectionSuggestion suggestion,
    required FeedbackDecision decision,
  }) async {
    if (_uid == null) throw Exception("User not logged in.");

    // 1. Log the decision for historical record
    final log = FeedbackLog(
      suggestionId: suggestion.id,
      decision: decision,
      score: suggestion.score,
      timestamp: DateTime.now(),
    );

    final logRef = _db.collection('users').doc(_uid).collection('feedback_log').doc();
    await logRef.set(log.toMap());

    // 2. Update the learning model based on the feedback
    await _updateLearningProfile(suggestion: suggestion, decision: decision);
  }

  /// Fetches the current learning profile with feature weights.
  Future<Map<String, dynamic>> getLearningProfile() async {
    if (_uid == null) return _defaultLearningProfile;

    final doc = await _learningProfileRef.get();
    if (doc.exists && doc.data() != null) {
      return doc.data()!;
    } else {
      return _defaultLearningProfile;
    }
  }

  /// The default weights and structure for the learning profile.
  static final Map<String, dynamic> _defaultLearningProfile = {
    'weights': {
      'textSimilarity': 0.5,
      'labelOverlap': 0.3,
      'labelCoherence': 0.1,
      'timeProximity': 0.1,
    },
    'labelCoherence': {},
  };

  /// Updates the feature weights and label coherence based on user feedback.
  Future<void> _updateLearningProfile({
    required ConnectionSuggestion suggestion,
    required FeedbackDecision decision,
  }) async {
    if (_uid == null) return;

    const double learningRate = 0.01;
    final direction = decision == FeedbackDecision.accepted ? 1 : -1;

    final profile = await getLearningProfile();
    final weights = Map<String, double>.from(profile['weights'] as Map);
    final coherence = Map<String, dynamic>.from(profile['labelCoherence'] as Map);

    // 1. Update feature weights
    suggestion.featureScores.forEach((feature, value) {
      if (weights.containsKey(feature)) {
        final currentWeight = weights[feature]!;
        // The update is proportional to the feature's score and the learning rate
        final update = learningRate * value * direction;
        weights[feature] = (currentWeight + update).clamp(0.05, 1.0); // Keep weights in a reasonable range
      }
    });

    // Normalize weights so they sum up to 1.0
    final totalWeight = weights.values.reduce((a, b) => a + b);
    weights.forEach((key, value) {
      weights[key] = value / totalWeight;
    });

    // 2. Update label coherence
    final labels1 = suggestion.first.labels;
    final labels2 = suggestion.second.labels;
    final allLabels = {...labels1, ...labels2};

    for (final labelA in allLabels) {
      for (final labelB in allLabels) {
        if (labelA == labelB) continue;
        // Create a canonical key for the pair to avoid duplicates (A-B vs B-A)
        final key = [labelA, labelB]..sort();
        final coherenceKey = key.join('|');

        final currentScore = (coherence[coherenceKey] as num? ?? 0.0).toDouble();
        final update = learningRate * direction;
        coherence[coherenceKey] = (currentScore + update).clamp(-1.0, 1.0);
      }
    }

    // Save the updated profile
    await _learningProfileRef.set({
      'weights': weights,
      'labelCoherence': coherence,
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Fetches a set of suggestion IDs that the user has already made a decision on.
  Future<Set<String>> getDecidedSuggestionIds() async {
    if (_uid == null) return {};

    final snapshot =
        await _db.collection('users').doc(_uid).collection('feedback_log').get();
    if (snapshot.docs.isEmpty) return {};

    return snapshot.docs.map((doc) => doc.data()['suggestionId'] as String).toSet();
  }
}