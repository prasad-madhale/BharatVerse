from datetime import date, datetime, timezone

from common.publishing import ist_today


def test_the_day_turns_at_midnight_in_india_which_is_1830_utc():
    assert ist_today(datetime(2026, 10, 5, 18, 29, tzinfo=timezone.utc)) == date(2026, 10, 5)
    assert ist_today(datetime(2026, 10, 5, 18, 30, tzinfo=timezone.utc)) == date(2026, 10, 6)


def test_defaults_to_now():
    assert ist_today() == ist_today(datetime.now(timezone.utc))
