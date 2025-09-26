import 'package:prophetie_app/models/connection_pair.dart';

class ConnectionSuggestion extends ConnectionPair {
  final String id;
  final double score;
  final String explanation;
  final Map<String, double> featureScores;

  ConnectionSuggestion({
    required super.first,
    required super.second,
    required this.id,
    required this.score,
    required this.explanation,
    this.featureScores = const {},
  }) : super(relationSummary: explanation);
}