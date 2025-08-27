import '../data/globals.dart';
import 'package:prophetie_app/main.dart';
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
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as pth;
import '../widgets/custom_app_bar.dart';
import '../models/traum.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'dart:convert'; // Für utf8.decode
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/traum_detail_sheet.dart';
import '../widgets/manage_labels_list.dart';
import '../services/label_service.dart';
import 'package:just_audio/just_audio.dart';
// import '../screens/phone_plus_screen.dart';
import '../services/traum_analysis_service.dart';
import 'package:prophetie_app/services/audio_transcription_service.dart';
import 'package:provider/provider.dart';
import '../providers/premium_provider.dart';
import '../providers/traum_provider.dart';
import '../widgets/status_card.dart';
import '../main.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../services/purchase_service.dart';
import 'package:flutter/foundation.dart';

Map<String, dynamic>? tryParseJson(String input) {
  try {
    final parsed = jsonDecode(input);
    return parsed is Map<String, dynamic> ? parsed : null;
  } catch (e) {
    return null;
  }
}

class TraeumeScreen extends StatefulWidget {
  const TraeumeScreen({super.key});

  @override
  TraeumeScreenState createState() => TraeumeScreenState();
}

class TraeumeScreenState extends State<TraeumeScreen> {
  // Set of expanded prophecy IDs for transcript expansion
  Set<String> expandedProphecies = {};
  double playbackSpeed = 1.0;
  bool showFavorites = true;
  // Suchanfrage für Träume
  String searchQuery = '';
  bool isSearchActive = false;
  String selectedFilter = 'Alle';
  bool hasInternet = true;
  bool isLoading = true;

  // List of labels with their Firestore document IDs
  List<Map<String, String>> labelDocs = [];
  List<String> filterOptions = [];
  // Trackt IDs der Prophetien, die gerade hochgeladen/analysiert werden
  final Set<String> uploadingTraumIds = {};

  // AudioPlayer-Instanz für Prophetie-Detailansicht
  final AudioPlayer _audioPlayer = AudioPlayer();

  void _openCreateSheet() {
    final isPremium = context.read<PremiumProvider>().isPremium;
    showModalBottomSheet(
      context: context,
      isScrollControlled: false,
      showDragHandle: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  leading: const Icon(Icons.upload_file),
                  title: const Text('Audio hochladen', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('MP3, M4A, WAV, AAC'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (isPremium) {
                      _createNewTraum();
                    } else {
                      try {
                        await PurchaseService().presentPaywall(
                          offeringId: 'ofrng9db6804728',
                        );
                      } catch (e) {
                        debugPrint('Paywall-Error: $e');
                      }
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.edit_note),
                  title: const Text('Text eingeben', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Manuellen Traum erfassen'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    if (isPremium) {
                      _createTextTraum();
                    } else {
                      try {
                        await PurchaseService().presentPaywall(
                          offeringId: 'ofrng9db6804728',
                        );
                      } catch (e) {
                        debugPrint('Paywall-Error: $e');
                      }
                    }
                  },
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        );
      },
    );
  }

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
    Provider.of<TraumProvider>(context, listen: false).loadTraeume();
  }

  Future<void> _checkInternetAndLoadData() async {
    try {
      final result = await InternetAddress.lookup('example.com');
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        setState(() {
          hasInternet = true;
        });
        await loadTraeumeFromFirestore();
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

  Future<void> refreshTraeume() async {
    await loadTraeumeFromFirestore();
  }

  // Entfernt: Methode loadProphetien, Speicherung/Laden erfolgt nur noch über Google Drive.

  Future<void> loadTraeumeFromFirestore() async {
    setState(() => isLoading = true);
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      setState(() => isLoading = false);
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('traeume')
        .orderBy('timestamp', descending: true)
        .get();

    // Auto-Retry unfinished transcriptions on app restart
    for (final doc in snapshot.docs) {
      final status = doc.data()['status'] as String?;
      if (status == 'transcribing') {
        print('🚀 Auto-Retry Transcription for ${doc.id}');
        retryFailedUpload(doc.id);
      }
    }

    // --- Watchdog: Set stuck transcriptions to failed ---
    final stuckThreshold = DateTime.now().subtract(Duration(minutes: 10));
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final status = data['status'];
      final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

      if (status == 'transcribing' &&
          timestamp != null &&
          timestamp.isBefore(stuckThreshold)) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .collection('traeume')
            .doc(doc.id)
            .update({'status': 'failed'});
        print(
          '⛔️ Watchdog: Transkription zu alt, auf failed gesetzt – ${doc.id}',
        );
      }
    }
    // --- Ende Watchdog ---
    final loaded = <Traum>[];
    // For each doc, check isAnalyzed and trigger analysis if needed
    for (final doc in snapshot.docs) {
      final d = doc.data();
      try {
        loaded.add(Traum.fromJson(d));
      } catch (e) {
        print("❌ Fehler beim Parsen eines Traums: $e");
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
          await analyzeTraum(doc);
        } catch (e) {
          debugPrint("Fehler beim Analysieren: $e");
        }
      }
    }

    // Starte Analyse, aber blockiere das UI nicht
    analyzeAll();
    if (!mounted) {
      setState(() => isLoading = false);
      return;
    }
    setState(() {
      traeume
        ..clear()
        ..addAll(loaded);
      isLoading = false;
    });
  }

  /// Analyzes a prophetie Firestore document (doc is a QueryDocumentSnapshot).
  Future<void> analyzeTraum(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    final audioUrl = data['audioUrl'] as String?;
    final text = data['text'] as String?;
    final docId = doc.id;
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;
    // Avoid duplicate analysis (set isAnalyzed=true as soon as possible)
    try {
      // Mark as "analyzing" to avoid race conditions (optional)
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('traeume')
          .doc(docId)
          .update({'isAnalyzed': false}); // Still false, but triggers update
    } catch (_) {}
    try {
      if (audioUrl != null && audioUrl.isNotEmpty) {
        // Use new transcription and analysis service
        await transcribeAndPrepareAnalysis(
          filePath: audioUrl,
          docId: docId,
          collectionName: 'traeume',
          onComplete: loadTraeumeFromFirestore,
          isRemoteUrl: true,
        );
      } else if (text != null && text.isNotEmpty) {
        await analyzeAndSaveTraum(
          transcript: text,
          firestoreDocId: docId,
          onReload: loadTraeumeFromFirestore,
        );
      }
    } catch (e) {
      print("Fehler bei analyzeTraum: $e");
      // Mark as analyzed to avoid re-triggering
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('traeume')
          .doc(docId)
          .update({'isAnalyzed': true});
    }
  }

  void _createNewTraum() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'm4a', 'wav', 'aac'],
    );
    if (result == null || result.files.single.path == null) return;
    final filePath = result.files.single.path!;
    final id = const Uuid().v4();
    await Provider.of<TraumProvider>(context, listen: false).handleNewTraum(
      id: id,
      localFilePath: filePath,
      transcriptText: null,
      labels: [],
    );
  }

  void _createTextTraum() {
    final controller = TextEditingController();
    final _creatorNameController = TextEditingController();
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
                left: 20,
                right: 20,
                top: 0,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Titel wie im Labels-Sheet
                  Padding(
                    padding: const EdgeInsets.only(top: 0, bottom: 4),
                    child: Center(
                      child: Text(
                        "Neuen Traum eingeben",
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Textfeld (multiline) – visuell an Labels-Suche angelehnt
                  SizedBox(
                    // Höhe anpassbar, aber gleiche Optik (Radius/Fill)
                    child: TextField(
                      controller: controller,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: "Gib hier deinen Traum ein...",
                        hintStyle: TextStyle(color: Theme.of(context).hintColor),
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[850]
                            : Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Creator-Name – 40px hoch wie im Labels-Sheet
                  SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _creatorNameController,
                      decoration: InputDecoration(
                        hintText: "Von wem stammt dieser Traum?",
                        hintStyle: TextStyle(color: Theme.of(context).hintColor),
                        prefixIcon: const Icon(Icons.person_outline, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[850]
                            : Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Primärer Action-Button – gleiches Branding (FF2C55) und 12er Radius behalten
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF2C55),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        if (isProcessing) return;
                        final enteredText = controller.text.trim();
                        final wordCount = enteredText
                            .split(RegExp(r'\s+'))
                            .where((w) => w.isNotEmpty)
                            .length;
                        if (wordCount < 25) {
                          setModalState(() => isProcessing = false);
                          showFlushbar(
                            'Bitte mindestens 25 Wörter eingeben (aktuell $wordCount).',
                          );
                          return;
                        }
                        setModalState(() => isProcessing = true);
                        final newId = const Uuid().v4();
                        setModalState(() => isProcessing = false);
                        Navigator.of(ctx).pop();
                        await Provider.of<TraumProvider>(
                          context,
                          listen: false,
                        ).handleNewTraum(
                          id: newId,
                          localFilePath: null,
                          transcriptText: enteredText,
                          labels: [],
                          creatorName: _creatorNameController.text.trim(),
                        );
                      },
                      child: const Text(
                        "Fertig",
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
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
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: DraggableScrollableSheet(
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
        ),
      ),
    );
  }

  // Schritt 4: Manuelles Neustarten eines fehlgeschlagenen Uploads (robustere & erweiterte Version)
  Future<void> retryFailedUpload(String documentId) async {
    // Prevent concurrent retries
    if (uploadingTraumIds.contains(documentId)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Retry läuft bereits...')));
      return;
    }
    uploadingTraumIds.add(documentId);

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) {
      uploadingTraumIds.remove(documentId);
      return;
    }

    final docRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('traeume')
        .doc(documentId);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Retry gestartet...')));

    try {
      final doc = await docRef.get();
      final data = doc.data();
      final filePath = data?['filePath'] as String?;
      if (filePath == null || filePath.isEmpty) {
        throw Exception('Kein Dateipfad gefunden.');
      }

      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('Lokale Datei existiert nicht.');
      }

      // Update status to transcribing in Firestore
      await docRef.update({'status': 'transcribing'});

      String audioUrl = data?['audioUrl'] as String? ?? '';
      if (audioUrl.isEmpty) {
        final fileName = file.uri.pathSegments.last;
        final storageRef = FirebaseStorage.instance.ref().child(
          'users/$userId/traeume/$documentId/$fileName',
        );
        final snapshot = await storageRef.putFile(file);
        audioUrl = await snapshot.ref.getDownloadURL();
        await docRef.update({'audioUrl': audioUrl});
        print('✅ Datei erneut hochgeladen.');
      }

      // Start transcription & analysis
      await transcribeAndPrepareAnalysis(
        filePath: file.path,
        docId: documentId,
        collectionName: 'traeume',
        onComplete: () async {
          await docRef.update({'status': 'analyzing'});
        },
        isRemoteUrl: false,
      );
    } catch (e) {
      print('❌ Retry fehlgeschlagen: $e');
      await docRef.update({'status': 'failed'});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retry fehlgeschlagen: ${e.toString()}')),
      );
    } finally {
      uploadingTraumIds.remove(documentId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPremium = context.watch<PremiumProvider>().isPremium;
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
              // Prophetien-Screen-Layout: Suche oben volle Breite, darunter Labels als Chips, rotes Active, kein Haken, "+ Label verwalten" als ChoiceChip
              Padding(
                padding: EdgeInsets.only(
                  bottom: 8.0,
                  top: MediaQuery.of(context).size.height * 0.03,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // SUCHE OBEN – volle Breite (ProfilScreen-Stil)
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 40,
                            child: TextField(
                              decoration: InputDecoration(
                                hintText: 'Suchen',
                                prefixIcon: const Icon(Icons.search, size: 18),
                                isDense: true,
                                filled: true,
                                fillColor: Theme.of(context).brightness == Brightness.dark
                                    ? Colors.grey[850]
                                    : Colors.grey[200],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(14),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              style: const TextStyle(fontSize: 14),
                              onChanged: (v) => setState(() => searchQuery = v),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Label verwalten',
                          child: Material(
                            color: Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[850]
                                : Colors.grey[200],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: _showManageLabelsDialog,
                              child: const SizedBox(
                                width: 40,
                                height: 40,
                                child: Icon(Icons.local_offer_outlined, size: 20),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // LABELS DARUNTER – horizontal scrollbare Chips
                    SizedBox(
                      height: 36,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: () {
                            // Kopie der Optionen, 'Alle' nach vorne
                            final labels = List<String>.from(filterOptions);
                            labels.removeWhere((l) => l == 'Alle');
                            labels.insert(0, 'Alle');

                            final chips = labels.map((label) {
                              final isSelected = label == selectedFilter;
                              return Padding(
                                padding: const EdgeInsets.only(right: 10.0),
                                child: ChoiceChip(
                                  label: Text(
                                    label,
                                    style: TextStyle(
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: isSelected
                                          ? const Color(0xFFFF2C55)
                                          : Theme.of(
                                              context,
                                            ).textTheme.bodyMedium?.color,
                                    ),
                                  ),
                                  selected: isSelected,
                                  showCheckmark: false,
                                  selectedColor: const Color(
                                    0xFFFF2C55,
                                  ).withOpacity(0.2),
                                  backgroundColor: Theme.of(context).cardColor,
                                  labelStyle: TextStyle(
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: isSelected
                                        ? const Color(0xFFFF2C55)
                                        : Theme.of(
                                            context,
                                          ).textTheme.bodyMedium?.color,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 4,
                                  ),
                                  onSelected: (selected) {
                                    setState(() => selectedFilter = label);
                                  },
                                ),
                              );
                            }).toList();
                            return chips;
                          }(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: Consumer<TraumProvider>(
                  builder: (context, traumProvider, child) {
                    final all = traumProvider.traeume;
                    final searched = searchQuery.isEmpty
                        ? all
                        : all.where((t) {
                            final title = t.title?.toLowerCase() ?? '';
                            final transcript =
                                t.mainPoints?.toLowerCase() ?? '';
                            final creator = t.creatorName?.toLowerCase() ?? '';
                            final query = searchQuery.toLowerCase();
                            return title.contains(query) ||
                                transcript.contains(query) ||
                                creator.contains(query);
                          }).toList();
                    // Prophetien are already sorted by timestamp descending in loadProphetienFromFirestore.
                    final filtered = selectedFilter == 'Alle'
                        ? searched
                        : searched
                              .where((t) => t.labels.contains(selectedFilter))
                              .toList();
                    final favorites = filtered
                        .where((t) => t.isFavorit)
                        .toList();
                    final others = filtered.where((t) => !t.isFavorit).toList();

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
                            await traumProvider.loadTraeume();
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
                                  Traum? t;
                                  if (favorites.isNotEmpty) {
                                    if (idx == 1 && favIdx == 0) {
                                      t = favorites[0];
                                    } else {
                                      t = favorites[favIdx];
                                    }
                                  } else {
                                    t = others[favIdx];
                                  }
                                  if (idx == 1 && favIdx == 0) {
                                    cardWidget = Column(
                                      children: [
                                        const SizedBox(height: 20),
                                        _buildCard(t),
                                      ],
                                    );
                                  } else {
                                    cardWidget = _buildCard(t);
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
                              Traum? t;
                              if (favorites.isNotEmpty) {
                                if (idx == 0) {
                                  t = favorites[0];
                                } else if (showFavorites &&
                                    idx <= favorites.length) {
                                  t = favorites[idx - 1];
                                } else {
                                  int othersIndex =
                                      idx -
                                      1 -
                                      (showFavorites ? favorites.length : 0);
                                  t = others[othersIndex];
                                }
                              } else {
                                t = others[idx];
                              }
                              if (
                              // Im "Others"-Bereich: idx == 0 ist nur möglich, wenn es keine Favoriten gibt
                              idx == 0) {
                                cardWidget = Column(
                                  children: [
                                    const SizedBox(height: 20),
                                    _buildCard(t),
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
                                    _buildCard(t),
                                  ],
                                );
                              } else {
                                cardWidget = _buildCard(t);
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
        floatingActionButton: FloatingActionButton(
          backgroundColor: const Color(0xFFFF2C55),
          onPressed: _openCreateSheet,
          child: const Icon(Icons.add, color: Colors.white),
        ),
      ),
    );
  }

  Future<String?> _getShareableAudioPathForTraum(Traum t) async {
    try {
      // 1) Prefer local file if present
      final local = t.filePath;
      if (local != null && local.isNotEmpty) {
        final f = File(local);
        if (await f.exists()) return f.path;
      }

      // 2) Otherwise fetch audioUrl from Firestore and download to temp
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) return null;
      final docSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('traeume')
          .doc(t.id)
          .get();
      final audioUrl = docSnap.data()?['audioUrl'] as String?;
      if (audioUrl == null || audioUrl.isEmpty) return null;

      final tmpDir = await getTemporaryDirectory();
      // Guess extension from URL
      String ext = '.m4a';
      final lower = audioUrl.toLowerCase();
      if (lower.contains('.mp3')) ext = '.mp3';
      else if (lower.contains('.wav')) ext = '.wav';
      else if (lower.contains('.aac')) ext = '.aac';
      else if (lower.contains('.m4a') || lower.contains('.mp4')) ext = '.m4a';

      final savePath = pth.join(tmpDir.path, 'traum_${t.id}$ext');
      final resp = await http.get(Uri.parse(audioUrl));
      if (resp.statusCode == 200) {
        final f = File(savePath);
        await f.writeAsBytes(resp.bodyBytes);
        return f.path;
      }
    } catch (e) {
      debugPrint('Share-Audio (Traum) Download-Fehler: $e');
    }
    return null;
  }

  String _mimeForPath(String path) {
    final ext = pth.extension(path).toLowerCase();
    switch (ext) {
      case '.mp3':
        return 'audio/mpeg';
      case '.wav':
        return 'audio/wav';
      case '.aac':
        return 'audio/aac';
      default:
        // Covers .m4a / .mp4 audio in MP4-Container
        return 'audio/mp4';
    }
  }

  // Entfernt: _showAddLabelDialog und buildDriveDownloadLink

  Widget _buildCard(Traum t) {
    if (t.status != ProcessingStatus.complete &&
        t.status != ProcessingStatus.none) {
      final isStuckTranscribing =
          t.status == ProcessingStatus.transcribing &&
          DateTime.now().difference(t.timestamp) > Duration(seconds: 90);
      return Slidable(
        key: ValueKey(t.id),
        endActionPane: ActionPane(
          motion: const ScrollMotion(),
          extentRatio: 0.25,
          dismissible: DismissiblePane(
            onDismissed: () async {
              final userId = FirebaseAuth.instance.currentUser?.uid;
              if (userId != null) {
                try {
                  final docRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('traeume')
                      .doc(t.id);
                  final docSnap = await docRef.get();
                  final audioUrl = docSnap.data()?['audioUrl'] as String?;
                  if (audioUrl != null &&
                      audioUrl.isNotEmpty &&
                      (audioUrl.startsWith('https://') ||
                          audioUrl.startsWith('gs://'))) {
                    await FirebaseStorage.instance
                        .refFromURL(audioUrl)
                        .delete();
                  }
                } catch (e) {
                  print('Fehler beim Löschen der Audiodatei: $e');
                }
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('traeume')
                    .doc(t.id)
                    .delete();
              }
              Provider.of<TraumProvider>(
                context,
                listen: false,
              ).removeTraum(t.id);
            },
          ),
          children: [
            SlidableAction(
              onPressed: (_) async {
                final userId = FirebaseAuth.instance.currentUser?.uid;
                if (userId != null) {
                  try {
                    final docRef = FirebaseFirestore.instance
                        .collection('users')
                        .doc(userId)
                        .collection('traeume')
                        .doc(t.id);
                    final docSnap = await docRef.get();
                    final audioUrl = docSnap.data()?['audioUrl'] as String?;
                    if (audioUrl != null &&
                        audioUrl.isNotEmpty &&
                        (audioUrl.startsWith('https://') ||
                            audioUrl.startsWith('gs://'))) {
                      await FirebaseStorage.instance
                          .refFromURL(audioUrl)
                          .delete();
                    }
                  } catch (e) {
                    print('Fehler beim Löschen der Audiodatei: $e');
                  }
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('traeume')
                      .doc(t.id)
                      .delete();
                }
                setState(() {
                  traeume.removeWhere((element) => element.id == t.id);
                });
                await saveTraeume();
              },
              backgroundColor: Colors.red,
              borderRadius: BorderRadius.zero,
              foregroundColor: Colors.white,
              icon: Icons.delete,
              label: 'Löschen',
            ),
          ],
        ),
        child: StatusCard(
          statusText: isStuckTranscribing
              ? "Fehlgeschlagen"
              : t.status == ProcessingStatus.transcribing
              ? "Transkribiere..."
              : t.status == ProcessingStatus.analyzing
              ? "Analysiere..."
              : "Fehlgeschlagen",
          isError: isStuckTranscribing || t.status == ProcessingStatus.failed,
          onRetry: () => retryFailedUpload(t.id),
        ),
      );
    }

    // If analyzed, show normal interactive card with overlay chip at top-right
    return Slidable(
      key: ValueKey(t.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: 0.5,
        dismissible: DismissiblePane(
          onDismissed: () async {
            final userId = FirebaseAuth.instance.currentUser?.uid;
            if (userId != null) {
              try {
                final docRef = FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('traeume')
                    .doc(t.id);
                final docSnap = await docRef.get();
                final audioUrl = docSnap.data()?['audioUrl'] as String?;
                if (audioUrl != null &&
                    audioUrl.isNotEmpty &&
                    (audioUrl.startsWith('https://') ||
                        audioUrl.startsWith('gs://'))) {
                  await FirebaseStorage.instance
                      .refFromURL(audioUrl)
                      .delete()
                      .catchError((_) {});
                }
              } catch (e) {
                print('Fehler beim Löschen der Audiodatei: $e');
              }
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(userId)
                  .collection('traeume')
                  .doc(t.id)
                  .delete()
                  .catchError((_) {});
            }
            Provider.of<TraumProvider>(
              context,
              listen: false,
            ).removeTraum(t.id);
          },
        ),
        children: [
          SlidableAction(
            onPressed: (_) async {
              // Compose share text
              final buffer = StringBuffer();
              buffer.writeln('Hallo, ich teile mit dir hier einen Traum.');
              if ((t.title ?? '').isNotEmpty) buffer.writeln('Titel: ${t.title}');
              if ((t.summary ?? '').isNotEmpty) buffer.writeln('\nZusammenfassung:\n${t.summary}');
              final shareText = buffer.toString();

              // Resolve audio path (local preferred, else download from audioUrl)
              final audioPath = await _getShareableAudioPathForTraum(t);
              if (audioPath != null) {
                final mime = _mimeForPath(audioPath);
                final x = XFile(audioPath, mimeType: mime, name: pth.basename(audioPath));
                await Share.shareXFiles([x], text: shareText, subject: 'PHONĒ Traum');
              } else {
                // Fallback: kein Audio verfügbar -> Transkript mitsenden
                final transcriptText = (t.transcript ?? '').trim();
                final textWithTranscript = transcriptText.isNotEmpty
                    ? shareText + '\n\nTranskript:\n' + transcriptText
                    : shareText + '\n\n(Kein Audio oder Transkript verfügbar)';
                await Share.share(textWithTranscript, subject: 'PHONĒ Traum');
              }
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
              if (userId != null) {
                try {
                  final docRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('traeume')
                      .doc(t.id);
                  final docSnap = await docRef.get();
                  final audioUrl = docSnap.data()?['audioUrl'] as String?;
                  if (audioUrl != null &&
                      audioUrl.isNotEmpty &&
                      (audioUrl.startsWith('https://') ||
                          audioUrl.startsWith('gs://'))) {
                    await FirebaseStorage.instance
                        .refFromURL(audioUrl)
                        .delete()
                        .catchError((_) {});
                  }
                } catch (e) {
                  print('Fehler beim Löschen der Audiodatei: $e');
                }
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(userId)
                    .collection('traeume')
                    .doc(t.id)
                    .delete()
                    .catchError((_) {});
              }
              setState(() {
                traeume.removeWhere((element) => element.id == t.id);
              });
              await saveTraeume();
            },
            backgroundColor: Colors.red,
            borderRadius: BorderRadius.zero,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: 'Löschen',
          ),
        ],
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: () async {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Theme.of(context).cardColor,
                builder: (_) => TraumDetailSheet(traumId: t.id),
              );
            },
            child: Container(
              decoration: const BoxDecoration(color: Colors.transparent),
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
                            "${t.timestamp.day}. ${_monthName(t.timestamp.month)} ${t.timestamp.year}",
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              color:
                                  (Theme.of(
                                            context,
                                          ).textTheme.bodySmall?.color ??
                                          Colors.grey)
                                      .withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            t.creatorName ?? '',
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(
                                context,
                              ).textTheme.bodySmall?.color,
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
                              (t.title?.isNotEmpty ?? false)
                                  ? t.title!
                                  : "Kein Titel",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color ??
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
                  if (t.labels != null &&
                      t.labels.isNotEmpty &&
                      (t.labels.first != null && t.labels.first.isNotEmpty))
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
                            t.labels.first,
                            style: const TextStyle(
                              color: Color(0xFFFF2C55),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          labelStyle: const TextStyle(
                            color: Color(0xFFFF2C55),
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                          backgroundColor: const Color(
                            0xFFFF2C55,
                          ).withOpacity(0.1),
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
          const Divider(height: 1, thickness: 0.5),
        ],
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

extension TraumeCopyWith on Traum {
  Traum copyWith({
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
    String? transcript,
  }) {
    return Traum(
      id: id ?? this.id,
      labels: labels ?? this.labels,
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
Future<void> saveTraeume() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userId = user.uid;

  for (var traum in traeume) {
    final id = traum.id;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('traeume')
        .doc(id)
        .set(traum.toJson());
  }
}
