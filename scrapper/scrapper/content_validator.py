"""
Automated content validation for generated articles.

Stands in for human-in-the-loop (historian) review, which is explicitly
deferred for now (see .kiro/specs/bharatverse-mvp/roadmap.md, Phase 4).
Checks structural/quality properties that are cheap to verify
automatically; it cannot verify factual accuracy.
"""

from common.models import Article

MIN_WORD_COUNT = 1500
MAX_WORD_COUNT = 2000
# Small tolerance since the LLM's stated limit in the generation prompt is a
# target, not a hard guarantee -- reject only on a meaningful overshoot/undershoot.
WORD_COUNT_TOLERANCE = 200

MIN_SECTIONS = 3
MIN_CITATIONS = 1


def article_metrics(article: Article) -> dict[str, int]:
    """What the validator measures, and what the pipeline logs for every article it generates."""
    return {
        "word_count": len(article.content.split()),
        "citation_count": len(article.citations),
        "section_count": len(article.sections),
    }


class ContentValidator:
    """Automated structural/quality checks for a generated Article."""

    def validate(self, article: Article) -> tuple[bool, list[str]]:
        """
        Check an article against automated quality rules.

        Returns:
            (True, []) if the article passes all checks, otherwise
            (False, [reason, ...]) listing every failed check.
        """
        issues: list[str] = []

        if not article.title.strip():
            issues.append("title is empty")
        if not article.summary.strip():
            issues.append("summary is empty")

        metrics = article_metrics(article)
        word_count = metrics["word_count"]
        min_allowed = MIN_WORD_COUNT - WORD_COUNT_TOLERANCE
        max_allowed = MAX_WORD_COUNT + WORD_COUNT_TOLERANCE
        if word_count < min_allowed or word_count > max_allowed:
            issues.append(
                f"word count {word_count} outside allowed range [{min_allowed}, {max_allowed}]"
            )

        if metrics["section_count"] < MIN_SECTIONS:
            issues.append(f"only {metrics['section_count']} section(s), need at least {MIN_SECTIONS}")

        if metrics["citation_count"] < MIN_CITATIONS:
            issues.append(f"only {metrics['citation_count']} citation(s), need at least {MIN_CITATIONS}")

        return (len(issues) == 0, issues)
