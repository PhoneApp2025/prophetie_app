import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import '../models/prophetie.dart';
import 'package:intl/intl.dart';
import '../services/prophetie_analysis_service.dart';
import '../services/audio_transcription_service.dart';
import 'package:prophetie_app/main.dart';

class ProphetieDetailSheet extends StatefulWidget {
  final String prophetieId;
  const ProphetieDetailSheet({required this.prophetieId, Key? key})
    : super(key: key);

  @override
  State<ProphetieDetailSheet> createState() => _ProphetieDetailSheetState();
}

class _ProphetieDetailSheetState extends State<ProphetieDetailSheet> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _prophetieFuture;
  final _titleController = TextEditingController();
  final _creatorController = TextEditingController();
  final _dateController = TextEditingController();
  late Future<List<Map<String, String>>> _labelsFuture;
  // Persistent audio player to avoid restarting on rebuild
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadProphetie();
    _labelsFuture = _loadLabels();
  }

  Future<void> _loadProphetie() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('prophetien')
        .doc(widget.prophetieId);

    // Attempt to load from cache first, then fallback to server
    _prophetieFuture = docRef
        .get(const GetOptions(source: Source.cache))
        .catchError((_) => docRef.get());

    // Also populate controllers with cached data
    final doc = await docRef
        .get(const GetOptions(source: Source.cache))
        .catchError((_) => docRef.get());
    final data = doc.data()!;
    _titleController.text = data['title'] as String? ?? '';
    _creatorController.text = data['creatorName'] as String? ?? '';
    final rawTs = data['timestamp'];
    DateTime dateTime;
    if (rawTs is Timestamp) {
      dateTime = rawTs.toDate();
    } else if (rawTs is String) {
      dateTime = DateTime.parse(rawTs);
    } else {
      dateTime = DateTime.now();
    }
    _dateController.text = DateFormat('dd.MM.yyyy').format(dateTime);
    // Ensure the FutureBuilder is triggered with updated data
    _prophetieFuture = docRef.get();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _creatorController.dispose();
    _dateController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<List<Map<String, String>>> _loadLabels() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('labels')
        .get();
    return snapshot.docs
        .map(
          (doc) => {
            'id': doc.id,
            'label': (doc.data()['label'] as String?) ?? doc.id,
          },
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _prophetieFuture,
      builder: (ctx, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Fehler beim Laden der Prophetie.'),
          );
        }
        final data = snapshot.data!.data()!;
        // Bottom-sheet UI:
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle drag handle
                    Padding(
                      padding: const EdgeInsets.only(top: 1, bottom: 10),
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    // Title and edit button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            _titleController.text.isNotEmpty
                                ? _titleController.text
                                : data['text'] as String? ?? '',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 20,
                            ),
                          ),
                        ),
                        IconButton(
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final result = await showModalBottomSheet<Map<String, dynamic>>(
                              context: context,
                              backgroundColor:
                                  Theme.of(context).brightness ==
                                      Brightness.light
                                  ? Colors.white
                                  : Theme.of(context).scaffoldBackgroundColor,
                              isScrollControlled: true,
                              shape: const RoundedRectangleBorder(
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
                              ),
                              builder: (ctx) {
                                return StatefulBuilder(
                                  builder: (ctx2, setModalState) {
                                    return Material(
                                      color:
                                          Theme.of(context).brightness ==
                                              Brightness.light
                                          ? Colors.white
                                          : Theme.of(
                                              context,
                                            ).scaffoldBackgroundColor,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                          top: Radius.circular(24),
                                        ),
                                      ),
                                      clipBehavior: Clip.antiAlias,
                                      child: SafeArea(
                                        child: Padding(
                                          padding: EdgeInsets.only(
                                            left: 24,
                                            right: 24,
                                            top: 16,
                                            bottom:
                                                MediaQuery.of(
                                                  ctx,
                                                ).viewInsets.bottom +
                                                16,
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Container(
                                                width: 40,
                                                height: 4,
                                                margin: const EdgeInsets.only(
                                                  bottom: 12,
                                                ),
                                                decoration: BoxDecoration(
                                                  color:
                                                      Theme.of(
                                                            ctx,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors.grey[600]
                                                      : Colors.grey[400],
                                                  borderRadius:
                                                      BorderRadius.circular(2),
                                                ),
                                              ),
                                              Text(
                                                'Prophetie bearbeiten',
                                                style: Theme.of(ctx)
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                              ),
                                              const SizedBox(height: 16),
                                              // Titel
                                              TextField(
                                                controller: _titleController,
                                                decoration: InputDecoration(
                                                  labelText: 'Titel',
                                                  filled: true,
                                                  fillColor:
                                                      Theme.of(
                                                            ctx,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors.grey[800]
                                                      : Colors.grey[100],
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              // Gegeben von
                                              TextField(
                                                controller: _creatorController,
                                                decoration: InputDecoration(
                                                  labelText: 'Gegeben von',
                                                  filled: true,
                                                  fillColor:
                                                      Theme.of(
                                                            ctx,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors.grey[800]
                                                      : Colors.grey[100],
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(height: 12),
                                              // Empfangen am
                                              TextField(
                                                controller: _dateController,
                                                readOnly: true,
                                                decoration: InputDecoration(
                                                  labelText: 'Empfangen am',
                                                  filled: true,
                                                  fillColor:
                                                      Theme.of(
                                                            ctx,
                                                          ).brightness ==
                                                          Brightness.dark
                                                      ? Colors.grey[800]
                                                      : Colors.grey[100],
                                                  border: OutlineInputBorder(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          8,
                                                        ),
                                                    borderSide: BorderSide.none,
                                                  ),
                                                ),
                                                onTap: () async {
                                                  final initialDate =
                                                      _dateController
                                                          .text
                                                          .isNotEmpty
                                                      ? DateFormat(
                                                          'dd.MM.yyyy',
                                                        ).parse(
                                                          _dateController.text,
                                                        )
                                                      : DateTime.now();
                                                  final picked =
                                                      await showDatePicker(
                                                        context: context,
                                                        locale: const Locale(
                                                          'de',
                                                          'DE',
                                                        ),
                                                        initialDate:
                                                            initialDate,
                                                        firstDate: DateTime(
                                                          2000,
                                                        ),
                                                        lastDate:
                                                            DateTime.now(),
                                                      );
                                                  if (picked != null) {
                                                    setModalState(() {
                                                      _dateController.text =
                                                          DateFormat(
                                                            'dd.MM.yyyy',
                                                          ).format(picked);
                                                    });
                                                  }
                                                },
                                              ),
                                              const SizedBox(height: 24),
                                              // Buttons
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.black,
                                                        foregroundColor:
                                                            Colors.white,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                      ),
                                                      onPressed: () =>
                                                          Navigator.of(
                                                            ctx,
                                                          ).pop(),
                                                      child: const Text(
                                                        'Abbrechen',
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 12),
                                                  Expanded(
                                                    child: ElevatedButton(
                                                      style: ElevatedButton.styleFrom(
                                                        backgroundColor:
                                                            Colors.black,
                                                        foregroundColor:
                                                            Colors.white,
                                                        shape: RoundedRectangleBorder(
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                        ),
                                                      ),
                                                      onPressed: () {
                                                        final updateData =
                                                            <String, dynamic>{};

                                                        if (_titleController
                                                                .text
                                                                .trim() !=
                                                            (data['title'] ??
                                                                    '')
                                                                .toString()
                                                                .trim()) {
                                                          updateData['title'] =
                                                              _titleController
                                                                  .text
                                                                  .trim();
                                                        }

                                                        if (_creatorController
                                                                .text
                                                                .trim() !=
                                                            (data['creatorName'] ??
                                                                    '')
                                                                .toString()
                                                                .trim()) {
                                                          updateData['creatorName'] =
                                                              _creatorController
                                                                  .text
                                                                  .trim();
                                                        }

                                                        if (_dateController.text
                                                            .trim()
                                                            .isNotEmpty) {
                                                          try {
                                                            final parsedDate =
                                                                DateFormat(
                                                                  'dd.MM.yyyy',
                                                                ).parse(
                                                                  _dateController
                                                                      .text
                                                                      .trim(),
                                                                );
                                                            final originalTimestamp =
                                                                data['timestamp'];
                                                            final originalDate =
                                                                originalTimestamp
                                                                    is Timestamp
                                                                ? originalTimestamp
                                                                      .toDate()
                                                                : (originalTimestamp
                                                                          is String
                                                                      ? DateTime.tryParse(
                                                                          originalTimestamp,
                                                                        )
                                                                      : null);

                                                            if (originalDate ==
                                                                    null ||
                                                                !isSameDate(
                                                                  parsedDate,
                                                                  originalDate,
                                                                )) {
                                                              updateData['timestamp'] =
                                                                  Timestamp.fromDate(
                                                                    parsedDate,
                                                                  );
                                                            }
                                                          } catch (e) {
                                                            print(
                                                              '❌ Fehler beim Parsen des Datums: $e',
                                                            );
                                                          }
                                                        }

                                                        Navigator.of(
                                                          ctx,
                                                        ).pop(updateData);
                                                      },
                                                      child: const Text(
                                                        'Speichern',
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            );
                            if (result != null) {
                              final uid =
                                  FirebaseAuth.instance.currentUser!.uid;
                              final docRef = FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(uid)
                                  .collection('prophetien')
                                  .doc(widget.prophetieId);
                              await docRef.update(result);
                              // Refresh detail via FutureBuilder
                              setState(() {
                                _prophetieFuture = docRef.get();
                              });
                            }
                          },
                        ),
                        SizedBox(width: 0),
                        IconButton(
                          padding: const EdgeInsets.all(4),
                          constraints: const BoxConstraints(),
                          icon: const Icon(Icons.refresh),
                          tooltip: 'Prophetie neu analysieren',
                          onPressed: () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Prophetie neu analysieren?'),
                                content: const Text(
                                  'Möchtest du die Prophetie erneut von der KI analysieren lassen?',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(false),
                                    child: const Text('Abbrechen'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () =>
                                        Navigator.of(ctx).pop(true),
                                    child: const Text('OK'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;

                            final uid = FirebaseAuth.instance.currentUser!.uid;
                            final docRef = FirebaseFirestore.instance
                                .collection('users')
                                .doc(uid)
                                .collection('prophetien')
                                .doc(widget.prophetieId);

                            // Lade-Dialog anzeigen
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (_) => AlertDialog(
                                content: Row(
                                  children: const [
                                    SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                    SizedBox(width: 16),
                                    Expanded(child: Text('Analyse läuft…')),
                                  ],
                                ),
                              ),
                            );

                            // Prophetie-Daten laden & Logik für Analyse/Transkription
                            final prophetieDoc = await docRef.get();
                            final dataMap = prophetieDoc.data() ?? {};

                            // Use existing transcript or fallback to the 'text' field
                            final rawTranscript = dataMap['transcript'];
                            final transcriptText = rawTranscript is String
                                ? rawTranscript.trim()
                                : '';
                            final fallbackText =
                                (dataMap['text'] as String?)?.trim() ?? '';
                            final textContent = transcriptText.isNotEmpty
                                ? transcriptText
                                : fallbackText;

                            if (textContent.isNotEmpty) {
                              // Analyse basierend auf vorhandenem Text oder Transkript
                              await analyzeAndSaveProphetie(
                                transcript: textContent,
                                firestoreDocId: widget.prophetieId,
                                onReload: _loadProphetie,
                              );
                            } else {
                              // Keine Textdaten, daher Audio transkribieren und dann analysieren
                              final audioUrl = dataMap['audioUrl'] as String?;
                              final filePath =
                                  audioUrl ?? (dataMap['filePath'] as String?);
                              if (filePath != null && filePath.isNotEmpty) {
                                await transcribeAndPrepareAnalysis(
                                  filePath: filePath,
                                  docId: widget.prophetieId,
                                  collectionName: 'prophetien',
                                  isRemoteUrl: audioUrl != null,
                                  onComplete: _loadProphetie,
                                );
                              } else {
                                Navigator.of(
                                  context,
                                ).pop(); // Lade-Dialog schließen
                                showFlushbar(
                                  'Kein Text/Transkript oder Audio verfügbar.',
                                );
                                return;
                              }
                            }

                            // Lade-Dialog schließen
                            Navigator.of(context).pop();

                            // Prophetie neu laden & UI updaten
                            await _loadProphetie();
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Gegeben von: ${_creatorController.text.isNotEmpty ? _creatorController.text : (data['creatorName'] ?? 'Unbekannt')}",
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    Text(
                      "Empfangen am: ${_dateController.text.isNotEmpty
                          ? _dateController.text
                          : data['timestamp'] is String
                          ? DateFormat('dd.MM.yyyy').format(DateTime.parse(data['timestamp'] as String))
                          : ''}",
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    // Audio player if present
                    if (((data['audioUrl'] as String?)?.isNotEmpty == true) ||
                        ((data['driveAudioId'] as String?)?.isNotEmpty ==
                            true) ||
                        ((data['filePath'] as String?)?.isNotEmpty == true))
                      _ProphetieAudioPlayer(
                        audioPath:
                            (data['audioUrl'] as String?) ??
                            (data['driveAudioId'] as String?) ??
                            (data['filePath'] as String)!,
                        audioPlayer: _audioPlayer,
                      ),
                    const SizedBox(height: 24),
                    // Hauptpunkte
                    const Text(
                      "🔑 Hauptpunkte",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['mainPoints'] as String? ??
                          "Noch keine Hauptpunkte verfügbar.",
                    ),
                    const SizedBox(height: 24),
                    // Zusammenfassung
                    const Text(
                      "📝 Zusammenfassung",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['summary'] as String? ??
                          "Noch keine Zusammenfassung verfügbar.",
                    ),
                    const SizedBox(height: 24),
                    // Beispiele & Zitate
                    const Text(
                      "📚 Beispiele & Zitate",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['storiesExamplesCitations'] as String? ??
                          "Noch keine Beispiele verfügbar.",
                    ),
                    const SizedBox(height: 24),
                    // Reflexionsfragen
                    const Text(
                      "🔍 Reflexionsfragen",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['questions'] as String? ??
                          "Noch keine Reflexionsfragen verfügbar.",
                    ),
                    const SizedBox(height: 24),
                    // Handlungsschritte
                    const Text(
                      "✅ Handlungsschritte",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['actionItems'] as String? ??
                          "Noch keine Schritte verfügbar.",
                    ),
                    const SizedBox(height: 24),
                    // Bibelstellen
                    const Text(
                      "📖 Bibelstellen",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['verses'] as String? ??
                          "Noch keine Bibelstellen verfügbar.",
                    ),
                    const SizedBox(height: 24),
                    // Verwandte Themen
                    const Text(
                      "🔗 Verwandte Themen",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      data['relatedTopics'] as String? ??
                          "Noch keine verwandten Themen verfügbar.",
                    ),
                    const SizedBox(height: 24),
                    // Transkript
                    _TranscriptSection(
                      prophetie: Prophetie(
                        id: widget.prophetieId,
                        label: data['label'] as String? ?? '',
                        isFavorit: data['isFavorit'] as bool? ?? false,
                        timestamp: data['timestamp'] is Timestamp
                            ? (data['timestamp'] as Timestamp).toDate()
                            : DateTime.parse(data['timestamp'] as String),
                        filePath:
                            data['audioUrl'] as String? ??
                            data['filePath'] as String?,
                        creatorName: data['creatorName'] as String?,
                        mainPoints: data['mainPoints'] as String?,
                        summary: data['summary'] as String?,
                        verses: data['verses'] as String?,
                        questions: data['questions'] as String?,
                        similar: data['similar'] as String?,
                        title: data['title'] as String?,
                        storiesExamplesCitations:
                            data['storiesExamplesCitations'] as String?,
                        actionItems: data['actionItems'] as String?,
                        relatedTopics: data['relatedTopics'] as String?,
                        transcript: data['transcript'] as String?,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Label-Anpassung
                    const Text(
                      "🏷️ Label anpassen",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    // Label-Chips: State lokal im StatefulBuilder, kein globales setState!
                    StatefulBuilder(
                      builder: (ctx, setLabelState) {
                        // Lokale Variable, damit kein globales setState benötigt wird
                        String? currentLabel = data['label'] as String?;
                        return FutureBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .collection('labels')
                              .get(),
                          builder: (ctx, labelSnapshot) {
                            if (labelSnapshot.connectionState !=
                                    ConnectionState.done ||
                                !labelSnapshot.hasData) {
                              return const SizedBox.shrink();
                            }
                            final labelDocs = labelSnapshot.data!.docs;
                            return Wrap(
                              spacing: 8,
                              children: labelDocs.map((labelDoc) {
                                final label = labelDoc['label'] as String;
                                final isSelected = label == currentLabel;
                                return ChoiceChip(
                                  label: Text(
                                    label,
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black,
                                      fontSize: 14,
                                    ),
                                  ),
                                  selected: isSelected,
                                  onSelected: (selected) async {
                                    if (!selected) return;
                                    final uid =
                                        FirebaseAuth.instance.currentUser!.uid;
                                    await FirebaseFirestore.instance
                                        .collection('users')
                                        .doc(uid)
                                        .collection('prophetien')
                                        .doc(widget.prophetieId)
                                        .update({'label': label});
                                    setLabelState(() {
                                      currentLabel = label;
                                    });
                                  },
                                  selectedColor: Colors.black,
                                  backgroundColor: Colors.white,
                                  side: const BorderSide(color: Colors.black),
                                  labelPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Widget für Audio-Playback einer Prophetie
class _ProphetieAudioPlayer extends StatefulWidget {
  final String audioPath;
  final AudioPlayer audioPlayer;
  const _ProphetieAudioPlayer({
    required this.audioPath,
    required this.audioPlayer,
    Key? key,
  }) : super(key: key);

  @override
  State<_ProphetieAudioPlayer> createState() => _ProphetieAudioPlayerState();
}

class _ProphetieAudioPlayerState extends State<_ProphetieAudioPlayer> {
  double _playbackSpeed = 1.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    try {
      if (widget.audioPath.startsWith('http')) {
        await widget.audioPlayer.setUrl(widget.audioPath);
        await widget.audioPlayer.setSpeed(_playbackSpeed);
      } else {
        final file = File(widget.audioPath);
        if (!file.existsSync()) {
          setState(() {
            _error = 'Die Audiodatei existiert nicht (${widget.audioPath})';
          });
          debugPrint(_error!);
          return;
        }
        final size = await file.length();
        if (size < 1000) {
          setState(() {
            _error =
                'Die Audiodatei ist zu klein oder beschädigt (${size} Bytes)';
          });
          debugPrint(_error!);
          return;
        }
        await widget.audioPlayer.setFilePath(widget.audioPath);
        await widget.audioPlayer.setSpeed(_playbackSpeed);
      }
    } catch (e) {
      setState(() {
        _error = 'Fehler beim Initialisieren des Audios: $e';
      });
      debugPrint('Fehler beim Initialisieren des Audios: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "",
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        const SizedBox(height: 8),
        StreamBuilder<PlayerState>(
          stream: widget.audioPlayer.playerStateStream,
          builder: (context, snapshot) {
            final playerState = snapshot.data;
            final playing = playerState?.playing ?? false;
            return Row(
              children: [
                IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (playing) {
                      widget.audioPlayer.pause();
                    } else {
                      widget.audioPlayer.play();
                    }
                  },
                ),
                GestureDetector(
                  onTap: () async {
                    const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
                    final currentIndex = speeds.indexOf(_playbackSpeed);
                    final nextIndex = (currentIndex + 1) % speeds.length;
                    final nextSpeed = speeds[nextIndex];
                    // Preserve current playback state and position
                    final wasPlaying = widget.audioPlayer.playing;
                    final position = widget.audioPlayer.position;
                    setState(() {
                      _playbackSpeed = nextSpeed;
                    });
                    await widget.audioPlayer.setSpeed(nextSpeed);
                    await widget.audioPlayer.seek(position);
                    if (wasPlaying) {
                      widget.audioPlayer.play();
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      '${_playbackSpeed.toStringAsFixed(_playbackSpeed.truncateToDouble() == _playbackSpeed ? 0 : 2)}x',
                      style: TextStyle(
                        color: Theme.of(context).iconTheme.color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                StreamBuilder<Duration?>(
                  stream: widget.audioPlayer.durationStream,
                  builder: (context, durationSnapshot) {
                    final duration = durationSnapshot.data ?? Duration.zero;
                    return StreamBuilder<Duration>(
                      stream: widget.audioPlayer.positionStream,
                      builder: (context, posSnapshot) {
                        final pos = posSnapshot.data ?? Duration.zero;
                        return Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: const Color(0xFFFF2D55),
                              inactiveTrackColor: const Color(
                                0xFFFF2D55,
                              ).withOpacity(0.3),
                              thumbColor: const Color(0xFFFF2D55),
                              overlayColor: const Color(
                                0xFFFF2D55,
                              ).withOpacity(0.2),
                            ),
                            child: Slider(
                              min: 0,
                              max: duration.inMilliseconds.toDouble(),
                              value: pos.inMilliseconds
                                  .clamp(0, duration.inMilliseconds)
                                  .toDouble(),
                              onChanged: (value) {
                                widget.audioPlayer.seek(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  @override
  void dispose() {
    // Stop and dispose audio when sheet is closed, catching errors
    widget.audioPlayer.stop().catchError((e) {
      debugPrint('AudioPlayer.stop error: $e');
    });
    widget.audioPlayer.dispose().catchError((e) {
      debugPrint('AudioPlayer.dispose error: $e');
    });
    super.dispose();
  }
}

/// Widget für Transkript-Anzeige mit "Mehr anzeigen"/"Weniger anzeigen" Logik
class _TranscriptSection extends StatefulWidget {
  final Prophetie prophetie;
  const _TranscriptSection({required this.prophetie, Key? key})
    : super(key: key);

  @override
  State<_TranscriptSection> createState() => _TranscriptSectionState();
}

class _TranscriptSectionState extends State<_TranscriptSection> {
  bool isExpandedTranscript = false;

  @override
  Widget build(BuildContext context) {
    final rawTranscript = widget.prophetie.transcript;
    final transcript = (rawTranscript != null && rawTranscript.isNotEmpty)
        ? rawTranscript
        : (widget.prophetie.transcript ?? '');
    if (transcript.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '🎧 Transkript',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          isExpandedTranscript
              ? transcript
              : transcript.length > 150
              ? '${transcript.substring(0, 150)}...'
              : transcript,
          style: const TextStyle(fontSize: 14),
        ),
        if (transcript.length > 150)
          TextButton(
            onPressed: () {
              setState(() {
                isExpandedTranscript = !isExpandedTranscript;
              });
            },
            child: Text(
              isExpandedTranscript ? 'Weniger anzeigen' : 'Mehr anzeigen',
            ),
          ),
      ],
    );
  }
}

bool isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
