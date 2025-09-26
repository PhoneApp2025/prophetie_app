import 'package:flutter/material.dart';
import '../models/match_models.dart';
import '../services/match_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UebereinstimmungenScreen extends StatefulWidget {
  const UebereinstimmungenScreen({super.key});

  @override
  State<UebereinstimmungenScreen> createState() =>
      _UebereinstimmungenScreenState();
}

class _UebereinstimmungenScreenState extends State<UebereinstimmungenScreen> {
  late Future<AnalysisResult> _future;
  late final MatchService _matchService;

  @override
  void initState() {
    super.initState();
    final userId = FirebaseAuth.instance.currentUser!.uid;
    _matchService = MatchService(userId: userId);
    _future = _matchService.analyzeConnections();
  }

  void _rebuildConnections() {
    setState(() {
      _future = _matchService.analyzeConnections(forceRebuild: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Übereinstimmungen'),
        actions: [
          IconButton(
            tooltip: 'Neu berechnen',
            icon: const Icon(Icons.autorenew_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Alle Übereinstimmungen neu berechnen?'),
                  content: const Text(
                    'Dies kann eine Weile dauern und Rate Limits beanspruchen.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Starten'),
                    ),
                  ],
                ),
              );
              if (ok == true) {
                _rebuildConnections();
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<AnalysisResult>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Fehler: ${snapshot.error}'));
          }
          final result = snapshot.data;
          if (result == null || result.matches.isEmpty) {
            return const Center(
              child: Text('Keine Übereinstimmungen gefunden.'),
            );
          }
          return ListView.builder(
            itemCount: result.matches.length,
            itemBuilder: (context, index) {
              final match = result.matches[index];
              return ListTile(
                title: Text('Match: ${match.aId} ↔ ${match.bId}'),
                subtitle: Text(match.rationale),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () {
                        // TODO: Implement accept logic
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        // TODO: Implement reject logic
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}