import '../data/globals.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:io';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:share_plus/share_plus.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../widgets/custom_app_bar.dart';
import '../widgets/expandable_fab.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import '../models/prophetie.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert'; // Für utf8.decode
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/prophetie_detail_sheet.dart';
import '../widgets/manage_labels_list.dart';
import '../services/label_service.dart';
import 'package:just_audio/just_audio.dart';
import '../screens/phone_plus_screen.dart';
import '../services/prophetie_analysis_service.dart';
import '../services/audio_transcription_service.dart';
import 'package:provider/provider.dart';
import '../providers/prophetie_provider.dart';
import '../widgets/status_card.dart';

Map<String, dynamic>? tryParseJson(String input) {
  try {
    final parsed = jsonDecode(input);
    return parsed is Map<String, dynamic> ? parsed : null;
  } catch (e) {
    return null;
  }
}

class ProphetienScreen extends StatefulWidget {
  const ProphetienScreen({super.key});

  @override
  ProphetienScreenState createState() => ProphetienScreenState();
}

class ProphetienScreenState extends State<ProphetienScreen> {
  // Set of expanded prophecy IDs for transcript expansion
  Set<String> expandedProphecies = {};
  double playbackSpeed = 1.0;
  bool showFavorites = true;
  String selectedFilter = 'Alle';
  bool hasInternet = true;
  bool isLoading = true;

  // List of labels with their Firestore document IDs
  List<Map<String, String>> labelDocs = [];
  List<String> filterOptions = [];
  // Trackt IDs der Prophetien, die gerade hochgeladen/analysiert werden
  final Set<String> uploadingProphetieIds = {};

  // AudioPlayer-Instanz für Prophetie-Detailansicht
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();

    LabelManager.instance.listenToLabels((updatedLabels) {
      if (!mounted) return;
      setState(() {
        filterOptions = ['Alle', ...updatedLabels];
      });
    });

    _checkInternetAndLoadData();
    Provider.of<ProphetieProvider>(context, listen: false).loadProphetien();
  }

  Future<void> _checkInternetAndLoadData() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        setState(() {
          hasInternet = true;
        });
        await loadProphetienFromFirestore();
        return;
      }
    } on SocketException catch (_) {
      // kein Internet
    }
    setState(() {
      hasInternet = false;
    });
  }

  Future<void> saveLabelsToFirestore() async {
    await FirebaseFirestore.instance.collection('config').doc('labels').set({
      'labels': filterOptions,
    });
  }

  Future<void> refreshProphetien() async {
    await loadProphetienFromFirestore();
  }

  // Entfernt: Methode loadProphetien, Speicherung/Laden erfolgt nur noch über Google Drive.

  Future<void> loadProphetienFromFirestore() async {
    setState(() => isLoading = true);
    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        return;
      }

      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prophetien')
          .orderBy('timestamp', descending: true)
          .get();
      final loaded = <Prophetie>[];
      // For each doc, check isAnalyzed and trigger analysis if needed
      for (final doc in snapshot.docs) {
        final d = doc.data();
        try {
          loaded.add(Prophetie.fromJson(d));
        } catch (e) {
          print("❌ Fehler beim Parsen einer Prophetie: $e");
        }
      }
      // Sort loaded Prophetien by timestamp descending (newest first)
      loaded.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      // Neue: Prophetien mit isAnalyzed == false analysieren (asynchron und mit Fehlerbehandlung)
      final toAnalyze = snapshot.docs.where(
        (doc) => doc.data()['isAnalyzed'] == false,
      );
      Future<void> analyzeAll() async {
        for (final doc in toAnalyze) {
          try {
            await analyzeProphetie(doc);
          } catch (e) {
            debugPrint("Fehler beim Analysieren: $e");
          }
        }
      }

      // Starte Analyse, aber blockiere das UI nicht
      analyzeAll();
      if (!mounted) {
        return;
      }
      setState(() {
        prophetien
          ..clear()
          ..addAll(loaded);
      });
    } catch (e) {
      debugPrint("Error loading Prophetien: $e");
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  /// Analyzes a prophetie Firestore document (doc is a QueryDocumentSnapshot).
  Future<void> analyzeProphetie(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final audioUrl = data['audioUrl'] as String?;
    final transkript = data['transkript'] as String?;
    final docId = doc.id;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    // Avoid duplicate analysis (set isAnalyzed=true as soon as possible)
    try {
      // Mark as "analyzing" to avoid race conditions (optional)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prophetien')
          .doc(docId)
          .update({'isAnalyzed': false}); // Still false, but triggers update
    } catch (_) {}
    try {
      if (audioUrl != null && audioUrl.isNotEmpty) {
        // Use new transcription and analysis service
        await transcribeAndPrepareAnalysis(
          filePath: audioUrl,
          docId: docId,
          collectionName: 'prophetien',
          onComplete: loadProphetienFromFirestore,
          isRemoteUrl: true,
        );
      } else if (transkript != null && transkript.isNotEmpty) {
        await analyzeAndSaveProphetie(
          transcript: transkript,
          firestoreDocId: docId,
          onReload: loadProphetienFromFirestore,
        );
      }
    } catch (e) {
      print("Fehler bei analyzeProphetie: $e");
      // Mark as analyzed to avoid re-triggering
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('prophetien')
          .doc(docId)
          .update({'isAnalyzed': true});
    }
  }

  void _createNewProphetie() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
    );
    if (result == null || result.files.single.path == null) return;
    final filePath = result.files.single.path!;
    final id = const Uuid().v4();
    await Provider.of<ProphetieProvider>(
      context,
      listen: false,
    ).handleNewProphetie(
      id: id,
      localFilePath: filePath,
      transcriptText: null,
      label: 'Neu',
    );
  }

  void _createTextProphetie() {
    final controller = TextEditingController();
    final _creatorNameController = TextEditingController();
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -5),
                  ),
                ],
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 5,
                    margin: const EdgeInsets.only(bottom: 15),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const Text(
                    "Neue Prophetie eingeben",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 10,
                    decoration: InputDecoration(
                      hintText: "Gib hier deine Prophetie ein...",
                      hintStyle: TextStyle(color: Theme.of(context).hintColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.all(16),
                    ),
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _creatorNameController,
                    decoration: InputDecoration(
                      hintText: "Von wem stammt diese Prophetie?",
                      hintStyle: TextStyle(color: Theme.of(context).hintColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: EdgeInsets.all(16),
                    ),
                    style: TextStyle(
                      color: Theme.of(context).textTheme.bodyLarge?.color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      padding: EdgeInsets.symmetric(
                        vertical: 9,
                        horizontal: 24,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () async {
                      if (isProcessing) return;
                      final enteredText = controller.text.trim();
                      // Count words (non-empty segments)
                      final wordCount = enteredText
                          .split(RegExp(r'\s+'))
                          .where((w) => w.isNotEmpty)
                          .length;
                      if (wordCount < 25) {
                        setModalState(() => isProcessing = false);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Bitte mindestens 25 Wörter eingeben (aktuell $wordCount).',
                            ),
                          ),
                        );
                        return;
                      }
                      setModalState(() => isProcessing = true);
                      final newId = const Uuid().v4();
                      // Set processing false and then pop sheet
                      setModalState(() => isProcessing = false);
                      Navigator.of(ctx).pop();
                      await Provider.of<ProphetieProvider>(
                        context,
                        listen: false,
                      ).handleNewProphetie(
                        id: newId,
                        localFilePath: null,
                        transcriptText: enteredText,
                        label: 'Neu',
                        creatorName: _creatorNameController.text.trim(),
                      );
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Icon(Icons.check, color: Colors.white),
                        SizedBox(width: 8),
                        Text(
                          "Fertig",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showManageLabelsDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          expand: false,
          builder: (BuildContext context, ScrollController scrollController) {
            return StatefulBuilder(
              builder: (ctx2, setModalState) {
                final labels = filterOptions
                    .where((l) => l != 'Alle' && l != '+ Label verwalten')
                    .toList();
                return ManageLabelsList(
                  labels: labels,
                  onReorder: (updatedLabels) async {
                    labels.clear();
                    labels.addAll(updatedLabels);
                    setState(() {
                      filterOptions = ['Alle', ...updatedLabels];
                    });
                    await LabelService.instance.updateOrder(updatedLabels);
                    Future.microtask(() {
                      setModalState(() {});
                    });
                  },
                  onRename: (oldLabel, newLabel) async {
                    await LabelService.instance.renameLabel(oldLabel, newLabel);
                    setModalState(() {});
                  },
                  onDelete: (label) async {
                    await LabelService.instance.deleteLabel(label);
                    setModalState(() {});
                  },
                  onAddLabel: (label) async {
                    await LabelService.instance.addLabel(label);
                    setModalState(() {});
                  },
                  showTitle: true,
                );
              },
            );
          },
        );
      },
    );
  }

  // Schritt 4: Manuelles Neustarten eines fehlgeschlagenen Uploads
  void retryFailedUpload(String prophetieId) async {
    if (!uploadingProphetieIds.contains(prophetieId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          uploadingProphetieIds.add(prophetieId);
        });
      });

      final prophetie = prophetien.firstWhere((p) => p.id == prophetieId);
      if (prophetie.filePath != null && prophetie.filePath!.isNotEmpty) {
        try {
          // Versuche erneut die Prophetie zu speichern
          await saveProphetien();

          // Optional: Starte die Analyse neu, falls gewünscht
          await transcribeAndPrepareAnalysis(
            filePath: prophetie.filePath!,
            docId: prophetieId,
            collectionName: 'prophetien',
            onComplete: loadProphetienFromFirestore,
          );
        } catch (e) {
          print("Fehler beim erneuten Hochladen: $e");
        }
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          uploadingProphetieIds.remove(prophetieId);
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!hasInternet) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Keine Internetverbindung.\nBitte verbinde dich mit dem Internet und lade die Seite neu.',
              style: const TextStyle(fontSize: 18, color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }
    return SafeArea(
      child: Scaffold(
        appBar: const CustomAppBar(pageTitle: "Träume"),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Padding(
          padding: const EdgeInsets.only(
            left: 15.0,
            right: 15.0,
            top: 5.0, // Reduziert von 24.0 auf 16.0 für mehr vertikalen Raum
            bottom: 24.0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ensure "Alle" is always rendered first and fixed to the left
              Padding(
                padding: EdgeInsets.only(top: 25.0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: () {
                      // Copy filterOptions to a new list and ensure "Alle" is first and unique
                      final labels = List<String>.from(filterOptions);
                      labels.removeWhere((l) => l == "Alle");
                      labels.insert(0, "Alle");
                      // Build the list of label chips
                      final chips = labels.map((label) {
                        final isSelected = label == selectedFilter;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(label),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (label == "+ Label hinzufügen") {
                                _showManageLabelsDialog();
                              } else {
                                setState(() => selectedFilter = label);
                              }
                            },
                          ),
                        );
                      }).toList();
                      // Append the "+ Label verwalten" chip at the end, always
                      chips.add(
                        Padding(
                          padding: const EdgeInsets.only(right: 4, left: 2),
                          child: GestureDetector(
                            onTap: _showManageLabelsDialog,
                            child: Chip(
                              label: Text('+ Label verwalten'),
                              backgroundColor: Theme.of(context).cardColor,
                            ),
                          ),
                        ),
                      );
                      return chips;
                    }(),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Consumer<ProphetieProvider>(
                  builder: (context, prophetieProvider, child) {
                    final all = prophetieProvider.prophetien;
                    // Prophetien are already sorted by timestamp descending in loadProphetienFromFirestore.
                    final filtered = selectedFilter == 'Alle'
                        ? all
                        : all.where((p) => p.label == selectedFilter).toList();
                    final favorites = filtered
                        .where((p) => p.isFavorit)
                        .toList();
                    final others = filtered.where((p) => !p.isFavorit).toList();

                    if (all.isEmpty) {
                      if (isLoading) {
                        return const Center(child: CircularProgressIndicator());
                      } else {
                        return const Center(
                          child: Text("Keine Träume gefunden."),
                        );
                      }
                    }

                    // Ersetze RefreshIndicator und ListView durch CustomScrollView mit CupertinoSliverRefreshControl und SliverList
                    int itemCount =
                        (favorites.isNotEmpty
                            ? 1 +
                                  (showFavorites ? favorites.length : 0) +
                                  (showFavorites ? 1 : 0)
                            : 0) +
                        others.length;

                    return CustomScrollView(
                      slivers: [
                        CupertinoSliverRefreshControl(
                          onRefresh: () async {
                            await prophetieProvider.loadProphetien();
                            await HapticFeedback.mediumImpact();
                            setState(() {});
                          },
                        ),
                        SliverList(
                          delegate: SliverChildBuilderDelegate((context, idx) {
                            int cursor = 0;
                            // Favoriten-Header
                            if (favorites.isNotEmpty) {
                              if (idx == cursor) {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: GestureDetector(
                                    onTap: () {
                                      setState(
                                        () => showFavorites = !showFavorites,
                                      );
                                    },
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          "★ Favoriten",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Icon(
                                          showFavorites
                                              ? Icons.expand_less
                                              : Icons.expand_more,
                                          size: 20,
                                          color: Colors.black54,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }
                              cursor++;
                              // Favoriten Cards
                              if (showFavorites) {
                                final favIdx = idx - cursor;
                                if (favIdx < favorites.length) {
                                  // --- PATCH: Abstand vor erster Prophetie ---
                                  Widget cardWidget;
                                  Prophetie? p;
                                  if (favorites.isNotEmpty) {
                                    if (idx == 1 && favIdx == 0) {
                                      p = favorites[0];
                                    } else {
                                      p = favorites[favIdx];
                                    }
                                  } else {
                                    p = others[favIdx];
                                  }
                                  if (idx == 1 && favIdx == 0) {
                                    cardWidget = Column(
                                      children: [
                                        const SizedBox(height: 20),
                                        _buildCard(p),
                                      ],
                                    );
                                  } else {
                                    cardWidget = _buildCard(p);
                                  }
                                  return cardWidget;
                                  // --- ENDE PATCH ---
                                }
                                cursor += favorites.length;
                                // SizedBox nach Favoriten
                                if (idx == cursor) {
                                  return const SizedBox(height: 5);
                                }
                                cursor++;
                              }
                            }
                            // Others
                            final othersIdx = idx - cursor;
                            if (othersIdx >= 0 && othersIdx < others.length) {
                              // --- PATCH: Abstand vor erster Prophetie ---
                              Widget cardWidget;
                              Prophetie? p;
                              if (favorites.isNotEmpty) {
                                if (idx == 0) {
                                  p = favorites[0];
                                } else if (showFavorites &&
                                    idx <= favorites.length) {
                                  p = favorites[idx - 1];
                                } else {
                                  int othersIndex =
                                      idx -
                                      1 -
                                      (showFavorites ? favorites.length : 0);
                                  p = others[othersIndex];
                                }
                              } else {
                                p = others[idx];
                              }
                              if (
                              // Im "Others"-Bereich: idx == 0 ist nur möglich, wenn es keine Favoriten gibt
                              idx == 0) {
                                cardWidget = Column(
                                  children: [
                                    const SizedBox(height: 20),
                                    _buildCard(p),
                                  ],
                                );
                              } else if (
                              // Im "Others"-Bereich: Wenn es Favoriten gibt, dann ist das erste Element nach Favoriten
                              favorites.isNotEmpty &&
                                  showFavorites &&
                                  idx ==
                                      (1 +
                                          favorites.length +
                                          1) // Header + Favoriten + SizedBox
                                      ) {
                                cardWidget = Column(
                                  children: [
                                    const SizedBox(height: 17),
                                    _buildCard(p),
                                  ],
                                );
                              } else {
                                cardWidget = _buildCard(p);
                              }
                              return cardWidget;
                              // --- ENDE PATCH ---
                            }
                            // Fallback
                            return const SizedBox.shrink();
                          }, childCount: itemCount),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: SpeedDial(
          icon: Icons.add,
          activeIcon: Icons.close,
          backgroundColor: const Color(0xFFFF2C55),
          foregroundColor: Colors.white,
          children: [
            SpeedDialChild(
              child: const Icon(Icons.upload_file),
              label: 'Audio hochladen',
              onTap: () {
                if (hatPremium) {
                  _createNewProphetie();
                } else {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => FractionallySizedBox(
                      heightFactor: 0.9,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(30),
                          ),
                        ),
                        child: const PhonePlusScreen(),
                      ),
                    ),
                  );
                }
              },
            ),
            SpeedDialChild(
              child: const Icon(Icons.edit_note),
              label: 'Text eingeben',
              onTap: () {
                if (hatPremium) {
                  _createTextProphetie();
                } else {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => FractionallySizedBox(
                      heightFactor: 0.9,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(30),
                          ),
                        ),
                        child: const PhonePlusScreen(),
                      ),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // Entfernt: _showAddLabelDialog und buildDriveDownloadLink

  Widget _buildCard(Prophetie p) {
    if (p.status != ProcessingStatus.complete &&
        p.status != ProcessingStatus.none) {
      return StatusCard(
        statusText: p.status == ProcessingStatus.transcribing
            ? "Transkribiere..."
            : p.status == ProcessingStatus.analyzing
            ? "Analysiere..."
            : "Fehlgeschlagen",
        isError: p.status == ProcessingStatus.failed,
        onRetry: () => retryFailedUpload(p.id),
      );
    }

    // If analyzed, show normal interactive card with overlay chip at top-right
    return Slidable(
      key: ValueKey(p.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.5,
        dismissible: DismissiblePane(
          onDismissed: () async {
            final userId = FirebaseAuth.instance.currentUser?.uid;
            if (userId != null) {
              // Delete audio file if present
              final audioUrl = p.filePath;
              if (audioUrl != null && audioUrl.isNotEmpty) {
                await FirebaseStorage.instance
                    .refFromURL(audioUrl)
                    .delete()
                    .catchError((_) {});
              }
              // Delete Firestore document
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('prophetien')
                  .doc(p.id)
                  .delete()
                  .catchError((_) {});
            }
            // Remove from provider state so UI updates
            Provider.of<ProphetieProvider>(
              context,
              listen: false,
            ).removeProphetie(p.id);
          },
        ),
        children: [
          SlidableAction(
            onPressed: (_) async {
              final buffer = StringBuffer();
              buffer.writeln('Titel: ${p.title ?? p.title}');
              if (p.mainPoints != null && p.mainPoints!.isNotEmpty) {
                buffer.writeln('\nHauptpunkte:\n${p.mainPoints}');
              }
              if (p.summary != null && p.summary!.isNotEmpty) {
                buffer.writeln('\nZusammenfassung:\n${p.summary}');
              }
              if (p.storiesExamplesCitations != null &&
                  p.storiesExamplesCitations!.isNotEmpty) {
                buffer.writeln(
                  '\nBeispiele & Zitate:\n${p.storiesExamplesCitations}',
                );
              }
              if (p.actionItems != null && p.actionItems!.isNotEmpty) {
                buffer.writeln('\nHandlungsschritte:\n${p.actionItems}');
              }
              if (p.relatedTopics != null && p.relatedTopics!.isNotEmpty) {
                buffer.writeln('\nVerwandte Themen:\n${p.relatedTopics}');
              }
              // Build share text
              final shareText =
                  '${buffer.toString()}\n\n'
                  'Entdecke PHONĒ – lade die App jetzt herunterladen und erhalte inspirierende '
                  'Träume und Prophetien direkt auf dein Smartphone!';
              await Share.share(shareText, subject: 'PHONĒ Prophetie');
            },
            backgroundColor: Colors.blue,
            borderRadius: BorderRadius.zero,
            foregroundColor: Colors.white,
            icon: Icons.share,
            label: 'Teilen',
          ),
          SlidableAction(
            onPressed: (_) async {
              final userId = FirebaseAuth.instance.currentUser?.uid;
              final prophetienId = p.id;
              if (userId != null && prophetienId != null) {
                // Delete audio if exists
                final audioUrl = p.filePath;
                if (audioUrl != null && audioUrl.isNotEmpty) {
                  await FirebaseStorage.instance
                      .refFromURL(audioUrl)
                      .delete()
                      .catchError((_) {});
                }
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('prophetien')
                    .doc(prophetienId)
                    .delete()
                    .catchError((_) {});
              }
              setState(() {
                prophetien.removeWhere((element) => element.id == p.id);
              });
              await saveProphetien();
            },
            backgroundColor: Colors.red,
            borderRadius: BorderRadius.zero,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Löschen',
          ),
        ],
      ),
      child: GestureDetector(
        onTap: () async {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Theme.of(context).cardColor,
            builder: (_) => ProphetieDetailSheet(prophetieId: p.id),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.grey.withOpacity(0.2)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          margin: const EdgeInsets.symmetric(vertical: 1),
          child: Stack(
            children: [
              // Main content column
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date, dot, and creator
                  Row(
                    children: [
                      Text(
                        "${p.timestamp.day}. ${_monthName(p.timestamp.month)} ${p.timestamp.year}",
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color:
                              (Theme.of(context).textTheme.bodySmall?.color ??
                                      Colors.grey)
                                  .withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        p.creatorName ?? '',
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Title and optional spinner
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          (p.title?.isNotEmpty ?? false)
                              ? p.title!
                              : "Kein Titel",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Overlay label chip at right, vertically centered
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 1),
                  child: Chip(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    label: Text(
                      p.label,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    backgroundColor: Theme.of(
                      context,
                    ).colorScheme.secondary.withOpacity(0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose().catchError((e) {
      debugPrint('AudioPlayer.dispose error: $e');
    });
    super.dispose();
  }
}

extension ProphetienCopyWith on Prophetie {
  Prophetie copyWith({
    String? id,
    String? text,
    String? label,
    bool? isFavorit,
    DateTime? timestamp,
    String? filePath,
    String? mainPoints,
    String? summary,
    String? verses,
    String? questions,
    String? similar,
    String? creatorName,
    String? title,
    String? storiesExamplesCitations,
    String? actionItems,
    String? relatedTopics,
    String? transcript,
  }) {
    return Prophetie(
      id: id ?? this.id,
      label: label ?? this.label,
      isFavorit: isFavorit ?? this.isFavorit,
      timestamp: timestamp ?? this.timestamp,
      filePath: filePath ?? this.filePath,
      mainPoints: mainPoints ?? this.mainPoints,
      summary: summary ?? this.summary,
      verses: verses ?? this.verses,
      questions: questions ?? this.questions,
      similar: similar ?? this.similar,
      creatorName: creatorName ?? this.creatorName,
      title: title ?? this.title,
      storiesExamplesCitations:
          storiesExamplesCitations ?? this.storiesExamplesCitations,
      actionItems: actionItems ?? this.actionItems,
      relatedTopics: relatedTopics ?? this.relatedTopics,
      transcript: transcript ?? this.transcript,
    );
  }
}

String _monthName(int month) {
  const months = [
    "Januar",
    "Februar",
    "März",
    "April",
    "Mai",
    "Juni",
    "Juli",
    "August",
    "September",
    "Oktober",
    "November",
    "Dezember",
  ];
  return months[month - 1];
}

/// Speichert alle Prophetien in Firestore (jeweils als einzelnes Dokument)
Future<void> saveProphetien() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userId = user.uid;

  for (var prophetie in prophetien) {
    final id = prophetie.id;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('prophetien')
        .doc(id)
        .set(prophetie.toJson());
  }
}
