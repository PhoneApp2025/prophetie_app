import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../widgets/blog_card.dart';
import '../screens/notion_detail_screen.dart';

class NotionService {
  static Future<List<Widget>> fetchBlogCards(BuildContext context) async {
    const databaseId = '212017fc7cf78002be6be94fa96763bc';
    const apiKey = 'ntn_So402423031xfNuvkCPyaUx6ZNajgujh375sRLmwa09aqF';
    const url = 'https://api.notion.com/v1/databases/$databaseId/query';

    final response = await http.post(
      Uri.parse(url),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Notion-Version': '2022-06-28',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({}),
    );

    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      final results = json['results'] as List;

      return results.map((page) {
        final properties = page['properties'] ?? {};
        final title =
            (properties['Titel']?['title'] as List?)?.firstWhere(
              (t) => t['text'] != null,
              orElse: () => {
                'text': {'content': 'Kein Titel'},
              },
            )['text']['content'] ??
            'Kein Titel';

        final category =
            properties['Kategorie']?['select']?['name'] ?? 'Allgemein';

        final author =
            (properties['Autor']?['rich_text'] as List?)?.firstWhere(
              (t) => t['text'] != null,
              orElse: () => {
                'text': {'content': 'Unbekannt'},
              },
            )['text']['content'] ??
            'Unbekannt';

        final datumRaw = properties['Datum']?['date']?['start'];
        final datum = datumRaw != null ? DateTime.tryParse(datumRaw) : null;

        final descriptionList =
            properties['Beschreibung']?['rich_text'] as List? ?? [];

        final linkProperty = properties['link'];
        final rawLink = (linkProperty != null && linkProperty['url'] != null)
            ? linkProperty['url']
            : '';
        final link = (rawLink is String && rawLink.isNotEmpty)
            ? (rawLink.startsWith('http') ? rawLink : 'https://$rawLink')
            : '';

        String imageUrl = '';
        final imageProp = properties['ImageUrl'];

        if (imageProp != null) {
          final fileList = imageProp['files'] as List?;
          if (fileList != null && fileList.isNotEmpty) {
            final firstFile = fileList.first;
            if (firstFile['type'] == 'external') {
              imageUrl = firstFile['external']?['url'] ?? '';
            } else if (firstFile['type'] == 'file') {
              imageUrl = firstFile['file']?['url'] ?? '';
            }
          }
        }

        if (imageUrl.isEmpty && page['cover'] != null) {
          if (page['cover']['file'] != null) {
            imageUrl = page['cover']['file']['url'] ?? '';
          } else if (page['cover']['external'] != null) {
            imageUrl = page['cover']['external']['url'] ?? '';
          }
        }

        bool isValidUrl(String url) {
          if (url.isEmpty) return false;
          final uri = Uri.tryParse(url);
          return uri != null && (uri.isScheme('http') || uri.isScheme('https'));
        }

        if (!isValidUrl(imageUrl)) {
          imageUrl = '';
        }

        return BlogCard(
          id: page['id'] ?? '',
          title: title,
          category: category,
          author: author,
          datum: datum != null
              ? '${datum.day.toString().padLeft(2, '0')}.${datum.month.toString().padLeft(2, '0')}.${datum.year}'
              : '',
          description: descriptionList
              .map((t) => t['text']?['content'] ?? '')
              .join('\n'),
          imageUrl: imageUrl,
          link: link,
        );
      }).toList();
    } else {
      throw Exception('Fehler beim Abrufen der Daten: ${response.body}');
    }
  }
}
