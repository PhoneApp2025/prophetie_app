import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../services/sent_recording_deleter.dart';
import 'package:prophetie_app/main.dart';

class SendRecordingsScreen extends StatelessWidget {
  const SendRecordingsScreen({Key? key}) : super(key: key);

  void _deleteRecording(String docId, String? url, BuildContext context) {
    final deleter = SentRecordingDeleter();
    deleter.deleteRecording(docId, url).catchError((error) {
      if (context.mounted) {
        showFlushbar('Fehler beim Löschen der Aufnahme: $error');
      }
      print('Deletion failed: $error');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Gesendete Aufnahmen',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color:
                Theme.of(context).textTheme.titleLarge?.color ?? Colors.black,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(FirebaseAuth.instance.currentUser!.uid)
              .collection('gesendet')
              .orderBy('timestamp', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final docs = snapshot.data?.docs ?? [];
            if (docs.isEmpty) {
              return const Center(child: Text('Noch nichts gesendet.'));
            }

            return ListView.builder(
              itemCount: docs.length,
              itemBuilder: (context, index) {
                final data = docs[index].data() as Map<String, dynamic>;
                final label = data['label'] ?? 'Unbenannt';
                final status = data['status'] ?? 'unbekannt';
                final ts = (data['timestamp'] as Timestamp?)?.toDate();
                final formattedTime = ts != null
                    ? DateFormat('dd.MM.yyyy – HH:mm').format(ts)
                    : '';
                final docId = snapshot.data!.docs[index].id;
                final url = data['audioUrl'];

                return Slidable(
                  key: ValueKey(docId),
                  endActionPane: ActionPane(
                    motion: const DrawerMotion(),
                    dismissible: DismissiblePane(
                      onDismissed: () => _deleteRecording(docId, url, context),
                    ),
                    children: [
                      SlidableAction(
                        onPressed: (_) => _deleteRecording(docId, url, context),
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        icon: Icons.delete,
                        label: 'Löschen',
                      ),
                    ],
                  ),
                  child: ListTile(
                    leading: Icon(
                      status == 'angenommen'
                          ? Icons.check_circle
                          : Icons.hourglass_top,
                      color: status == 'angenommen'
                          ? Colors.green
                          : Colors.grey,
                    ),
                    title: Text(label),
                    subtitle: Text('Status: $status\n$formattedTime'),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
