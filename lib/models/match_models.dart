import 'package:flutter/foundation.dart';

/// Represents a suggested match between two entries.
class Match {
  final String aId;
  final String bId;
  final String pairKey;
  final double confidence;
  final String rationale;
  final MatchFeatures features;

  Match({
    required this.aId,
    required this.bId,
    required this.pairKey,
    required this.confidence,
    required this.rationale,
    required this.features,
  });

  Map<String, dynamic> toJson() => {
        'aId': aId,
        'bId': bId,
        'pairKey': pairKey,
        'confidence': confidence,
        'rationale': rationale,
        'features': features.toJson(),
      };
}

/// Encapsulates the features of a match.
class MatchFeatures {
  final double semanticSimilarity;
  final double labelOverlapScore;
  final int timeDifferenceDays;

  MatchFeatures({
    required this.semanticSimilarity,
    required this.labelOverlapScore,
    required this.timeDifferenceDays,
  });

  Map<String, dynamic> toJson() => {
        'semanticSimilarity': semanticSimilarity,
        'labelOverlapScore': labelOverlapScore,
        'timeDifferenceDays': timeDifferenceDays,
      };
}

/// Represents a user-defined rule for filtering out unwanted matches.
class FeedbackRule {
  final String reason;
  final Map<String, dynamic> condition;

  FeedbackRule({
    required this.reason,
    required this.condition,
  });

  Map<String, dynamic> toJson() => {
        'reason': reason,
        'condition': condition,
      };
}

/// A top-level class to structure the final output.
class AnalysisResult {
  final List<Match> matches;
  final List<FeedbackRule> newRules;

  AnalysisResult({
    required this.matches,
    required this.newRules,
  });

  Map<String, dynamic> toJson() => {
        'matches': matches.map((m) => m.toJson()).toList(),
        'new_rules': newRules.map((r) => r.toJson()).toList(),
      };
}