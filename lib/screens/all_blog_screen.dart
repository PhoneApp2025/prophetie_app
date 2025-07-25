import 'package:flutter/material.dart';
import 'package:prophetie_app/services/notion_service.dart';
import 'package:prophetie_app/widgets/blog_card.dart';

Future<List<Widget>> fetchNotionBlogCards(BuildContext context) async {
  final blogCards = await NotionService.fetchBlogCards(context);
  return blogCards.map((blogCard) => blogCard as Widget).toList();
}

class AllBlogScreen extends StatelessWidget {
  const AllBlogScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Alle Blogeinträge',
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 24.0, bottom: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  FutureBuilder<List<Widget>>(
                    future: fetchNotionBlogCards(context),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      } else if (snapshot.hasError) {
                        return Text('Fehler beim Laden: ${snapshot.error}');
                      } else if (!snapshot.hasData || snapshot.data!.isEmpty) {
                        return const Text('Keine Blogartikel verfügbar.');
                      } else {
                        return ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          shrinkWrap: true,
                          itemCount: snapshot.data!.length,
                          itemBuilder: (context, index) {
                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.symmetric(vertical: 8.0),
                              child: snapshot.data![index],
                            );
                          },
                        );
                      }
                    },
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
