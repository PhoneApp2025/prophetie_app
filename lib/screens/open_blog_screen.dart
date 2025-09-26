import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart' as widgets;
import '../main.dart' show Handlebar;
import 'dart:async';
import 'dart:ui' show lerpDouble;
import 'dart:math' as math;

const Color _kAccent = Color(0xFFFF2C55);

class OpenBlogScreen extends StatefulWidget {
  final String id;
  final String title;
  final String description;
  final String imageUrl;
  final String category;
  final String author;
  final String datum; // dd.MM.yyyy
  final String link;

  const OpenBlogScreen({
    super.key,
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.category,
    required this.author,
    required this.datum,
    required this.link,
  });

  @override
  State<OpenBlogScreen> createState() => _OpenBlogScreenState();
}

class _OpenBlogScreenState extends State<OpenBlogScreen> with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  bool _favorite = false;

  Timer? _sbTimer; // scrollbar fade-out timer

  double _sbOpacity = 0.0; // 0..1 visible amount for minimal scrollbar
  bool _sbDragging = false;

  // Manual sheet (card) position – independent from scroll
  double? _cardTop; // current top of the content card (null => lazy init)
  late final AnimationController _sheetAnim;
  Animation<double>? _sheetTween;
  bool _sheetAnimating = false;
  double _dragStartTop = 0.0;
  double _dragStartDy = 0.0; // global dy at drag start
  bool _sheetDragging = false; // suppress scroll-driven UI updates while dragging the sheet

  // Passt die Titel-Schrift so an, dass sie innerhalb max. [maxLines] Zeilen bleibt
  double _fitTitleFont({
    required String text,
    required TextStyle base,
    required double maxWidth,
    int maxLines = 2,
    double minSize = 18,
    double maxSize = 32,
  }) {
    double lo = minSize, hi = maxSize, best = minSize;
    final span = (double size) => TextSpan(text: text, style: base.copyWith(fontSize: size));
    for (int i = 0; i < 8; i++) {
      final mid = (lo + hi) / 2;
      final tp = TextPainter(
        text: span(mid),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      final didOverflow = tp.didExceedMaxLines;
      if (!didOverflow) {
        best = mid; // passt, größer versuchen
        lo = mid;
      } else {
        hi = mid; // zu groß, kleiner
      }
    }
    return best.clamp(minSize, maxSize);
  }

  // Variante mit Höhenlimit: passt Schrift so an, dass innerhalb max. [maxLines] UND [maxHeight] bleibt
  double _fitTitleFontToBox({
    required String text,
    required TextStyle base,
    required double maxWidth,
    required double maxHeight,
    int maxLines = 3,
    double minSize = 16,
    double maxSize = 32,
  }) {
    double lo = minSize, hi = maxSize, best = minSize;
    final span = (double size) => TextSpan(text: text, style: base.copyWith(fontSize: size));
    for (int i = 0; i < 9; i++) {
      final mid = (lo + hi) / 2;
      final tp = TextPainter(
        text: span(mid),
        textDirection: TextDirection.ltr,
        maxLines: maxLines,
      )..layout(maxWidth: maxWidth);
      final overflowLines = tp.didExceedMaxLines;
      final overflowHeight = tp.size.height > maxHeight;
      if (!overflowLines && !overflowHeight) {
        best = mid; // passt, größer versuchen
        lo = mid;
      } else {
        hi = mid; // zu groß
      }
    }
    return best.clamp(minSize, maxSize);
  }

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_sheetDragging) return; // ignore scroll listener during sheet drag
      // show thumb while scrolling
      _sbTimer?.cancel();
      if (_sbOpacity != 1.0 && mounted) {
        setState(() => _sbOpacity = 1.0);
      } else if (!mounted) {
        return;
      }
      // schedule fade out after short idle
      _sbTimer = Timer(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() => _sbOpacity = 0.0);
      });
      // also rebuild for position/size updates
      if (mounted) setState(() {});
    });
    _sheetAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _sheetAnim.addListener(() {
      final t = _sheetTween;
      if (t != null) {
        final v = t.value;
        if ((_cardTop ?? v) != v && mounted) {
          setState(() => _cardTop = v);
        }
      }
    });
    _sheetAnim.addStatusListener((st) {
      if (st == AnimationStatus.completed || st == AnimationStatus.dismissed) {
        _sheetAnimating = false;
        _sheetTween = null;
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.imageUrl.isNotEmpty) {
      // Bild vorab in den Speicher laden, damit es ohne Fader sofort erscheint
      precacheImage(CachedNetworkImageProvider(widget.imageUrl), context);
    }
  }

  @override
  void dispose() {
    _sbTimer?.cancel();
    _scroll.dispose();
    _sheetAnim.dispose();
    super.dispose();
  }

  Future<void> _openLink() async {
    if (widget.link.isEmpty) return;
    final uri = Uri.tryParse(widget.link);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: widget.link));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte Link nicht öffnen. URL in die Zwischenablage kopiert.')),
      );
    }
  }

  void _animateCardTo({
    required double target,
    required double collapsedTop,
    required double initialTop,
  }) {
    final from = (_cardTop ?? initialTop).clamp(collapsedTop, initialTop);
    final to = target.clamp(collapsedTop, initialTop);
    if ((from - to).abs() < 0.5) {
      setState(() => _cardTop = to);
      return;
    }
    final tween = Tween<double>(begin: from, end: to).animate(CurvedAnimation(
      parent: _sheetAnim,
      curve: Curves.easeOutCubic,
    ));
    _sheetTween = tween;
    _sheetAnimating = true;
    _sheetAnim
      ..reset()
      ..forward();
  }

  void _snapToNearest({
    required double collapsedTop,
    required double initialTop,
  }) {
    final current = (_cardTop ?? initialTop).clamp(collapsedTop, initialTop);
    final mid = (collapsedTop + initialTop) / 2;
    final target = (current <= mid) ? collapsedTop : initialTop;
    _animateCardTo(target: target, collapsedTop: collapsedTop, initialTop: initialTop);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    // Responsive Helpers (Prozent statt fixe Pixel)
    final w = size.width;
    final h = size.height;
    double wp(double p) => w * p; // width percentage
    double hp(double p) => h * p; // height percentage
    double clampD(double v, double min, double max) => v < min ? min : (v > max ? max : v);

    // Header-Höhe als Prozent vom Screen
    final double headerHeight = h * 0.33; // 33% der Höhe
    final double overlap = clampD(hp(0.015), 8, 20); // sanfte Überlappung, responsiv

    // Safe-Zone unter der Top-Leiste, damit Kategorie/Titel nie in Buttons läuft
    final double topInset = MediaQuery.of(context).padding.top;
    final double hpad = clampD(wp(0.05), 12, 24); // horizontales Padding ~5%

    // Topbar-Höhe = responsive Button-Größe
    final double toolbarHeight = clampD(w * 0.10, 36, 48);
    final double topBarVerticalPadding = clampD(hp(0.01), 6, 12);
    final double contentTopGap = clampD(hp(0.015), 8, 16);
    final double headerSafeTop = topInset + topBarVerticalPadding + toolbarHeight + contentTopGap;

    // Typografie responsiv über Breite
    double clampFont(double v, double min, double max) => v < min ? min : (v > max ? max : v);
    final double catFont = clampFont(w * 0.032, 10, 14);    // ~12 @ 375px
    final double titleFont = clampFont(w * 0.074, 20, 32);  // ~28 @ 375px
    final double metaFont = clampFont(w * 0.034, 11, 14);   // ~13 @ 375px

    // Unterer Abstand im Header, damit Text nicht zu dicht am Bildrand klebt
    final double bottomGap = clampD(hp(0.055), 32, 60);

    final double availableTitleWidth = w - (2 * hpad);
    final TextStyle baseTitleStyle = const TextStyle(
      fontWeight: FontWeight.w800,
      color: Colors.white,
      height: 1.12,
    );

    // verfügbare Höhe für den Titel innerhalb des Header-Textbereichs berechnen
    final bool hasCategory = widget.category.isNotEmpty;
    final double catPaddingV = clampD(hp(0.007), 4, 10);
    final double catHeight = hasCategory ? (catPaddingV * 2 + catFont) : 0.0;
    final double gapCatTitle = hasCategory ? 10.0 : 0.0;
    final double gapTitleMeta = clampD(hp(0.008), 4, 10);
    final double metaRowHeight = (metaFont + 6); // Icon + Text, konservativ
    final double headerTextAreaHeight = (headerHeight + overlap + 8) - headerSafeTop - bottomGap;
    final double titleMaxHeight = headerTextAreaHeight - catHeight - gapCatTitle - gapTitleMeta - metaRowHeight;

    final double fittedTitleFont = _fitTitleFontToBox(
      text: widget.title,
      base: baseTitleStyle,
      maxWidth: availableTitleWidth,
      maxHeight: titleMaxHeight.clamp(28.0, headerTextAreaHeight),
      maxLines: 3,
      minSize: 16,
      maxSize: titleFont,
    );

    // Collapse-Animation Werte berechnen
    final ScrollPosition? _pos = _scroll.hasClients ? _scroll.position : null;
    final double _offset = _pos?.pixels ?? 0.0;
    final double _collapseThreshold = (headerHeight - overlap) - (topInset + topBarVerticalPadding + toolbarHeight + 8);
    final double _collapseT = (_offset / _collapseThreshold).clamp(0.0, 1.0);

    // Manual sheet positions (independent from scroll)
    final double collapsedTop = topInset + topBarVerticalPadding + toolbarHeight + 8; // docked under topbar
    final double initialTop = (headerHeight - overlap); // fully down (touching header bottom)
    _cardTop ??= initialTop; // lazy init
    // progress 0..1 for corner rounding based on card drag position
    final double sheetT = ((initialTop - (_cardTop ?? initialTop)) / (initialTop - collapsedTop)).clamp(0.0, 1.0);

    // Enforce snap when idle (no drag, no animation)
    if (!_sheetDragging && !_sheetAnimating && _cardTop != null) {
      final current = _cardTop!.clamp(collapsedTop, initialTop);
      final isAtCollapsed = (current - collapsedTop).abs() < 0.5;
      final isAtInitial = (current - initialTop).abs() < 0.5;
      if (!isAtCollapsed && !isAtInitial) {
        // Always animate to the nearest state to avoid resting mid-way
        final mid = (collapsedTop + initialTop) / 2;
        final target = (current <= mid) ? collapsedTop : initialTop;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_sheetAnimating && !_sheetDragging) {
            _animateCardTo(
              target: target,
              collapsedTop: collapsedTop,
              initialTop: initialTop,
            );
          }
        });
      }
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Fester Header: Bild + Titel (nicht scrollbar)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: headerHeight + overlap + 8,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Bild
                Positioned.fill(
                  child: Hero(
                    tag: 'blog_hero_${widget.id}',
                    child: widget.imageUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: widget.imageUrl,
                            fit: BoxFit.cover,
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            useOldImageOnUrlChange: true,
                            placeholder: (_, __) => const SizedBox.shrink(),
                            errorWidget: (_, __, ___) => Container(
                              color: theme.dividerColor.withOpacity(0.1),
                              child: const Icon(Icons.broken_image_outlined, size: 20),
                            ),
                          )
                        : Container(color: theme.dividerColor.withOpacity(0.1)),
                  ),
                ),
                // Gradient-Overlay
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.05),
                          Colors.black.withOpacity(0.35),
                          Colors.black.withOpacity(0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                // Kategorie, Titel, Autor/Datum
                Positioned(
                  left: hpad,
                  right: hpad,
                  top: headerSafeTop,
                  bottom: bottomGap,
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.category.isNotEmpty)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: clampD(wp(0.025), 8, 14),
                              vertical: clampD(hp(0.007), 4, 10),
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(clampD(wp(0.04), 6, 12)),
                            ),
                            child: Text(
                              widget.category,
                              style: TextStyle(
                                fontSize: catFont,
                                fontWeight: FontWeight.w700,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        if (widget.category.isNotEmpty)
                          const SizedBox(height: 10),
                        Expanded(
                          child: Text(
                            widget.title,
                            maxLines: 3,
                            softWrap: true,
                            overflow: TextOverflow.clip,
                            style: baseTitleStyle.copyWith(fontSize: fittedTitleFont),
                          ),
                        ),
                        SizedBox(height: clampD(hp(0.008), 4, 10)),
                        Row(
                          children: [
                            Icon(
                              Icons.person,
                              size: metaFont + 1,
                              color: Colors.white.withOpacity(0.85),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              widget.author,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: metaFont,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text('·', style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: metaFont)),
                            const SizedBox(width: 6),
                            Text(
                              widget.datum,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.85),
                                fontSize: metaFont,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Obere, fixe Button-Leiste (Zurück / Bookmark / Teilen)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: SizedBox(
                  height: toolbarHeight,
                  child: Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.arrow_back_ios_new,
                        tooltip: 'Zurück',
                        semanticLabel: 'Zurück',
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          if (mounted) Navigator.of(context).pop();
                        },
                      ),
                      const Spacer(),
                      _RoundIconButton(
                        icon: _favorite ? Icons.bookmark : Icons.bookmark_outline,
                        tooltip: _favorite ? 'Lesezeichen entfernen' : 'Lesezeichen setzen',
                        semanticLabel: _favorite ? 'Lesezeichen entfernen' : 'Lesezeichen setzen',
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          setState(() => _favorite = !_favorite);
                        },
                      ),
                      const SizedBox(width: 8),
                      _RoundIconButton(
                        icon: Icons.ios_share,
                        tooltip: 'Im Browser öffnen',
                        semanticLabel: 'Im Browser öffnen',
                        onTap: () async {
                          await HapticFeedback.selectionClick();
                          _openLink();
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Content-Karte: MANUELL per Handlebar – unabhängig vom Scroll der Inhalte
          Positioned(
            left: 0,
            right: 0,
            top: (() {
              // clamp top each build in case of rotation/resize
              final v = (_cardTop ?? initialTop).clamp(collapsedTop, initialTop);
              if (v != _cardTop) _cardTop = v;
              return v;
            })(),
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(lerpDouble(24, 0, sheetT)!),
                  topRight: Radius.circular(lerpDouble(24, 0, sheetT)!),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handlebar: thin look, large hit area; drives manual expand/collapse
                  Center(
                    child: Listener(
                      onPointerUp: (_) {
                        if (_sheetDragging) {
                          _sheetDragging = false;
                          _snapToNearest(collapsedTop: collapsedTop, initialTop: initialTop);
                        }
                      },
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onVerticalDragStart: (details) {
                          _sheetAnim.stop();
                          _sheetTween = null;
                          _sheetAnimating = false;
                          _dragStartTop = _cardTop ?? initialTop;
                          _dragStartDy = details.globalPosition.dy;
                          _sheetDragging = true;
                        },
                        onVerticalDragUpdate: (details) {
                          final dyFromStart = details.globalPosition.dy - _dragStartDy;
                          final next = (_dragStartTop + dyFromStart).clamp(collapsedTop, initialTop);
                          if (next != _cardTop && mounted) {
                            setState(() => _cardTop = next.toDouble());
                          }
                        },
                        onVerticalDragEnd: (details) {
                          _sheetDragging = false;
                          final vy = details.primaryVelocity ?? 0.0; // px/s (+ down, - up)
                          if (vy.abs() > 120) {
                            _animateCardTo(
                              target: vy < 0 ? collapsedTop : initialTop,
                              collapsedTop: collapsedTop,
                              initialTop: initialTop,
                            );
                          } else {
                            _snapToNearest(collapsedTop: collapsedTop, initialTop: initialTop);
                          }
                        },
                        onVerticalDragCancel: () {
                          _sheetDragging = false;
                          _snapToNearest(collapsedTop: collapsedTop, initialTop: initialTop);
                        },
                        child: const Handlebar(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),

                  // Der eigentliche Text – Scrollen wird über NotificationListener gegated
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final hasClients = _scroll.hasClients;
                        final position = hasClients ? _scroll.position : null;
                        final viewport = hasClients ? position!.extentInside : constraints.maxHeight;
                        final maxScroll = hasClients ? position!.maxScrollExtent : 0.0;
                        final offset = hasClients ? position!.pixels : 0.0;

                        final trackPaddingV = clampD(hp(0.01), 6, 10);
                        final trackWidth = 2.0;
                        final trackHeight = constraints.maxHeight - (trackPaddingV * 2);

                        final visibleFraction = hasClients
                            ? (viewport / (maxScroll + viewport)).clamp(0.0, 1.0)
                            : 1.0;
                        final thumbMin = 24.0;
                        final thumbHeight = (trackHeight * visibleFraction).clamp(thumbMin, trackHeight);
                        final thumbTop = (hasClients && maxScroll > 0)
                            ? (offset / maxScroll) * (trackHeight - thumbHeight)
                            : 0.0;

                        final double collapsedTop = topInset + topBarVerticalPadding + toolbarHeight + 8;
                        final double initialTop = (headerHeight - overlap);

                        return Stack(
                          children: [
                            NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                return false; // content scroll is independent
                              },
                              child: SingleChildScrollView(
                                controller: _scroll,
                                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                                padding: EdgeInsets.fromLTRB(
                                  hpad,
                                  clampD(hp(0.012), 8, 14),
                                  hpad,
                                  0,
                                ),
                                child: HtmlWidget(
                                  (widget.description.isNotEmpty
                                          ? widget.description
                                          : '<p>Öffne den Artikel, um die vollständigen Inhalte zu lesen.</p>')
                                      .trim(),
                                  textStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.42),
                                  customStylesBuilder: (element) {
                                    switch (element.localName) {
                                      case 'h1':
                                        return {
                                          'margin': '0 0 10px 0',
                                          'font-weight': '800',
                                          'font-size': '23px',
                                          'line-height': '1.12',
                                        };
                                      case 'h2':
                                        return {
                                          'margin': '16px 0 8px 0',
                                          'font-weight': '700',
                                          'font-size': '20px',
                                        };
                                      case 'h3':
                                        return {
                                          'margin': '14px 0 6px 0',
                                          'font-weight': '700',
                                          'font-size': '16px',
                                        };
                                      case 'p':
                                        return {'margin': '0 0 10px 0'};
                                      case 'ul':
                                      case 'ol':
                                        return {'margin': '6px 0 10px 18px'};
                                    }
                                    return null;
                                  },
                                ),
                              ),
                            ),
                            // Minimalistische Scroll-Anzeige rechts (interaktiv)
                            Positioned(
                              right: clampD(wp(0.01), 4, 8),
                              top: trackPaddingV,
                              bottom: trackPaddingV,
                              child: GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTapDown: (details) {
                                  if (!(hasClients && maxScroll > 0)) return;
                                  _sbTimer?.cancel();
                                  setState(() { _sbOpacity = 1.0; _sbDragging = true; });
                                  final localY = details.localPosition.dy;
                                  final clamped = (localY - (thumbHeight / 2)).clamp(0.0, trackHeight - thumbHeight);
                                  final ratio = trackHeight - thumbHeight == 0 ? 0.0 : (clamped / (trackHeight - thumbHeight));
                                  final target = ratio * maxScroll;
                                  _scroll.jumpTo(target);
                                },
                                onVerticalDragStart: (_) {
                                  if (!(hasClients && maxScroll > 0)) return;
                                  _sbTimer?.cancel();
                                  setState(() { _sbOpacity = 1.0; _sbDragging = true; });
                                },
                                onVerticalDragUpdate: (details) {
                                  if (!(hasClients && maxScroll > 0)) return;
                                  final dy = details.localPosition.dy;
                                  final clamped = (dy - (thumbHeight / 2)).clamp(0.0, trackHeight - thumbHeight);
                                  final ratio = trackHeight - thumbHeight == 0 ? 0.0 : (clamped / (trackHeight - thumbHeight));
                                  final target = ratio * maxScroll;
                                  _scroll.jumpTo(target);
                                },
                                onVerticalDragEnd: (_) {
                                  setState(() { _sbDragging = false; });
                                  _sbTimer?.cancel();
                                  _sbTimer = Timer(const Duration(milliseconds: 600), () {
                                    if (!mounted) return;
                                    setState(() => _sbOpacity = 0.0);
                                  });
                                },
                                onTapUp: (_) {
                                  setState(() { _sbDragging = false; });
                                  _sbTimer?.cancel();
                                  _sbTimer = Timer(const Duration(milliseconds: 600), () {
                                    if (!mounted) return;
                                    setState(() => _sbOpacity = 0.0);
                                  });
                                },
                                child: AnimatedOpacity(
                                  opacity: (hasClients && maxScroll > 0) ? _sbOpacity : 0.0,
                                  duration: const Duration(milliseconds: 220),
                                  curve: Curves.easeOut,
                                  child: Container(
                                    width: trackWidth + (_sbDragging ? 6.0 : 0.0),
                                    decoration: BoxDecoration(
                                      color: theme.dividerColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                    child: Stack(
                                      children: [
                                        Positioned(
                                          top: thumbTop,
                                          child: Container(
                                            width: trackWidth + (_sbDragging ? 6.0 : 0.0),
                                            height: thumbHeight,
                                            decoration: BoxDecoration(
                                              color: Colors.black.withOpacity(_sbDragging ? 0.55 : 0.35),
                                              borderRadius: BorderRadius.circular(2),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      hpad,
                      clampD(hp(0.015), 8, 16),
                      hpad,
                      clampD(hp(0.03), 16, 28),
                    ),
                    child: Row(
                      children: [
                        if (widget.link.isNotEmpty)
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _openLink,
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Im Browser öffnen'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kAccent,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  vertical: clampD(hp(0.016), 10, 16),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(clampD(wp(0.03), 10, 16)),
                                ),
                                elevation: 0,
                              ),
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
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final String? tooltip;
  final String? semanticLabel;
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap, this.tooltip, this.semanticLabel});

  @override
  Widget build(BuildContext context) {
    double clampD(double v, double min, double max) => v < min ? min : (v > max ? max : v);
    final w = MediaQuery.of(context).size.width;
    final double btnSize = clampD(w * 0.10, 36, 48);
    final double iconSize = clampD(btnSize * 0.45, 16, 22);
    final double splashRadius = (btnSize / 2) + 4;

    final btn = InkResponse(
      onTap: onTap,
      radius: splashRadius,
      child: Container(
        width: btnSize,
        height: btnSize,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.30),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(icon, size: iconSize, color: Colors.white),
      ),
    );

    return Semantics(
      button: true,
      label: semanticLabel ?? tooltip ?? '',
      child: tooltip != null ? Tooltip(message: tooltip!, child: btn) : btn,
    );
  }
}
