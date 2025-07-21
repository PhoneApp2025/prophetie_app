import 'dart:convert';

enum ProcessingStatus { none, transcribing, analyzing, complete, failed }

class Traum {
  final String id;
  final String label;
  final bool isFavorit;
  final DateTime timestamp;
  final String? filePath;
  final String? creatorName;
  final String? mainPoints; // Deprecated field, not used in the model
  final String? summary;
  final String? verses;
  final String? questions;
  final String? similar;
  final String? title;
  final String? storiesExamplesCitations;
  final String? actionItems;
  final String? relatedTopics;
  final String? transcript;
  final String? driveAudioId;
  final ProcessingStatus status;
  final String? lastErrorMessage;
  final List<String>? matchingTopics;
  bool? isTopNews;

  Traum({
    required this.id,
    required this.label,
    required this.isFavorit,
    required this.timestamp,
    this.filePath,
    this.creatorName,
    this.mainPoints,
    this.summary,
    this.verses,
    this.questions,
    this.similar,
    this.title,
    this.storiesExamplesCitations,
    this.actionItems,
    this.relatedTopics,
    this.transcript,
    this.driveAudioId,
    this.status = ProcessingStatus.none,
    this.lastErrorMessage,
    this.matchingTopics,
    this.isTopNews,
  });

  Traum copyWith({
    String? id,
    String? label,
    bool? isFavorit,
    DateTime? timestamp,
    String? filePath,
    String? creatorName,
    String? mainPoints, // Deprecated field
    String? summary,
    String? verses,
    String? questions,
    String? similar,
    String? title,
    String? storiesExamplesCitations,
    String? actionItems,
    String? relatedTopics,
    String? transcript,
    String? driveAudioId,
    ProcessingStatus? status,
    String? lastErrorMessage,
    List<String>? matchingTopics,
    bool? isTopNews,
  }) {
    return Traum(
      id: id ?? this.id,
      label: label ?? this.label,
      isFavorit: isFavorit ?? this.isFavorit,
      timestamp: timestamp ?? this.timestamp,
      filePath: filePath ?? this.filePath,
      creatorName: creatorName ?? this.creatorName,
      mainPoints: mainPoints ?? this.mainPoints, // Deprecated field
      summary: summary ?? this.summary,
      verses: verses ?? this.verses,
      questions: questions ?? this.questions,
      similar: similar ?? this.similar,
      title: title ?? this.title,
      storiesExamplesCitations:
          storiesExamplesCitations ?? this.storiesExamplesCitations,
      actionItems: actionItems ?? this.actionItems,
      relatedTopics: relatedTopics ?? this.relatedTopics,
      transcript: transcript ?? this.transcript,
      driveAudioId: driveAudioId ?? this.driveAudioId,
      status: status ?? this.status,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      matchingTopics: matchingTopics ?? this.matchingTopics,
      isTopNews: isTopNews ?? this.isTopNews,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'isFavorit': isFavorit,
      'timestamp': timestamp.toIso8601String(),
      'filePath': filePath,
      'creatorName': creatorName,
      'mainPoints': mainPoints, // Deprecated field, not used in the model
      'summary': summary,
      'verses': verses,
      'questions': questions,
      'similar': similar,
      'title': title,
      'storiesExamplesCitations': storiesExamplesCitations,
      'actionItems': actionItems,
      'relatedTopics': relatedTopics,
      'transcript': transcript,
      'driveAudioId': driveAudioId,
      'status': status.toString(),
      'lastErrorMessage': lastErrorMessage,
      'matchingTopics': matchingTopics ?? [],
      'isTopNews': this.isTopNews ?? false,
    };
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

    ProcessingStatus parseProcessingStatus(String? status) {
      switch (status) {
        case 'ProcessingStatus.transcribing':
          return ProcessingStatus.transcribing;
        case 'ProcessingStatus.analyzing':
          return ProcessingStatus.analyzing;
        case 'ProcessingStatus.complete':
          return ProcessingStatus.complete;
        case 'ProcessingStatus.failed':
          return ProcessingStatus.failed;
        default:
          return ProcessingStatus.none;
      }
    }

    return Traum(
      id: json['id'],
      label: json['label'],
      isFavorit: json['isFavorit'] ?? false,
      timestamp: DateTime.parse(json['timestamp']),
      filePath: json['filePath'],
      creatorName: json['creatorName'],
      mainPoints: parseField(json['mainPoints']), // Deprecated field
      summary: parseField(json['summary']),
      verses: parseField(json['verses']),
      questions: parseField(json['questions']),
      similar: parseField(json['similar']),
      title: parseField(json['title']),
      storiesExamplesCitations: parseField(json['storiesExamplesCitations']),
      actionItems: parseField(json['actionItems']),
      relatedTopics: parseField(json['relatedTopics']),
      transcript: parseField(json['transcript']),
      driveAudioId: json['driveAudioId'],
      status: parseProcessingStatus(json['status']),
      lastErrorMessage: json['lastErrorMessage'],
      matchingTopics: (json['matchingTopics'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList(),
      isTopNews: json['isTopNews'] ?? false,
    );
  }

  /// Returns the audio identifier to play: prefers cloud Drive ID over local file path.
  String? get audioReference {
    if (driveAudioId != null && driveAudioId!.isNotEmpty) {
      return driveAudioId;
    }
    if (filePath != null && filePath!.isNotEmpty) {
      return filePath;
    }
    return null;
  }
}
