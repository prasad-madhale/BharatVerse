"""
When an article goes live: on its `date` in India, unless withdrawn -- the same rule as the articles read policy in
backend/database/schema.sql, which uses `ist_today()` there too.
"""

from datetime import date, datetime, timedelta, timezone

IST = timezone(timedelta(hours=5, minutes=30), "IST")  # India has one time zone and no daylight saving
PUBLISHED = "published"
WITHDRAWN = "withdrawn"


def ist_today(now: datetime | None = None) -> date:
    """Today's date in India."""
    return (now or datetime.now(timezone.utc)).astimezone(IST).date()
