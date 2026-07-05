/// Mirrors common/models.py's Article/Section/Citation on the backend --
/// keep field names and JSON keys in sync with that file.
class ArticleSection {
  final String heading;
  final String content;
  final int order;

  const ArticleSection({
    required this.heading,
    required this.content,
    required this.order,
  });

  factory ArticleSection.fromJson(Map<String, dynamic> json) => ArticleSection(
        heading: json['heading'] as String,
        content: json['content'] as String,
        order: json['order'] as int,
      );
}

class ArticleCitation {
  final String text;
  final String sourceUrl;
  final String sourceName;
  final DateTime accessedDate;

  const ArticleCitation({
    required this.text,
    required this.sourceUrl,
    required this.sourceName,
    required this.accessedDate,
  });

  factory ArticleCitation.fromJson(Map<String, dynamic> json) =>
      ArticleCitation(
        text: json['text'] as String,
        sourceUrl: json['source_url'] as String,
        sourceName: json['source_name'] as String,
        accessedDate: DateTime.parse(json['accessed_date'] as String),
      );
}

class Article {
  final String id;
  final String title;
  final String summary;
  final String content;
  final List<ArticleSection> sections;
  final List<ArticleCitation> citations;
  final DateTime publicationDate;
  final int readingTimeMinutes;
  final String author;
  final List<String> tags;
  final String? imageUrl;

  const Article({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    required this.sections,
    required this.citations,
    required this.publicationDate,
    required this.readingTimeMinutes,
    required this.author,
    required this.tags,
    this.imageUrl,
  });

  factory Article.fromJson(Map<String, dynamic> json) => Article(
        id: json['id'] as String,
        title: json['title'] as String,
        summary: json['summary'] as String,
        content: json['content'] as String,
        sections: (json['sections'] as List<dynamic>)
            .map((s) => ArticleSection.fromJson(s as Map<String, dynamic>))
            .toList(),
        citations: (json['citations'] as List<dynamic>)
            .map((c) => ArticleCitation.fromJson(c as Map<String, dynamic>))
            .toList(),
        publicationDate: DateTime.parse(json['publication_date'] as String),
        readingTimeMinutes: json['reading_time_minutes'] as int,
        author: json['author'] as String,
        tags: List<String>.from(json['tags'] as List<dynamic>),
        imageUrl: json['image_url'] as String?,
      );
}
