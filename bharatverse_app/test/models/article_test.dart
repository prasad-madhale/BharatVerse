import 'package:flutter_test/flutter_test.dart';
import 'package:bharatverse_app/models/article.dart';

void main() {
  group('Article.fromJson', () {
    test('parses a full article response', () {
      final json = {
        'id': 'art_20260703_001',
        'title': 'The Mauryan Empire',
        'summary': 'A summary.',
        'content': '## Origins\n\nSome content.',
        'sections': [
          {'heading': 'Origins', 'content': 'Some content.', 'order': 1},
        ],
        'citations': [
          {
            'text': 'Maurya Empire',
            'source_url': 'https://en.wikipedia.org/wiki/Maurya_Empire',
            'source_name': 'wikipedia',
            'accessed_date': '2026-07-03T00:00:00Z',
          },
        ],
        'publication_date': '2026-07-03',
        'reading_time_minutes': 13,
        'author': 'BharatVerse AI',
        'tags': ['mauryan-empire', 'ancient-india'],
        'image_url': null,
      };

      final article = Article.fromJson(json);

      expect(article.id, 'art_20260703_001');
      expect(article.title, 'The Mauryan Empire');
      expect(article.sections, hasLength(1));
      expect(article.sections.first.heading, 'Origins');
      expect(article.citations, hasLength(1));
      expect(article.citations.first.sourceName, 'wikipedia');
      expect(article.publicationDate, DateTime.parse('2026-07-03'));
      expect(article.readingTimeMinutes, 13);
      expect(article.tags, ['mauryan-empire', 'ancient-india']);
      expect(article.imageUrl, isNull);
    });

    test('parses an article with an image_url', () {
      final json = {
        'id': 'art_20260703_002',
        'title': 'Title',
        'summary': 'Summary',
        'content': 'Content',
        'sections': [],
        'citations': [],
        'publication_date': '2026-07-03',
        'reading_time_minutes': 5,
        'author': 'BharatVerse AI',
        'tags': [],
        'image_url': 'https://example.com/image.jpg',
      };

      final article = Article.fromJson(json);

      expect(article.imageUrl, 'https://example.com/image.jpg');
    });
  });
}
