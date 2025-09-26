import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/connection_item.dart';
import '../models/connection_pair.dart';

class UebereinstimmungenScreen extends StatefulWidget {
  const UebereinstimmungenScreen({super.key});

  @override
  State<UebereinstimmungenScreen> createState() =>
      _UebereinstimmungenScreenState();
}

class _UebereinstimmungenScreenState extends State<UebereinstimmungenScreen> {
  List<ConnectionPair>? _pairs;
  bool _isLoading = true;
  String? _error;
  final Set<String> _processingPairs = {};

  @override
  void initState() {
    super.initState();
    _loadConnections();
  }

  Future<void> _loadConnections({bool force = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = force
          ? (await ConnectionService.rebuildAllConnections(),
            await ConnectionService.fetchConnectionsAll())
          : await ConnectionService.fetchConnectionsAll();
      if (!mounted) return;
      setState(() {
        _pairs = result is List<ConnectionPair> ? result : result.$2;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Fehler beim Laden: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _handleAccept(ConnectionPair pair) async {
    final pairKey = ConnectionService._pairKey(pair.first, pair.second);
    setState(() => _processingPairs.add(pairKey));
    try {
      await ConnectionService.acceptConnection(pair);
      setState(() => _pairs!.removeWhere((p) =>
          ConnectionService._pairKey(p.first, p.second) == pairKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Übereinstimmung akzeptiert.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Akzeptieren: $e')),
      );
    } finally {
      setState(() => _processingPairs.remove(pairKey));
    }
  }

  Future<void> _handleReject(ConnectionPair pair) async {
    final pairKey = ConnectionService._pairKey(pair.first, pair.second);
    setState(() => _processingPairs.add(pairKey));
    try {
      await ConnectionService.rejectConnection(pair);
      setState(() => _pairs!.removeWhere((p) =>
          ConnectionService._pairKey(p.first, p.second) == pairKey));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Übereinstimmung abgelehnt.')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Fehler beim Ablehnen: $e')),
      );
    } finally {
      setState(() => _processingPairs.remove(pairKey));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Übereinstimmungen'),
        actions: [
          IconButton(
            tooltip: 'Neu berechnen',
            icon: const Icon(Icons.autorenew_rounded),
            onPressed: () async {
              if (!mounted) return;
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Alle Übereinstimmungen neu berechnen?'),
                  content: const Text(
                    'Alte, nicht mehr passende Verbindungen werden gelöscht.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Abbrechen'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Starten'),
                    ),
                  ],
                ),
              );
              if (ok != true) return;

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Berechnung gestartet…')),
              );
              await _loadConnections(force: true);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Fertig.')),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }
    if (_pairs == null || _pairs!.isEmpty) {
      return const Center(
        child: Text('Keine Übereinstimmungen gefunden.'),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8.0),
      itemCount: _pairs!.length,
      itemBuilder: (context, index) {
        final pair = _pairs![index];
        final pairKey = ConnectionService._pairKey(pair.first, pair.second);
        final isProcessing = _processingPairs.contains(pairKey);

        return Card(
          elevation: 2.0,
          margin: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 4.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12.0),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${pair.first.title} ↔ ${pair.second.title}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16.0,
                  ),
                ),
                const SizedBox(height: 8.0),
                Text(
                  pair.relationSummary ?? '',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 12.0),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (isProcessing)
                      const CircularProgressIndicator()
                    else ...[
                      TextButton(
                        onPressed: () => _handleReject(pair),
                        child: const Text('Ablehnen'),
                      ),
                      const SizedBox(width: 8.0),
                      ElevatedButton(
                        onPressed: () => _handleAccept(pair),
                        child: const Text('Akzeptieren'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Holt Embeddings per Qwen AI (robust mit Retry & Timeout)
Future<List<List<double>>?> fetchQwenEmbeddings(List<String> texts) async {
  final apiKey = dotenv.env['QWEN_API_KEY'];
  if (apiKey == null || apiKey.trim().isEmpty) {
    // ignore: avoid_print
    print('Qwen Embeddings Error: QWEN_API_KEY fehlt.');
    return null;
  }

  // defensiv: Texte normalisieren & kürzen (API kann bei sehr langen Inputs 5xx/400 werfen)
  List<String> _prepare(List<String> xs) => xs
      .map((s) => s.replaceAll(RegExp(r'\s+'), ' ').trim())
      .map((s) => s.length > 4000 ? s.substring(0, 4000) : s)
      .toList();

  final payload = {
    'model': 'text-embedding-v3',
    'input': _prepare(texts),
  };

  const maxAttempts = 4;
  Duration backoff(int attempt) => Duration(milliseconds: 300 * (1 << attempt));

  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      final response = await http
          .post(
            Uri.parse(
              'https://dashscope-intl.aliyuncs.com/compatible-mode/v1/embeddings',
            ),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final list = data['data'];
        if (list is List) {
          try {
            return list.map<List<double>>((e) {
              final emb = e['embedding'] as List;
              return emb.map((v) => (v as num).toDouble()).toList();
            }).toList();
          } catch (e) {
            // ignore: avoid_print
            print('Qwen Embeddings Parse Error: $e');
            return null;
          }
        } else {
          // ignore: avoid_print
          print('Qwen Embeddings Error: Unerwartete Antwortstruktur.');
          return null;
        }
      }

      // 429/5xx sowie Qwen "InternalError" (kommt fieserweise oft als 400) -> Retry mit Backoff
      final body = response.body;
      final retryable = response.statusCode == 429 ||
          response.statusCode >= 500 ||
          (response.statusCode == 400 && body.contains('Internal server error'));

      // ignore: avoid_print
      print(
          'Qwen Embeddings Error (status ${response.statusCode}): ${response.body} | attempt=${attempt + 1}/$maxAttempts');

      if (!retryable || attempt == maxAttempts - 1) {
        return null;
      }

      await Future.delayed(backoff(attempt));
    } catch (e) {
      // Netzwerk/Timeout -> retry bis maxAttempts
      // ignore: avoid_print
      print('Qwen Embeddings Transport Error: $e | attempt=${attempt + 1}/$maxAttempts');
      if (attempt == maxAttempts - 1) return null;
      await Future.delayed(backoff(attempt));
    }
  }

  return null;
}
// Kürzt und säubert Texte für Embeddings, um API-Fehler durch Überlänge/Noise zu vermeiden
String _cleanForEmbedding(String s) {
  final trimmed = s.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Qwen kommt mit sehr langen Strings teils ins Straucheln; hart auf ~4000 Zeichen begrenzen
  return trimmed.length > 4000 ? trimmed.substring(0, 4000) : trimmed;
}

/// Kosinus-Ähnlichkeit
double _cosineSimilarity(List<double> a, List<double> b) {
  double dot = 0, normA = 0, normB = 0;
  final len = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  return dot / (sqrt(normA) * sqrt(normB) + 1e-8);
}

class ConnectionService {
  // Namespaced Keys
  static String _keyOf(ConnectionItem it) => '${describeEnum(it.type)}:${it.id}';

  static String _pairKey(ConnectionItem a, ConnectionItem b) {
    final ka = _keyOf(a);
    final kb = _keyOf(b);
    return ka.compareTo(kb) <= 0 ? '${ka}__${kb}' : '${kb}__${ka}';
  }

  // robust timestamp parser for legacy data
  static DateTime _parseTimestamp(dynamic raw) {
    if (raw is Timestamp) return raw.toDate();
    if (raw is DateTime) return raw;
    if (raw is int) {
      if (raw > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(raw);
      return DateTime.fromMillisecondsSinceEpoch(raw * 1000);
    }
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return DateTime.fromMillisecondsSinceEpoch(0);
      try {
        return DateTime.parse(s);
      } catch (_) {
        final ms = int.tryParse(s);
        if (ms != null) {
          if (ms > 1000000000000) return DateTime.fromMillisecondsSinceEpoch(ms);
          return DateTime.fromMillisecondsSinceEpoch(ms * 1000);
        }
      }
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

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

  // sanity check for legacy embeddings
  static bool _isSaneEmbedding(List<double> v) {
    if (v.isEmpty) return false;
    if (v.length < 64) return false;
    double norm = 0;
    for (final x in v) {
      if (x.isNaN || x.isInfinite) return false;
      norm += x * x;
    }
    norm = sqrt(norm);
    return norm > 0.1 && norm < 1000;
  }

  static Future<List<ConnectionItem>> _loadItems(
    String collection,
    ItemType type,
    String uid,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection(collection)
        .orderBy('timestamp', descending: true)
        .get();
    return snap.docs.map((d) {
      final data = d.data();
      final ts = _parseTimestamp(data['timestamp']);

      // prefer rich text fields, then title fallback
      final textValue = (
            data['text'] as String? ??
            data['transcript'] as String? ??
            data['summary'] as String? ??
            data['content'] as String? ??
            data['description'] as String? ??
            data['body'] as String? ??
            ''
          ).trim();
      final titleValue = (data['title'] as String?)?.trim().isNotEmpty == true
          ? (data['title'] as String).trim()
          : (textValue.split('\n').firstWhere(
                (e) => e.trim().isNotEmpty,
                orElse: () => '',
              ).trim());

      return ConnectionItem(
        id: d.id,
        title: titleValue.isNotEmpty ? titleValue : '[ohne Titel]',
        text: textValue,
        type: type,
        timestamp: ts,
        filePath: data['audioUrl'] as String?,
      );
    }).toList();
  }

  // Rückwärtskompatibler Wrapper
  static String _pairId(ConnectionItem a, ConnectionItem b) => _pairKey(a, b);

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
        final id = _pairKey(p.first, p.second);
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
    Set<String> rejectedKeys = const {},
  }) {
    final byKey = {for (final it in all) _keyOf(it): it};
    final results = <MapEntry<ConnectionPair, double>>[];

    for (var i = 0; i < all.length; i++) {
      final a = all[i];
      final ea = embeddings[_keyOf(a)];
      if (ea == null) continue;
      for (var j = i + 1; j < all.length; j++) {
        final b = all[j];
        final eb = embeddings[_keyOf(b)];
        if (eb == null) continue;

        if (_keyOf(a) == _keyOf(b)) continue; // defensive

        final pairKey = _pairKey(a, b);
        if (rejectedKeys.contains(pairKey)) continue;

        final raw = _cosineSimilarity(ea, eb);
        final sim = raw.clamp(-1.0, 1.0);
        if (sim > threshold) {
          final pct = ((sim * 100).clamp(0, 100)).round().toString();
          results.add(
            MapEntry(
              ConnectionPair(
                first: byKey[_keyOf(b)]!,
                second: byKey[_keyOf(a)]!,
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

  static Future<Map<String, List<double>>> _ensureEmbeddings(
    String uid,
    List<ConnectionItem> items, {
    bool force = false,
  }) async {
    final existing = <String, List<double>>{};

    String _typeKeyForCollection(String c) {
      final v = c.toLowerCase();
      if (v.contains('traeum')) return 'dream';
      if (v.contains('prophet')) return 'prophecy';
      return _normalizeType(v);
    }

    Future<void> loadEmbeddings(String collection) async {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection(collection)
          .get();
      for (final d in snap.docs) {
        final data = d.data();
        final emb = data['embedding'];
        if (emb is List) {
          final vec = emb.map((e) => (e as num).toDouble()).toList();
          final typeKey = _typeKeyForCollection(collection);
          existing['$typeKey:${d.id}'] = vec; // e.g. 'dream:abc123'
        }
      }
    }

    await Future.wait([
      loadEmbeddings('traeume'),
      loadEmbeddings('prophetien'),
    ]);

    // fehlende oder kaputte Embeddings bestimmen
    final missing = <ConnectionItem>[];
    for (final it in items) {
      final k = _keyOf(it);
      final vec = existing[k];
      final needs = force || vec == null || !_isSaneEmbedding(vec);
      if (needs) missing.add(it);
    }
    if (missing.isEmpty) return existing;

    String collOf(ConnectionItem it) =>
        it.type == ItemType.dream ? 'traeume' : 'prophetien';

    const batchSize = 16;
    for (var i = 0; i < missing.length; i += batchSize) {
      final slice = missing.sublist(
        i,
        i + batchSize > missing.length ? missing.length : i + batchSize,
      );
      final texts = slice.map((e) => _cleanForEmbedding(e.text)).toList();
      final vecs = await fetchQwenEmbeddings(texts);
      if (vecs == null || vecs.length != slice.length) {
        // ignore: avoid_print
        print('Qwen Embeddings Warn: Vecs null oder Längen-Mismatch (got ${vecs?.length}, expected ${slice.length}). Überspringe diesen Batch.');
        continue;
      }

      final batch = FirebaseFirestore.instance.batch();
      for (var k = 0; k < slice.length; k++) {
        final it = slice[k];
        final v = vecs[k];
        existing[_keyOf(it)] = v;
        final docRef = FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection(collOf(it))
            .doc(it.id);
        batch.set(docRef, {
          'embedding': v,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();
    }

    return existing;
  }

  static Future<void> acceptConnection(ConnectionPair pair) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final pairKey = _pairKey(pair.first, pair.second);
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('connections')
        .doc(pairKey)
        .update({'pinned': true, 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> rejectConnection(ConnectionPair pair) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final pairKey = _pairKey(pair.first, pair.second);

    final batch = FirebaseFirestore.instance.batch();

    // Delete from connections
    final connectionDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('connections')
        .doc(pairKey);
    batch.delete(connectionDoc);

    // Add to rejected_connections (as a blocklist)
    final rejectedDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rejected_connections')
        .doc(pairKey);
    batch.set(rejectedDoc, {'rejectedAt': FieldValue.serverTimestamp()});

    await batch.commit();
  }

  static Future<Set<String>> _loadRejectedConnectionKeys(String uid) async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('rejected_connections')
        .get();
    return snap.docs.map((d) => d.id).toSet();
  }

  static Future<int> rebuildAllConnections({double threshold = 0.7}) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final rejectedKeys = await _loadRejectedConnectionKeys(uid);

    final dreams = await _loadItems('traeume', ItemType.dream, uid);
    final props = await _loadItems('prophetien', ItemType.prophecy, uid);
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
    final embeddings = await _ensureEmbeddings(uid, all, force: true);
    final pairs = _computePairsFromEmbeddings(
      all,
      embeddings,
      threshold: threshold,
      rejectedKeys: rejectedKeys,
    );

    await _persistPairs(uid, pairs);
    final keepIds = pairs.map((p) => _pairKey(p.first, p.second)).toSet();
    await _deleteConnectionsNotIn(uid, keepIds);
    return pairs.length;
  }

  static Future<List<ConnectionPair>> _loadSavedPairs(
    String uid,
    List<ConnectionItem> all, {
    int? limit,
    Set<String> rejectedKeys = const {},
  }) async {
    final index = {for (final it in all) _keyOf(it): it};
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

    final docs = snap.docs.where((d) => !rejectedKeys.contains(d.id));

    for (final d in docs) {
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

      final key = _pairKey(a, b);
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

    final rejectedKeys = await _loadRejectedConnectionKeys(uid);

    final dreams = await _loadItems('traeume', ItemType.dream, uid);
    final props = await _loadItems('prophetien', ItemType.prophecy, uid);
    final all = [
      ...dreams,
      ...props,
    ]
        .where((i) => i.text.trim() != 'Wird analysiert...')
        .where((i) => !_isLowInfoText(i.text))
        .toList()
          ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (all.length < 2) return [];

    final saved = await _loadSavedPairs(uid, all, rejectedKeys: rejectedKeys);

    final connectedKeys = <String>{};
    for (final p in saved) {
      connectedKeys.add(_keyOf(p.first));
      connectedKeys.add(_keyOf(p.second));
    }
    final newItems =
        all.where((it) => !connectedKeys.contains(_keyOf(it))).toList();

    final embeddings = await _ensureEmbeddings(uid, all, force: false);

    final byKey = {for (final it in all) _keyOf(it): it};
    final scored = _computePairsFromEmbeddings(
      all,
      embeddings,
      rejectedKeys: rejectedKeys,
    );

    if (scored.isNotEmpty) {
      await _persistPairs(uid, scored);
      final savedAll =
          await _loadSavedPairs(uid, all, rejectedKeys: rejectedKeys);
      return savedAll;
    }

    return saved;
  }
}