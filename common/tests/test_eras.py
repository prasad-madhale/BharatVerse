from common.eras import ERAS, canonical_era


def test_thirteen_eras_with_no_dates_or_dashes():
    assert len(ERAS) == 13
    assert len(set(ERAS)) == 13
    assert not any(c.isdigit() or c in "-–—" for era in ERAS for c in era)


def test_canonical_era_matches_whatever_the_case_spacing_or_quotes():
    assert canonical_era("Maurya Empire") == "Maurya Empire"
    assert canonical_era('  "delhi   sultanate". ') == "Delhi Sultanate"


def test_canonical_era_leaves_an_unlisted_label_stripped():
    assert canonical_era(" Mauryan Empire ") == "Mauryan Empire"
    assert canonical_era("") == ""
