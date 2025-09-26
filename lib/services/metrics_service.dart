import 'package:cloud_firestore/cloud_firestore.dart';

/// Client-side metrics updates without Cloud Functions
class MetricsService {
  static Future<void> updateOnCreate({
    required String uid,
    required String type, // 'traum' | 'prophetie'
    List<String> labels = const [],
  }) async {
    final metricsRef = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('metrics')
        .doc('summary');

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(metricsRef);
      final now = DateTime.now();
      final yearStart = DateTime(now.year, 1, 1);

      Map<String, dynamic> data = {};
      if (!snap.exists) {
        data = {
          'totalTraeume': 0,
          'totalProphetien': 0,
          'ytdTraeume': 0,
          'ytdProphetien': 0,
          'streakDays': 0,
          'lastEntryDate': _dateKey(now),
          'labelsCount': <String, int>{},
          'dailyLast56': List.generate(56, (_) => 0),
          'dailyLast56Start': _dateKey(now.subtract(const Duration(days: 55))),
        };
        tx.set(metricsRef, data);
      } else {
        data = snap.data() as Map<String, dynamic>;
      }

      if (type == 'traum') {
        data['totalTraeume'] = (data['totalTraeume'] ?? 0) + 1;
        if (!now.isBefore(yearStart)) {
          data['ytdTraeume'] = (data['ytdTraeume'] ?? 0) + 1;
        }
      } else {
        data['totalProphetien'] = (data['totalProphetien'] ?? 0) + 1;
        if (!now.isBefore(yearStart)) {
          data['ytdProphetien'] = (data['ytdProphetien'] ?? 0) + 1;
        }
      }

      // Streak
      final lastDateStr = (data['lastEntryDate'] ?? _dateKey(now)) as String;
      final lastDate = DateTime.tryParse(lastDateStr) ?? now;
      final today = DateTime(now.year, now.month, now.day);
      final lastDay = DateTime(lastDate.year, lastDate.month, lastDate.day);
      final diff = today.difference(lastDay).inDays;
      if (diff == 1) {
        data['streakDays'] = (data['streakDays'] ?? 0) + 1;
      } else if (diff > 1) {
        data['streakDays'] = 1;
      }
      data['lastEntryDate'] = _dateKey(now);

      // Labels optional
      final Map<String, dynamic> labelMap = Map<String, dynamic>.from(
        data['labelsCount'] ?? <String, int>{},
      );
      for (final l in labels) {
        labelMap[l] = (labelMap[l] ?? 0) + 1;
      }
      data['labelsCount'] = labelMap;

      // Rolling 56-day window
      DateTime start = DateTime.tryParse(
            (data['dailyLast56Start'] ?? _dateKey(now.subtract(const Duration(days: 55)))) as String,
          ) ??
          now.subtract(const Duration(days: 55));
      List<dynamic> arr = List<dynamic>.from(
        data['dailyLast56'] ?? List.generate(56, (_) => 0),
      );
      while (today.isAfter(start.add(const Duration(days: 55)))) {
        arr = [...arr.skip(1), 0];
        start = start.add(const Duration(days: 1));
      }
      final idx = today.difference(start).inDays;
      if (idx >= 0 && idx < 56) {
        arr[idx] = (arr[idx] as int) + 1;
      }
      data['dailyLast56'] = arr;
      data['dailyLast56Start'] = _dateKey(start);

      tx.set(metricsRef, data, SetOptions(merge: true));
    });
  }

  static Future<void> rebuildFromExisting({required String uid}) async {
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();
    final jan1 = DateTime(now.year, 1, 1);
    DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

    int totalTraeume = 0;
    int totalProphetien = 0;
    int ytdTraeume = 0;
    int ytdProphetien = 0;
    final Map<String, int> labelsCount = {};
    final Set<DateTime> activeDays = {};

    Future<void> scan(String coll) async {
      Query query = fs
          .collection('users')
          .doc(uid)
          .collection(coll)
          .orderBy('timestamp');
      const pageSize = 500;
      DocumentSnapshot? last;
      while (true) {
        var q = query.limit(pageSize);
        if (last != null) q = q.startAfterDocument(last);
        final snap = await q.get();
        if (snap.docs.isEmpty) break;
        for (final doc in snap.docs) {
          final data = doc.data() as Map<String, dynamic>;
          final ts = data['timestamp'];
          if (ts is! Timestamp) continue;
          final dt = ts.toDate();
          activeDays.add(day(dt));
          final labels = (data['labels'] as List?) ?? const [];
          for (final l in labels) {
            if (l is String && l.isNotEmpty) {
              labelsCount[l] = (labelsCount[l] ?? 0) + 1;
            }
          }
          if (coll == 'traeume') {
            totalTraeume++;
            if (!dt.isBefore(jan1)) ytdTraeume++;
          } else {
            totalProphetien++;
            if (!dt.isBefore(jan1)) ytdProphetien++;
          }
        }
        last = snap.docs.last;
        if (snap.docs.length < pageSize) break;
      }
    }

    await scan('traeume');
    await scan('prophetien');

    // Streak
    int streak = 0;
    DateTime cur = day(now);
    while (activeDays.contains(cur)) {
      streak++;
      cur = cur.subtract(const Duration(days: 1));
    }

    // 56-day window
    final start = day(now.subtract(const Duration(days: 55)));
    final Map<DateTime, int> perDay = { for (int i = 0; i < 56; i++) day(start.add(Duration(days: i))): 0 };

    Future<void> fillDaily(String coll) async {
      final snap = await fs
          .collection('users')
          .doc(uid)
          .collection(coll)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .orderBy('timestamp')
          .get();
      for (final d in snap.docs) {
        final ts = (d.data() as Map<String, dynamic>)['timestamp'];
        if (ts is! Timestamp) continue;
        final dd = day(ts.toDate());
        perDay[dd] = (perDay[dd] ?? 0) + 1;
      }
    }

    await fillDaily('traeume');
    await fillDaily('prophetien');

    final dailyLast56 = List<int>.generate(56, (i) {
      final d = day(start.add(Duration(days: i)));
      return perDay[d] ?? 0;
    });

    await fs
        .collection('users')
        .doc(uid)
        .collection('metrics')
        .doc('summary')
        .set({
          'totalTraeume': totalTraeume,
          'totalProphetien': totalProphetien,
          'ytdTraeume': ytdTraeume,
          'ytdProphetien': ytdProphetien,
          'streakDays': streak,
          'lastEntryDate': now.toIso8601String(),
          'labelsCount': labelsCount,
          'dailyLast56': dailyLast56,
          'dailyLast56Start': start.toIso8601String(),
        }, SetOptions(merge: true));
  }

  static String _dateKey(DateTime d) =>
      DateTime(d.year, d.month, d.day).toIso8601String();
}
