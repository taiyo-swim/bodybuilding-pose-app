"""英語のディビジョン表記 → サイト内 ID への正規化。

公式サイトの見出しは "Men's Open", "Mens Bodybuilding", "212 Bodybuilding" など揺れがあるため、
上から順に正規表現でマッチさせる（具体的なものを先に置くこと）。
"""
import re

DIVISION_PATTERNS: list[tuple[str, re.Pattern]] = [
    ("wheelchair", re.compile(r"wheel\s*chair", re.I)),
    ("212", re.compile(r"\b212\b", re.I)),
    ("classic-physique", re.compile(r"classic\s+physique", re.I)),
    ("womens-physique", re.compile(r"wom[ae]n'?s?\s+physique", re.I)),
    ("mens-physique", re.compile(r"\bmen'?s?\s+physique", re.I)),
    ("womens-bodybuilding", re.compile(r"wom[ae]n'?s?\s+(open\s+)?bodybuilding", re.I)),
    ("mens-open", re.compile(r"\bmen'?s?\s+(open|bodybuilding)|^\s*open\s+bodybuilding|^\s*bodybuilding\s*$", re.I)),
    ("figure", re.compile(r"\bfigure\b", re.I)),
    ("fitness", re.compile(r"\bfitness\b", re.I)),
    ("wellness", re.compile(r"\bwellness\b", re.I)),
    ("bikini", re.compile(r"\bbikini\b", re.I)),
]


def detect_division(text: str) -> str | None:
    t = " ".join(text.split())
    if len(t) > 80:  # 長い段落は見出しではない
        return None
    for div_id, pat in DIVISION_PATTERNS:
        if pat.search(t):
            return div_id
    return None
