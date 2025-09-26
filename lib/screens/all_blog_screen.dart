import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import '../services/notion_service.dart';
import '../widgets/blog_card.dart';

const double _kPinnedTopHeight =
    64 + 48 + 16; // search(64) + labels(48) + spacer(16)

class _PinnedHeader extends SliverPersistentHeaderDelegate {
  final Widget child;
  final double height;
  _PinnedHeader({required this.child, required this.height});

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    return SizedBox(
      height: height,
      child: Container(color: theme.scaffoldBackgroundColor, child: child),
    );
  }

  @override
  double get maxExtent => height;

  @override
  double get minExtent => height;

  @override
  bool shouldRebuild(covariant _PinnedHeader oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

Future<List<Widget>> fetchNotionBlogCards(BuildContext context) async {
  return await NotionService.fetchBlogCards(context);
}

class AllBlogScreen extends StatefulWidget {
  const AllBlogScreen({Key? key}) : super(key: key);

  @override
  State<AllBlogScreen> createState() => _AllBlogScreenState();
}

class _AllBlogScreenState extends State<AllBlogScreen> {
  late Future<List<Widget>> _blogCardsFuture;
  String selectedCategory = 'Alle';
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  String _sort = 'Neu';

  @override
  void initState() {
    super.initState();
    _blogCardsFuture = fetchNotionBlogCards(context);
  }

  Future<void> _refreshBlogCards() async {
    setState(() {
      _blogCardsFuture = fetchNotionBlogCards(context);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Nützliche Tools',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.titleLarge?.color,
          ),
        ),
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: theme.iconTheme,
      ),
      body: Column(
        children: [
          // Search + labels like ProphetienScreen
          // Search row
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'Suchen',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        filled: true,
                        fillColor: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[850]
                            : Colors.grey[200],
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: 'Kategorien',
                  child: Material(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[850]
                        : Colors.grey[200],
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () async {
                        // Optional: kurze Haptik; keine weitere Aktion nötig
                        await HapticFeedback.selectionClick();
                      },
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.local_offer_outlined, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Labels under search: ChoiceChips like ProphetienScreen
          SizedBox(
            height: 36,
            child: FutureBuilder<List<Widget>>(
              future: _blogCardsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting || !snapshot.hasData) {
                  return const SizedBox.shrink();
                }
                final cards = snapshot.data!.whereType<BlogCard>().toList();
                final cats = <String>{};
                for (final c in cards) {
                  final cat = c.category.trim();
                  if (cat.isNotEmpty) cats.add(cat);
                }
                final labels = <String>['Alle', ...cats.toList()];

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      for (final label in labels)
                        Padding(
                          padding: const EdgeInsets.only(right: 10.0),
                          child: ChoiceChip(
                            label: Text(
                              label,
                              style: TextStyle(
                                fontWeight: (selectedCategory == label)
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: (selectedCategory == label)
                                    ? const Color(0xFFFF2C55)
                                    : Theme.of(context).textTheme.bodyMedium?.color,
                              ),
                            ),
                            selected: selectedCategory == label,
                            showCheckmark: false,
                            selectedColor: const Color(0xFFFF2C55).withOpacity(0.2),
                            backgroundColor: Theme.of(context).cardColor,
                            labelStyle: TextStyle(
                              fontWeight: (selectedCategory == label)
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: (selectedCategory == label)
                                  ? const Color(0xFFFF2C55)
                                  : Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            onSelected: (_) => setState(() => selectedCategory = label),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          // Content list scrollable
          Expanded(
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                CupertinoSliverRefreshControl(
                  onRefresh: () async {
                    await _refreshBlogCards();
                    await HapticFeedback.mediumImpact();
                    if (mounted) setState(() {});
                  },
                  builder:
                      (
                        context,
                        refreshState,
                        pulledExtent,
                        refreshTriggerPullDistance,
                        refreshIndicatorExtent,
                      ) {
                        return const CupertinoActivityIndicator();
                      },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 16)),
                // The rest of your FutureBuilder list rendering stays unchanged
                FutureBuilder<List<Widget>>(
                  future: _blogCardsFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 40),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text('Fehler beim Laden: ${snapshot.error}'),
                        ),
                      );
                    }
                    final cards = (snapshot.data ?? const <Widget>[])
                        .whereType<BlogCard>()
                        .toList();
                    List<BlogCard> filtered = cards;
                    if (_query.isNotEmpty) {
                      filtered = filtered.where((c) {
                        final t = (c.title ?? '').toLowerCase();
                        final cat = c.category.toLowerCase();
                        return t.contains(_query) || cat.contains(_query);
                      }).toList();
                    }
                    if (selectedCategory != 'Alle') {
                      filtered = filtered
                          .where((c) => c.category == selectedCategory)
                          .toList();
                    }
                    if (_sort == 'Beliebt') {
                      filtered.sort(
                        (a, b) => (a.title ?? '').toLowerCase().compareTo(
                          (b.title ?? '').toLowerCase(),
                        ),
                      );
                    }
                    if (filtered.isEmpty) {
                      return const SliverToBoxAdapter(
                        child: Padding(
                          padding: EdgeInsets.all(16.0),
                          child: Center(
                            child: Text('Keine Blogartikel verfügbar.'),
                          ),
                        ),
                      );
                    }
                    return SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
                          child: filtered[index],
                        );
                      }, childCount: filtered.length),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
