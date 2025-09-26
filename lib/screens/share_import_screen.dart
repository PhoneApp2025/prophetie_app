import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../providers/prophetie_provider.dart';
import '../providers/traum_provider.dart';
import '../main.dart'; // for showFlushbar

const Color _kAccent = Color(0xFFFF2C55);

class ShareImportScreen extends StatefulWidget {
  final String filePath;
  const ShareImportScreen({super.key, required this.filePath});

  @override
  State<ShareImportScreen> createState() => _ShareImportScreenState();
}

class _ShareImportScreenState extends State<ShareImportScreen> {
  String? _type; // 'prophetie' | 'traum'
  bool _isImporting = false;

  Future<void> _startImport() async {
    if (_type == null || _isImporting) return;
    await HapticFeedback.mediumImpact();
    setState(() => _isImporting = true);

    try {
      final file = File(widget.filePath);
      if (!await file.exists()) {
        // Kein Navigationswechsel -> Flushbar darf direkt angezeigt werden
        showFlushbar('Datei wurde nicht gefunden.');
        setState(() => _isImporting = false);
        return;
      }

      final id = const Uuid().v4();

      if (_type == 'prophetie') {
        await Provider.of<ProphetieProvider>(context, listen: false).handleNewProphetie(
          id: id,
          localFilePath: widget.filePath,
          transcriptText: null,
          labels: const [],
        );
      } else if (_type == 'traum') {
        await Provider.of<TraumProvider>(context, listen: false).handleNewTraum(
          id: id,
          localFilePath: widget.filePath,
          transcriptText: null,
          labels: const [],
        );
      }

      // 1) Mini-Delay, damit der Nutzer das Loading sieht
      await Future.delayed(const Duration(seconds: 2));

      // 2) Screen schließen
      if (mounted) Navigator.of(context).pop();

      // 3) Warten bis Pop-Transition fertig ist, damit der Navigator nicht locked ist
      await Future.delayed(const Duration(milliseconds: 400));

      // 4) Flushbar sicher auf dem Root-Navigator zeigen
      final rootCtx = navigatorKey.currentContext;
      if (rootCtx != null) {
        if (_type == 'prophetie') {
          showFlushbar('Prophetie importiert. Transkription & Analyse gestartet.');
        } else if (_type == 'traum') {
          showFlushbar('Traum importiert. Transkription & Analyse gestartet.');
        }
      }
    } catch (e) {
      // Bei Fehlern wieder interaktiv werden und Feedback geben
      showFlushbar('Import fehlgeschlagen: $e');
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseName = widget.filePath.split('/').last;
    final theme = Theme.of(context);

    return HeroMode(
      enabled: false,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          title: const Text('Audio importieren'),
          centerTitle: false,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 720),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.dividerColor.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _kAccent.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.audiotrack,
                            size: 22,
                            color: _kAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Was möchtest du importieren?',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Wähle aus, ob die Aufnahme ein Traum oder eine Prophetie ist. Danach starten Transkription und Analyse automatisch.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(0.8),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 16),

                    // Type selection
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'prophetie',
                          label: Text('Prophetie'),
                          icon: Icon(Icons.record_voice_over_outlined),
                        ),
                        ButtonSegment(
                          value: 'traum',
                          label: Text('Traum'),
                          icon: Icon(Icons.nights_stay_outlined),
                        ),
                      ],
                      selected: _type == null ? {} : {_type!},
                      emptySelectionAllowed: true,
                      onSelectionChanged: (set) => setState(() => _type = set.isEmpty ? null : set.first),
                    ),

                    const SizedBox(height: 16),

                    // File chip
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: _kAccent.withOpacity(0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _kAccent.withOpacity(0.12)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.music_note, size: 18, color: _kAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              baseName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.textTheme.bodyMedium?.color?.withOpacity(0.9),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Primary action
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _isImporting
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.download_done),
                        label: Text(_isImporting ? 'Importiere…' : 'Importieren'),
                        onPressed: (_type == null || _isImporting) ? null : _startImport,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
