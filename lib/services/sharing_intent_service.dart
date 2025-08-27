import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../main.dart'; // navigatorKey
import '../screens/share_import_screen.dart';

class SharingIntentService {
  static StreamSubscription? _sub;
  static bool _isNavigating = false;

  // De-Dupe: merke, was zuletzt geöffnet wurde, plus kleiner Cooldown
  static String? _lastHandledPath;
  static DateTime _lastHandledAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _dedupeWindow = Duration(seconds: 2);

  /// Call this ONCE after runApp(), am besten via addPostFrameCallback.
  static void init() {
    debugPrint("[SharingIntentService] init...");
    if (_sub != null) {
      debugPrint("[SharingIntentService] already initialized");
      return;
    }

    // 1) Warmstart: App läuft bereits
    _sub = ReceiveSharingIntent.instance.getMediaStream().listen(
      (items) async {
        debugPrint(
          "[SharingIntentService] stream: ${items.map((f) => f.path).join(', ')}",
        );
        await _handleIncoming(items);
      },
      onError: (e) => debugPrint("[SharingIntentService] stream error: $e"),
    );

    // 2) Kaltstart: App wird durch Teilen gestartet
    ReceiveSharingIntent.instance.getInitialMedia().then((items) async {
      debugPrint(
        "[SharingIntentService] initial: ${items.map((f) => f.path).join(', ')}",
      );
      await _handleIncoming(items);
    }).catchError((e) {
      debugPrint("[SharingIntentService] initial error: $e");
    });
  }

  static void dispose() {
    debugPrint("[SharingIntentService] dispose");
    _sub?.cancel();
    _sub = null;
  }

  // ------------------ intern ------------------

  static Future<void> _handleIncoming(List<SharedMediaFile> items) async {
    if (items.isEmpty) {
      debugPrint("[SharingIntentService] no items");
      return;
    }

    final SharedMediaFile picked = _pickBestAudio(items);
    final srcPath = picked.path;

    // De-Dupe: zwei Events kurz hintereinander ignorieren
    final now = DateTime.now();
    if (_lastHandledPath == srcPath &&
        now.difference(_lastHandledAt) < _dedupeWindow) {
      debugPrint("[SharingIntentService] deduped: $srcPath");
      return;
    }

    // Datei existiert?
    final src = File(srcPath);
    if (!await src.exists()) {
      debugPrint("[SharingIntentService] src missing: $srcPath");
      // Wir versuchen trotzdem zu öffnen, aber das wird im Screen dann scheitern.
      // Besser: früh raus.
      return;
    }

    // Sofort in App-Storage sichern, Temp-Verzeichnis der Extension ist flüchtig
    final safePath = await _persistToAppStorage(srcPath);

    // De-Dupe-Status aktualisieren
    _lastHandledPath = srcPath;
    _lastHandledAt = now;

    await _openImportScreen(safePath);
  }

  static SharedMediaFile _pickBestAudio(List<SharedMediaFile> items) {
    SharedMediaFile? preferred;
    for (final f in items) {
      final lower = f.path.toLowerCase();
      if (lower.endsWith('.m4a') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.aac') ||
          lower.endsWith('.mp3') ||
          lower.endsWith('.caf')) {
        preferred = f;
        break;
      }
    }
    return preferred ?? items.first;
  }

  static Future<String> _persistToAppStorage(String srcPath) async {
    try {
      final src = File(srcPath);
      final docs = await getApplicationDocumentsDirectory();
      final basename = p.basename(srcPath);
      // Eindeutiger Dateiname, um Überschreiben zu vermeiden
      final uniqueName =
          "${DateTime.now().millisecondsSinceEpoch}_${basename.replaceAll(' ', '_')}";
      final dest = File(p.join(docs.path, uniqueName));
      final copied = await src.copy(dest.path);
      debugPrint(
          "[SharingIntentService] copied to ${copied.path} (${await copied.length()} bytes)");
      return copied.path;
    } catch (e) {
      debugPrint("[SharingIntentService] copy failed: $e");
      // Fallback: nutze Originalpfad
      return srcPath;
    }
  }

  static Future<void> _openImportScreen(String filePath) async {
    debugPrint("[SharingIntentService] open ImportScreen: $filePath");

    if (_isNavigating) {
      debugPrint("[SharingIntentService] navigation busy, skip");
      return;
    }

    Future<void> push() async {
      final nav = navigatorKey.currentState;
      if (nav == null) {
        debugPrint("[SharingIntentService] NavigatorState null");
        return;
      }
      _isNavigating = true;
      await nav.push(
        MaterialPageRoute(
          builder: (_) => ShareImportScreen(filePath: filePath),
          fullscreenDialog: true,
        ),
      );
      _isNavigating = false;
    }

    // Falls der Navigator noch nicht bereit ist (Kaltstart)
    if (navigatorKey.currentState == null) {
      debugPrint("[SharingIntentService] wait for navigator...");
      // auf nächsten Frame warten
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        // kurze Pufferzeit
        await Future.delayed(const Duration(milliseconds: 300));
        if (navigatorKey.currentState != null) {
          await push();
        } else {
          // letzter Versuch
          await Future.delayed(const Duration(milliseconds: 700));
          if (navigatorKey.currentState != null) {
            await push();
          } else {
            debugPrint("[SharingIntentService] navigator still null");
          }
        }
      });
      return;
    }

    await push();
  }
}