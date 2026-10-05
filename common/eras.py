"""
The eras an article can belong to (launch plan D4), oldest first. Each article has exactly one; the app shows them as
Search's era cards and searches them as typed, so no label has a date or a dash.
"""

ERAS = (
    "Indus Valley",
    "Vedic Age",
    "Maurya Empire",
    "Sangam Age",
    "Gupta Empire",
    "Early Medieval Kingdoms",
    "Delhi Sultanate",
    "Vijayanagara Empire",
    "Mughal Empire",
    "Maratha Empire",
    "Colonial India",
    "Freedom Struggle",
    "Independent India",
)

_BY_KEY = {era.casefold(): era for era in ERAS}


def canonical_era(label: str) -> str:
    """The listed era `label` names, whatever its case, spacing or surrounding quotes; otherwise `label`, stripped."""
    cleaned = " ".join(label.strip().strip("\"'.").split())
    return _BY_KEY.get(cleaned.casefold(), cleaned)
