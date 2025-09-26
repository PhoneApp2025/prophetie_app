import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prophetie_app/screens/all_blog_screen.dart';
import '../models/prophetie.dart';
import '../models/traum.dart';
import '../widgets/custom_app_bar.dart';
import '../services/notion_service.dart';
import '../widgets/connection_card.dart';
import '../widgets/blog_card.dart';
import '../services/connection_service.dart';
import '../services/insight_service.dart';
import '../services/metrics_service.dart';
import '../models/connection_pair.dart';
import '../widgets/prophetie_detail_sheet.dart';
import '../widgets/traum_detail_sheet.dart';
import '../main.dart';


// Preview item for entry quick filters
class EntryPreviewItem {
  final String coll; // 'traeume' | 'prophetien'
  final String id;
  final String title;
  final DateTime timestamp;
  final bool isFavorit;
  final List<dynamic> labels;
  EntryPreviewItem({
    required this.coll,
    required this.id,
    required this.title,
    required this.timestamp,
    required this.isFavorit,
    required this.labels,
  });
}

// Enum for quick filters
enum QuickFilter { heute, woche, unbewertet }




class _InsightCard extends StatelessWidget {
  final String id;
  final String title;
  final String body;
  final String cta;
  final String type;
  final VoidCallback onPrimary;
  final VoidCallback onDismiss;
  const _InsightCard({
    required this.id,
    required this.title,
    required this.body,
    required this.cta,
    required this.type,
    required this.onPrimary,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Color(0x14FF2D55),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(
              _iconFor(type),
              size: 20,
              color: const Color(0xFFFF2D55),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: onPrimary,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    side: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.6)),
                    foregroundColor: Theme.of(context).colorScheme.onSurface.withOpacity(0.9),
                    textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  child: Text(cta),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  static IconData _iconFor(String t) {
    switch (t) {
      case 'record_nudge':
        return Icons.mic_none;
      case 'label_missing':
        return Icons.sell_outlined;
      case 'new_connection':
        return Icons.link_outlined;
      case 'inactivity_reflect':
        return Icons.self_improvement_outlined;
      default:
        return Icons.auto_awesome;
    }
  }
}


class _InsightsSkeleton extends StatelessWidget {
  final bool single;
  const _InsightsSkeleton({this.single = false});
  @override
  Widget build(BuildContext context) {
    if (single) {
      return _skel(context, height: 100);
    }
    return Column(
      children: [
        _skel(context, height: 68),
        const SizedBox(height: 8),
        _skel(context, height: 68),
      ],
    );
  }

  Widget _skel(BuildContext context, {required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).dividerColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _FriendlyError extends StatelessWidget {
  final String title;
  final String? subtitle;
  final VoidCallback onRetry;
  const _FriendlyError({required this.title, this.subtitle, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 28, color: Theme.of(context).dividerColor.withOpacity(0.9)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onRetry,
            child: const Text('Erneut versuchen'),
          ),
        ],
      ),
    );
  }
}


class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Prophetie> prophetien = [];
  List<Traum> traeume = [];

  String? userName;
  String greeting = "";

  List<dynamic> matchingResults = [];
  late final PageController _connectionsPageController;
  late final PageController _singleConnectionsController;
  late final PageController _insightsController;
  int _insightsPage = 0;

  // Cache for insights docs (to stabilize docs between builds)
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _insightsDocs = [];

  // Quick filter state
  QuickFilter _activeFilter = QuickFilter.heute;

  // Cached futures/streams
  late final Future<QuerySnapshot<Map<String, dynamic>>?> _insightsFuture;
  late final Stream<List<ConnectionPair>> _connectionsStream;
  late Future<List<EntryPreviewItem>> _entriesFuture;

  @override
  void initState() {
    super.initState();

    _connectionsPageController = PageController(
      viewportFraction: 0.96, // nahezu volle Breite; nur leichter Peek links/rechts
      initialPage: 0,
    );
    _singleConnectionsController = PageController(
      viewportFraction: 1.0,
      initialPage: 0,
    );
    _insightsController = PageController(
      viewportFraction: 0.96,
      initialPage: 0,
    );
    _entriesFuture = _fetchFilteredEntries(_activeFilter);

    _markTopNewsFromFirestore();
    _loadUserName();
    _ensureInsightsForToday();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _insightsFuture = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('insights')
          .where(
            'createdAt',
            isGreaterThanOrEqualTo: DateTime(
              DateTime.now().year,
              DateTime.now().month,
              DateTime.now().day,
            ),
          )
          .orderBy('createdAt', descending: true)
          .limit(3)
          .get();
      _connectionsStream = _streamConnections(interval: const Duration(seconds: 12));
    } else {
      _insightsFuture = Future.value(null);
      _connectionsStream = Stream<List<ConnectionPair>>.periodic(const Duration(seconds: 12), (_) => const <ConnectionPair>[]);
    }
  }
  Stream<List<ConnectionPair>> _streamConnections({Duration interval = const Duration(seconds: 20)}) async* {
    while (mounted) {
      try {
        final data = await ConnectionService.fetchConnections();
        yield data;
      } catch (_) {
        // ignore errors in polling step
        yield const <ConnectionPair>[];
      }
      await Future.delayed(interval);
    }
  }

  @override
  void dispose() {
    _connectionsPageController.dispose();
    _singleConnectionsController.dispose();
    _insightsController.dispose();
    super.dispose();
  }

  void _loadUserName() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      if (!mounted) return;
      setState(() {
        userName = user.displayName ?? user.email?.split('@')[0] ?? "Gast";
      });
    } else {
      userName = "Gast";
    }
  }

  Future<void> _loadData() async {
    try {
      // Load propheties from Firestore
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final prophetienSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('prophetien')
          .orderBy('timestamp', descending: true)
          .get();
      final loadedProphetien = prophetienSnapshot.docs.map((doc) {
        final data = doc.data();
        return Prophetie(
          id: doc.id,
          transcript: data['transkript'] as String? ?? '',
          labels: List<String>.from(data['labels'] ?? []),
          isFavorit: data['isFavorit'] as bool? ?? false,
          timestamp: (data['timestamp'] as Timestamp).toDate(),
          filePath: data['audioUrl'] as String?,
          creatorName: data['creatorName'] as String?,
        );
      }).toList();

      // Load dreams from Firestore
      final traeumeSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('traeume')
          .orderBy('timestamp', descending: true)
          .get();
      final loadedTraeume = traeumeSnapshot.docs.map((doc) {
        final data = doc.data();
        return Traum(
          id: doc.id,
          title: data['title'] as String? ?? '',
          labels: List<String>.from(data['labels'] ?? []),
          isFavorit: data['isFavorit'] as bool? ?? false,
          timestamp: (data['timestamp'] as Timestamp).toDate(),
          filePath: data['audioUrl'] as String?,
          creatorName: data['creatorName'] as String?,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        prophetien = loadedProphetien;
        traeume = loadedTraeume;
      });

      _saveTopNewsToFirestore(loadedProphetien);
    } catch (e) {
      print("Fehler beim Laden der Daten: $e");
    }
  }

  void _saveTopNewsToFirestore(List<Prophetie> prophetien) async {
    final firestore = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final userId = user.uid;
    final collectionRef = firestore
        .collection('users')
        .doc(userId)
        .collection('prophetien');

    for (var p in prophetien) {
      await collectionRef.doc(p.timestamp.toIso8601String()).set({
        'title': p.title,
        'timestamp': p.timestamp.toIso8601String(),
        'summary': p.summary,
        'matchingTopics': p.matchingTopics,
        'isTopNews': p.isTopNews ?? false,
      }, SetOptions(merge: true));
    }
  }

  Future<void> _markTopNewsFromFirestore() async {
    final firestore = FirebaseFirestore.instance;
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) return;

    final userId = user.uid;
    final snapshot = await firestore
        .collection('users')
        .doc(userId)
        .collection('prophetien')
        .where('isTopNews', isEqualTo: true)
        .get();

    final topNewsTimestamps = snapshot.docs.map((doc) => doc.id).toSet();

    if (!mounted) return;

    setState(() {
      for (var p in prophetien) {
        if (topNewsTimestamps.contains(p.timestamp.toIso8601String())) {
          p.isTopNews = true;
        }
      }
    });
  }

  void _onRecordPressed() {
    HapticFeedback.selectionClick();
    try {
      // Falls du eine dedizierte Route hast, benutze sie. Sonst fallback Snackbar.
      Navigator.of(context).pushNamed('/record');
    } catch (_) {
      showFlushbar('Aufnahme-Flow noch nicht verdrahtet.');
    }
  }

  void _showImportSheet() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.nightlight_round),
                title: const Text('Traum importieren'),
                onTap: () => _onImport('traeume'),
              ),
              ListTile(
                leading: const Icon(Icons.bolt),
                title: const Text('Prophetie importieren'),
                onTap: () => _onImport('prophetien'),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }


  void _onImport(String coll) {
    Navigator.of(context).pop();
    HapticFeedback.selectionClick();
    final route = '/import_' + coll; // z.B. /import_traeume oder /import_prophetien
    try {
      Navigator.of(context).pushNamed(route);
    } catch (_) {
      showFlushbar('Import-Flow für ' + coll + ' noch nicht verdrahtet.');
    }
  }

  Future<int> _loadToolsCount() async {
    final items = await NotionService.fetchBlogCards(context);
    // Zähle nur echte Tools (nicht Resources)
    final tools = items
        .whereType<BlogCard>()
        .where((c) => c.isResource != true)
        .toList();
    return tools.length;
  }

  Future<void> _ensureInsightsForToday() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await InsightsService.ensureDailyInsights(uid: uid);
      if (mounted) setState(() {});
      await InsightsService.cleanupOldInsights(uid: uid);
    } catch (e) {
      // ignore
    }
  }

  Future<void> _markInsightSeen(String insightId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('insights')
        .doc(insightId)
        .set({
          'seen': true,
          'expiresAt': DateTime.now().add(const Duration(hours: 36)),
        }, SetOptions(merge: true));
  }

  Future<void> _deleteInsight(String insightId) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('insights')
        .doc(insightId)
        .delete();
  }

  void _setFilter(QuickFilter f) {
    if (_activeFilter == f) return;
    setState(() {
      _activeFilter = f;
      _entriesFuture = _fetchFilteredEntries(_activeFilter);
    });
  }

  void _openEntryDetail(BuildContext ctx, EntryPreviewItem it) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (_) {
        final isDream = it.coll == 'traeume';
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: isDream
                      ? TraumDetailSheet(traumId: it.id)
                      : ProphetieDetailSheet(prophetieId: it.id),
                ),
                Positioned(
                  top: 6,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).dividerColor.withOpacity(0.8),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<List<EntryPreviewItem>> _fetchFilteredEntries(QuickFilter f) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];
    final fs = FirebaseFirestore.instance;

    DateTime? since;
    bool unlabeled = false;

    switch (f) {
      case QuickFilter.heute:
        final now = DateTime.now();
        since = DateTime(now.year, now.month, now.day);
        break;
      case QuickFilter.woche:
        since = DateTime.now().subtract(const Duration(days: 7));
        break;
      case QuickFilter.unbewertet:
        unlabeled = true;
        break;
    }

    Future<List<EntryPreviewItem>> q(String coll) async {
      Query<Map<String, dynamic>> q = fs
          .collection('users')
          .doc(uid)
          .collection(coll);
      if (since != null) {
        q = q.where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(since!));
      }
      // Für unbewertet können wir in Firestore nicht "array is empty" abfragen.
      // Wir holen die letzten 100 und filtern clientseitig.
      q = q.orderBy('timestamp', descending: true).limit(100);
      final snap = await q.get();
      final list = snap.docs.map((d) {
        final m = d.data();
        return EntryPreviewItem(
          coll: coll,
          id: d.id,
          title: (m['title'] ?? m['summary'] ?? m['transkript'] ?? 'Ohne Titel') as String,
          timestamp: (m['timestamp'] as Timestamp).toDate(),
          isFavorit: (m['isFavorit'] as bool?) ?? false,
          labels: (m['labels'] as List?) ?? const [],
        );
      }).toList();
      if (unlabeled) {
        return list.where((e) => e.labels.isEmpty).toList();
      }
      return list;
    }

    final results = <EntryPreviewItem>[];
    final a = await q('traeume');
    final b = await q('prophetien');
    results.addAll(a);
    results.addAll(b);
    results.sort((x, y) => y.timestamp.compareTo(x.timestamp));
    return results.take(5).toList();
  }

  String _formatDate(DateTime d) {
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final yyyy = d.year.toString();
    return '$dd.$mm.$yyyy';
  }

  String _labelForFilter(QuickFilter f) {
    switch (f) {
      case QuickFilter.heute:
        return 'Heute';
      case QuickFilter.woche:
        return 'Woche';
      case QuickFilter.unbewertet:
        return 'Unbewertet';
    }
  }

  String _emptyTitleFor(QuickFilter f) {
    switch (f) {
      case QuickFilter.unbewertet:
        return 'Top! Alles gelabelt.';
      case QuickFilter.heute:
        return 'Heute gibt es keine neuen Einträge.';
      case QuickFilter.woche:
        return 'Keine Einträge in den letzten 7 Tagen.';
    }
  }

  String? _emptySubtitleFor(QuickFilter f) {
    switch (f) {
      case QuickFilter.unbewertet:
        return 'Alle aktuellen Träume und Prophetien haben Labels.';
      case QuickFilter.heute:
        return 'Schau dir Woche oder deine Favoriten an.';
      case QuickFilter.woche:
        return 'Vielleicht war es eine ruhigere Zeit — alles gut.';
    }
  }

  Widget _emptyPreviewTile(QuickFilter f) {
    final icon = f == QuickFilter.unbewertet
        ? Icons.verified_outlined
        : (f == QuickFilter.heute ? Icons.calendar_today_outlined : Icons.date_range_outlined);
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(_emptyTitleFor(f)),
      subtitle: (_emptySubtitleFor(f) == null) ? null : Text(_emptySubtitleFor(f)!),
    );
  }

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.light
            : Brightness.dark,
        statusBarBrightness: Theme.of(context).brightness == Brightness.dark
            ? Brightness.dark
            : Brightness.light,
      ),
    );
    return Scaffold(
      extendBodyBehindAppBar: false,
      appBar: const CustomAppBar(isHome: true),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Stack(
          children: [
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(),
            ),
            NotificationListener<UserScrollNotification>(
              onNotification: (notification) {
                return false;
              },
              child: CustomScrollView(
              slivers: [
                // Heute für dich (dynamisch aus Insights)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16.0, 10.0, 16.0, 8.0),
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>?>(
                      stream: FirebaseAuth.instance.currentUser != null
                          ? FirebaseFirestore.instance
                              .collection('users')
                              .doc(FirebaseAuth.instance.currentUser!.uid)
                              .collection('insights')
                              .where(
                                'createdAt',
                                isGreaterThanOrEqualTo: DateTime(
                                  DateTime.now().year,
                                  DateTime.now().month,
                                  DateTime.now().day,
                                ),
                              )
                              .orderBy('createdAt', descending: true)
                              .limit(3)
                              .snapshots()
                          : const Stream.empty(),
                      builder: (ctx, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const _InsightsSkeleton();
                        }
                        final data = snap.data;
                        final incoming = data?.docs.where((d) => (d.data()['seen'] as bool?) != true).toList() ?? const [];

                        // Update cache only if the list of IDs actually changed.
                        bool changed = false;
                        if (incoming.length != _insightsDocs.length) {
                          changed = true;
                        } else {
                          for (int i = 0; i < incoming.length; i++) {
                            if (incoming[i].id != _insightsDocs[i].id) { changed = true; break; }
                          }
                        }
                        if (changed) {
                          _insightsDocs = List.from(incoming);
                        }

                        if (_insightsDocs.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        final docs = _insightsDocs;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Heute für dich",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (int i = 0; i < docs.length; i++) ...[
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 2.0),
                                    child: _InsightCard(
                                      id: docs[i].id,
                                      title: (docs[i].data()['title'] as String?) ?? '',
                                      body: (docs[i].data()['body'] as String?) ?? '',
                                      cta: (docs[i].data()['cta'] as String?) ?? 'Ansehen',
                                      type: (docs[i].data()['type'] as String?) ?? 'generic',
                                      onPrimary: () {
                                        final type = (docs[i].data()['type'] as String?) ?? 'generic';
                                        if (type == 'inactivity_reflect') {
                                          setState(() {
                                            _activeFilter = QuickFilter.woche;
                                            _entriesFuture = _fetchFilteredEntries(_activeFilter);
                                          });
                                          showFlushbar('Filter auf "Woche" gesetzt. Scrolle zu deinen jüngsten Einträgen.');
                                        } else if (type == 'label_missing') {
                                          setState(() {
                                            _activeFilter = QuickFilter.unbewertet;
                                            _entriesFuture = _fetchFilteredEntries(_activeFilter);
                                          });
                                          showFlushbar('Filter auf "Unbewertet" gesetzt. Scrolle zu deinen Einträgen ohne Labels.');
                                        } else if (type == 'new_connection') {
                                          _openAllMatches();
                                        }
                                        _markInsightSeen(docs[i].id);
                                      },
                                      onDismiss: () => _deleteInsight(docs[i].id),
                                    ),
                                  ),
                                  if (i != docs.length - 1) const SizedBox(height: 8),
                                ],
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                // Stats under header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 12.0,
                      bottom: 4.0,
                    ),
                    child: Builder(
                      builder: (context) {
                        final uid = FirebaseAuth.instance.currentUser?.uid;
                        if (uid == null) return const SizedBox.shrink();
                        return StatsSection(uid: uid);
                      },
                    ),
                  ),
                ),
                // Schnellfilter-Chips + Preview-Liste
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 16.0, right: 16.0, top: 6.0, bottom: 2.0),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(0, 0, 0, 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Segmented control styled as a compact, seamless group
                          Padding(
                            padding: EdgeInsets.zero,
                            child: Container(
                              height: 36,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.18)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final count = QuickFilter.values.length;
                                  final segW = constraints.maxWidth / count;
                                  final selected = _activeFilter.index; // 0,1,2

                                  return Stack(
                                    children: [
                                      // Sliding highlight background
                                      AnimatedPositioned(
                                        duration: const Duration(milliseconds: 220),
                                        curve: Curves.easeOutCubic,
                                        left: segW * selected,
                                        top: 0,
                                        bottom: 0,
                                        width: segW,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black,
                                            borderRadius: BorderRadius.only(
                                              topLeft: selected == 0 ? const Radius.circular(12) : Radius.zero,
                                              topRight: selected == count - 1 ? const Radius.circular(12) : Radius.zero,
                                              bottomLeft: Radius.zero,
                                              bottomRight: Radius.zero,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Interactive labels row
                                      Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          for (int i = 0; i < count; i++) ...[
                                            Expanded(
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  onTap: () => _setFilter(QuickFilter.values[i]),
                                                  child: Container(
                                                    alignment: Alignment.center,
                                                    // Per-button background now transparent; highlight slides underneath
                                                    decoration: const BoxDecoration(
                                                      color: Colors.transparent,
                                                    ),
                                                    child: Text(
                                                      _labelForFilter(QuickFilter.values[i]),
                                                      textAlign: TextAlign.center,
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.w700,
                                                        color: i == selected
                                                            ? Colors.white
                                                            : (Theme.of(context).brightness == Brightness.dark
                                                                ? Colors.white
                                                                : Colors.black),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          FutureBuilder<List<EntryPreviewItem>>(
                            future: _entriesFuture,
                            builder: (ctx, snap) {
                              if (snap.connectionState == ConnectionState.waiting) {
                                return const _InsightsSkeleton();
                              }
                              final items = snap.data ?? const <EntryPreviewItem>[];
                              if (items.isEmpty) {
                                // Zeige eine freundliche leere-Status-Zeile statt weißer Fläche
                                return _emptyPreviewTile(_activeFilter);
                              }
                              return Column(
                                children: [
                                  for (final it in items)
                                    ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12.0),
                                      dense: true,
                                      visualDensity: VisualDensity.compact,
                                      leading: it.coll == 'traeume'
                                          ? SvgPicture.asset('assets/icons/traeume.svg', width: 20, height: 20)
                                          : SvgPicture.asset('assets/icons/prophetie.svg', width: 20, height: 20),
                                      title: Text(
                                        it.title.isEmpty ? (it.coll == 'traeume' ? 'Traum' : 'Prophetie') : it.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        _formatDate(it.timestamp) + (it.isFavorit ? '  •  Favorit' : ''),
                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                          color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.black).withOpacity(0.75),
                                        ),
                                      ),
                                      onTap: () => _openEntryDetail(context, it),
                                    ),
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                // Greeting above Top Treffer REMOVED
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 18.0,
                      bottom: 0.0,
                    ),
                    child: Text(
                      "Übereinstimmungen",
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                      ),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: StreamBuilder<List<ConnectionPair>>(
                    stream: _connectionsStream,
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                          child: _InsightsSkeleton(single: true),
                        );
                      } else if (snap.hasError ||
                          snap.data == null ||
                          snap.data!.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.connect_without_contact,
                                  size: 36,
                                  color: Theme.of(context).dividerColor.withOpacity(0.8),
                                ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Noch keine Verbindungen. Fang an aufzunehmen oder importiere bestehende Einträge.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      final items = snap.data!.take(4).toList();

                      return LayoutBuilder(
                        builder: (context, viewport) {
                          final double viewportW = viewport.maxWidth; // tatsächliche Breite, nach Außen-Padding
                          final bool isTablet = viewportW > 600;
                          final bool hasSingle = items.length == 1;

                          // Nur horizontaler Seitenabstand für die Kartenränder; Breite/Höhe bestimmt die Karte selbst.
                          final double hMargin = hasSingle ? 0.0 : (isTablet ? 6.0 : 4.0);

                          // Höhe des Carousels: nutze eine konservative Obergrenze, damit PageView gebounded ist,
                          // ohne die Karte zu strecken. Die Karte regelt ihre eigentliche Höhe intern.
                          final double maxH = isTablet ? 320.0 : 164.0;

                          return Padding(
                            padding: EdgeInsets.fromLTRB(
                              hasSingle ? 13.0 : 0.0,
                              2.0,
                              hasSingle ? 13.0 : 0.0,
                              2.0,
                            ),
                            child: AnimatedBuilder(
                              animation: hasSingle ? _singleConnectionsController : _connectionsPageController,
                              builder: (context, _) {
                                final controller = hasSingle ? _singleConnectionsController : _connectionsPageController;
                                final double currentPage = controller.hasClients
                                    ? (controller.page ?? controller.initialPage.toDouble())
                                    : 0.0;
                                return SizedBox(
                                  height: maxH,
                                  child: PageView.builder(
                                    controller: hasSingle ? _singleConnectionsController : _connectionsPageController,
                                    itemCount: items.length,
                                    physics: hasSingle
                                        ? const NeverScrollableScrollPhysics()
                                        : const PageScrollPhysics(),
                                    padEnds: true,
                                    clipBehavior: Clip.none,
                                    itemBuilder: (ctx, index) {
                                      final pair = items[index];

                                      final double delta = hasSingle ? 0.0 : (currentPage - index).abs();
                                      final double scale = hasSingle ? 1.0 : (1 - (delta * 0.06)).clamp(0.92, 1.0);
                                      final double opacity = hasSingle ? 1.0 : (1 - (delta * 0.40)).clamp(0.70, 1.0);
                                      final double translateY = hasSingle ? 0.0 : (delta * 8.0).clamp(0.0, 10.0);

                                      return Center(
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          curve: Curves.easeOut,
                                          margin: EdgeInsets.symmetric(horizontal: hMargin),
                                          child: Transform(
                                            alignment: Alignment.center,
                                            transform: Matrix4.identity()
                                              ..translate(0.0, translateY)
                                              ..scale(scale, scale),
                                            child: Opacity(
                                              opacity: opacity,
                                              child: ConnectionCard(pair),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                // Inserted "Oft gelesen" block as a new SliverToBoxAdapter
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 9.0,
                      bottom: 14.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Nützliche Tools",
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => AllBlogScreen(),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0, vertical: 6.0),
                                child: Text(
                                  'Alles sehen',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.white
                                        : Colors.black,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<Widget>>(
                          future: fetchNotionBlogCards(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const _InsightsSkeleton();
                            } else if (snapshot.hasError) {
                              return _FriendlyError(
                                title: 'Inhalt konnte nicht geladen werden.',
                                subtitle: 'Möglicherweise schwache Internetverbindung. Die Tools werden angezeigt, sobald wieder Verbindung besteht.',
                                onRetry: () => setState(() {}),
                              );
                            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Text('Keine Blogartikel verfügbar.');
                            } else {
                              final cards = snapshot.data!;
                              // Nur Nicht-Resources anzeigen
                              final tools = cards
                                  .whereType<BlogCard>()
                                  .where((c) => c.isResource != true)
                                  .cast<Widget>()
                                  .toList();

                              if (tools.isEmpty) {
                                return const Text('Keine Tools verfügbar.');
                              }

                              final vertical = tools.take(3).toList();
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int i = 0; i < vertical.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == vertical.length - 1 ? 0 : 12,
                                      ),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: vertical[i],
                                      ),
                                    ),
                                ],
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                // Resources section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 16.0,
                      right: 16.0,
                      top: 0.0,
                      bottom: 16.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Resources",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<Widget>>(
                          future: fetchNotionBlogCards(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState == ConnectionState.waiting) {
                              return const _InsightsSkeleton();
                            } else if (snapshot.hasError) {
                              return _FriendlyError(
                                title: 'Inhalt konnte nicht geladen werden.',
                                subtitle: 'Bitte Internet prüfen und erneut versuchen.',
                                onRetry: () => setState(() {}),
                              );
                            } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                              return const Text('Keine Blogartikel verfügbar.');
                            } else {
                              final cards = snapshot.data!;
                              // Filter: only entries marked as Resources (via category)
                              final resourceCards = cards
                                  .whereType<BlogCard>()
                                  .where((c) => c.isResource == true)
                                  .toList();

                              final vertical = resourceCards.take(3).toList();
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int i = 0; i < vertical.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == vertical.length - 1 ? 0 : 12,
                                      ),
                                      child: SizedBox(
                                        width: double.infinity,
                                        child: vertical[i],
                                      ),
                                    ),
                                ],
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  void _openAllMatches() {
    // Navigiere zu einer Seite, die alle Übereinstimmungen anzeigt
    // (Placeholder: Scrollt zu Übereinstimmungen oder öffnet ggf. Seite)
    // Hier kannst du die gewünschte Navigation einbauen.
    // Zum Beispiel:
    // Navigator.of(context).pushNamed('/connections');
  }

  Widget _buildInfoCard(String title) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Center(
        child: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black,
          ),
        ),
      ),
    );
  }

  Future<List<Widget>> fetchNotionBlogCards() async {
    final notionCards = await NotionService.fetchBlogCards(context);
    // Show only the 4 newest cards
    return notionCards.take(4).toList();
  }
}


class StatsSection extends StatefulWidget {
  final String uid;
  const StatsSection({super.key, required this.uid});

  @override
  State<StatsSection> createState() => _StatsSectionState();
}

class _StatsSectionState extends State<StatsSection> {
  late Future<DocumentSnapshot<Map<String, dynamic>>> _future;
  bool _rebuilding = false;

  @override
  void initState() {
    super.initState();
    _future = _loadOrRebuild();
  }

  Future<DocumentSnapshot<Map<String, dynamic>>> _loadOrRebuild() async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.uid)
        .collection('metrics')
        .doc('summary');
    final snap = await ref.get();
    if (!snap.exists && !_rebuilding) {
      _rebuilding = true;
      try {
        await MetricsService.rebuildFromExisting(uid: widget.uid);
      } catch (e) {
        // ignore: avoid_print
        print('Metrics rebuild failed: $e');
      }
      return await ref.get();
    }
    return snap;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const _StatsSkeleton();
        }
        if (!snap.hasData || !(snap.data?.exists ?? false)) {
          return const _StatsSkeleton();
        }
        final data = snap.data!.data() ?? const <String, dynamic>{};
        final totalTraeume = (data['totalTraeume'] ?? 0) as int;
        final totalProphetien = (data['totalProphetien'] ?? 0) as int;
        final ytdTraeume = (data['ytdTraeume'] ?? 0) as int;
        final ytdProphetien = (data['ytdProphetien'] ?? 0) as int;

        final title = Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800);
        final caption = Theme.of(context).textTheme.bodySmall?.copyWith(
              color: (Theme.of(context).textTheme.bodySmall?.color ?? Colors.black).withOpacity(0.7),
            );

        return Row(
          children: [
            Expanded(
              child: _KpiDualTile(
                title: 'Träume',
                primary: totalTraeume,
                secondaryLabel: 'davon dieses Jahr',
                secondary: ytdTraeume,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KpiDualTile(
                title: 'Prophetien',
                primary: totalProphetien,
                secondaryLabel: 'davon dieses Jahr',
                secondary: ytdProphetien,
              ),
            ),
          ],
        );
      },
    );
  }
}


class _KpiColumn extends StatelessWidget {
  final int value;
  final String label;
  final TextStyle? title;
  final TextStyle? caption;
  const _KpiColumn({required this.value, required this.label, this.title, this.caption});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$value', style: title),
        const SizedBox(height: 2),
        Text(label, style: caption, maxLines: 1, overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

class _KpiDualTile extends StatelessWidget {
  final String title;
  final int primary;
  final String secondaryLabel;
  final int secondary;
  const _KpiDualTile({
    required this.title,
    required this.primary,
    required this.secondaryLabel,
    required this.secondary,
  });

  @override
  Widget build(BuildContext context) {
    final tone = Theme.of(context).textTheme;
    final numStyle = tone.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: (tone.titleSmall?.color ?? Colors.black).withOpacity(0.85),
    );
    final labelStyle = tone.bodySmall?.copyWith(
      color: (tone.bodySmall?.color ?? Colors.black).withOpacity(0.65),
      height: 1.15,
      fontWeight: FontWeight.w500,
    );
    final titleStyle = tone.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateTime.now().year}: $secondary',
                  style: labelStyle,
                  softWrap: true,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final tone = Theme.of(context).textTheme;
              final base = (tone.bodySmall?.fontSize ?? 12.0);
              final lineH = (1.15); // matches labelStyle height above
              final twoLineHeight = (base * lineH * 2) + 2; // slight buffer

              return SizedBox(
                height: twoLineHeight,
                child: FittedBox(
                  fit: BoxFit.contain,
                  alignment: Alignment.centerRight,
                  child: Text(
                    '$primary',
                    textAlign: TextAlign.right,
                    style: (numStyle ?? const TextStyle()).copyWith(
                      // scale number so its glyph height roughly equals two lines of body text
                      fontSize: base * 2.6,
                      height: 1.0,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatsSkeleton extends StatelessWidget {
  const _StatsSkeleton();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (int i = 0; i < 4; i++) ...[
            Expanded(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (i < 3) const SizedBox(width: 12),
          ]
        ],
      ),
    );
  }
}

class _ToolsCtaCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ToolsCtaCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFFF2D55);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.25),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(Icons.add, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Mehr Tools ansehen',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Alle Videos & Beiträge in einer Übersicht',
                      style: Theme.of(context).textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolsCtaCardPlaceholder extends StatelessWidget {
  const _ToolsCtaCardPlaceholder();
  @override
  Widget build(BuildContext context) {
    return _ToolsCtaCard(
      onTap: () async {
        await HapticFeedback.selectionClick();
        if (context.mounted) {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (context) => const AllBlogScreen()),
          );
        }
      },
    );
  }
}
