enum ItemType { dream, prophecy }

class ConnectionItem {
  final String title; // Für die Anzeige
  final String id;
  final String text;
  final ItemType type;
  final DateTime timestamp;
  final String? filePath; // Audio-URL, falls vorhanden
  ConnectionItem({
    required this.title,
    required this.id,
    required this.text,
    required this.type,
    required this.timestamp,
    this.filePath,
  });
}
