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

  Map<String, dynamic> toJson() =>
      {'heading': heading, 'content': content, 'order': order};

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

  Map<String, dynamic> toJson() => {
        'text': text,
        'source_url': sourceUrl,
        'source_name': sourceName,
        'accessed_date': accessedDate.toIso8601String(),
      };

  factory ArticleCitation.fromJson(Map<String, dynamic> json) =>
      ArticleCitation(
        text: json['text'] as String,
        sourceUrl: json['source_url'] as String,
        sourceName: json['source_name'] as String,
        accessedDate: DateTime.parse(json['accessed_date'] as String),
      );
}

class ArticleImage {
  final String url;
  final String altText;
  final String? caption;
  final String credit;
  final String sourceUrl;
  final String license;

  const ArticleImage({
    required this.url,
    required this.altText,
    this.caption,
    required this.credit,
    required this.sourceUrl,
    required this.license,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'alt_text': altText,
        'caption': caption,
        'credit': credit,
        'source_url': sourceUrl,
        'license': license,
      };

  factory ArticleImage.fromJson(Map<String, dynamic> json) => ArticleImage(
        url: json['url'] as String,
        altText: json['alt_text'] as String,
        caption: json['caption'] as String?,
        credit: json['credit'] as String,
        sourceUrl: json['source_url'] as String,
        license: json['license'] as String,
      );
}

class Article {
  final String id;
  final String title;
  final String summary;
  final String content;
  final List<ArticleSection> sections;
  final List<ArticleCitation> citations;
  final List<ArticleImage> images;
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
    this.images = const [],
    required this.publicationDate,
    required this.readingTimeMinutes,
    required this.author,
    required this.tags,
    this.imageUrl,
  });

  /// "2026-09-20 · 12 min read", the byline under a title in lists and on the
  /// article.
  String get dateAndReadingTime =>
      '${publicationDate.toLocal().toString().split(' ').first}'
      ' · $readingTimeMinutes min read';

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'summary': summary,
        'content': content,
        'sections': sections.map((section) => section.toJson()).toList(),
        'citations': citations.map((citation) => citation.toJson()).toList(),
        'images': images.map((image) => image.toJson()).toList(),
        'publication_date': publicationDate.toIso8601String(),
        'reading_time_minutes': readingTimeMinutes,
        'author': author,
        'tags': tags,
        'image_url': imageUrl,
      };

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
        images: (json['images'] as List<dynamic>? ?? [])
            .map((i) => ArticleImage.fromJson(i as Map<String, dynamic>))
            .toList(),
        publicationDate: DateTime.parse(json['publication_date'] as String),
        readingTimeMinutes: json['reading_time_minutes'] as int,
        author: json['author'] as String,
        tags: List<String>.from(json['tags'] as List<dynamic>),
        imageUrl: json['image_url'] as String?,
      );
}
