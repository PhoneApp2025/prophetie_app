class InfoCard {
  final String title;
  final String subtitle;
  final String category;
  final String imageUrl;
  final String type;

  InfoCard({
    required this.title,
    required this.subtitle,
    required this.category,
    required this.imageUrl,
    required this.type,
  });

  factory InfoCard.fromJson(Map<String, dynamic> json) {
    return InfoCard(
      title: json['title'] ?? '',
      subtitle: json['subtitle'] ?? '',
      category: json['category'] ?? '',
      imageUrl: json['image'] ?? '',
      type: json['type'] ?? '',
    );
  }
}
