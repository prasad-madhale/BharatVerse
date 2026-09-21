"""Seeds three sample articles through the backend's own ArticleService (row upsert plus storage upload).

Run by stack.sh with SUPABASE_URL and the keys pointing at the stand-in; never run it against a hosted project.
"""
import asyncio
import sys
from datetime import date, datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from backend.services.article_service import ArticleService  # noqa: E402
from common.models import Article, Citation, Section  # noqa: E402

NOW = datetime.now(timezone.utc)


def cite(title, url):
    return Citation(text=title, source_url=url, source_name="wikipedia", accessed_date=NOW)


ARTICLES = [
    ("art_20260920_001", date(2026, 9, 20), "The Mauryan Empire: India's First Great Dynasty",
     "How Chandragupta Maurya built a subcontinental empire, and how Ashoka turned its power toward dhamma.",
     ["mauryan-empire", "ancient-india", "ashoka"], [
         ("Origins", "Around 321 BCE, Chandragupta Maurya overthrew the Nanda dynasty of Magadha, reportedly guided by the "
                     "scholar Chanakya. From the capital at Pataliputra he expanded west and south, and in about 305 BCE "
                     "he negotiated a treaty with Seleucus I Nicator that secured the north-western frontier and brought "
                     "war elephants into his army."),
         ("Ashoka and the Kalinga War", "Ashoka came to the throne around 268 BCE. His campaign against Kalinga, about 261 "
                                        "BCE, cost enormous loss of life, and his own edicts record remorse. He turned toward "
                                        "the principle of dhamma, promoting non-violence, tolerance, and public welfare, and "
                                        "had these ideas carved on rocks and pillars across the empire."),
         ("Administration and Legacy", "The empire was governed through provinces under royal officials, linked by roads and "
                                       "a network of spies and inspectors. Ashoka's pillars survive across the subcontinent, "
                                       "and the lion capital from Sarnath became the emblem of the Republic of India."),
     ], [cite("Maurya Empire", "https://en.wikipedia.org/wiki/Maurya_Empire"), cite("Ashoka", "https://en.wikipedia.org/wiki/Ashoka")]),
    ("art_20260919_001", date(2026, 9, 19), "The Indus Valley Civilisation",
     "Planned cities, standard weights, and long-distance trade on the plains of the Indus, over four thousand years ago.",
     ["indus-valley", "ancient-india", "harappa"], [
         ("Cities of the Indus", "Harappa and Mohenjo-daro were laid out on regular grids, with brick houses, wells, and "
                                 "covered drains running beneath the streets. The scale of the planning suggests a shared "
                                 "civic culture across a region larger than ancient Egypt or Mesopotamia."),
         ("Trade and Craft", "Carved stone seals, standardised weights, and carnelian beads travelled far beyond the valley. "
                             "Objects of Indus origin turn up in Mesopotamia, pointing to sea and overland trade in "
                             "materials such as lapis lazuli, copper, and shell."),
         ("Decline", "From about 1900 BCE the cities were gradually abandoned. Scholars debate the causes, and shifting "
                     "rivers, changing monsoon patterns, and trade disruption are all discussed. The script remains "
                     "undeciphered."),
     ], [cite("Indus Valley Civilisation", "https://en.wikipedia.org/wiki/Indus_Valley_Civilisation")]),
    ("art_20260918_001", date(2026, 9, 18), "The Cholas and the Sea",
     "A Tamil dynasty that built great temples and sent fleets across the Bay of Bengal.",
     ["chola-dynasty", "medieval-india", "maritime-history"], [
         ("The Rise of the Cholas", "The Cholas rose to imperial strength under Rajaraja I, who came to the throne in 985 CE. "
                                    "He consolidated southern India and built the Brihadisvara Temple at Thanjavur, completed "
                                    "around 1010 CE, which still dominates the town."),
         ("Rajendra Chola's Expeditions", "Rajendra I extended Chola power north to the Ganges and, around 1025 CE, sent a naval "
                                          "expedition against the Srivijaya realm in South-East Asia. The campaign reflects "
                                          "a state with real reach over the sea lanes of the Bay of Bengal."),
         ("Art and Bronze", "Chola workshops cast bronzes by the lost-wax method, and the dancing Shiva, Nataraja, became one "
                            "of the best-known images in Indian art."),
     ], [cite("Chola dynasty", "https://en.wikipedia.org/wiki/Chola_dynasty")]),
]


def build(article_id, published, title, summary, tags, sections, citations):
    body = "\n\n".join(f"## {heading}\n\n{text}" for heading, text in sections)
    return Article(id=article_id, title=title, summary=summary, content=body, publication_date=published,
                   reading_time_minutes=12, tags=tags, citations=citations,
                   sections=[Section(heading=h, content=t, order=i + 1) for i, (h, t) in enumerate(sections)])


async def main():
    service = ArticleService()
    for spec in ARTICLES:
        saved = await service.save_article(build(*spec))
        print("saved", saved.id, "-", saved.title)


asyncio.run(main())
