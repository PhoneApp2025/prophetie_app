import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:prophetie_app/main.dart';

class ImportScreen extends StatefulWidget {
  final String? type;
  final String? id;
  final String? creator;

  const ImportScreen({super.key, this.type, this.id, this.creator});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _isLoading = false;

  Future<void> _import(BuildContext context) async {
    if (widget.type == null || widget.id == null) return;

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    setState(() {
      _isLoading = true;
    });

    if (widget.id == null || widget.id!.isEmpty) {
      showFlushbar('Fehler: Keine ID zum Importieren übergeben.');
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Original in Firestore finden
      print('Importing document with ID: ${widget.id}');
      if (widget.id == null) {
        showFlushbar('Fehler: Dokumenten-ID ist null.');
        setState(() => _isLoading = false);
        return;
      }
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('gesendet')
          .where(FieldPath.documentId, isEqualTo: widget.id)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        showFlushbar('Fehler: Original nicht gefunden.');
        setState(() => _isLoading = false);
        return;
      }

      final originalDoc = snapshot.docs.first;
      final originalData = originalDoc.data();
      final originalRef = originalDoc.reference;

      final audioUrl = originalData['audioUrl'] as String?;
      if (audioUrl == null) {
        showFlushbar('Fehler: Audio-URL nicht gefunden.');
        setState(() => _isLoading = false);
        return;
      }

      // Beim aktuellen User speichern
      final targetCollection = widget.type == 'traum'
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
          });

      // Informiere den Sender über die Annahme via Cloud Functions
      final senderUid = originalRef.parent.parent?.id;
      if (senderUid != null) {
        // Informiere den Sender über die Annahme via Cloud Functions
        final functions = FirebaseFunctions.instance;
        await functions.httpsCallable('markSentRecordingAccepted').call({
          'senderUid': senderUid,
          'docId': widget.id!,
        });
      } else {
        print("Sender-UID konnte nicht ermittelt werden.");
      }

      showFlushbar('Import erfolgreich');
    } catch (e) {
      showFlushbar('Import fehlgeschlagen: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
      Navigator.of(context).pop();
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
        onTap: () {
          FocusScope.of(context).unfocus();
        },
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
                Text('Importiere: ${widget.type ?? ''}'),
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
