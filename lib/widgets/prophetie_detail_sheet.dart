import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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

  /// Live stream of the Prophetie document
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _prophetieStream;

  DocumentReference<Map<String, dynamic>> _docRef() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('prophetien')
        .doc(widget.prophetieId);
  }

  @override
  void initState() {
    super.initState();
    _loadProphetie();
    _labelsFuture = _loadLabels();
    _prophetieStream = _docRef().snapshots();
  }

  Future<void> _loadProphetie() async {
    final docRef = _docRef();

    // Attempt to load from cache first to prefill controllers fast
    final doc = await docRef
        .get(const GetOptions(source: Source.cache))
        .catchError((_) => docRef.get());
    final data = doc.data();
    if (data != null) {
      _titleController.text = (data['title'] as String?) ?? '';
      _creatorController.text = (data['creatorName'] as String?) ?? '';
      final rawTs = data['timestamp'];
      DateTime dateTime;
      if (rawTs is Timestamp) {
        dateTime = rawTs.toDate();
      } else if (rawTs is String) {
        dateTime = DateTime.tryParse(rawTs) ?? DateTime.now();
      } else {
        dateTime = DateTime.now();
      }
      _dateController.text = DateFormat('dd.MM.yyyy').format(dateTime);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _creatorController.dispose();
    _dateController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// Robustly render a field that may be String or List or null.
  Widget _renderField(dynamic value) {
    if (value == null) {
      return const Text('');
    }
    if (value is List) {
      final items = value
          .cast<dynamic>()
          .map((e) => e?.toString() ?? '')
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (items.isEmpty) return const Text('');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('• '),
                  Expanded(child: Text(item)),
                ],
              ),
            ),
        ],
      );
    }
    if (value is String) {
      final v = value.trim();
      return Text(v.isEmpty ? '' : v);
    }
    return Text(value.toString());
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
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _prophetieStream,
      builder: (ctx, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || !snapshot.hasData || !snapshot.data!.exists) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Fehler beim Laden der Prophetie.'),
          );
        }
        final data = snapshot.data!.data()!;

        // Keep controllers in sync if they are empty (first paint) or if values changed
        if (_titleController.text.isEmpty &&
            (data['title'] as String?) != null) {
          _titleController.text = (data['title'] as String?) ?? '';
        }
        if (_creatorController.text.isEmpty &&
            (data['creatorName'] as String?) != null) {
          _creatorController.text = (data['creatorName'] as String?) ?? '';
        }
        if (_dateController.text.isEmpty && data['timestamp'] != null) {
          final rawTs = data['timestamp'];
          DateTime dateTime;
          if (rawTs is Timestamp) {
            dateTime = rawTs.toDate();
          } else if (rawTs is String) {
            dateTime = DateTime.tryParse(rawTs) ?? DateTime.now();
          } else {
            dateTime = DateTime.now();
          }
          _dateController.text = DateFormat('dd.MM.yyyy').format(dateTime);
        }

        // Bottom-sheet UI with sticky action bar
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 16),
                          // Title and actions
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Expanded(
                                child: SelectableText(
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
                                  final result = await _openEditBottomSheet(
                                    context,
                                    data,
                                  );
                                  if (result != null) {
                                    await _docRef().update(result);
                                  }
                                },
                              ),
                              IconButton(
                                padding: const EdgeInsets.all(4),
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.refresh),
                                tooltip: 'Prophetie neu analysieren',
                                onPressed: () async {
                                  await _reanalyze(context, data);
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Gegeben von: ${_creatorController.text.isNotEmpty ? _creatorController.text : (data['creatorName'] ?? 'Unbekannt')}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            "Empfangen am: ${_dateController.text.isNotEmpty
                                ? _dateController.text
                                : data['timestamp'] is String
                                ? DateFormat('dd.MM.yyyy').format(DateTime.parse(data['timestamp'] as String))
                                : ''}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Audio player if present
                          if (((data['audioUrl'] as String?)?.isNotEmpty ==
                                  true) ||
                              ((data['driveAudioId'] as String?)?.isNotEmpty ==
                                  true) ||
                              ((data['filePath'] as String?)?.isNotEmpty ==
                                  true))
                            _ProphetieAudioPlayer(
                              audioPath:
                                  (data['audioUrl'] as String?) ??
                                  (data['driveAudioId'] as String?) ??
                                  (data['filePath'] as String)!,
                              audioPlayer: _audioPlayer,
                              title: data['title'] as String? ?? '',
                            ),
                          const SizedBox(height: 16),

                          // Collapsible sections
                          _Section(
                            title: '🔑 Hauptpunkte',
                            child: _renderField(
                              data['mainPoints'] ??
                                  'Noch keine Hauptpunkte verfügbar.',
                            ),
                          ),
                          _Section(
                            title: '📝 Zusammenfassung',
                            child: _renderField(
                              data['summary'] ??
                                  'Noch keine Zusammenfassung verfügbar.',
                            ),
                          ),
                          _Section(
                            title: '📚 Beispiele & Zitate',
                            child: _renderField(
                              data['storiesExamplesCitations'] ??
                                  'Noch keine Beispiele verfügbar.',
                            ),
                          ),
                          _Section(
                            title: '🔍 Reflexionsfragen',
                            child: _renderField(
                              data['questions'] ??
                                  'Noch keine Reflexionsfragen verfügbar.',
                            ),
                          ),
                          _Section(
                            title: '✅ Handlungsschritte',
                            child: _renderField(
                              data['actionItems'] ??
                                  'Noch keine Schritte verfügbar.',
                            ),
                          ),
                          _Section(
                            title: '📖 Bibelstellen',
                            child: _renderField(
                              data['verses'] ??
                                  'Noch keine Bibelstellen verfügbar.',
                            ),
                          ),

                          _Section(
                            title: '🎧 Transkript',
                            child: _TranscriptSection(
                              prophetie: Prophetie(
                                id: widget.prophetieId,
                                labels: List<String>.from(data['labels'] ?? []),
                                isFavorit: data['isFavorit'] as bool? ?? false,
                                timestamp: data['timestamp'] is Timestamp
                                    ? (data['timestamp'] as Timestamp).toDate()
                                    : DateTime.parse(
                                        data['timestamp'] as String,
                                      ),
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
                                transcript: data['transcript'] as String?,
                              ),
                            ),
                            initiallyExpanded: false,
                          ),

                          const SizedBox(height: 12),
                          const Text(
                            "🏷️ Label anpassen",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 8),
                          FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
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
                              List<String> _currentLabels = List<String>.from(
                                data['labels'] ?? [],
                              );
                              return StatefulBuilder(
                                builder: (ctx2, setChipState) {
                                  return Wrap(
                                    spacing: 8,
                                    children: labelDocs.map((labelDoc) {
                                      final label = labelDoc['label'] as String;
                                      final isSelected = _currentLabels
                                          .contains(label);
                                      return FilterChip(
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
                                          final docRef = _docRef();
                                          if (selected) {
                                            await docRef.update({
                                              'labels': FieldValue.arrayUnion([
                                                label,
                                              ]),
                                            });
                                            if (!ctx2.mounted) return;
                                            setChipState(
                                              () => _currentLabels.add(label),
                                            );
                                          } else {
                                            await docRef.update({
                                              'labels': FieldValue.arrayRemove([
                                                label,
                                              ]),
                                            });
                                            if (!ctx2.mounted) return;
                                            setChipState(
                                              () =>
                                                  _currentLabels.remove(label),
                                            );
                                          }
                                        },
                                        selectedColor: Colors.black,
                                        checkmarkColor: Colors.white,
                                        backgroundColor: Colors.white,
                                        side: const BorderSide(
                                          color: Colors.black,
                                        ),
                                        labelPadding:
                                            const EdgeInsets.symmetric(
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
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),

                // Sticky action bar
                const SizedBox.shrink(),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>?> _openEditBottomSheet(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    return await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? Colors.white
          : Theme.of(context).scaffoldBackgroundColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Material(
              color: Theme.of(context).brightness == Brightness.light
                  ? Colors.white
                  : Theme.of(context).scaffoldBackgroundColor,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              clipBehavior: Clip.antiAlias,
              child: SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 24,
                    right: 24,
                    top: 16,
                    bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).brightness == Brightness.dark
                              ? Colors.grey[600]
                              : Colors.grey[400],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      Text(
                        'Prophetie bearbeiten',
                        style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _titleController,
                        decoration: InputDecoration(
                          labelText: 'Titel',
                          filled: true,
                          fillColor: Theme.of(ctx).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _creatorController,
                        decoration: InputDecoration(
                          labelText: 'Gegeben von',
                          filled: true,
                          fillColor: Theme.of(ctx).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _dateController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Empfangen am',
                          filled: true,
                          fillColor: Theme.of(ctx).brightness == Brightness.dark
                              ? Colors.grey[800]
                              : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onTap: () async {
                          final initialDate = _dateController.text.isNotEmpty
                              ? DateFormat(
                                  'dd.MM.yyyy',
                                ).parse(_dateController.text)
                              : DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            locale: const Locale('de', 'DE'),
                            initialDate: initialDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) {
                            setModalState(() {
                              _dateController.text = DateFormat(
                                'dd.MM.yyyy',
                              ).format(picked);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () => Navigator.of(ctx).pop(),
                              child: const Text('Abbrechen'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.black,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onPressed: () {
                                final updateData = <String, dynamic>{};
                                if (_titleController.text.trim() !=
                                    (data['title'] ?? '').toString().trim()) {
                                  updateData['title'] = _titleController.text
                                      .trim();
                                }
                                if (_creatorController.text.trim() !=
                                    (data['creatorName'] ?? '')
                                        .toString()
                                        .trim()) {
                                  updateData['creatorName'] = _creatorController
                                      .text
                                      .trim();
                                }
                                if (_dateController.text.trim().isNotEmpty) {
                                  try {
                                    final parsedDate = DateFormat(
                                      'dd.MM.yyyy',
                                    ).parse(_dateController.text.trim());
                                    final originalTimestamp = data['timestamp'];
                                    final originalDate =
                                        originalTimestamp is Timestamp
                                        ? originalTimestamp.toDate()
                                        : (originalTimestamp is String
                                              ? DateTime.tryParse(
                                                  originalTimestamp,
                                                )
                                              : null);
                                    if (originalDate == null ||
                                        !isSameDate(parsedDate, originalDate)) {
                                      updateData['timestamp'] =
                                          Timestamp.fromDate(parsedDate);
                                    }
                                  } catch (e) {
                                    debugPrint(
                                      '❌ Fehler beim Parsen des Datums: $e',
                                    );
                                  }
                                }
                                Navigator.of(ctx).pop(updateData);
                              },
                              child: const Text('Speichern'),
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
  }

  Future<void> _reanalyze(
    BuildContext context,
    Map<String, dynamic> data,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Prophetie neu analysieren?'),
        content: const Text(
          'Möchtest du die Prophetie erneut von der KI analysieren lassen?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    // Lade-Dialog anzeigen
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 16),
            Expanded(child: Text('Analyse läuft…')),
          ],
        ),
      ),
    );

    final dataMap = data;
    final rawTranscript = dataMap['transcript'];
    final transcriptText = rawTranscript is String ? rawTranscript.trim() : '';
    final fallbackText = (dataMap['text'] as String?)?.trim() ?? '';
    final textContent = transcriptText.isNotEmpty
        ? transcriptText
        : fallbackText;

    if (textContent.isNotEmpty) {
      await analyzeAndSaveProphetie(
        transcript: textContent,
        firestoreDocId: widget.prophetieId,
        onReload: _loadProphetie,
      );
    } else {
      final audioUrl = dataMap['audioUrl'] as String?;
      final filePath = audioUrl ?? (dataMap['filePath'] as String?);
      if (filePath != null && filePath.isNotEmpty) {
        await transcribeAndPrepareAnalysis(
          filePath: filePath,
          docId: widget.prophetieId,
          collectionName: 'prophetien',
          isRemoteUrl: audioUrl != null,
          onComplete: _loadProphetie,
        );
      } else {
        Navigator.of(context).pop();
        showFlushbar('Kein Text/Transkript oder Audio verfügbar.');
        return;
      }
    }

    Navigator.of(context).pop();
  }
}

/// Widget für Audio-Playback einer Prophetie
class _ProphetieAudioPlayer extends StatefulWidget {
  final String audioPath;
  final AudioPlayer audioPlayer;
  final String title;
  const _ProphetieAudioPlayer({
    required this.audioPath,
    required this.audioPlayer,
    this.title = '',
    Key? key,
  }) : super(key: key);

  @override
  State<_ProphetieAudioPlayer> createState() => _ProphetieAudioPlayerState();
}

class _ProphetieAudioPlayerState extends State<_ProphetieAudioPlayer> {
  double _playbackSpeed = 1.0;
  String? _error;
  bool isLoadingAudio = false;

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    setState(() {
      isLoadingAudio = true;
      _error = null;
    });
    try {
      String localPath = widget.audioPath;
      if (widget.audioPath.startsWith('http')) {
        // Download mit Cache Manager
        final file = await DefaultCacheManager().getSingleFile(
          widget.audioPath,
        );
        localPath = file.path;
      }
      final file = File(localPath);
      if (!file.existsSync()) {
        setState(() {
          _error = 'Die Audiodatei existiert nicht ($localPath)';
          isLoadingAudio = false;
        });
        debugPrint(_error!);
        return;
      }
      final size = await file.length();
      if (size < 1000) {
        setState(() {
          _error =
              'Die Audiodatei ist zu klein oder beschädigt (${size} Bytes)';
          isLoadingAudio = false;
        });
        debugPrint(_error!);
        return;
      }
      await widget.audioPlayer.setAudioSource(
        AudioSource.uri(
          Uri.parse(
            localPath.startsWith('http')
                ? localPath
                : Uri.file(localPath).toString(),
          ),
          tag: MediaItem(
            id: widget.audioPath,
            album: 'Prophetien',
            title: widget.title.isNotEmpty ? widget.title : 'title',
          ),
        ),
      );
      await widget.audioPlayer.setSpeed(_playbackSpeed);
      // Removed auto-play to require user interaction for playback
      // widget.audioPlayer.play();
      setState(() {
        isLoadingAudio = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Fehler beim Initialisieren des Audios: $e';
        isLoadingAudio = false;
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
                  icon: isLoadingAudio
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: isLoadingAudio
                      ? null
                      : () {
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
    // Important: Do NOT dispose the passed-in AudioPlayer here – owner manages lifecycle.
    // We just pause to be safe.
    try {
      if (widget.audioPlayer.playing) {
        widget.audioPlayer.pause();
      }
    } catch (e) {
      debugPrint('Audio player pause error on dispose: $e');
    }
    super.dispose();
  }
}

/// Widget für Transkript-Anzeige ohne Toggle. Zeigt immer den vollständigen Text.
class _TranscriptSection extends StatelessWidget {
  final Prophetie prophetie;
  const _TranscriptSection({required this.prophetie, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final rawTranscript = prophetie.transcript;
    final transcript = (rawTranscript != null && rawTranscript.isNotEmpty)
        ? rawTranscript
        : (prophetie.transcript ?? '');

    if (transcript.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          transcript,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }
}

bool isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Section extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  const _Section({
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
  });

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _expanded;
  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: widget.child,
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }
}
