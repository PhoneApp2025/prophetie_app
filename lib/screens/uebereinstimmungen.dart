import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:prophetie_app/models/connection_pair.dart';
import 'package:prophetie_app/services/connection_service.dart';
import 'package:prophetie_app/widgets/connection_card.dart';
import 'package:prophetie_app/main.dart';

class UebereinstimmungenScreen extends StatefulWidget {
  const UebereinstimmungenScreen({super.key});

  @override
  State<UebereinstimmungenScreen> createState() =>
      _UebereinstimmungenScreenState();
}

class _UebereinstimmungenScreenState extends State<UebereinstimmungenScreen> {
  String _query = '';
  String _sort = 'Neueste'; // Optionen: Neueste, Älteste

  late Future<List<ConnectionPair>> _future;

  String _pairSearchText(ConnectionPair p) {
    final parts = <String>[];
    final d = p as dynamic;

    void addStr(Object? v) {
      if (v == null) return;
      final s = v.toString().trim();
      if (s.isNotEmpty) parts.add(s);
    }

    // Pair-level fields
    try {
      addStr(d.relationSummary);
    } catch (_) {}

    // First/Second items (ConnectionItem)
    dynamic first;
    dynamic second;
    try {
      first = d.first;
    } catch (_) {}
    try {
      second = d.second;
    } catch (_) {}

    void fromItem(dynamic it) {
      if (it == null) return;
      try {
        addStr(it.title);
      } catch (_) {}
      try {
        addStr(it.text);
      } catch (_) {}
      try {
        addStr(it.type);
      } catch (_) {}
    }

    fromItem(first);
    fromItem(second);

    // Fallbacks for saved pair snapshot-style fields
    try {
      addStr(d.firstTitle);
    } catch (_) {}
    try {
      addStr(d.secondTitle);
    } catch (_) {}

    return parts.join(' ').toLowerCase();
  }

  DateTime _pairDate(ConnectionPair p) {
    final d = p as dynamic;
    try {
      final second = d.second;
      if (second != null && second.timestamp is DateTime) {
        return second.timestamp as DateTime;
      }
    } catch (_) {}
    try {
      final first = d.first;
      if (first != null && first.timestamp is DateTime) {
        return first.timestamp as DateTime;
      }
    } catch (_) {}
    // Pair-level timestamps as fallback
    try {
      final t = d.createdAt as DateTime?;
      if (t != null) return t;
    } catch (_) {}
    try {
      final t = d.updatedAt as DateTime?;
      if (t != null) return t;
    } catch (_) {}
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  @override
  void initState() {
    super.initState();
    _future = ConnectionService.fetchConnectionsAll();
  }

  Future<void> _refresh() async {
    await HapticFeedback.selectionClick();
    setState(() {
      _future = ConnectionService.fetchConnectionsAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleColor =
        Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Übereinstimmungen',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color:
                Theme.of(context).textTheme.titleLarge?.color ?? Colors.black,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        iconTheme: IconThemeData(color: Theme.of(context).iconTheme.color),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: TextField(
                      onChanged: (v) =>
                          setState(() => _query = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Suchen…',
                        prefixIcon: const Icon(Icons.search),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 36,
                  child: PopupMenuButton<String>(
                    onSelected: (v) {
                      setState(() => _sort = v);
                      HapticFeedback.selectionClick();
                    },
                    position: PopupMenuPosition.under,
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'Neueste',
                        child: Row(
                          children: [
                            if (_sort == 'Neueste')
                              const Icon(Icons.check, size: 18),
                            if (_sort == 'Neueste') const SizedBox(width: 8),
                            const Text('Neueste'),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'Älteste',
                        child: Row(
                          children: [
                            if (_sort == 'Älteste')
                              const Icon(Icons.check, size: 18),
                            if (_sort == 'Älteste') const SizedBox(width: 8),
                            const Text('Älteste'),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.25),
                        ),
                      ),
                      child: const Icon(Icons.filter_list_rounded, size: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: InkWell(
                    onTap: () async {
                      await HapticFeedback.selectionClick();
                      if (!context.mounted) return;
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text(
                            'Alle Übereinstimmungen neu berechnen?',
                          ),
                          content: const Text(
                            'Alte, nicht mehr passende Verbindungen werden gelöscht.',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(context).pop(false),
                              child: const Text('Abbrechen'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Starten'),
                            ),
                          ],
                        ),
                      );
                      if (ok != true) return;

                      if (mounted) {
                        showFlushbar('Berechnung gestartet…');
                      }
                      try {
                        final count =
                            await ConnectionService.rebuildAllConnections();
                        if (mounted) {
                          showFlushbar(
                            'Fertig. ${count.toString()} Übereinstimmungen.',
                          );
                          setState(() {
                            _future = ConnectionService.fetchConnectionsAll();
                          });
                        }
                      } catch (e) {
                        if (mounted) {
                          showFlushbar('Fehler: ${e.toString()}');
                        }
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).dividerColor.withOpacity(0.25),
                        ),
                      ),
                      child: const Icon(Icons.autorenew_rounded, size: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: FutureBuilder<List<ConnectionPair>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CupertinoActivityIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Fehler beim Laden: ${snap.error}'),
              ),
            );
          }
          final data = snap.data ?? [];
          var list = List<ConnectionPair>.from(data);
          if (_query.isNotEmpty) {
            list = list
                .where((p) => _pairSearchText(p).contains(_query))
                .toList();
          }
          list.sort(
            (a, b) => _pairDate(b).compareTo(_pairDate(a)),
          ); // default Neueste
          if (_sort == 'Älteste') {
            list = list.reversed.toList();
          }

          return CustomScrollView(
            slivers: [
              CupertinoSliverRefreshControl(onRefresh: _refresh),
              if (list.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.connect_without_contact,
                          size: 72,
                          color: Theme.of(context).disabledColor,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Noch keine Übereinstimmungen',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color:
                                Theme.of(context).textTheme.bodyLarge?.color ??
                                Colors.black,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Sobald genug Prophetien und Träume vorhanden sind, siehst du hier alle passenden Verbindungen.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(15, 14, 15, 24),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final pair = list[index];
                      return ConnectionCard(pair);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}