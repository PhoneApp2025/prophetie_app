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
          // Search bar (统一样式)
          SizedBox(
            height: 55,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
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
                    fillColor: theme.brightness == Brightness.dark
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
          ),
          // Labels row
          SizedBox(
            height: 38,
            child: FutureBuilder<List<Widget>>(
              future: _blogCardsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting ||
                    !snapshot.hasData) {
                  return const SizedBox(height: 8);
                }
                final cards = snapshot.data!.whereType<BlogCard>().toList();
                final cats = <String>{'Alle'};
                for (final c in cards) {
                  if (c.category.trim().isNotEmpty) cats.add(c.category.trim());
                }
                final list = cats.toList();
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final cat = list[i];
                    final selected = cat == selectedCategory;
                    return InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () async {
                        await HapticFeedback.selectionClick();
                        setState(() => selectedCategory = cat);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFFFF2C55).withOpacity(0.14)
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.white.withOpacity(0.08)
                                    : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          cat,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13.5,
                            color: selected
                                ? const Color(0xFFFF2C55)
                                : (Theme.of(context).brightness ==
                                          Brightness.dark
                                      ? Colors.white.withOpacity(0.92)
                                      : theme.textTheme.bodyMedium?.color
                                            ?.withOpacity(0.9)),
                          ),
                        ),
                      ),
                    );
                  },
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
