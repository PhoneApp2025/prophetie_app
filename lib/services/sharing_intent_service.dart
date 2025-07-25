import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:async';
import '../screens/import_screen.dart';

class SharingIntentService {
  static StreamSubscription? _intentDataStreamSubscription;
  static BuildContext? _rootContext;

  static void init(BuildContext context) {
    // Nur einmal initialisieren
    if (_intentDataStreamSubscription != null) return;

    _rootContext = context;

    // Listener: App läuft und erhält eine Datei
    _intentDataStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(
          (List<SharedMediaFile> value) {
            if (value.isNotEmpty) {
              _openImportScreen(value.first.path);
            }
          },
          onError: (err) {
            print("getMediaStream error: $err");
          },
        );

    // Listener: App wird durch Teilen gestartet
    ReceiveSharingIntent.instance.getInitialMedia().then((
      List<SharedMediaFile> value,
    ) {
      if (value.isNotEmpty) {
        _openImportScreen(value.first.path);
      }
    });
  }

  static void dispose() {
    _intentDataStreamSubscription?.cancel();
    _intentDataStreamSubscription = null;
    _rootContext = null;
  }

  static void _openImportScreen(String filePath) {
    if (_rootContext == null) return;

    Navigator.push(
      _rootContext!,
      MaterialPageRoute(
        builder: (context) => ImportScreen(audioFilePath: filePath),
      ),
    );
  }
}
