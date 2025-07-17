import 'dart:convert';

enum UploadStatus { idle, uploading, success, failed }

class Prophetie {
  final String id;
  final String text;
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
  final UploadStatus uploadStatus;
  final String? lastErrorMessage;
  final List<String>? matchingTopics;
  bool? isTopNews;
  final bool? isAnalyzed;

  Prophetie({
    required this.id,
    required this.text,
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
    this.uploadStatus = UploadStatus.idle,
    this.lastErrorMessage,
    this.matchingTopics,
    this.isTopNews,
    this.isAnalyzed,
  });

  Prophetie copyWith({
    String? id,
    String? text,
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
    UploadStatus? uploadStatus,
    String? lastErrorMessage,
    List<String>? matchingTopics,
    bool? isTopNews,
    bool? isAnalyzed,
  }) {
    return Prophetie(
      id: id ?? this.id,
      text: text ?? this.text,
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
      uploadStatus: uploadStatus ?? this.uploadStatus,
      lastErrorMessage: lastErrorMessage ?? this.lastErrorMessage,
      matchingTopics: matchingTopics ?? this.matchingTopics,
      isTopNews: isTopNews ?? this.isTopNews,
      isAnalyzed: isAnalyzed ?? this.isAnalyzed,
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
      'uploadStatus': uploadStatus.toString(),
      'lastErrorMessage': lastErrorMessage,
      'matchingTopics': matchingTopics ?? [],
      'isTopNews': this.isTopNews ?? false,
      'isAnalyzed': isAnalyzed,
    };
  }

  factory Prophetie.fromJson(Map<String, dynamic> json) {
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

    UploadStatus parseUploadStatus(String? status) {
      switch (status) {
        case 'UploadStatus.uploading':
          return UploadStatus.uploading;
        case 'UploadStatus.success':
          return UploadStatus.success;
        case 'UploadStatus.failed':
          return UploadStatus.failed;
        case 'UploadStatus.idle':
        default:
          return UploadStatus.idle;
      }
    }

    return Prophetie(
      id: json['id'],
      text: json['text'],
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
      uploadStatus: parseUploadStatus(json['uploadStatus']),
      lastErrorMessage: json['lastErrorMessage'],
      matchingTopics: (json['matchingTopics'] as List<dynamic>?)
          ?.map((item) => item.toString())
          .toList(),
      isTopNews: json['isTopNews'] ?? false,
      isAnalyzed: json['isAnalyzed'] as bool? ?? false,
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
