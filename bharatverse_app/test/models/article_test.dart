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
      expect(article.images, isEmpty);
    });

    test('parses images, defaulting caption to null when absent', () {
      final json = {
        'id': 'art_1',
        'title': 'T',
        'summary': 'S',
        'content': 'C',
        'sections': [],
        'citations': [],
        'images': [
          {
            'url': 'https://storage.example/0.jpg',
            'alt_text': 'The Great Stupa',
            'caption': null,
            'credit': 'Jane Doe via Wikimedia Commons',
            'source_url': 'https://commons.wikimedia.org/wiki/File:Stupa.jpg',
            'license': 'CC BY-SA 4.0',
            'width': 1200,
            'height': 800,
          },
        ],
        'publication_date': '2026-07-03',
        'reading_time_minutes': 5,
        'author': 'BharatVerse AI',
        'tags': [],
        'image_url': 'https://storage.example/0.jpg',
      };

      final article = Article.fromJson(json);

      expect(article.images, hasLength(1));
      expect(article.images.first.credit, 'Jane Doe via Wikimedia Commons');
      expect(article.images.first.license, 'CC BY-SA 4.0');
      expect(article.images.first.caption, isNull);
      expect(article.images.first.aspectRatio, 1200 / 800);
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

  test('dateAndReadingTime is the byline shown under a title', () {
    final article = Article.fromJson({
      'id': 'art_1',
      'title': 'T',
      'summary': 'S',
      'content': 'C',
      'sections': [],
      'citations': [],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'A',
      'tags': [],
      'image_url': null,
    });

    expect(article.dateAndReadingTime, '2026-07-03 · 13 min read');
  });

  test('toJson writes the shape fromJson reads, losing nothing', () {
    final article = Article.fromJson({
      'id': 'art_1',
      'title': 'T',
      'summary': 'S',
      'content': 'C',
      'sections': [
        {'heading': 'H', 'content': 'B', 'order': 1},
      ],
      'citations': [
        {
          'text': 'Maurya Empire',
          'source_url': 'https://en.wikipedia.org/wiki/Maurya_Empire',
          'source_name': 'wikipedia',
          'accessed_date': '2026-07-03T00:00:00.000Z',
        },
      ],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'A',
      'tags': ['mauryan-empire'],
      'image_url': 'https://example.org/i.png',
    });

    final again = Article.fromJson(article.toJson());

    expect(again.toJson(), article.toJson());
    expect(again.publicationDate, article.publicationDate);
    expect(again.citations.single.accessedDate,
        article.citations.single.accessedDate);
    expect(again.imageUrl, 'https://example.org/i.png');
  });

  test('toJson keeps a missing image missing', () {
    final article = Article.fromJson({
      'id': 'art_1',
      'title': 'T',
      'summary': 'S',
      'content': 'C',
      'sections': [],
      'citations': [],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'A',
      'tags': [],
      'image_url': null,
    });

    expect(Article.fromJson(article.toJson()).imageUrl, isNull);
  });

  test('toJson writes images, losing nothing on the round trip', () {
    final article = Article.fromJson({
      'id': 'art_1',
      'title': 'T',
      'summary': 'S',
      'content': 'C',
      'sections': [],
      'citations': [],
      'images': [
        {
          'url': 'https://storage.example/0.jpg',
          'alt_text': 'The Great Stupa',
          'caption': 'A restored Mauryan-era stupa',
          'credit': 'Jane Doe via Wikimedia Commons',
          'source_url': 'https://commons.wikimedia.org/wiki/File:Stupa.jpg',
          'license': 'CC BY-SA 4.0',
          'width': 1200,
          'height': 800,
        },
      ],
      'publication_date': '2026-07-03',
      'reading_time_minutes': 13,
      'author': 'A',
      'tags': [],
      'image_url': 'https://storage.example/0.jpg',
    });

    final again = Article.fromJson(article.toJson());

    expect(again.toJson(), article.toJson());
    expect(again.images.single.caption, 'A restored Mauryan-era stupa');
  });
}
