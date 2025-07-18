import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class TraeumeLexikonScreen extends StatefulWidget {
  const TraeumeLexikonScreen({super.key});

  @override
  _TraeumeLexikonScreenState createState() => _TraeumeLexikonScreenState();
}

class _TraeumeLexikonScreenState extends State<TraeumeLexikonScreen> {
  Map<String, Map<String, String>> lexikon = {};
  bool showDisclaimer = true;

  Future<void> loadLexikonFromAsset() async {
    final jsonString = await rootBundle.loadString(
      'assets/data/traeume_lexikon.json',
    );
    final Map<String, dynamic> jsonMap = json.decode(jsonString);

    final Map<String, Map<String, String>> castedMap = {};
    jsonMap.forEach((category, terms) {
      final Map<String, String> termsMap = {};
      (terms as Map).forEach((termKey, termDesc) {
        termsMap[termKey.toString()] = termDesc.toString();
      });
      castedMap[category.toString()] = termsMap;
    });

    setState(() {
      lexikon = castedMap;
    });
  }

  @override
  void initState() {
    super.initState();
    loadLexikonFromAsset();
  }

  String searchQuery = '';

  @override
  Widget build(BuildContext context) {
    final bool isSearching = searchQuery.trim().isNotEmpty;

    // Alle Begriffe mit Kategorien als Liste für Suche
    final List<_TermWithCategory> allTerms = [];
    lexikon.forEach((category, terms) {
      terms.forEach((term, desc) {
        allTerms.add(
          _TermWithCategory(category: category, term: term, description: desc),
        );
      });
    });

    // Begriffe filtern bei Suche
    final filteredTerms = isSearching
        ? allTerms
              .where(
                (t) => t.term.toLowerCase().contains(searchQuery.toLowerCase()),
              )
              .toList()
        : [];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Träume-Lexikon',
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
      ),
      body: Column(
        children: [
          if (showDisclaimer)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16.0,
                vertical: 8.0,
              ),
              child: Container(
                padding: const EdgeInsets.all(12.0),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 24.0),
                      child: Text(
                        'Hinweis: Dieses Lexikon dient als unterstützende Orientierung. Die Bedeutung von Träumen und Symbolen soll stets im Gebet geprüft werden und ersetzt niemals direktes Reden Gottes.',
                        style: TextStyle(
                          fontSize: 12,
                          color:
                              Theme.of(context).textTheme.bodySmall?.color ??
                              Colors.black87,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            showDisclaimer = false;
                          });
                        },
                        child: Icon(
                          Icons.close,
                          size: 16,
                          color:
                              Theme.of(context).textTheme.bodySmall?.color ??
                              Colors.black87,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 4,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: CupertinoSearchTextField(
                  placeholder: 'Begriff suchen',
                  prefixIcon: Icon(
                    CupertinoIcons.search,
                    color: CupertinoColors.systemGrey,
                  ),
                  backgroundColor: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(8),
                  style: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  placeholderStyle: TextStyle(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white70
                        : Colors.black54,
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value;
                    });
                  },
                ),
              ),
            ),
          ),
          Expanded(
            child: isSearching
                ? filteredTerms.isEmpty
                      ? Center(
                          child: Text(
                            'Kein Begriff gefunden.',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.grey,
                            ),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filteredTerms.length,
                          itemBuilder: (context, index) {
                            final item = filteredTerms[index];
                            return ExpansionTile(
                              title: Text(item.term),
                              subtitle: Text(
                                'Kategorie: ${item.category}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.all(16.0),
                                  child: Text(item.description),
                                ),
                              ],
                            );
                          },
                        )
                : ListView(
                    children: lexikon.keys.map((category) {
                      final terms = lexikon[category]!;
                      return ExpansionTile(
                        title: Text(
                          category,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color:
                                Theme.of(context).textTheme.bodySmall?.color ??
                                Colors.black87,
                          ),
                        ),
                        children: terms.entries.map((entry) {
                          return ExpansionTile(
                            title: Text(entry.key),
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(entry.value),
                              ),
                            ],
                          );
                        }).toList(),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }
}

class _TermWithCategory {
  final String category;
  final String term;
  final String description;

  _TermWithCategory({
    required this.category,
    required this.term,
    required this.description,
  });
}
