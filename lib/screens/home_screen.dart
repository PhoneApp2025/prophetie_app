import 'package:flutter/material.dart';
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
import '../models/connection_pair.dart';

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
  final PageController _connectionsPageController = PageController(
    viewportFraction: 1.0,
  );

  @override
  void initState() {
    super.initState();
    _markTopNewsFromFirestore();
    _loadUserName();
  }

  @override
  void dispose() {
    _connectionsPageController.dispose();
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
      final prophetienSnapshot = await FirebaseFirestore.instance
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
      appBar: null,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
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
                SliverAppBar(
                  floating: true,
                  snap: true,
                  toolbarHeight: kToolbarHeight,
                  backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                  elevation: 0,
                  flexibleSpace: const CustomAppBar(isHome: true),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 15.0,
                      right: 15.0,
                      top: 40.0,
                      bottom: 2.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(
                            top: 16.0,
                            bottom: 0.0,
                          ),
                          child: Text(
                            "Top Treffer",
                            style: TextStyle(
                              fontSize: 25,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFFFF2C55),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: FutureBuilder<List<ConnectionPair>>(
                    future: ConnectionService.fetchConnections(),
                    builder: (ctx, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snap.hasError ||
                          snap.data == null ||
                          snap.data!.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.connect_without_contact,
                                size: 54,
                                color: Color.fromARGB(255, 167, 167, 167),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'Sobald du mehr Prophetien und Träume hast, werden hier passende Verbindungen angezeigt.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 15),
                              ),
                            ],
                          ),
                        );
                      }
                      final items = snap.data!.take(4).toList();
                      final double _screenW = MediaQuery.of(ctx).size.width;
                      final double cardHeight =
                          _screenW * 0.44; // ~44% der Breite

                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 15.0),
                        child: SizedBox(
                          height: cardHeight,
                          child: PageView.builder(
                            controller: _connectionsPageController,
                            itemCount: items.length,
                            physics: const PageScrollPhysics(),
                            padEnds: false,
                            clipBehavior: Clip.none,
                            itemBuilder: (ctx, index) {
                              final pair = items[index];
                              return ConnectionCard(pair);
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Inserted "Oft gelesen" block as a new SliverToBoxAdapter
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(
                      left: 15.0,
                      right: 15.0,
                      top: 24.0,
                      bottom: 24.0,
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
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color:
                                    Theme.of(
                                      context,
                                    ).textTheme.bodyLarge?.color ??
                                    Colors.black,
                              ),
                            ),
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => AllBlogScreen(),
                                  ),
                                );
                              },
                              child: Text(
                                "Alles sehen",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white
                                      : Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<Widget>>(
                          future: fetchNotionBlogCards(),
                          builder: (context, snapshot) {
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            } else if (snapshot.hasError) {
                              return Text(
                                'Fehler beim Laden: ${snapshot.error}',
                              );
                            } else if (!snapshot.hasData ||
                                snapshot.data!.isEmpty) {
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
                              final screenW = MediaQuery.of(context).size.width;
                              final double itemH =
                                  screenW *
                                  0.32; // proportional zur Gerätebreite

                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int i = 0; i < vertical.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == vertical.length - 1
                                            ? 0
                                            : 12,
                                      ),
                                      child: SizedBox(
                                        height: itemH,
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
                      left: 15.0,
                      right: 15.0,
                      top: 0.0,
                      bottom: 24.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Resources",
                          style: TextStyle(
                            fontSize: 24,
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
                            if (snapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            } else if (snapshot.hasError) {
                              return Text(
                                'Fehler beim Laden: ${snapshot.error}',
                              );
                            } else if (!snapshot.hasData ||
                                snapshot.data!.isEmpty) {
                              return const Text('Keine Blogartikel verfügbar.');
                            } else {
                              final cards = snapshot.data!;
                              // Filter: only entries marked as Resources (via category)
                              final resourceCards = cards
                                  .whereType<BlogCard>()
                                  .where((c) => c.isResource == true)
                                  .toList();
                              final vertical = resourceCards.take(3).toList();
                              final screenW = MediaQuery.of(context).size.width;
                              final double itemH = screenW * 0.32;
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (int i = 0; i < vertical.length; i++)
                                    Padding(
                                      padding: EdgeInsets.only(
                                        bottom: i == vertical.length - 1
                                            ? 0
                                            : 12,
                                      ),
                                      child: SizedBox(
                                        height: itemH,
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
    );
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

class _ToolsCtaCard extends StatelessWidget {
  final VoidCallback onTap;
  const _ToolsCtaCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = const Color(0xFFFF2D55);
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
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
