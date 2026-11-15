"""Bounded lexical retrieval from the packaged, attributed source records."""
import json
import re
from functools import lru_cache
from pathlib import Path


@lru_cache(maxsize=1)
def corpus():
    return json.loads(Path(__file__).with_name("chat_references.json").read_text())


def retrieve(question, farm):
    data = corpus()
    text = (question + " " + str(farm.get("crops grown", ""))).casefold()
    terms = set(re.findall(r"[^\W_]{3,}", text)) - {"the", "and", "for", "what", "should", "about", "field", "with", "this", "have"}
    crop_ids = {c["id"] for c in data["crops"] if any(
        len(alias) >= 4 and re.search(r"(?<!\w)" + re.escape(alias.casefold()) + r"(?!\w)", text)
        for alias in [c["scientific_name"], *c.get("aliases", [])]
    )}
    ranked = []
    for claim in data["claims"]:
        source = data["sources"].get(claim["source_id"], {})
        url = source.get("url", "")
        if not isinstance(url, str) or not url.startswith("https://"):
            continue
        if crop_ids and claim.get("crop_id") not in crop_ids:
            continue
        haystack = json.dumps(claim, ensure_ascii=False).casefold()
        score = sum(term in haystack for term in terms)
        if score:
            ranked.append((score, claim, source))
    ranked.sort(key=lambda item: (-item[0], item[1]["id"]))
    return [{"citation_id": f"R{i + 1}", "record": claim,
             "title": source.get("title", source["id"]), "url": source["url"]}
            for i, (_, claim, source) in enumerate(ranked[:5])]
