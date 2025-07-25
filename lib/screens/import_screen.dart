import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:prophetie_app/main.dart';
import 'package:provider/provider.dart';
import '../providers/prophetie_provider.dart';
import '../providers/traum_provider.dart';
import 'package:uuid/uuid.dart';

class ImportScreen extends StatefulWidget {
  final String? type; // Internes Sharing (Prophetie/Traum)
  final String? id;
  final String? creator;
  final String? audioFilePath; // Externes Sharing (Dateipfad)

  const ImportScreen({
    super.key,
    this.type,
    this.id,
    this.creator,
    this.audioFilePath,
  });

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
    // === EXTERNER WORKFLOW: Audio-Datei von außerhalb importieren ===
    if (widget.audioFilePath != null && _importType != null) {
      setState(() {
        _isLoading = true;
      });
      try {
        final id = const Uuid().v4();
        if (_importType == 'prophetie') {
          await Provider.of<ProphetieProvider>(
            context,
            listen: false,
          ).handleNewProphetie(
            id: id,
            localFilePath: widget.audioFilePath!,
            transcriptText: null,
            labels: [],
          );
          Navigator.of(context).pop();
          showFlushbar('Prophetie importiert!');
        } else if (_importType == 'traum') {
          await Provider.of<TraumProvider>(
            context,
            listen: false,
          ).handleNewTraum(
            id: id,
            localFilePath: widget.audioFilePath!,
            transcriptText: null,
            labels: [],
          );
          Navigator.of(context).pop();
          showFlushbar('Traum importiert!');
        }
      } catch (e) {
        showFlushbar('Fehler beim Import: $e');
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    // === ALTER WORKFLOW: Interner Import via ID & Typ ===
    if (_importType == null || widget.id == null) return;

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
      print('Importing document with ID: ${widget.id}');
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

      final targetCollection = _importType == 'traum'
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

      final senderUid = originalRef.parent.parent?.id;
      if (senderUid != null) {
        final functions = FirebaseFunctions.instance;
        await functions.httpsCallable('markSentRecordingAccepted').call({
          'senderUid': senderUid,
          'docId': widget.id!,
        });
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
    // === EXTERNER AUDIO-IMPORT: Typ-Auswahl + Datei-Info ===
    if (widget.audioFilePath != null && _importType == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio importieren')),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.audiotrack, size: 60, color: Colors.deepPurple),
              const SizedBox(height: 20),
              Text('Dateipfad:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                widget.audioFilePath!,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 40),
              Text(
                'Was möchtest du importieren?',
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton.icon(
                    icon: Icon(Icons.flash_on_outlined),
                    label: Text('Prophetie'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                    ),
                    onPressed: () => setState(() => _importType = 'prophetie'),
                  ),
                  const SizedBox(width: 20),
                  ElevatedButton.icon(
                    icon: Icon(Icons.nightlight_outlined),
                    label: Text('Traum'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                    ),
                    onPressed: () => setState(() => _importType = 'traum'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    // === EXTERNER AUDIO-IMPORT: Import-Button anzeigen, wenn Typ gewählt ===
    if (widget.audioFilePath != null && _importType != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Audio importieren')),
        body: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.audiotrack, size: 60, color: Colors.deepPurple),
              const SizedBox(height: 20),
              Text(
                'Importiere als ${_importType == 'prophetie' ? 'Prophetie' : 'Traum'}',
              ),
              const SizedBox(height: 20),
              Text(
                widget.audioFilePath!,
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 40),
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
      );
    }

    // === ALTER WORKFLOW: Internes Sharing ===
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
                Text('Importiere: ${_importType ?? ''}'),
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
