import 'connection_item.dart';

class ConnectionPair {
  final ConnectionItem first;
  final ConnectionItem second;
  final String relationSummary; // z.B. „Bestätigt Thema X…“
  ConnectionPair({
    required this.first,
    required this.second,
    required this.relationSummary,
  });
}
