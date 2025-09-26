import 'package:cloud_firestore/cloud_firestore.dart';

enum FeedbackDecision {
  accepted,
  rejected,
}

class FeedbackLog {
  final String suggestionId;
  final FeedbackDecision decision;
  final double score;
  final DateTime timestamp;

  FeedbackLog({
    required this.suggestionId,
    required this.decision,
    required this.score,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'suggestionId': suggestionId,
      'decision': decision.toString(),
      'score': score,
      'timestamp': Timestamp.fromDate(timestamp),
    };
  }

  factory FeedbackLog.fromMap(Map<String, dynamic> map) {
    return FeedbackLog(
      suggestionId: map['suggestionId'] as String,
      decision: (map['decision'] as String) == FeedbackDecision.accepted.toString()
          ? FeedbackDecision.accepted
          : FeedbackDecision.rejected,
      score: (map['score'] as num).toDouble(),
      timestamp: (map['timestamp'] as Timestamp).toDate(),
    );
  }
}