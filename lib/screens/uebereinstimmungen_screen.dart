import 'package:flutter/material.dart';
import 'package:prophetie_app/models/connection_suggestion.dart';
import 'package:prophetie_app/models/feedback_log.dart';
import 'package:prophetie_app/services/connection_suggestion_service.dart';
import 'package:prophetie_app/services/feedback_service.dart';

class UebereinstimmungenScreen extends StatefulWidget {
  const UebereinstimmungenScreen({super.key});

  @override
  State<UebereinstimmungenScreen> createState() =>
      _UebereinstimmungenScreenState();
}

class _UebereinstimmungenScreenState extends State<UebereinstimmungenScreen> {
  final ConnectionSuggestionService _suggestionService =
      ConnectionSuggestionService();
  final FeedbackService _feedbackService = FeedbackService.instance;
  late Future<List<ConnectionSuggestion>> _suggestionsFuture;

  @override
  void initState() {
    super.initState();
    _loadSuggestions();
  }

  void _loadSuggestions() {
    setState(() {
      _suggestionsFuture = _suggestionService.getSuggestions();
    });
  }

  Future<void> _handleDecision(
      ConnectionSuggestion suggestion, FeedbackDecision decision) async {
    // Optimistically remove the card from the UI
    final currentState = await _suggestionsFuture;
    setState(() {
      currentState.removeWhere((s) => s.id == suggestion.id);
    });

    try {
      await _feedbackService.recordDecision(
        suggestion: suggestion,
        decision: decision,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Danke für dein Feedback! ${decision == FeedbackDecision.accepted ? 'Verbindung gespeichert.' : 'Vorschlag verworfen.'}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      // If the API call fails, add the card back and show an error
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler: ${e.toString()}')),
      );
      _loadSuggestions(); // Reload to get the correct state
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vorschläge für Verbindungen'),
        actions: [
          IconButton(
            tooltip: 'Vorschläge aktualisieren',
            icon: const Icon(Icons.refresh),
            onPressed: _loadSuggestions,
          ),
        ],
      ),
      body: FutureBuilder<List<ConnectionSuggestion>>(
        future: _suggestionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Fehler beim Laden der Vorschläge: ${snapshot.error}'));
          }
          final suggestions = snapshot.data ?? [];
          if (suggestions.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Sehr gut! Du hast alle aktuellen Vorschläge bewertet. Das System lernt aus deinen Entscheidungen und generiert bald neue.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            itemCount: suggestions.length,
            itemBuilder: (context, index) {
              final suggestion = suggestions[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${suggestion.first.title} ↔ ${suggestion.second.title}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      Chip(
                        label: Text(
                          '${(suggestion.score * 100).toInt()}% Übereinstimmung',
                        ),
                        backgroundColor:
                            Colors.blue.shade50.withOpacity(0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(suggestion.explanation,
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _handleDecision(
                                suggestion, FeedbackDecision.rejected),
                            child: const Text('Verwerfen'),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: () => _handleDecision(
                                suggestion, FeedbackDecision.accepted),
                            child: const Text('Passt'),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}