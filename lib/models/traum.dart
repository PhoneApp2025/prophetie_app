import 'dart:convert';

class Traum {
  final String id;
  final String text;
  final String label;
  final bool isFavorit;
  final DateTime timestamp;
  final String? filePath;
  final String? creatorName;
  final String? summary;
  final String? verses;
  final String? questions;
  final String? similar;
  final String? title;
  final String? mainPoints;
  final String? followUpQuestions;
  final String? supportingScriptures;
  final String? storiesExamplesCitations;
  final String? actionItems;
  final String? relatedTopics;
  final String? transcript;
  final bool? isTopNews;
  final bool? isAnalyzed;
  List<String>? matchingTopics;

  Traum({
    required this.id,
    required this.text,
    required this.label,
    required this.isFavorit,
    required this.timestamp,
    this.filePath,
    this.creatorName,
    this.summary,
    this.verses,
    this.questions,
    this.similar,
    this.title,
    this.mainPoints,
    this.followUpQuestions,
    this.supportingScriptures,
    this.storiesExamplesCitations,
    this.actionItems,
    this.relatedTopics,
    this.transcript,
    this.isTopNews,
    this.isAnalyzed,
    this.matchingTopics,
  });

  Traum copyWith({
    String? id,
    String? text,
    String? label,
    bool? isFavorit,
    DateTime? timestamp,
    String? filePath,
    String? creatorName,
    String? summary,
    String? verses,
    String? questions,
    String? similar,
    String? title,
    String? mainPoints,
    String? followUpQuestions,
    String? supportingScriptures,
    String? storiesExamplesCitations,
    String? actionItems,
    String? relatedTopics,
    String? transcript,
    bool? isTopNews,
    bool? isAnalyzed,
    List<String>? matchingTopics,
  }) {
    return Traum(
      id: id ?? this.id,
      text: text ?? this.text,
      label: label ?? this.label,
      isFavorit: isFavorit ?? this.isFavorit,
      timestamp: timestamp ?? this.timestamp,
      filePath: filePath ?? this.filePath,
      creatorName: creatorName ?? this.creatorName,
      summary: summary ?? this.summary,
      verses: verses ?? this.verses,
      questions: questions ?? this.questions,
      similar: similar ?? this.similar,
      title: title ?? this.title,
      mainPoints: mainPoints ?? this.mainPoints,
      followUpQuestions: followUpQuestions ?? this.followUpQuestions,
      supportingScriptures: supportingScriptures ?? this.supportingScriptures,
      storiesExamplesCitations:
          storiesExamplesCitations ?? this.storiesExamplesCitations,
      actionItems: actionItems ?? this.actionItems,
      relatedTopics: relatedTopics ?? this.relatedTopics,
      transcript: transcript ?? this.transcript,
      isTopNews: isTopNews ?? this.isTopNews,
      isAnalyzed: isAnalyzed ?? this.isAnalyzed,
      matchingTopics: matchingTopics ?? this.matchingTopics,
    );
  }

  factory Traum.fromJson(Map<String, dynamic> json) {
    String? parseField(dynamic value) {
      if (value == null) return null;
      if (value is String) {
        try {
          final decoded = jsonDecode(value);
          if (decoded is Map) return decoded.values.join('\n');
          if (decoded is List) return decoded.join('\n');
        } catch (_) {}
      }
      return value.toString();
    }

    return Traum(
      id: json['id'],
      text: json['text'],
      label: json['label'],
      isFavorit: json['isFavorit'] ?? false,
      timestamp: DateTime.parse(json['timestamp']),
      filePath: json['filePath'],
      creatorName: json['creatorName'],
      summary: parseField(json['summary']),
      verses: parseField(json['verses']),
      questions: parseField(json['questions']),
      similar: parseField(json['similar']),
      title: parseField(json['title']),
      mainPoints: parseField(json['mainPoints']),
      followUpQuestions: parseField(json['followUpQuestions']),
      supportingScriptures: parseField(json['supportingScriptures']),
      storiesExamplesCitations: parseField(json['storiesExamplesCitations']),
      actionItems: parseField(json['actionItems']),
      relatedTopics: parseField(json['relatedTopics']),
      transcript: parseField(json['transcript']),
      isTopNews: json['isTopNews'] as bool? ?? false,
      isAnalyzed: json['isAnalyzed'] as bool? ?? false,
      matchingTopics: json['matchingTopics'] != null
          ? List<String>.from(json['matchingTopics'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'text': text,
      'label': label,
      'isFavorit': isFavorit,
      'timestamp': timestamp.toIso8601String(),
      'filePath': filePath,
      'creatorName': creatorName,
      'summary': summary,
      'verses': verses,
      'questions': questions,
      'similar': similar,
      'title': title,
      'mainPoints': mainPoints,
      'followUpQuestions': followUpQuestions,
      'supportingScriptures': supportingScriptures,
      'storiesExamplesCitations': storiesExamplesCitations,
      'actionItems': actionItems,
      'relatedTopics': relatedTopics,
      'transcript': transcript,
      'isTopNews': isTopNews ?? false,
      'isAnalyzed': isAnalyzed ?? false,
      'matchingTopics': matchingTopics,
    };
  }
}
