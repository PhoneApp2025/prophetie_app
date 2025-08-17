import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import '../screens/share_import_screen.dart';
import '../main.dart'; // for navigatorKey

class SharingIntentService {
  static StreamSubscription? _intentDataStreamSubscription;
  static bool _isNavigating = false;

  /// Initializes listeners for sharing intents. Call this once from main().
  static void init(BuildContext context) {
    print("[SharingIntentService] Initializing...");
    if (_intentDataStreamSubscription != null) {
      print("[SharingIntentService] Already initialized.");
      return;
    }

    // Listener: App läuft und erhält eine Datei
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            print(
              "[SharingIntentService] Received media stream: ${value.map((f) => f.path).join(', ')}",
            );
            if (value.isNotEmpty) {
              final SharedMediaFile audio = value.firstWhere((f) {
                final lower = f.path.toLowerCase();
                return lower.endsWith('.m4a') ||
                    lower.endsWith('.wav') ||
                    lower.endsWith('.aac') ||
                    lower.endsWith('.mp3') ||
                    lower.endsWith('.caf');
              }, orElse: () => value.first);
              _openImportScreen(audio.path);
            } else {
              print("[SharingIntentService] Media stream was empty.");
            }
          },
          onError: (err) {
            print("[SharingIntentService] getMediaStream error: $err");
          },
        );
    print("[SharingIntentService] Media stream listener set up.");

    // Listener: App wird durch Teilen gestartet
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      print(
        "[SharingIntentService] Received initial media: ${value.map((f) => f.path).join(', ')}",
      );
      if (value.isNotEmpty) {
        final SharedMediaFile audio = value.firstWhere((f) {
          final lower = f.path.toLowerCase();
          return lower.endsWith('.m4a') ||
              lower.endsWith('.wav') ||
              lower.endsWith('.aac') ||
              lower.endsWith('.mp3') ||
              lower.endsWith('.caf');
        }, orElse: () => value.first);
        _openImportScreen(audio.path);
      } else {
        print("[SharingIntentService] Initial media was empty.");
      }
    });
    print("[SharingIntentService] Initial media handler set up.");
  }

  /// Stops listening to sharing intents. Call this in dispose if needed.
  static void dispose() {
    print("[SharingIntentService] Disposing...");
    _intentDataStreamSubscription?.cancel();
    _intentDataStreamSubscription = null;
  }

  /// Navigates to the ImportScreen via the global navigatorKey.
  static void _openImportScreen(String filePath) {
    print(
      "[SharingIntentService] Attempting navigation via navigatorKey with file: $filePath",
    );
    if (_isNavigating) {
      print('[SharingIntentService] Navigation already in progress, skipping.');
      return;
    }

    // Basic guard: ensure we have a plausible audio file path
    final lower = filePath.toLowerCase();
    final isAudio =
        lower.endsWith('.m4a') ||
        lower.endsWith('.wav') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.caf');
    if (!isAudio) {
      print('[SharingIntentService] Skipping: not an audio file.');
      // We still try to open ImportScreen; many iOS share targets provide temp extensions
      // If you want to strictly block, return here instead of continuing.
    }

    void pushImport() {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        print('[SharingIntentService] NavigatorState still null at pushImport');
        return;
      }
      _isNavigating = true;
      nav
          .push(
            MaterialPageRoute(
              builder: (context) => ShareImportScreen(filePath: filePath),
            ),
          )
          .then((_) => _isNavigating = false);
      print('[SharingIntentService] Navigation to ImportScreen triggered.');
    }

    // If navigator is not ready yet (cold start on iOS), delay until next frame
    if (navigatorKey.currentState == null) {
      print('[SharingIntentService] Navigator not ready, delaying push...');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // small delay to ensure MaterialApp is mounted
        Future.delayed(const Duration(milliseconds: 300), () {
          if (navigatorKey.currentState != null) {
            pushImport();
          } else {
            // last resort: schedule once more
            Future.delayed(const Duration(milliseconds: 700), () {
              if (navigatorKey.currentState != null) {
                pushImport();
              } else {
                print(
                  '[SharingIntentService] Failed to acquire Navigator after delays.',
                );
              }
            });
          }
        });
      });
      return;
    }

    // Navigator ready now
    pushImport();
  }
}
