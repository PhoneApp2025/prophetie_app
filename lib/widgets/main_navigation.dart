import 'dart:async';
import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../data/globals.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import 'package:uni_links/uni_links.dart'; // Deep Link Vorbereitung
import 'package:uuid/uuid.dart';
import '../screens/import_screen.dart';
import '../models/prophetie.dart';
import '../models/traum.dart';
import '../screens/home_screen.dart';
import '../screens/prophetien_screen.dart';
import '../screens/aufnahme_screen.dart';
import '../screens/traeume_screen.dart';
import '../screens/profil_screen.dart';
import '../screens/phone_plus_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/audio_transcription_service.dart';
import '../services/traum_analysis_service.dart';
import '../services/prophetie_analysis_service.dart';
import '../services/recording_service.dart';
import 'package:provider/provider.dart';
import '../providers/prophetie_provider.dart';
import '../providers/traum_provider.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation>
    with TickerProviderStateMixin {
  int _currentIndex = 0;

  bool shouldRefreshProphetien = false;
  bool shouldRefreshTraeume = false;

  final GlobalKey<ProphetienScreenState> _prophetienScreenKey =
      GlobalKey<ProphetienScreenState>();
  final GlobalKey<TraeumeScreenState> _traeumeScreenKey =
      GlobalKey<TraeumeScreenState>();

  // Deep Link Handling auf dedizierten ImportScreen verschoben

  List<Widget> get _pages => [
    HomeScreen(),
    ProphetienScreen(key: _prophetienScreenKey),
    const AufnahmeScreen(), // ✅ jetzt ok
    TraeumeScreen(key: _traeumeScreenKey),
    const ProfilScreen(),
  ];

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });

    // Prophetien automatisch laden entfernt
    /*
    if (index == 1) {
      loadProphetien().then((_) {
        setState(() {
          _shouldRefreshProphetien = false;
        });
        _prophetienScreenKey.currentState?.refreshProphetien();
      });
    }
    */
    if (shouldRefreshTraeume && index == 3) {
      Provider.of<TraumProvider>(context, listen: false).loadTraeume().then((
        _,
      ) {
        setState(() {
          shouldRefreshTraeume = false;
        });
      });
    }
  }

  Widget _buildIcon(String asset, int index) {
    return IconButton(
      onPressed: () => _onTabTapped(index),
      icon: SvgPicture.asset(
        asset,
        color: _currentIndex == index ? const Color(0xFFFF2C55) : Colors.grey,
        width: 24,
        height: 24,
      ),
    );
  }

  Widget _buildMiddleButton() {
    return GestureDetector(
      onTap: () {
        if (hatPremium) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            transitionAnimationController: AnimationController(
              duration: const Duration(milliseconds: 500),
              vsync: Navigator.of(context),
            ),
            builder: (_) => RecordingBottomSheet(
              onSaved: () {
                _prophetienScreenKey.currentState?.refreshProphetien();
                _traeumeScreenKey.currentState?.refreshTraeume();
              },
            ),
          );
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
      child: Hero(
        tag: 'mic-button',
        child: Transform.rotate(
          angle: 0.785398, // 45 degrees
          child: Container(
            height: 64,
            width: 64,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Transform.rotate(
                angle: -0.785398,
                child: SvgPicture.asset(
                  'assets/icons/aufnahme.svg',
                  color: Colors.white,
                  width: 28,
                  height: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Labels beim Start laden
    handleInitialLink(); // Für zukünftigen Firebase Import
  }

  void handleInitialLink() async {
    try {
      final initialUri = await getInitialUri();
      if (initialUri != null && mounted) {
        final type = initialUri.queryParameters['type'];
        final id = initialUri.queryParameters['id'];
        if (type != null && id != null) {
          Navigator.pushNamed(context, '/import');
        }
      }
    } catch (e) {
      print('Fehler beim Verarbeiten des initialen Deep Links: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Container(
        height: 80,
        margin: const EdgeInsets.all(2), // Abstand zu den Seiten
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor, // <- statt Colors.white
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 15,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.topCenter,
          clipBehavior: Clip.none,
          children: [
            // Icons links & rechts
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 30.0,
                vertical: 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Linke Seite
                  Row(
                    children: [
                      _buildIcon('assets/icons/home.svg', 0),
                      const SizedBox(width: 16),
                      _buildIcon('assets/icons/prophetie.svg', 1),
                    ],
                  ),
                  // Rechte Seite
                  Row(
                    children: [
                      _buildIcon('assets/icons/traeume.svg', 3),
                      const SizedBox(width: 16),
                      _buildIcon('assets/icons/profil.svg', 4),
                    ],
                  ),
                ],
              ),
            ),

            // Mittlerer Button ragt heraus
            Positioned(top: -15, child: _buildMiddleButton()),
          ],
        ),
      ),
    );
  }
}

class RecordingBottomSheet extends StatefulWidget {
  final VoidCallback? onSaved;

  const RecordingBottomSheet({super.key, this.onSaved});

  @override
  State<RecordingBottomSheet> createState() => _RecordingBottomSheetState();
}

class _RecordingBottomSheetState extends State<RecordingBottomSheet> {
  late final RecordingService _recordingService;
  bool isRecording = false;
  Duration _elapsed = Duration.zero;
  String? selectedType;
  bool _isSaving = false;

  Future<bool> _onWillPop() async {
    final shouldClose = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: const Text('Aufnahme verwerfen?'),
        content: const Text('Möchtest du die Aufnahme wirklich verwerfen?'),
        actions: [
          CupertinoDialogAction(
            child: const Text('Nein'),
            onPressed: () => Navigator.of(context).pop(false),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Ja'),
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return shouldClose ?? false;
  }

  @override
  void initState() {
    super.initState();
    _recordingService = RecordingService(
      onTimerTick: (duration) {
        if (mounted) {
          setState(() {
            _elapsed = duration;
          });
        }
      },
    );
    _startRecording();
  }

  @override
  void dispose() {
    _recordingService.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    await _recordingService.startRecording();
    if (mounted) {
      setState(() {
        isRecording = true;
      });
    }
  }

  Future<void> _pauseRecording() async {
    await _recordingService.pauseRecording();
    if (mounted) {
      setState(() {
        isRecording = false;
      });
    }
  }

  Future<void> _resumeRecording() async {
    await _recordingService.resumeRecording();
    if (mounted) {
      setState(() {
        isRecording = true;
      });
    }
  }

  Future<void> _stopRecording() async {
    await _recordingService.stopRecording();
    if (mounted) {
      setState(() {
        isRecording = false;
      });

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setState) {
              return Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(30),
                  ),
                ),
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(minHeight: 310),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Was möchtest du speichern?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              selectedType = 'prophetie';
                            });
                          },
                          icon: const Icon(Icons.lightbulb),
                          label: const Text('Prophetie'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() {
                              selectedType = 'traum';
                            });
                          },
                          icon: const Icon(Icons.nightlight),
                          label: const Text('Traum'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                    if (selectedType != null) ...[
                      const SizedBox(height: 24),
                      Text(
                        'Ist diese ${selectedType == 'traum' ? 'Traum' : 'Prophetie'} für dich oder jemand anderen?',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton(
                            onPressed: () async {
                              await _saveProphetie(selectedType!);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Für mich'),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              await _saveProphetie(
                                selectedType!,
                                shareAfter: true,
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.black,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Für jemand anderen'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      );
    }
  }

  Future<String> transcribeWithWhisper(String filePath) async {
    print('[WHISPER] Sende Datei: $filePath');
    final apiKey = dotenv.env['OPENAI_API_KEY'];
    final uri = Uri.parse('https://api.openai.com/v1/audio/transcriptions');

    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $apiKey'
      ..files.add(await http.MultipartFile.fromPath('file', filePath))
      ..fields['model'] = 'whisper-1';

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    print('[WHISPER] Antwortcode: ${response.statusCode}');
    print('[WHISPER] Antworttext: ${response.body}');

    if (response.statusCode == 200) {
      final result = jsonDecode(response.body);
      return result['text'] ?? '';
    } else {
      throw Exception('Fehler bei Transkription: ${response.body}');
    }
  }

  Future<void> _saveProphetie(String type, {bool shareAfter = false}) async {
    if (_isSaving || _recordingService.recordingPath == null) return;
    _isSaving = true;
    final id = const Uuid().v4();
    final file = File(_recordingService.recordingPath!);
    // 1. Upload audio to Firebase Storage
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final storageRef = FirebaseStorage.instance.ref().child(
      'users/$userId/${type}-audio/$id.wav',
    );
    await storageRef.putFile(file);
    final audioUrl = await storageRef.getDownloadURL();
    // 2. Prepare Firestore data
    final data = {
      'text': null,
      'label': 'NEU',
      'isFavorit': false,
      'timestamp': DateTime.now(),
      'audioUrl': audioUrl,
      'creatorName': FirebaseAuth.instance.currentUser?.displayName,
      // 'isAnalyzed': false, // Entfernt: isAnalyzed wird beim Anlegen nicht mehr gesetzt
    };
    // 3. Save document (nur wenn für dich)
    if (!shareAfter) {
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection(type == 'prophetie' ? 'prophetien' : 'traeume')
          .doc(id);

      await docRef.set({
        ...data,
        'title': 'Wird analysiert',
      }, SetOptions(merge: true));

      // Direkt nach dem Speichern Bottom Sheet schließen und Callback aufrufen
      if (mounted) {
        Navigator.of(context).pop(); // Close selection bottom sheet
        Navigator.of(context).pop(); // Close recording bottom sheet
      }
      if (widget.onSaved != null) {
        widget.onSaved!();
      }

      final navState = context.findAncestorStateOfType<_MainNavigationState>();
      if (type == 'prophetie') {
        navState?._prophetienScreenKey.currentState?.handleNewProphetie(
          id: id,
          localFilePath: audioUrl,
          transcriptText: null,
          label: 'NEU',
        );
      } else {
        navState?._traeumeScreenKey.currentState?.handleNewTraum(
          id: id,
          localFilePath: audioUrl,
          transcriptText: null,
          label: 'NEU',
        );
      }
    }

    // 4. Analyse starten (nur bei "Für mich")
    final localPath = _recordingService.recordingPath;
    if (localPath != null) {
      Future.microtask(() async {
        final transcript = await transcribeAudioFile(localPath);
        if (transcript != null) {
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .collection(type == 'prophetie' ? 'prophetien' : 'traeume')
              .doc(id)
              .set({'transcript': transcript}, SetOptions(merge: true));

          if (type == 'traum') {
            await analyzeAndSaveTraum(
              transcript: transcript,
              firestoreDocId: id,
            );
          } else {
            await analyzeAndSaveProphetie(
              transcript: transcript,
              firestoreDocId: id,
            );
          }
        }
      });
    }

    // 5. Optional Teilen
    if (shareAfter) {
      final creatorName =
          FirebaseAuth.instance.currentUser?.displayName ?? 'unbekannt';
      final url =
          'https://phone.simonnikel.de/add?type=$type&id=$id&creator=${Uri.encodeComponent(creatorName)}';
      final shareText =
          'Hey! Ich habe für dich eine ${type == 'traum' ? 'Traum' : 'Prophetie'} aufgenommen.\n\n$url';

      // Share audio file as attachment with text
      final xfile = XFile(_recordingService.recordingPath!);
      await Share.shareXFiles([xfile], text: shareText);
      // Optionally delete audio file after sharing
      try {
        await file.delete();
      } catch (e) {
        print('Datei konnte nach dem Teilen nicht gelöscht werden: $e');
      }
      // Vor dem Speichern in die globale Liste in Firestore hochladen
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('gesendet')
          .doc(id)
          .set({
            'text': null,
            'label': type == 'traum' ? 'Traum' : 'Prophetie',
            'timestamp': DateTime.now(),
            'audioUrl': audioUrl,
            'category': type,
            'status': 'gesendet',
            'creatorName': FirebaseAuth.instance.currentUser?.displayName,
          });
    }

    // 6. Nach dem Speichern: refresh, Navigation
    Future.microtask(() {
      if (!mounted) return;
      final navState = context.findAncestorStateOfType<_MainNavigationState>();
      if (type == 'prophetie') {
        Provider.of<ProphetieProvider>(context, listen: false).loadProphetien();
        navState?._onTabTapped(1);
      } else {
        Provider.of<TraumProvider>(context, listen: false).loadTraeume();
        navState?._onTabTapped(3);
      }
    });
    // 7. Clear temp path
    _isSaving = false;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Aufnahme',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedOpacity(
                  opacity: isRecording ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: isRecording ? 12 : 8,
                    height: isRecording ? 12 : 8,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${_elapsed.inMinutes.remainder(60).toString().padLeft(2, '0')}:${_elapsed.inSeconds.remainder(60).toString().padLeft(2, '0')}.${(_elapsed.inMilliseconds.remainder(1000) ~/ 10).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10, width: double.infinity),
            AudioWaveforms(
              size: Size(MediaQuery.of(context).size.width - 48, 100),
              recorderController: _recordingService.recorderController,
              enableGesture: true,
              waveStyle: const WaveStyle(
                waveColor: Color(0xFFFF2C55),
                showMiddleLine: false,
                extendWaveform: true,
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    final shouldClose = await _onWillPop();
                    if (shouldClose) {
                      if (mounted) Navigator.of(context).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade50,
                    foregroundColor: Colors.red,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(100, 40),
                  ),
                  child: const Text(
                    "Abbrechen",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (isRecording) {
                      await _pauseRecording();
                    } else {
                      await _resumeRecording();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromARGB(255, 67, 67, 67),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(
                      40,
                      40,
                    ), // gleiche Höhe wie andere Buttons
                    padding: EdgeInsets.zero,
                  ),
                  child: Icon(
                    isRecording ? Icons.pause : Icons.play_arrow,
                    size: 20,
                    color: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _stopRecording,
                  icon: const Icon(Icons.check, color: Colors.green),
                  label: const Text(
                    "Fertig",
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade50,
                    foregroundColor: Colors.green,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    minimumSize: const Size(100, 40),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
