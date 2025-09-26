import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:async';
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

  // Transcript editing state
  final TextEditingController _transcriptController = TextEditingController();
  bool _isEditingTranscript = false;
  String _originalTranscript = '';
  Timer? _transcriptDebounce;

  // Notes editing state
  final TextEditingController _notesController = TextEditingController();
  bool _isEditingNotes = false;
  String _originalNotes = '';
  Timer? _notesDebounce;

  final GlobalKey<_SectionState> _transcriptSectionKey = GlobalKey<_SectionState>();
  final GlobalKey<_SectionState> _notesSectionKey = GlobalKey<_SectionState>();

  // Keyboard-safe scrolling helpers
  final ScrollController _sheetScroll = ScrollController();
  final FocusNode _transcriptFocus = FocusNode();
  final FocusNode _notesFocus = FocusNode();
  final GlobalKey _transcriptFieldKey = GlobalKey();
  final GlobalKey _notesFieldKey = GlobalKey();

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
      // Prefill transcript editor from loaded data
      final tx = (data['transcript'] as String?)?.trim() ?? '';
      if (tx.isNotEmpty && _transcriptController.text.isEmpty) {
        _transcriptController.text = tx;
      }
      // Prefill notes editor
      final nx = (data['notes'] as String?)?.trim() ?? '';
      if (nx.isNotEmpty && _notesController.text.isEmpty) {
        _notesController.text = nx;
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _creatorController.dispose();
    _dateController.dispose();
    _audioPlayer.dispose();
    _transcriptDebounce?.cancel();
    _transcriptController.dispose();
    _notesDebounce?.cancel();
    _notesController.dispose();
    _sheetScroll.dispose();
    _transcriptFocus.dispose();
    _notesFocus.dispose();
    super.dispose();
  }

  void _startEditingTranscript(String current) {
    setState(() {
      _originalTranscript = current;
      _transcriptController.text = current;
      _isEditingTranscript = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Falls die Section noch nicht offen ist, öffnen
      _transcriptSectionKey.currentState?.expand();
      // Fokus setzen
      FocusScope.of(context).requestFocus(_transcriptFocus);
      // Sichtbar machen (über Tastatur hinaus)
      final ctx = _transcriptFieldKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveTranscript() async {
    final text = _transcriptController.text.trim();
    try {
      await _docRef().update({'transcript': text});
      if (!mounted) return;
      setState(() {
        _isEditingTranscript = false;
      });
      showFlushbar('Transkript gespeichert.');
    } catch (e) {
      debugPrint('Fehler beim Speichern des Transkripts: $e');
      showFlushbar('Speichern fehlgeschlagen. Versuche es erneut.');
    }
  }

  void _onTranscriptChanged(String value) {
    // Debounced autosave while editing
    _transcriptDebounce?.cancel();
    _transcriptDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        await _docRef().update({'transcript': value.trim()});
      } catch (e) {
        debugPrint('Autosave-Fehler Transkript: $e');
      }
    });
  }

  void _startEditingNotes(String current) {
    setState(() {
      _originalNotes = current;
      _notesController.text = current;
      _isEditingNotes = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notesSectionKey.currentState?.expand();
      FocusScope.of(context).requestFocus(_notesFocus);
      final ctx = _notesFieldKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 250),
          alignment: 0.1,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _saveNotes() async {
    final text = _notesController.text.trim();
    try {
      await _docRef().update({'notes': text});
      if (!mounted) return;
      setState(() {
        _isEditingNotes = false;
      });
      showFlushbar('Notizen gespeichert.');
    } catch (e) {
      debugPrint('Fehler beim Speichern der Notizen: $e');
      showFlushbar('Speichern fehlgeschlagen. Versuche es erneut.');
    }
  }

  void _onNotesChanged(String value) {
    _notesDebounce?.cancel();
    _notesDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        await _docRef().update({'notes': value.trim()});
      } catch (e) {
        debugPrint('Autosave-Fehler Notizen: $e');
      }
    });
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

        final liveTranscript = (data['transcript'] as String?)?.trim() ?? '';
        if (liveTranscript.isNotEmpty && _transcriptController.text.isEmpty) {
          _transcriptController.text = liveTranscript;
        }
        final liveNotes = (data['notes'] as String?)?.trim() ?? '';
        if (!_isEditingNotes && (liveNotes.isNotEmpty || _notesController.text.isNotEmpty) &&
            _notesController.text != liveNotes) {
          _notesController.text = liveNotes;
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
                      controller: _sheetScroll,
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
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                    icon: const Icon(Icons.edit, size: 20),
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
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                                    icon: const Icon(Icons.refresh, size: 20),
                                    tooltip: 'Prophetie neu analysieren',
                                    onPressed: () async {
                                      await _reanalyze(context, data);
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            "Gegeben von: ${_creatorController.text.isNotEmpty ? _creatorController.text : (data['creatorName'] ?? 'Unbekannt')}",
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.grey,
                              height: 1.2,
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
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Divider(
                            thickness: 0.8,
                            color: Theme.of(context).dividerColor.withOpacity(0.25),
                          ),
                          const SizedBox(height: 12),

                          // Audio player removed from scroll area

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
                            key: _transcriptSectionKey,
                            title: '🎧 Transkript',
                            initiallyExpanded: false,
                            action: _isEditingTranscript
                                ? IconButton(
                                    icon: const Icon(Icons.check),
                                    iconSize: 20,
                                    tooltip: 'Speichern',
                                    onPressed: _saveTranscript,
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    iconSize: 20,
                                    tooltip: 'Bearbeiten',
                                    onPressed: () {
                                      _transcriptSectionKey.currentState?.expand();
                                      _startEditingTranscript(
                                        (data['transcript'] as String?)?.trim() ?? '',
                                      );
                                    },
                                  ),
                            child: Builder(builder: (context) {
                              final transcriptText = (data['transcript'] as String?)?.trim() ?? '';
                              // Keep local controller in sync when not editing
                              if (!_isEditingTranscript && transcriptText.isNotEmpty &&
                                  _transcriptController.text != transcriptText) {
                                _transcriptController.text = transcriptText;
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isEditingTranscript)
                                    TextFormField(
                                      key: _transcriptFieldKey,
                                      focusNode: _transcriptFocus,
                                      controller: _transcriptController,
                                      onChanged: _onTranscriptChanged,
                                      minLines: 6,
                                      maxLines: null,
                                      keyboardType: TextInputType.multiline,
                                      decoration: InputDecoration(
                                        hintText: 'Transkript hier bearbeiten…',
                                        filled: true,
                                        fillColor: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.grey[800]
                                            : Colors.grey[100],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    )
                                  else
                                    SelectableText(
                                      transcriptText.isNotEmpty ? transcriptText : 'Kein Transkript vorhanden.',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                ],
                              );
                            }),
                          ),
                          _Section(
                            key: _notesSectionKey,
                            title: '🗒️ Notizen',
                            initiallyExpanded: true,
                            action: _isEditingNotes
                                ? IconButton(
                                    icon: const Icon(Icons.check),
                                    iconSize: 20,
                                    tooltip: 'Speichern',
                                    onPressed: _saveNotes,
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.edit_outlined),
                                    iconSize: 20,
                                    tooltip: 'Bearbeiten',
                                    onPressed: () {
                                      _notesSectionKey.currentState?.expand();
                                      _startEditingNotes(
                                        (data['notes'] as String?)?.trim() ?? '',
                                      );
                                    },
                                  ),
                            child: Builder(builder: (context) {
                              final notesText = (data['notes'] as String?)?.trim() ?? '';
                              if (!_isEditingNotes && _notesController.text != notesText) {
                                _notesController.text = notesText;
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_isEditingNotes)
                                    TextFormField(
                                      key: _notesFieldKey,
                                      focusNode: _notesFocus,
                                      controller: _notesController,
                                      onChanged: _onNotesChanged,
                                      minLines: 4,
                                      maxLines: null,
                                      keyboardType: TextInputType.multiline,
                                      decoration: InputDecoration(
                                        hintText: 'Notizen hier bearbeiten…',
                                        filled: true,
                                        fillColor: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.grey[800]
                                            : Colors.grey[100],
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(8),
                                          borderSide: BorderSide.none,
                                        ),
                                      ),
                                    )
                                  else
                                    SelectableText(
                                      notesText.isNotEmpty ? notesText : 'Keine Notizen vorhanden.',
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                ],
                              );
                            }),
                          ),

                          const SizedBox(height: 8),
                          Divider(
                            thickness: 0.8,
                            color: Theme.of(context).dividerColor.withOpacity(0.25),
                          ),
                          const SizedBox(height: 12),
                          
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
                          SizedBox(height: 24 + MediaQuery.of(context).viewInsets.bottom),
                        ],
                      ),
                    ),
                  ),
                ),

                // Sticky mini audio player
                Builder(builder: (context) {
                  final hasAudio = ((data['audioUrl'] as String?)?.isNotEmpty == true) ||
                      ((data['driveAudioId'] as String?)?.isNotEmpty == true) ||
                      ((data['filePath'] as String?)?.isNotEmpty == true);
                  if (!hasAudio) return const SizedBox.shrink();
                  final audioPath = (data['audioUrl'] as String?) ??
                      (data['driveAudioId'] as String?) ??
                      (data['filePath'] as String)!;
                  return ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: Theme.of(context).brightness == Brightness.dark
                                ? [
                                    const Color(0xCC121212),
                                    const Color(0xCC1A1A1A),
                                  ]
                                : [
                                    const Color(0xCCFFFFFF),
                                    const Color(0xCCF7F7F7),
                                  ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          border: Border(
                            top: BorderSide(
                              color: Theme.of(context).dividerColor.withOpacity(0.16),
                              width: 0.8,
                            ),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 20,
                              offset: const Offset(0, -8),
                            ),
                          ],
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            child: _ProphetieAudioPlayer(
                              audioPath: audioPath,
                              audioPlayer: _audioPlayer,
                              title: data['title'] as String? ?? '',
                              isMini: true,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }),
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
  final bool isMini;
  const _ProphetieAudioPlayer({
    required this.audioPath,
    required this.audioPlayer,
    this.title = '',
    this.isMini = false,
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
    if (widget.isMini) {
      return _buildMini(context);
    }
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

  Widget _buildMini(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: widget.audioPlayer.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final playing = playerState?.playing ?? false;
        return SizedBox(
          height: 56,
          child: Row(
            children: [
              // Play/Pause as soft capsule button
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.white.withOpacity(0.06)
                      : Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: IconButton(
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: () {
                    if (playing) {
                      widget.audioPlayer.pause();
                    } else {
                      widget.audioPlayer.play();
                    }
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Optional title (truncated) for context
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.title.isNotEmpty)
                      Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.9),
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
                            return SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                                activeTrackColor: const Color(0xFFFF2D55),
                                inactiveTrackColor: const Color(0xFFFF2D55).withOpacity(0.28),
                                thumbColor: const Color(0xFFFF2D55),
                              ),
                              child: Slider(
                                min: 0,
                                max: duration.inMilliseconds.toDouble().clamp(0.0, double.infinity),
                                value: pos.inMilliseconds
                                    .clamp(0, duration.inMilliseconds)
                                    .toDouble(),
                                onChanged: (value) {
                                  widget.audioPlayer.seek(Duration(milliseconds: value.toInt()));
                                },
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              // Speed chip
              GestureDetector(
                onTap: () async {
                  const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
                  final currentIndex = speeds.indexOf(_playbackSpeed);
                  final nextIndex = (currentIndex + 1) % speeds.length;
                  final nextSpeed = speeds[nextIndex];
                  final wasPlaying = widget.audioPlayer.playing;
                  final position = widget.audioPlayer.position;
                  setState(() { _playbackSpeed = nextSpeed; });
                  await widget.audioPlayer.setSpeed(nextSpeed);
                  await widget.audioPlayer.seek(position);
                  if (wasPlaying) widget.audioPlayer.play();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${_playbackSpeed.toStringAsFixed(_playbackSpeed.truncateToDouble() == _playbackSpeed ? 0 : 2)}x',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).textTheme.bodyMedium?.color,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
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


bool isSameDate(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}

class _Section extends StatefulWidget {
  final String title;
  final Widget child;
  final bool initiallyExpanded;
  final Widget? action;
  const _Section({
    Key? key,
    required this.title,
    required this.child,
    this.initiallyExpanded = true,
    this.action,
  }) : super(key: key);

  @override
  State<_Section> createState() => _SectionState();
}

class _SectionState extends State<_Section> {
  late bool _expanded;

  void expand() {
    if (!_expanded) {
      setState(() => _expanded = true);
    }
  }

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header (flat)
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: SizedBox(
            height: 40,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (widget.action != null) widget.action!,
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                      child: AnimatedRotation(
                        duration: const Duration(milliseconds: 200),
                        turns: _expanded ? 0.5 : 0.0,
                        child: const Icon(Icons.expand_more, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // Body (flat)
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
            child: widget.child,
          ),
          crossFadeState:
              _expanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 200),
        ),
      ],
    );
  }
}
