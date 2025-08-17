import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

enum ProcessingStatus { none, transcribing, analyzing, complete, failed }

class Prophetie {
  final String id;
  final List<String> labels;
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

  Prophetie({
    required this.id,
    required this.labels,
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

  Prophetie copyWith({
    String? id,
    List<String>? labels,
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
    return Prophetie(
      id: id ?? this.id,
      labels: labels ?? this.labels,
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
      'labels': labels,
      'isFavorit': isFavorit,
      'timestamp': Timestamp.fromDate(timestamp),
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

  factory Prophetie.fromJson(Map<String, dynamic> json) {
    // Helper to parse timestamp from various formats
    DateTime parseTimestamp(dynamic value) {
      if (value is String) {
        return DateTime.parse(value);
      } else if (value is Timestamp) {
        return value.toDate();
      } else if (value is Map &&
          value.containsKey('_seconds') &&
          value.containsKey('_nanoseconds')) {
        // Firestore Timestamp-like object
        return DateTime.fromMillisecondsSinceEpoch(
          value['_seconds'] * 1000 + (value['_nanoseconds'] / 1000000).round(),
        );
      }
      // Add more checks if other formats are expected
      throw ArgumentError('Invalid timestamp format');
    }

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

    List<String> labels = [];
    if (json['labels'] is List) {
      labels = List<String>.from(json['labels']);
    } else if (json['label'] is String) {
      labels = [json['label']];
    }

    return Prophetie(
      id: json['id'],
      labels: labels,
      isFavorit: json['isFavorit'] ?? false,
      timestamp: parseTimestamp(json['timestamp']), // Use the robust parser
      filePath: json['filePath'],
      creatorName: json['creatorName'],
      mainPoints: parseField(json['mainPoints']),
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
