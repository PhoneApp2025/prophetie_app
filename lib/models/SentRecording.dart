class SentRecording {
  final String id;
  final String recipientName;
  final String? recipientId; // optional: Firestore-User-ID des Empfängers
  final String text;
  final DateTime date;
  final String status; // "gesendet", "übernommen", "abgelehnt", etc.
  final String category; // "prophecy" oder "dream"

  SentRecording({
    required this.id,
    required this.recipientName,
    required this.text,
    required this.date,
    this.recipientId,
    this.status = "gesendet",
    required this.category,
  });

  // Für Speicherung/Sync in Firestore oder lokal (z.B. SharedPreferences)
  Map<String, dynamic> toJson() => {
    'id': id,
    'recipientName': recipientName,
    'recipientId': recipientId,
    'text': text,
    'date': date.toIso8601String(),
    'status': status,
    'category': category,
  };

  factory SentRecording.fromJson(Map<String, dynamic> json) {
    return SentRecording(
      id: json['id'] as String,
      recipientName: json['recipientName'] as String,
      recipientId: json['recipientId'] as String?,
      text: json['text'] as String,
      date: DateTime.parse(json['date'] as String),
      status: json['status'] as String? ?? "gesendet",
      category: json['category'] as String? ?? 'prophecy',
    );
  }
}
