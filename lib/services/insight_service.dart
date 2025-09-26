import 'package:cloud_firestore/cloud_firestore.dart';

class InsightsService {
  /// Notes on retention:
  /// - We set `expiresAt` on every insight. If you enable Firestore TTL
  ///   (Time-to-Live) on `users/{uid}/insights` using the `expiresAt` field,
  ///   the backend will auto-delete expired documents.
  /// - `cleanupOldInsights` is a client-side safety net.
  /// Erzeugt max. 3 Insights pro Tag, rein clientseitig
  static Future<void> ensureDailyInsights({required String uid}) async {
    final fs = FirebaseFirestore.instance;
    final today = DateTime.now();
    final dayStart = DateTime(today.year, today.month, today.day);
    final dayKey = DateTime(today.year, today.month, today.day).toIso8601String();

    // housekeeping: remove old insights beyond retention window
    await cleanupOldInsights(uid: uid);

    final existing = await fs
        .collection('users')
        .doc(uid)
        .collection('insights')
        .where('createdAt', isGreaterThanOrEqualTo: dayStart)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return; // bereits erzeugt

    final List<Map<String, dynamic>> out = [];

    // 1) Stille-Phase: zur Reflexion einladen (kein Aufnahme-Druck)
    final threeDaysAgo = dayStart.subtract(const Duration(days: 3));
    final lastTraeum = await fs
        .collection('users').doc(uid).collection('traeume')
        .where('timestamp', isGreaterThan: Timestamp.fromDate(threeDaysAgo))
        .limit(1)
        .get();
    final lastProphet = await fs
        .collection('users').doc(uid).collection('prophetien')
        .where('timestamp', isGreaterThan: Timestamp.fromDate(threeDaysAgo))
        .limit(1)
        .get();
    if (lastTraeum.docs.isEmpty && lastProphet.docs.isEmpty) {
      out.add({
        'type': 'inactivity_reflect',
        'title': 'Stille Tage – prüfe und erinnere',
        'body': 'Nimm dir kurz Zeit und lies die letzten Einträge. Gibt es Zusagen, Eindrücke oder offene Punkte, die du markieren kannst?',
        'cta': 'Reflexion öffnen',
        'createdAt': dayStart,
        'expiresAt': dayStart.add(const Duration(days: 3)),
        'seen': false,
      });
    }

    // 2) Unbewertete/ohne Labels
    final unlabeledCount = await _countUnlabeledLast30(uid);
    if (unlabeledCount > 0) {
      out.add({
        'type': 'label_missing',
        'title': 'Einträge ohne Labels',
        'body': unlabeledCount == 1
            ? 'Du hast 1 Eintrag ohne Label. Markiere Themen für bessere Übereinstimmungen.'
            : 'Du hast $unlabeledCount Einträge ohne Labels. Markiere Themen für bessere Übereinstimmungen.',
        'cta': 'Jetzt labeln',
        'createdAt': dayStart,
        'expiresAt': dayStart.add(const Duration(days: 3)),
        'seen': false,
      });
    }

    // Idempotent pro Tag und Typ: deterministische Doc-IDs + Transaction
    for (final m in out.take(3)) {
      final type = (m['type'] as String?) ?? 'generic';
      final ref = fs
          .collection('users')
          .doc(uid)
          .collection('insights')
          .doc('${type}_$dayKey');

      await fs.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          tx.set(ref, m);
        }
      });
    }
  }

  static Future<void> cleanupOldInsights({required String uid, int retentionDays = 3}) async {
    // Optional safety net in addition to Firestore TTL on `expiresAt`
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: retentionDays));
    try {
      // A) anything older than retention window
      final old = await fs
          .collection('users')
          .doc(uid)
          .collection('insights')
          .where('createdAt', isLessThan: cutoff)
          .limit(500)
          .get();

      // B) seen insights older than 36h, even if within retention window
      // Avoid composite index by splitting: fetch seen==true and filter client-side by createdAt
      final seenCutoff = now.subtract(const Duration(hours: 36));
      List<QueryDocumentSnapshot<Map<String, dynamic>>> oldSeenDocs = [];
      try {
        final oldSeen = await fs
            .collection('users')
            .doc(uid)
            .collection('insights')
            .where('seen', isEqualTo: true)
            .limit(500)
            .get();

        // Client-side filter by createdAt < seenCutoff
        oldSeenDocs = oldSeen.docs.where((d) {
          final data = d.data();
          final createdAt = data['createdAt'];
          final dt = createdAt is Timestamp ? createdAt.toDate() : (createdAt is DateTime ? createdAt : null);
          return dt != null && dt.isBefore(seenCutoff);
        }).toList();
      } catch (_) {
        oldSeenDocs = [];
      }

      if (old.docs.isEmpty && oldSeenDocs.isEmpty) return;

      final batch = fs.batch();
      for (final d in old.docs) {
        batch.delete(d.reference);
      }
      for (final d in oldSeenDocs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      // ignore cleanup errors to keep app flow smooth
    }
  }

  static Future<int> _countUnlabeledLast30(String uid) async {
    final fs = FirebaseFirestore.instance;
    final since = DateTime.now().subtract(const Duration(days: 30));
    int total = 0;
    for (final coll in ['traeume', 'prophetien']) {
      final snap = await fs
          .collection('users').doc(uid).collection(coll)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(since))
          .limit(500)
          .get();
      for (final d in snap.docs) {
        final labels = (d.data()['labels'] as List?) ?? const [];
        if (labels.isEmpty) total++;
      }
    }
    return total;
  }
}