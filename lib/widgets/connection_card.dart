import 'package:flutter/material.dart';
import '../models/connection_pair.dart';
import '../models/connection_item.dart';
import 'package:intl/intl.dart';
import '../widgets/prophetie_detail_sheet.dart';
import '../widgets/traum_detail_sheet.dart';

class ConnectionCard extends StatelessWidget {
  final ConnectionPair pair;
  const ConnectionCard(this.pair, {super.key});

  @override
  Widget build(BuildContext ctx) {
    final a = pair.first;
    final b = pair.second;
    final firstType = a.type == ItemType.dream ? 'Traum' : 'Prophetie';
    final secondType = b.type == ItemType.dream ? 'Traum' : 'Prophetie';
    final diffDays = b.timestamp.difference(a.timestamp).inDays;
    String diffText;
    if (diffDays >= 365) {
      final years = diffDays ~/ 365;
      diffText = 'vor $years ${years == 1 ? 'Jahr' : 'Jahren'}';
    } else if (diffDays >= 30) {
      final months = diffDays ~/ 30;
      diffText = 'vor $months ${months == 1 ? 'Monat' : 'Monaten'}';
    } else {
      diffText = 'vor $diffDays ${diffDays == 1 ? 'Tag' : 'Tagen'}';
    }
    final contextText =
        '$firstType $diffText erhalten – $secondType bestätigt es jetzt.';
    return Card(
      color: Theme.of(ctx).cardColor,
      margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      elevation: 0.5,
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Context
            Text(
              contextText,
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 12),
            // Items row
            Row(
              children: [
                // First item
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      showModalBottomSheet(
                        context: ctx,
                        isScrollControlled: true,
                        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
                        builder: (_) => a.type == ItemType.dream
                            ? TraumDetailSheet(traumId: a.id)
                            : ProphetieDetailSheet(prophetieId: a.id),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          a.type == ItemType.dream
                              ? Icons.nights_stay_outlined
                              : Icons.campaign_outlined,
                          size: 28,
                          color: Theme.of(
                            ctx,
                          ).iconTheme.color?.withOpacity(0.7),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          a.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(ctx).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat.yMMMd().format(a.timestamp),
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  height: 54,
                  margin: const EdgeInsets.symmetric(horizontal: 16),
                  color: Theme.of(ctx).dividerColor,
                ),
                // Second item
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      showModalBottomSheet(
                        context: ctx,
                        isScrollControlled: true,
                        backgroundColor: Theme.of(ctx).scaffoldBackgroundColor,
                        builder: (_) => b.type == ItemType.dream
                            ? TraumDetailSheet(traumId: b.id)
                            : ProphetieDetailSheet(prophetieId: b.id),
                      );
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Icon(
                          b.type == ItemType.dream
                              ? Icons.nights_stay_outlined
                              : Icons.campaign_outlined,
                          size: 28,
                          color: Theme.of(
                            ctx,
                          ).iconTheme.color?.withOpacity(0.7),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(ctx).textTheme.bodyLarge,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          DateFormat.yMMMd().format(b.timestamp),
                          style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Relation summary
            Text(
              pair.relationSummary,
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
