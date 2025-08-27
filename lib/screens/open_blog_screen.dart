import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

class _OpenBlogScreenState extends State<OpenBlogScreen> {
  bool _favorite = false;

  Future<void> _openLink() async {
    if (widget.link.isEmpty) return;
    final uri = Uri.tryParse(widget.link);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Konnte Link nicht öffnen.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;
    final double headerHeight = size.height / 3; // exakt 1/3
    const double overlap = 12; // sichtbare, aber sanfte Überlappung

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Fester Header: Bild + Titel (nicht scrollbar)
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: headerHeight + overlap + 8, // slightly more visible overlap
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Bild
                Positioned.fill(
                  child: widget.imageUrl.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: widget.imageUrl,
                          fit: BoxFit.cover,
                          placeholder: (_, __) => Container(
                            color: theme.dividerColor.withOpacity(0.1),
                          ),
                          errorWidget: (_, __, ___) => Container(
                            color: theme.dividerColor.withOpacity(0.1),
                          ),
                        )
                      : Container(color: theme.dividerColor.withOpacity(0.1)),
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
                  left: 20,
                  right: 20,
                  bottom: 45,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.category.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.9),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Text(
                            widget.category,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      if (widget.category.isNotEmpty)
                        const SizedBox(height: 10),
                      Text(
                        widget.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.person,
                            size: 14,
                            color: Colors.white.withOpacity(0.85),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            widget.author,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '·',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            widget.datum,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.85),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ],
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    _RoundIconButton(
                      icon: Icons.arrow_back_ios_new,
                      onTap: () async {
                        await HapticFeedback.selectionClick();
                        if (mounted) Navigator.of(context).pop();
                      },
                    ),
                    const Spacer(),
                    _RoundIconButton(
                      icon: _favorite ? Icons.bookmark : Icons.bookmark_outline,
                      onTap: () async {
                        await HapticFeedback.selectionClick();
                        setState(() => _favorite = !_favorite);
                      },
                    ),
                    const SizedBox(width: 8),
                    _RoundIconButton(
                      icon: Icons.ios_share,
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

          // FIXE Karte, die den unteren Bereich IMMER bedeckt und das Bild leicht überlappt
          Positioned(
            left: 0,
            right: 0,
            top: headerHeight - overlap,
            bottom: 0,
            child: Container(
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
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
                  const SizedBox(height: 6),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: HtmlWidget(
                        (widget.description.isNotEmpty
                                ? widget.description
                                : '<p>Öffne den Artikel, um die vollständigen Inhalte zu lesen.</p>')
                            .trim(),
                        // Basis-Schrift der App übernehmen
                        textStyle: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.42),
                        // Einfache Whitelist für Tags, die wir erwarten
                        customStylesBuilder: (element) {
                          switch (element.localName) {
                            case 'h1':
                              return {
                                'margin': '0 0 10px 0',
                                'font-weight': '800',
                                'font-size': '28px',
                                'line-height': '1.12',
                              };
                            case 'h2':
                              return {
                                'margin': '16px 0 8px 0',
                                'font-weight': '700',
                                'font-size': '22px',
                              };
                            case 'h3':
                              return {
                                'margin': '14px 0 6px 0',
                                'font-weight': '700',
                                'font-size': '18px',
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
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
  final VoidCallback onTap;
  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.30),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _CircleAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            shape: BoxShape.circle,
            border: Border.all(
              color: Theme.of(context).dividerColor.withOpacity(0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Icon(icon, color: _kAccent),
        ),
      ),
    );
  }
}
