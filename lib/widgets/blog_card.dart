import 'package:flutter/material.dart';
import '../screens/open_blog_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/services.dart';

class BlogCard extends StatefulWidget {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String category;
  final String author;
  final String datum;
  final String link;
  final bool isFeatured;
  final bool isResource;

  const BlogCard({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.category,
    required this.author,
    required this.datum,
    required this.link,
    this.isFeatured = false,
    this.isResource = false,
  });

  @override
  State<BlogCard> createState() => _BlogCardState();
}

/// App-weite Bild-Cache-Konfiguration für BlogCard
class _AppImageCache {
  static final CacheManager instance = CacheManager(
    Config(
      'appImageCache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: 'appImageCache'),
      fileService: HttpFileService(),
    ),
  );
}

class _BlogCardState extends State<BlogCard> {
  // UI state for hover/keyboard focus highlighting
  bool _hovering = false;
  void _openBlog() {
    // Subtiles haptisches Feedback auf unterstützten Geräten
    HapticFeedback.selectionClick();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => OpenBlogScreen(
          id: widget.id,
          title: widget.title,
          description: widget.description,
          imageUrl: widget.imageUrl,
          category: widget.category,
          author: widget.author,
          datum: widget.datum,
          link: widget.link,
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // Prefetch: holt Datei, wenn nicht im Cache. Lädt aus Cache, wenn vorhanden.
    _prefetchImage();
  }

  void _prefetchImage() {
    // Verwende eine stabile cacheKey (widget.id), damit signierte URLs keinen neuen Cache erzeugen
    _AppImageCache.instance.getFileFromCache(widget.id).then((cached) async {
      if (cached == null) {
        try {
          await _AppImageCache.instance.downloadFile(
            widget.imageUrl,
            key: widget.id,
          );
        } catch (_) {
          // still graceful fallback
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bool isPhone = MediaQuery.of(context).size.width < 600;

    // Größen/Style
    final bool featured = widget.isFeatured;
    const double radius = 16;
    final double thumbWidth =
        MediaQuery.of(context).size.width * 0.24; // ~24% der Screenbreite

    return Semantics(
      button: true,
      label: '${widget.title} – '
          '${widget.category.isNotEmpty ? widget.category + ', ' : ''}'
          'von ${widget.author}, veröffentlicht am ${widget.datum}. Öffnen',
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        autofocus: false,
        onShowFocusHighlight: (v) => setState(() => _hovering = v || _hovering),
        onShowHoverHighlight: (v) => setState(() => _hovering = v),
        onFocusChange: (_) {},
        shortcuts: const <ShortcutActivator, Intent>{
          // Enter/Space als Aktivierung
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (intent) {
            _openBlog();
            return null;
          }),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovering = true),
          onExit: (_) => setState(() => _hovering = false),
          child: AnimatedScale(
            scale: _hovering ? 1.03 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              onTap: _openBlog,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [theme.cardColor, theme.cardColor.withOpacity(0.92)],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail links: feste Breite, quadratisch
                    SizedBox(
                      width: thumbWidth,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CachedNetworkImage(
                                  imageUrl: widget.imageUrl,
                                  cacheKey: widget.id, // stabile ID statt wechselnder, signierter URLs
                                  cacheManager: _AppImageCache.instance,
                                  fit: BoxFit.cover,
                                  fadeInDuration: const Duration(milliseconds: 150),
                                  fadeOutDuration: const Duration(milliseconds: 150),
                                  useOldImageOnUrlChange: true,
                                  placeholderFadeInDuration: const Duration(milliseconds: 100),
                                  placeholder: (context, url) => Container(
                                    color: theme.dividerColor.withOpacity(0.15),
                                  ),
                                  errorWidget: (context, url, error) => Container(
                                    color: theme.dividerColor.withOpacity(0.15),
                                    child: const Icon(
                                      Icons.image_not_supported,
                                      size: 20,
                                    ),
                                  ),
                                ),
                              ),
                              if (featured)
                                Positioned(
                                  top: 6,
                                  left: 6,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF2C55).withOpacity(0.95),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Text(
                                      'FEATURED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 12),

                    // Text rechts: 3 Zonen ohne Spacer/Expanded im Inneren
                    Expanded(
                      child: SizedBox(
                        height: thumbWidth, // rechte Spalte an Bildhöhe koppeln
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Kategorie oben
                            if (widget.category.isNotEmpty)
                              Text(
                                widget.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.textTheme.bodySmall?.color?.withOpacity(
                                    0.7,
                                  ),
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            else
                              const SizedBox.shrink(),

                            // Titel mittig (dank spaceBetween automatisch in der Mitte)
                            Text(
                              widget.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontSize: featured ? 16 : 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),

                            // Meta unten
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Flexible(
                                    child: Text(
                                      widget.author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        fontSize: isPhone ? 12 : theme.textTheme.bodySmall?.fontSize,
                                        color: theme.textTheme.bodySmall?.color
                                            ?.withOpacity(0.75),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '·',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withOpacity(0.75),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    widget.datum,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.textTheme.bodySmall?.color
                                          ?.withOpacity(0.75),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .trim()
        .split(RegExp(r"\s+"))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
