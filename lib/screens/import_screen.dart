import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:prophetie_app/services/sent_recordings_service.dart';

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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fehler: Keine ID zum Importieren übergeben.'),
        ),
      );
      setState(() {
        _isLoading = false;
      });
      return;
    }

    try {
      // Original in Firestore finden
      final snapshot = await FirebaseFirestore.instance
          .collectionGroup('gesendet')
          .where(FieldPath.documentId, isEqualTo: widget.id)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler: Original nicht gefunden.')),
        );
        setState(() => _isLoading = false);
        return;
      }

      final originalDoc = snapshot.docs.first;
      final originalData = originalDoc.data();
      final originalRef = originalDoc.reference;

      final audioUrl = originalData['recordingUrl'] as String?;
      if (audioUrl == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fehler: Audio-URL nicht gefunden.')),
        );
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

      // Den Sender über die Annahme informieren via Cloud Function
      final senderUid = originalRef.parent.parent?.id;
      if (senderUid != null) {
        await SentRecordingService.instance.markAsAccepted(
          senderUid,
          widget.id!,
        );
      } else {
        // Fallback oder Fehlerbehandlung, wenn senderUid nicht ermittelt werden kann
        print("Sender-UID konnte nicht ermittelt werden.");
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Import erfolgreich')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Import fehlgeschlagen: $e')));
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
