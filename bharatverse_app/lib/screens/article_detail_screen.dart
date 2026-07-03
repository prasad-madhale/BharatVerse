import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../models/article.dart';

class ArticleDetailScreen extends StatelessWidget {
  final Article article;

  const ArticleDetailScreen({super.key, required this.article});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(article.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(article.title, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            '${article.publicationDate.toLocal().toString().split(' ').first} '
            '· ${article.readingTimeMinutes} min read · ${article.author}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (article.tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: article.tags.map((t) => Chip(label: Text(t))).toList(),
            ),
          ],
          const Divider(height: 32),
          MarkdownBody(data: article.content),
          if (article.citations.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Sources', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final citation in article.citations)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${citation.sourceName}: ${citation.text}\n${citation.sourceUrl}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
