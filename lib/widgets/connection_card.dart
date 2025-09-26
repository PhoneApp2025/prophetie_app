import 'package:flutter/material.dart';
import '../models/connection_pair.dart';
import '../models/connection_item.dart';
import 'package:intl/intl.dart';
import '../widgets/prophetie_detail_sheet.dart';
import '../widgets/traum_detail_sheet.dart';
import 'dart:math' as math;

class ConnectionCard extends StatelessWidget {
  final ConnectionPair pair;
  const ConnectionCard(this.pair, {super.key});

  static const Color brandAccent = Color(
    0xFFFF2D55,
  ); // App-Accent (helles Rot/Pink)

  String _diffText(DateTime a, DateTime b) {
    final diffDays = b.difference(a).inDays;
    if (diffDays >= 365) {
      final years = diffDays ~/ 365;
      return 'vor $years ${years == 1 ? 'Jahr' : 'Jahren'}';
    } else if (diffDays >= 30) {
      final months = diffDays ~/ 30;
      return 'vor $months ${months == 1 ? 'Monat' : 'Monaten'}';
    } else {
      if (diffDays == 0) return 'heute';
      if (diffDays == 1) return 'gestern';
      return 'vor $diffDays Tagen';
    }
  }

  @override
  Widget build(BuildContext ctx) {
    final bool _isTablet = MediaQuery.of(ctx).size.width > 600;
    final a = pair.first;
    final b = pair.second;
    final sim = pair.similarity;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(ctx).colorScheme.surface,
            Theme.of(ctx).colorScheme.surfaceVariant.withOpacity(0.6),
          ],
        ),
        border: Border.all(
          color: Theme.of(ctx).colorScheme.outlineVariant.withOpacity(0.35),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            spreadRadius: 1,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, _isTablet ? 10 : 12, 16, _isTablet ? 10 : 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 6),

            // Content row: A — connector — B
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: _EntryTile(item: a, onTap: () => _openDetail(ctx, a)),
                ),

                // Connector in der Mitte
                _MatchConnector(sim: sim),

                Expanded(
                  child: _EntryTile(
                    item: b,
                    alignEnd: true,
                    onTap: () => _openDetail(ctx, b),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext ctx, ConnectionItem item) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.25),
      builder: (_) {
        return SafeArea(
          top: false,
          bottom: false,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(ctx).cardColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(20),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: item.type == ItemType.dream
                      ? TraumDetailSheet(traumId: item.id)
                      : ProphetieDetailSheet(prophetieId: item.id),
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
}

class _EntryTile extends StatelessWidget {
  final ConnectionItem item;
  final VoidCallback onTap;
  final bool alignEnd;
  const _EntryTile({
    required this.item,
    required this.onTap,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    final bool _isTablet = MediaQuery.of(context).size.width > 600;
    final icon = item.type == ItemType.dream
        ? Icons.nights_stay_outlined
        : Icons.campaign_outlined;

    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      fontSize: _isTablet ? 18 : theme.textTheme.titleMedium?.fontSize,
    );
    final dateStyle = theme.textTheme.labelMedium?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.6),
      fontSize: _isTablet ? 13 : theme.textTheme.labelMedium?.fontSize,
    );

    final content = Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Align(
          alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
          child: _TypeChip(
            icon: icon,
            label: item.type == ItemType.dream ? 'Traum' : 'Prophetie',
            color: item.type == ItemType.dream
                ? Theme.of(context).colorScheme.primary
                : ConnectionCard.brandAccent,
          ),
        ),
        SizedBox(height: _isTablet ? 10 : 8),
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: titleStyle,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        ),
        SizedBox(height: _isTablet ? 8 : 6),
        Text(
          DateFormat.yMMMd().format(item.timestamp),
          style: dateStyle,
          textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        ),
      ],
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Align(
            alignment: alignEnd ? Alignment.centerRight : Alignment.centerLeft,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _MatchConnector extends StatelessWidget {
  final double? sim;
  const _MatchConnector({this.sim});

  @override
  Widget build(BuildContext context) {
    final dividerColor = Theme.of(context).dividerColor.withOpacity(0.6);
    final accent = ConnectionCard.brandAccent;
    final bool _isTablet = MediaQuery.of(context).size.width > 600;

    // Fallback: kein Similarity-Wert → klassischer Link-Connector
    if (sim == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: SizedBox(
          width: _isTablet ? 64 : 56,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                height: _isTablet ? 8 : 8,
                child: Center(
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Container(
                width: _isTablet ? 32 : 28,
                height: _isTablet ? 32 : 28,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.9),
                  shape: BoxShape.circle,
                  border: Border.all(color: dividerColor, width: 1),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(Icons.link, size: 16),
              ),
              SizedBox(
                height: _isTablet ? 8 : 8,
                child: Center(
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Moderner Mittel-Connector: Ring mit % + Match-Label
    final clamped = sim!.clamp(0.0, 1.0);
    final pct = (clamped * 100).round();
    final value = pct / 100.0;

    final double ringSize = _isTablet ? 64 : 68; // iPad etwas flacher
    final double stroke = _isTablet ? 5 : 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: _isTablet ? 8 : 8,
            child: Center(
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              // Track circle
              CustomPaint(
                size: Size(ringSize, ringSize),
                painter: _ArcPainter(
                  value: 1.0,
                  color: dividerColor.withOpacity(0.22),
                  strokeWidth: stroke,
                  rounded: true,
                  asTrack: true,
                ),
              ),
              // Progress arc
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: value),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOutCubic,
                builder: (context, v, _) {
                  return CustomPaint(
                    size: Size(ringSize, ringSize),
                    painter: _ArcPainter(
                      value: v,
                      color: accent,
                      strokeWidth: stroke,
                      rounded: true,
                    ),
                  );
                },
              ),
              // Center content
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pct%',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: _isTablet ? 16 : 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Match',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: accent,
                          fontSize: _isTablet ? 12 : Theme.of(context).textTheme.labelSmall?.fontSize,
                        ),
                  ),
                ],
              ),
            ],
          ),
          SizedBox(
            height: _isTablet ? 8 : 8,
            child: Center(
              child: Container(
                width: 2,
                decoration: BoxDecoration(
                  color: dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  final double value; // 0..1
  final Color color;
  final double strokeWidth;
  final bool rounded;
  final bool asTrack;
  _ArcPainter({
    required this.value,
    required this.color,
    required this.strokeWidth,
    this.rounded = true,
    this.asTrack = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = rounded ? StrokeCap.round : StrokeCap.butt
      ..color = color;

    final start = -math.pi / 2; // 12 Uhr
    final sweep = (asTrack ? 2 * math.pi : (2 * math.pi * value).clamp(0.0, 2 * math.pi));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      start,
      sweep,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ArcPainter oldDelegate) {
    return oldDelegate.value != value ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.rounded != rounded ||
        oldDelegate.asTrack != asTrack;
  }
}

class _TypeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _TypeChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final bg = color.withOpacity(0.10);
    final border = color.withOpacity(0.25);
    final bool _isTablet = MediaQuery.of(context).size.width > 600;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: _isTablet ? 12 : 10, vertical: _isTablet ? 6 : 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: _isTablet ? 14 : 12, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                  fontSize: _isTablet ? 12 : Theme.of(context).textTheme.labelSmall?.fontSize,
                ),
          ),
        ],
      ),
    );
  }
}
