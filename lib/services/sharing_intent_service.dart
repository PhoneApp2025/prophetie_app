import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../main.dart'; // navigatorKey
import '../screens/share_import_screen.dart';

class SharingIntentService {
  static bool _handoverInProgress = false;
  static bool _handoverAttempted = false;

  static StreamSubscription? _sub;
  static bool _isNavigating = false;

  // De-Dupe: merke, was zuletzt geöffnet wurde, plus kleiner Cooldown
  static String? _lastHandledPath;
  static DateTime _lastHandledAt = DateTime.fromMillisecondsSinceEpoch(0);
  static const _dedupeWindow = Duration(seconds: 2);

  static const MethodChannel _shareChannel = MethodChannel('com.simonnikel.phone/share');

  static Future<void> _deleteIfSafe(String srcPath) async {
    try {
      final lower = srcPath.toLowerCase();
      final isInbox = lower.contains('/documents/inbox/');
      final isTmp = lower.contains('/tmp/') || lower.contains('/tmp-') || lower.endsWith('.tmp');
      // Auch AppGroup-Pfade können gefahrlos nach dem Kopieren gelöscht werden
      // (sie dienen nur als Übergabe-Container).
      final isShareContainer = lower.contains('shared app group') || lower.contains('/appgroup/') || lower.contains('/group.');
      if (isInbox || isTmp || isShareContainer) {
        final f = File(srcPath);
        if (await f.exists()) {
          await f.delete();
          debugPrint('[SharingIntentService] deleted source: $srcPath');
        }
      }
    } catch (e) {
      debugPrint('[SharingIntentService] delete source failed: $e');
    }
  }

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
        debugPrint("[SharingIntentService] stream: ${items.map((f) => f.path).join(', ')}");
        await _handleIncoming(items);
      },
      onError: (e) => debugPrint("[SharingIntentService] stream error: $e"),
    );

    // 2) Kaltstart: App wird durch Teilen gestartet
    ReceiveSharingIntent.instance.getInitialMedia().then((items) async {
      debugPrint("[SharingIntentService] initial: ${items.map((f) => f.path).join(', ')}");
      await _handleIncoming(items);
    }).catchError((e) {
      debugPrint("[SharingIntentService] initial error: $e");
    });

    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'wakeFromShare') {
        debugPrint('[SharingIntentService] wakeFromShare received');
        await _pollForHandover(timeoutMs: 8000, intervalMs: 250);
      }
      return null;
    });

    // FALLBACK: Wenn das Plugin keine Items liefert, warte kurz auf Handover
    Future<void>.delayed(const Duration(milliseconds: 500), () async {
      if (!_handoverAttempted && _lastHandledPath == null) {
        await _pollForHandover(timeoutMs: 6000, intervalMs: 300);
      }
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
    if (_lastHandledPath == srcPath && now.difference(_lastHandledAt) < _dedupeWindow) {
      debugPrint("[SharingIntentService] deduped: $srcPath");
      return;
    }

    // Datei existiert?
    final src = File(srcPath);
    if (!await src.exists()) {
      debugPrint("[SharingIntentService] src missing: $srcPath");
      return;
    }

    // Sofort in App-Storage sichern, Temp-Verzeichnis der Extension ist flüchtig
    final safePath = await _persistToAppStorage(srcPath);

    // Quelle aus Übergabe-Container löschen
    await _deleteIfSafe(srcPath);

    // De-Dupe-Status aktualisieren
    _lastHandledPath = srcPath;
    _lastHandledAt = now;

    await _openImportScreen(safePath);
  }

  static SharedMediaFile _pickBestAudio(List<SharedMediaFile> items) {
    for (final f in items) {
      final lower = f.path.toLowerCase();
      if (lower.endsWith('.m4a') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.aac') ||
          lower.endsWith('.mp3') ||
          lower.endsWith('.caf') ||
          lower.endsWith('.ogg') ||
          lower.endsWith('.opus') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.flac')) {
        return f;
      }
    }
    return items.first;
  }

  static String _pickBestPath(List<String> paths) {
    for (final p in paths) {
      final lower = p.toLowerCase();
      if (lower.endsWith('.m4a') ||
          lower.endsWith('.wav') ||
          lower.endsWith('.aac') ||
          lower.endsWith('.mp3') ||
          lower.endsWith('.caf') ||
          lower.endsWith('.ogg') ||
          lower.endsWith('.opus') ||
          lower.endsWith('.mp4') ||
          lower.endsWith('.flac')) {
        return p;
      }
    }
    return paths.first;
  }

  static Future<void> _handleIncomingPaths(List<String> paths) async {
    if (paths.isEmpty) {
      debugPrint('[SharingIntentService] no paths');
      return;
    }

    final srcPath = _pickBestPath(paths);

    final now = DateTime.now();
    if (_lastHandledPath == srcPath && now.difference(_lastHandledAt) < _dedupeWindow) {
      debugPrint('[SharingIntentService] deduped (paths): $srcPath');
      return;
    }

    final src = File(srcPath);
    if (!await src.exists()) {
      debugPrint('[SharingIntentService] src missing (paths): $srcPath');
      return;
    }

    final safePath = await _persistToAppStorage(srcPath);

    await _deleteIfSafe(srcPath);

    _lastHandledPath = srcPath;
    _lastHandledAt = now;

    await _openImportScreen(safePath);
  }

  static Future<bool> _fetchFromAppGroup() async {
    try {
      // Wenn bereits etwas verarbeitet wurde, nicht doppelt öffnen
      if (_lastHandledPath != null) return false;
      final List<dynamic> raw = await _shareChannel.invokeMethod('fetchSharedFilePaths');
      final paths = raw.cast<String>();
      if (paths.isEmpty) {
        // nur einmal pro Aufruf loggen, kein Spam
        debugPrint('[SharingIntentService] AppGroup fetch: no files');
        return false;
      }
      debugPrint('[SharingIntentService] AppGroup paths: ${paths.join(', ')}');
      await _handleIncomingPaths(paths);
      return true;
    } catch (e) {
      debugPrint('[SharingIntentService] AppGroup fetch error: $e');
      return false;
    }
  }

  static Future<void> _pollForHandover({int timeoutMs = 8000, int intervalMs = 250}) async {
    if (_handoverInProgress || _lastHandledPath != null) return;
    _handoverInProgress = true;
    try {
      final sw = Stopwatch()..start();
      var tries = 0;
      while (sw.elapsedMilliseconds < timeoutMs && _lastHandledPath == null) {
        final handled = await _fetchFromAppGroup();
        tries++;
        if (handled || _lastHandledPath != null) {
          break;
        }
        await Future.delayed(Duration(milliseconds: intervalMs));
      }
      if (_lastHandledPath == null) {
        debugPrint('[SharingIntentService] pollForHandover: timed out after ${sw.elapsedMilliseconds}ms');
      } else {
        debugPrint('[SharingIntentService] pollForHandover: success');
      }
    } finally {
      _handoverInProgress = false;
      _handoverAttempted = true;
    }
  }

  static Future<String> _persistToAppStorage(String srcPath) async {
    try {
      final src = File(srcPath);
      final docs = await getApplicationDocumentsDirectory();
      final basename = p.basename(srcPath);
      // Eindeutiger Dateiname, um Überschreiben zu vermeiden
      final uniqueName = "${DateTime.now().millisecondsSinceEpoch}_${basename.replaceAll(' ', '_')}";
      final dest = File(p.join(docs.path, uniqueName));
      final copied = await src.copy(dest.path);
      debugPrint("[SharingIntentService] copied to ${copied.path} (${await copied.length()} bytes)");
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
      try {
        await nav.push(
          MaterialPageRoute(
            builder: (_) => ShareImportScreen(filePath: filePath),
            fullscreenDialog: true,
          ),
        );
      } finally {
        _isNavigating = false;
      }
    }

    // Falls der Navigator noch nicht bereit ist (Kaltstart)
    if (navigatorKey.currentState == null) {
      debugPrint('[SharingIntentService] wait for navigator...');
      const total = Duration(milliseconds: 3000);
      const step = Duration(milliseconds: 150);
      var waited = Duration.zero;
      void tryLater() async {
        await Future.delayed(step);
        waited += step;
        if (navigatorKey.currentState != null) {
          await push();
        } else if (waited < total) {
          tryLater();
        } else {
          debugPrint('[SharingIntentService] navigator still null after 3s');
        }
      }
      WidgetsBinding.instance.addPostFrameCallback((_) { tryLater(); });
      return;
    }

    await push();
  }
}