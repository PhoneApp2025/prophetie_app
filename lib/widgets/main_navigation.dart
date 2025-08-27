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
// import '../screens/phone_plus_screen.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import '../services/purchase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/audio_transcription_service.dart';
import '../services/traum_analysis_service.dart';
import '../services/prophetie_analysis_service.dart';
import '../services/recording_service.dart';
import 'package:provider/provider.dart';
import '../providers/premium_provider.dart';
import '../providers/prophetie_provider.dart';
import '../providers/traum_provider.dart';

import '../services/sharing_intent_service.dart';

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

  // Deep Link Handling auf dedizierten ImportScreen verschoben

  List<Widget> get _pages => [
    HomeScreen(),
    ProphetienScreen(key: _prophetienScreenKey),
    const AufnahmeScreen(), // ✅ jetzt ok
    const TraeumeScreen(),
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
    final isPremium = context.watch<PremiumProvider>().isPremium;
    return GestureDetector(
      onTap: () async {
        if (isPremium) {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            transitionAnimationController: AnimationController(
              duration: const Duration(milliseconds: 500),
              vsync: Navigator.of(context),
            ),
            builder: (_) => const RecordingBottomSheet(),
          );
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
    SharingIntentService.init(); // ✅ ohne context
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
  const RecordingBottomSheet({super.key});

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

  void _showBlockingLoader() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                CupertinoActivityIndicator(radius: 14),
                SizedBox(height: 12),
                Text(
                  'Vorbereiten…',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _hideBlockingLoader() {
    if (!mounted) return;
    // Pop the loader dialog if it is shown
    Navigator.of(context, rootNavigator: true).pop();
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
      // Haptik: Abschluss der Aufnahme
      await HapticFeedback.mediumImpact();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useRootNavigator: true,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(0.25),
        builder: (context) {
          return SafeArea(
            top: false,
            bottom: false,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Aufnahme speichern',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Wähle direkt eine Aktion – schneller, weniger Taps.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),

                  // Quick Actions Grid (4 Optionen)
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisExtent: 92,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    children: [
                      _QuickActionTile(
                        iconWidget: SvgPicture.asset(
                          'assets/icons/prophetie.svg',
                          width: 20,
                          height: 20,
                          color: const Color(0xFFFF2C55),
                        ),
                        title: 'Prophetie',
                        subtitle: 'für mich',
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          _saveRecording('prophetie', shareAfter: false);
                        },
                      ),
                      _QuickActionTile(
                        iconWidget: SvgPicture.asset(
                          'assets/icons/prophetie.svg',
                          width: 20,
                          height: 20,
                          color: const Color(0xFFFF2C55),
                        ),
                        title: 'Prophetie',
                        subtitle: 'teilen',
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          _saveRecording('prophetie', shareAfter: true);
                        },
                      ),
                      _QuickActionTile(
                        iconWidget: SvgPicture.asset(
                          'assets/icons/traeume.svg',
                          width: 20,
                          height: 20,
                          color: const Color(0xFFFF2C55),
                        ),
                        title: 'Traum',
                        subtitle: 'für mich',
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          _saveRecording('traum', shareAfter: false);
                        },
                      ),
                      _QuickActionTile(
                        iconWidget: SvgPicture.asset(
                          'assets/icons/traeume.svg',
                          width: 20,
                          height: 20,
                          color: const Color(0xFFFF2C55),
                        ),
                        title: 'Traum',
                        subtitle: 'teilen',
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          _saveRecording('traum', shareAfter: true);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),
                  // Hint / Info
                  Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Theme.of(context).hintColor,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Teilen lädt die Aufnahme hoch und öffnet die System-Teilen-Funktion.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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

  Future<void> _saveRecording(String type, {bool shareAfter = false}) async {
    if (_isSaving || _recordingService.recordingPath == null) return;
    setState(() => _isSaving = true);

    if (shareAfter) {
      _showBlockingLoader();
      // give the UI a beat to paint the dialog before heavy work
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final id = const Uuid().v4();
    final file = File(_recordingService.recordingPath!);
    final userId = FirebaseAuth.instance.currentUser!.uid;
    final collectionName = type == 'prophetie' ? 'prophetien' : 'traeume';

    try {
      String? audioUrl;

      if (shareAfter) {
        // --- Temporär deaktiviert: Upload nach Storage für geteilte Aufnahmen ---
        // final storageRef = FirebaseStorage.instance.ref().child(
        //   'users/$userId/$collectionName/$id.wav',
        // );
        // await storageRef.putFile(file);
        // audioUrl = await storageRef.getDownloadURL();
        // -----------------------------------------------------------------------

        // Temporarily disabled: saving to Firestore for share actions
        // Only sharing via system share sheet is active.

        // Nur Text + Audio teilen, KEIN Link
        final shareText = 'Hey! Ich habe für dich eine ' 
            '${type == 'traum' ? 'Traum' : 'Prophetie'} aufgenommen.';

        final xfile = XFile(_recordingService.recordingPath!);
        await Share.shareXFiles([xfile], text: shareText);

        // await FirebaseFirestore.instance
        //     .collection('users')
        //     .doc(userId)
        //     .collection('gesendet')
        //     .doc(id)
        //     .set({
        //       'id': id,
        //       'text': null,
        //       'label': type == 'traum' ? 'Traum' : 'Prophetie',
        //       'timestamp': DateTime.now(),
        //       // 'audioUrl': audioUrl, // temporär deaktiviert
        //       'category': type,
        //       'status': 'gesendet',
        //       'creatorName': FirebaseAuth.instance.currentUser?.displayName,
        //     });
      } else {
        // Fire-and-forget saving for "für mich"
        if (type == 'prophetie') {
          final provider = Provider.of<ProphetieProvider>(
            context,
            listen: false,
          );
          Future(
            () => provider.handleNewProphetie(
              id: id,
              localFilePath: file.path,
              labels: [],
            ),
          );
        } else {
          final provider = Provider.of<TraumProvider>(context, listen: false);
          Future(
            () => provider.handleNewTraum(
              id: id,
              localFilePath: file.path,
              labels: [],
            ),
          );
        }
      }

      // Close sheets and switch tab immediately
      if (mounted) {
        Navigator.of(context).pop(); // Close "Was möchtest du speichern?" sheet
        Navigator.of(context).pop(); // Close recording bottom sheet
        context.findAncestorStateOfType<_MainNavigationState>()?._onTabTapped(
          type == 'prophetie' ? 1 : 3,
        );
      }
    } catch (e) {
      // Handle errors, e.g., show a snackbar
      print("Error saving recording: $e");
    } finally {
      if (shareAfter) {
        // Close the blocking loader before closing any sheets
        _hideBlockingLoader();
      }
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
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
                    await HapticFeedback.lightImpact();
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
                    await HapticFeedback.selectionClick();
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
                  onPressed: () async {
                    await HapticFeedback.heavyImpact();
                    await _stopRecording();
                  },
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

class _QuickActionTile extends StatelessWidget {
  final Widget iconWidget;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickActionTile({
    required this.iconWidget,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFFF2D55);
    return Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF1C1C1E)
          : Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTapDown: (_) => HapticFeedback.lightImpact(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Center(child: iconWidget),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}