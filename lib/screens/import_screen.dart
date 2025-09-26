import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:prophetie_app/main.dart';

class ImportScreen extends StatefulWidget {
  final String? type; // Internes Sharing (Prophetie/Traum)
  final String? id;
  final String? creator;

  const ImportScreen({super.key, this.type, this.id, this.creator});

  factory ImportScreen.fromSharedId({
    required String type, // 'prophetie' | 'traum'
    required String id,
    String? creator,
  }) {
    return ImportScreen(type: type, id: id, creator: creator);
  }

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _isLoading = false;
  String? _importType; // 'prophetie' oder 'traum' bei externem Import

  @override
  void initState() {
    super.initState();
    // Bei internem Sharing direkt Typ übernehmen
    if (widget.type != null) {
      _importType = widget.type;
    }
  }

  Future<void> _import(BuildContext context) async {
    // === INTERNER WORKFLOW: Import via ID & Typ aus der Deeplink-URL ===
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      showFlushbar('Fehler: Nicht eingeloggt.');
      return;
    }
    if ((widget.id == null || widget.id!.isEmpty)) {
      showFlushbar('Fehler: Keine ID zum Importieren übergeben.');
      return;
    }
    if ((widget.type == null || widget.type!.isEmpty)) {
      showFlushbar('Fehler: Kein Typ (Prophetie/Traum) übergeben.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      QuerySnapshot<Map<String, dynamic>> snapshot;
      // 1) Prefer a normal field equality (more portable across SDKs)
      snapshot = await FirebaseFirestore.instance
          .collectionGroup('gesendet')
          .where('id', isEqualTo: widget.id)
          .limit(1)
          .get();

      // 2) Fallback: try by documentId if 'id' field does not exist in docs
      if (snapshot.docs.isEmpty) {
        snapshot = await FirebaseFirestore.instance
            .collectionGroup('gesendet')
            .where(FieldPath.documentId, isEqualTo: widget.id)
            .limit(1)
            .get();
      }

      if (snapshot.docs.isEmpty) {
        showFlushbar('Fehler: Originalaufnahme nicht gefunden.');
        setState(() => _isLoading = false);
        return;
      }

      final originalDoc = snapshot.docs.first;
      final originalData = originalDoc.data();
      final originalRef = originalDoc.reference;

      final importTypeFromDoc = originalData['category'] as String?;
      final resolvedType = widget.type ?? importTypeFromDoc;
      if (resolvedType == null) {
        showFlushbar('Fehler: Aufnahmetyp (Prophetie/Traum) nicht gefunden.');
        setState(() => _isLoading = false);
        return;
      }

      final audioUrl = originalData['audioUrl'] as String?;
      if (audioUrl == null) {
        showFlushbar('Fehler: Audio-URL nicht gefunden.');
        setState(() => _isLoading = false);
        return;
      }

      final targetCollection = resolvedType == 'traum'
          ? 'traeume'
          : 'prophetien';

      await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .collection(targetCollection)
          .doc(widget.id)
          .set({
            ...originalData,
            'audioUrl': audioUrl,
            'label': 'Empfangen',
            'timestamp': FieldValue.serverTimestamp(),
            'status': 'empfangen',
            'id': widget.id,
            'category': resolvedType,
          });

      final senderUid = originalRef.parent.parent?.id;
      if (senderUid != null) {
        final functions = FirebaseFunctions.instance;
        await functions.httpsCallable('markSentRecordingAccepted').call({
          'senderUid': senderUid,
          'docId': widget.id!,
        });
      }

      showFlushbar('Import erfolgreich!');
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      showFlushbar('Import fehlgeschlagen: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _onWillPop(BuildContext context) async {
    final reallyClose = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Import abbrechen?"),
        content: const Text("Möchtest du wirklich nicht importieren?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Nein"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Ja"),
          ),
        ],
      ),
    );
    return reallyClose == true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () => _onWillPop(context),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: Center(
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_download, size: 48),
                const SizedBox(height: 16),
                Text('Importiere: ${_importType ?? (widget.type ?? '')}'),
                const SizedBox(height: 4),
                Text('ID: ${widget.id ?? ''}'),
                const SizedBox(height: 4),
                Text('Von: ${widget.creator ?? ''}'),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _isLoading ? null : () => _import(context),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Importieren'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
