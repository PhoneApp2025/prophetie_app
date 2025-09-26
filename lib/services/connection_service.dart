import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:prophetie_app/services/connection_utils.dart';
import '../models/connection_item.dart';
import '../models/connection_pair.dart';

class ConnectionService {
  // map legacy collection/type strings to canonical values
  static String _normalizeType(String? t) {
    final v = (t ?? '').toLowerCase().trim();
    switch (v) {
      case 'traeume':
      case 'traum':
      case 'dream':
      case 'dreams':
        return 'dream';
      case 'prophetien':
      case 'prophetie':
      case 'prophecy':
      case 'prophecies':
        return 'prophecy';
      default:
        return v.isEmpty ? 'dream' : v;
    }
  }

  // sehr kurze / inhaltsarme Texte rausfiltern
  static bool _isLowInfoText(String s) {
    final cleaned = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (cleaned.length < 40) return true;
    final words = cleaned
        .toLowerCase()
        .split(RegExp(r'[^a-zA-ZäöüÄÖÜß]+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return words.toSet().length < 6;
  }

  // Rückwärtskompatibler Wrapper
  static String _pairId(ConnectionItem a, ConnectionItem b) => getPairKey(a, b);

  static Map<String, dynamic> _pairDoc(
    ConnectionItem a,
    ConnectionItem b,
    double similarityRaw, // 0..1
  ) {
    final pct = ((similarityRaw * 100).clamp(0, 100)).round();
    return {
      'firstId': a.id,
      'secondId': b.id,
      'firstType': describeEnum(a.type), // 'dream' | 'prophecy'
      'secondType': describeEnum(b.type),
      'firstTitle': a.title,
      'secondTitle': b.title,
      'firstTimestamp': a.timestamp,
      'secondTimestamp': b.timestamp,
      'similarity': similarityRaw,      // 0..1
      'similarityPct': pct,             // 0..100 (int)
      'similarityText': 'Semantische Ähnlichkeit ${pct}%',
      'pinned': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static Future<void> _persistPairs(
    String uid,
    List<ConnectionPair> pairs,
  ) async {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('connections');

    const chunkSize = 450;
    for (var i = 0; i < pairs.length; i += chunkSize) {
      final slice = pairs.sublist(
        i,
        i + chunkSize > pairs.length ? pairs.length : i + chunkSize,
      );
      final batch = FirebaseFirestore.instance.batch();
      for (final p in slice) {
        final id = getPairKey(p.first, p.second);
        final docRef = col.doc(id);
        final sim = (p.similarity ?? 0).clamp(0.0, 1.0);
        batch.set(docRef, {
          ..._pairDoc(p.first, p.second, sim),
          'updatedAt': FieldValue.serverTimestamp(),
          'similarity': sim, // 0..1 speichern
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }
  }

  static Future<void> _deleteConnectionsNotIn(
    String uid,
    Set<String> keepIds,
  ) async {
    final col = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('connections');

    final snap = await col.get();
    final toDelete = snap.docs.where((d) => !keepIds.contains(d.id)).toList();
    if (toDelete.isEmpty) return;

    const chunkSize = 450;
    for (var i = 0; i < toDelete.length; i += chunkSize) {
      final slice = toDelete.sublist(
        i,
        i + chunkSize > toDelete.length ? toDelete.length : i + chunkSize,
      );
      final batch = FirebaseFirestore.instance.batch();
      for (final d in slice) {
        batch.delete(col.doc(d.id));
      }
      await batch.commit();
    }
  }

  static List<ConnectionPair> _computePairsFromEmbeddings(
    List<ConnectionItem> all,
    Map<String, List<double>> embeddings, {
    double threshold = 0.68,
  }) {
    final byKey = {for (final it in all) getItemKey(it): it};
    final results = <MapEntry<ConnectionPair, double>>[];

    for (var i = 0; i < all.length; i++) {
      final a = all[i];
      final ea = embeddings[getItemKey(a)];
      if (ea == null) continue;
      for (var j = i + 1; j < all.length; j++) {
        final b = all[j];
        final eb = embeddings[getItemKey(b)];
        if (eb == null) continue;

        if (getItemKey(a) == getItemKey(b)) continue; // defensive

        final raw = cosineSimilarity(ea, eb);
        final sim = raw.clamp(-1.0, 1.0);
        if (sim > threshold) {
          final pct = ((sim * 100).clamp(0, 100)).round().toString();
          results.add(
            MapEntry(
              ConnectionPair(
                first: byKey[getItemKey(b)]!,
                second: byKey[getItemKey(a)]!,
                relationSummary: 'Semantische Ähnlichkeit ${pct}%',
                similarity: sim, // 0..1
              ),
              sim,
            ),
          );
        }
      }
    }
    results.sort((a, b) => b.value.compareTo(a.value));
    final pairs = results.map((e) => e.key).toList()
      ..sort((a, b) => b.second.timestamp.compareTo(a.second.timestamp));
    return pairs;
  }

  static Future<int> rebuildAllConnections({double threshold = 0.7}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final dreams = await loadConnectionItems('traeume', ItemType.dream, uid);
    final props = await loadConnectionItems('prophetien', ItemType.prophecy, uid);
    final all = [
      ...dreams,
      ...props,
    ]
        .where((i) => i.text.trim() != 'Wird analysiert...')
        .where((i) => !_isLowInfoText(i.text))
        .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    if (all.length < 2) {
      await _deleteConnectionsNotIn(uid, <String>{});
      return 0;
    }

    // Vollständiger Rebuild: erzeugt absichtlich alle Embeddings neu (kann Rate Limits triggern)
    final embeddings = await ensureEmbeddings(uid, all, force: true);
    final pairs = _computePairsFromEmbeddings(
      all,
      embeddings,
      threshold: threshold,
    );

    await _persistPairs(uid, pairs);
    final keepIds = pairs.map((p) => getPairKey(p.first, p.second)).toSet();
    await _deleteConnectionsNotIn(uid, keepIds);
    return pairs.length;
  }

  static Future<List<ConnectionPair>> _loadSavedPairs(
    String uid,
    List<ConnectionItem> all, {
    int? limit,
  }) async {
    final index = {for (final it in all) getItemKey(it): it};
    var query = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('connections')
        .orderBy('updatedAt', descending: true);
    if (limit != null) {
      query = query.limit(limit);
    }
    final snap = await query.get();

    final out = <ConnectionPair>[];
    final seen = <String>{};

    for (final d in snap.docs) {
      final data = d.data();
      final aId = data['firstId'] as String?;
      final bId = data['secondId'] as String?;
      final aType = data['firstType'] as String?;
      final bType = data['secondType'] as String?;
      if (aId == null || bId == null || aType == null || bType == null) {
        continue;
      }

      final aTypeNorm = _normalizeType(aType);
      final bTypeNorm = _normalizeType(bType);

      final a = index['$aTypeNorm:$aId'] ?? index['$aType:$aId'];
      final b = index['$bTypeNorm:$bId'] ?? index['$bType:$bId'];
      if (a == null || b == null) continue;

      final key = getPairKey(a, b);
      if (seen.contains(key)) continue;
      seen.add(key);

      var simRaw = data['similarity'];
      double sim;
      if (simRaw is num) {
        sim = simRaw.toDouble();
      } else if (simRaw is String) {
        sim = double.tryParse(simRaw.replaceAll(',', '.')) ?? 0.0;
      } else {
        sim = 0.0;
      }
      if (sim > 1.0) sim = sim / 100.0; // Migration 0..100 → 0..1

      final pct = ((sim * 100).clamp(0, 100)).round();

      out.add(
        ConnectionPair(
          first: a,
          second: b,
          relationSummary: 'Semantische Ähnlichkeit ${pct}%',
          similarity: sim,
        ),
      );
    }
    out.sort((x, y) => y.second.timestamp.compareTo(x.second.timestamp));
    return out;
  }

  @Deprecated(
    'Nutze fetchConnectionsAll() – diese Methode existiert nur noch als Wrapper für die Home-Ansicht.',
  )
  static Future<List<ConnectionPair>> fetchConnections() async {
    final all = await fetchConnectionsAll();
    return all.take(4).toList();
  }

  /// Holt ALLE Matches ohne Limit
  static Future<List<ConnectionPair>> fetchConnectionsAll() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final dreams = await loadConnectionItems('traeume', ItemType.dream, uid);
    final props = await loadConnectionItems('prophetien', ItemType.prophecy, uid);
    final all = [
      ...dreams,
      ...props,
    ]
        .where((i) => i.text.trim() != 'Wird analysiert...')
        .where((i) => !_isLowInfoText(i.text))
        .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (all.length < 2) return [];

    final saved = await _loadSavedPairs(uid, all);

    final connectedKeys = <String>{};
    for (final p in saved) {
      connectedKeys.add(getItemKey(p.first));
      connectedKeys.add(getItemKey(p.second));
    }
    final newItems =
        all.where((it) => !connectedKeys.contains(getItemKey(it))).toList();

    final embeddings = await ensureEmbeddings(uid, all, force: false);

    final byKey = {for (final it in all) getItemKey(it): it};
    final scored = <MapEntry<ConnectionPair, double>>[];

    for (var i = 0; i < all.length; i++) {
      final a = all[i];
      final ea = embeddings[getItemKey(a)];
      if (ea == null) continue;
      for (var j = i + 1; j < all.length; j++) {
        final b = all[j];
        final eb = embeddings[getItemKey(b)];
        if (eb == null) continue;

        final sim = cosineSimilarity(ea, eb).clamp(-1.0, 1.0);
        if (sim > 0.68) {
          final pct = ((sim * 100).clamp(0, 100)).round().toString();
          scored.add(
            MapEntry(
              ConnectionPair(
                first: byKey[getItemKey(b)]!,
                second: byKey[getItemKey(a)]!,
                relationSummary: 'Semantische Ähnlichkeit ${pct}%',
                similarity: sim,
              ),
              sim,
            ),
          );
        }
      }
    }

    if (scored.isNotEmpty) {
      scored.sort((a, b) => b.value.compareTo(a.value));
      final pairs = scored.map((e) => e.key).toList()
        ..sort((a, b) => b.second.timestamp.compareTo(a.second.timestamp));

      await _persistPairs(uid, pairs);
      final savedAll = await _loadSavedPairs(uid, all);
      return savedAll;
    }

    return saved;
  }
}