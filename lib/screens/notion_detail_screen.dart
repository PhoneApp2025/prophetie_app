import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import '../widgets/blog_card.dart'; // Pfad anpassen je nach Projektstruktur

class NotionDetailScreen extends StatelessWidget {
  final String title;
  final List<dynamic> descriptionRichText;
  final String imageUrl;
  final String category;
  final String author;

  const NotionDetailScreen({
    Key? key,
    required this.title,
    required this.descriptionRichText,
    required this.imageUrl,
    required this.category,
    required this.author,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Blog',
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.black,
          ),
        ),
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 1,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ListView(
          children: [
            // Bild mit stärker abgerundeten Ecken
            if (imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Image.network(
                  Uri.encodeFull(imageUrl),
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 200,
                    color: Colors.grey[300],
                    child: const Icon(
                      Icons.image_not_supported,
                      color: Colors.white,
                      size: 60,
                    ),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // Kategorie unter Bild mit neuem Hintergrund
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                category,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.left,
              ),
            ),

            const SizedBox(height: 12),

            // Titel mit mehr Gewicht und Abstand
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 16),

            // Autor mit neuem Stil
            Text(
              'von $author',
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                fontStyle: FontStyle.italic,
              ),
            ),

            // Beschreibung mit Padding
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 32),
              child: RichText(
                text: TextSpan(
                  children: descriptionRichText.map<TextSpan>((t) {
                    final text = t['text']['content'] ?? '';
                    final annotations = t['annotations'] ?? {};
                    return TextSpan(
                      text: text,
                      style: TextStyle(
                        fontWeight: annotations['bold'] == true
                            ? FontWeight.bold
                            : FontWeight.normal,
                        fontStyle: annotations['italic'] == true
                            ? FontStyle.italic
                            : FontStyle.normal,
                        decoration: annotations['underline'] == true
                            ? TextDecoration.underline
                            : TextDecoration.none,
                        color: _mapNotionColorToFlutterColor(
                          annotations['color'],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            const Text(
              'Ähnliche Beiträge',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),

            FutureBuilder<List<Widget>>(
              future: fetchNotionBlogCards(
                limit: 3,
              ), // Neue Funktion muss angepasst sein
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                } else if (snapshot.hasError || !snapshot.hasData) {
                  return const Text('Keine ähnlichen Beiträge verfügbar.');
                } else {
                  return Column(
                    children: snapshot.data!
                        .map(
                          (card) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: card,
                          ),
                        )
                        .toList(),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _mapNotionColorToFlutterColor(String? color) {
    switch (color) {
      case 'default':
        return Colors.black;
      case 'gray':
      case 'grey':
        return Colors.grey;
      case 'brown':
        return Colors.brown;
      case 'orange':
        return Colors.orange;
      case 'yellow':
        return Colors.yellow.shade700;
      case 'green':
        return Colors.green;
      case 'blue':
        return Colors.blue;
      case 'purple':
        return Colors.purple;
      case 'pink':
        return Colors.pink;
      case 'red':
        return Colors.red;
      default:
        return Colors.black;
    }
  }
}

Future<List<Widget>> fetchNotionBlogCards({int limit = 3}) async {
  // TODO: Ersetze das mit echter Logik oder einem Import
  return [
    BlogCard(
      id: 'demo-id',
      title: 'Beispiel 1',
      description: 'Kurze Beschreibung des Blogbeitrags',
      category: 'Kategorie',
      imageUrl: '',
      author: 'Autor',
      datum: '',
      link: '',
    ),
  ];
}
