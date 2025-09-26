import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:prophetie_app/widgets/blog_card.dart';
import 'package:prophetie_app/services/notion_service.dart';

class SavedFavoritesScreen extends StatefulWidget {
  const SavedFavoritesScreen({super.key});

  @override
  State<SavedFavoritesScreen> createState() => _SavedFavoritesScreenState();
}

class _SavedFavoritesScreenState extends State<SavedFavoritesScreen> {
  final List<String> _categories = ['Blog', 'Prophetie', 'Träume'];
  int _selectedIndex = 0;
  List<Map<String, dynamic>> _favorites = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _favorites = [];
        _isLoading = false;
      });
      return;
    }

    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('favorites')
        .where('isFavorited', isEqualTo: true)
        .get();

    final favs = snapshot.docs.map((doc) {
      final data = doc.data();
      return {
        'id': data['pageId'],
        'category': data['kategorie'] ?? 'Unbekannt',
        'favorisiertAm': data['favorisiertAm'],
      };
    }).toList();

    setState(() {
      _favorites = favs;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Gespeichert")),
      body: Column(
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Theme.of(context).dividerColor),
              ),
              child: Stack(
                children: [
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 300),
                    alignment: Alignment(
                      (_selectedIndex - 1) *
                          1.0, // maps 0,1,2 to -1.0, 0.0, 1.0
                      0,
                    ),
                    child: FractionallySizedBox(
                      widthFactor: 1 / _categories.length,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    children: List.generate(_categories.length, (index) {
                      final isSelected = index == _selectedIndex;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedIndex = index;
                            });
                          },
                          child: Center(
                            child: Text(
                              _categories[index],
                              style: TextStyle(
                                color: isSelected ? Colors.white : Colors.black,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Builder(
                    builder: (context) {
                      final selectedCategory = _categories[_selectedIndex];
                      final filteredFavorites = _favorites
                          .where((fav) => fav['category'] == selectedCategory)
                          .map((fav) => fav['id'])
                          .toList();

                      return FutureBuilder<List<Widget>>(
                        future: NotionService.fetchBlogCards(context).then((
                          allCards,
                        ) {
                          final filteredCards = allCards.where((card) {
                            if (card is BlogCard) {
                              final match = filteredFavorites.contains(card.id);
                              debugPrint('Card ID: ${card.id}, Match: $match');
                              return match;
                            }
                            return false;
                          }).toList();
                          debugPrint(
                            'Filtered Cards Count: ${filteredCards.length}',
                          );
                          return filteredCards;
                        }),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState ==
                              ConnectionState.waiting) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          } else if (snapshot.hasError) {
                            return Text('Fehler beim Laden: ${snapshot.error}');
                          } else if (!snapshot.hasData ||
                              snapshot.data!.isEmpty) {
                            return const Text('Keine gespeicherten Beiträge.');
                          } else {
                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(children: snapshot.data!),
                            );
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
