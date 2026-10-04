"""IFBB Pro League 公式サイトから大会スケジュール・出場選手・結果を取得し contests.json を作る。

    pip install -r requirements.txt
    python scrape.py                    # 取得して ../web/public/data/contests.json を上書き
    python scrape.py --limit 5          # 動作確認用に5大会だけ
    python scrape.py --offline          # cache/ に保存済みの HTML だけで再パース（通信しない）

注意:
- 公式サイトの HTML 構造は予告なく変わる。パースはなるべく構造に依存しないヒューリスティック
  （見出しからディビジョンを検出し、その下の「順位 + 名前」行を拾う）にしているが、
  取得件数が極端に少ない場合は parse_* 関数のセレクタを調整すること。
- robots.txt を尊重し、リクエスト間隔を空ける（--delay）。取得した HTML は cache/ に保存し再利用する。
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import time
from datetime import date, datetime, timezone
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.robotparser import RobotFileParser

from bs4 import BeautifulSoup, Tag

from divisions import detect_division

BASE = "https://ifbbpro.com"
SCHEDULE_URLS = [f"{BASE}/schedule/"]
CONTEST_LINK = re.compile(r"/contests?/[^/?#]+/?$")
USER_AGENT = "ifbb-pro-jp-bot/0.1 (+unofficial Japanese fan site; low frequency)"

HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache"
OUT = HERE.parent / "web" / "public" / "data" / "contests.json"

MONTHS = {m: i for i, m in enumerate(
    ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"], 1)}

COUNTRY_NAMES = {
    "usa": "US", "united states": "US", "canada": "CA", "mexico": "MX", "brazil": "BR", "argentina": "AR",
    "colombia": "CO", "chile": "CL", "peru": "PE", "uk": "GB", "united kingdom": "GB", "england": "GB",
    "scotland": "GB", "ireland": "IE", "france": "FR", "germany": "DE", "italy": "IT", "spain": "ES",
    "portugal": "PT", "netherlands": "NL", "belgium": "BE", "switzerland": "CH", "austria": "AT",
    "poland": "PL", "czech republic": "CZ", "czechia": "CZ", "slovakia": "SK", "hungary": "HU",
    "romania": "RO", "bulgaria": "BG", "greece": "GR", "sweden": "SE", "norway": "NO", "finland": "FI",
    "denmark": "DK", "russia": "RU", "ukraine": "UA", "turkey": "TR", "egypt": "EG", "south africa": "ZA",
    "uae": "AE", "united arab emirates": "AE", "dubai": "AE", "saudi arabia": "SA", "kuwait": "KW",
    "qatar": "QA", "bahrain": "BH", "oman": "OM", "iran": "IR", "iraq": "IQ", "jordan": "JO",
    "india": "IN", "china": "CN", "hong kong": "HK", "taiwan": "TW", "korea": "KR", "south korea": "KR",
    "japan": "JP", "thailand": "TH", "vietnam": "VN", "philippines": "PH", "malaysia": "MY",
    "singapore": "SG", "indonesia": "ID", "australia": "AU", "new zealand": "NZ", "kazakhstan": "KZ",
    "puerto rico": "PR", "dominican republic": "DO", "ecuador": "EC", "venezuela": "VE", "georgia": "GE",
}
US_STATES = {
    "AL", "AK", "AZ", "AR", "CA", "CO", "CT", "DE", "FL", "GA", "HI", "ID", "IL", "IN", "IA", "KS", "KY",
    "LA", "ME", "MD", "MA", "MI", "MN", "MS", "MO", "MT", "NE", "NV", "NH", "NJ", "NM", "NY", "NC", "ND",
    "OH", "OK", "OR", "PA", "RI", "SC", "SD", "TN", "TX", "UT", "VT", "VA", "WA", "WV", "WI", "WY", "DC",
}


# --------------------------------------------------------------------------- fetch

class Fetcher:
    def __init__(self, delay: float, offline: bool, refresh: bool):
        self.delay, self.offline, self.refresh = delay, offline, refresh
        self._last = 0.0
        self._robots: dict[str, RobotFileParser] = {}
        self._session = None
        CACHE.mkdir(exist_ok=True)

    def _cache_path(self, url: str) -> Path:
        return CACHE / (hashlib.sha1(url.encode()).hexdigest()[:16] + ".html")

    def _allowed(self, url: str) -> bool:
        host = urlparse(url).netloc
        if host not in self._robots:
            rp = RobotFileParser(f"https://{host}/robots.txt")
            try:
                rp.read()
            except Exception:
                pass  # 取得できなければ許可扱い（RobotFileParser の既定動作）
            self._robots[host] = rp
        return self._robots[host].can_fetch(USER_AGENT, url)

    def get(self, url: str, max_age_days: float | None = None) -> str | None:
        path = self._cache_path(url)
        if path.exists() and not self.refresh:
            fresh = max_age_days is None or (time.time() - path.stat().st_mtime) < max_age_days * 86400
            if fresh or self.offline:
                return path.read_text(encoding="utf-8")
        if self.offline:
            return None
        if not self._allowed(url):
            print(f"  robots.txt disallows {url}", file=sys.stderr)
            return None
        import requests

        if self._session is None:
            self._session = requests.Session()
            self._session.headers["User-Agent"] = USER_AGENT
        wait = self.delay - (time.time() - self._last)
        if wait > 0:
            time.sleep(wait)
        self._last = time.time()
        try:
            r = self._session.get(url, timeout=30)
            r.raise_for_status()
        except Exception as e:
            print(f"  fetch failed {url}: {e}", file=sys.stderr)
            return None
        path.write_text(r.text, encoding="utf-8")
        return r.text


# --------------------------------------------------------------------------- parse helpers

def clean(s: str) -> str:
    return " ".join(s.replace("\xa0", " ").split())


def slug_from_url(url: str) -> str:
    return urlparse(url).path.rstrip("/").split("/")[-1]


DATE_RE = re.compile(
    r"(?P<m1>jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(?P<d1>\d{1,2})"
    r"(?:\s*[-–&]\s*(?:(?P<m2>jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+)?(?P<d2>\d{1,2}))?"
    r",?\s+(?P<y>20\d\d)",
    re.I,
)
ISO_RE = re.compile(r"(20\d\d)[-/](\d{1,2})[-/](\d{1,2})")


def parse_dates(text: str) -> tuple[str | None, str | None]:
    m = DATE_RE.search(text)
    if m:
        y = int(m["y"])
        start = date(y, MONTHS[m["m1"][:3].lower()], int(m["d1"]))
        end = None
        if m["d2"]:
            m2 = MONTHS[(m["m2"] or m["m1"])[:3].lower()]
            end = date(y, m2, int(m["d2"]))
        return start.isoformat(), end.isoformat() if end and end != start else None
    m = ISO_RE.search(text)
    if m:
        return date(int(m[1]), int(m[2]), int(m[3])).isoformat(), None
    return None, None


def parse_location(text: str) -> tuple[str | None, str | None]:
    """"Columbus, OH" / "Madrid, Spain" / "Tokyo, Japan" → (city, ISO2)"""
    parts = [p.strip() for p in text.split(",") if p.strip()]
    if not parts:
        return None, None
    last = parts[-1]
    if last.upper() in US_STATES or last.lower() in ("usa", "united states"):
        return parts[0], "US"
    code = COUNTRY_NAMES.get(last.lower())
    if code:
        return (parts[0] if len(parts) > 1 else None), code
    return parts[0], None


# 「1. John Doe」「1st John Doe」「1 - John Doe (USA)」「John Doe – 1st」などを拾う
PLACING_RE = re.compile(r"^\s*(\d{1,2})(?:st|nd|rd|th)?\s*(?:place)?\s*[.):\-–]?\s+(.+?)\s*$", re.I)
PLACING_TAIL_RE = re.compile(r"^\s*(.+?)\s*[-–:]\s*(\d{1,2})(?:st|nd|rd|th)\s*(?:place)?\s*$", re.I)
TRAILING_COUNTRY = re.compile(r"\s*[(\[]([A-Za-z .]+)[)\]]\s*$")


def parse_placing_line(line: str) -> dict | None:
    line = clean(line)
    m = PLACING_RE.match(line)
    if m:
        place, name = int(m[1]), m[2]
    else:
        m = PLACING_TAIL_RE.match(line)
        if not m:
            return None
        name, place = m[1], int(m[2])
    country = None
    cm = TRAILING_COUNTRY.search(name)
    if cm:
        country = COUNTRY_NAMES.get(cm[1].strip().lower()) or (cm[1].strip().upper() if len(cm[1].strip()) == 2 else None)
        name = name[: cm.start()]
    name = name.strip(" -–,")
    if not re.search(r"[A-Za-z]", name) or len(name) > 60 or place < 1:
        return None
    p = {"place": place, "athlete": name.title() if name.isupper() else name}
    if country:
        p["country"] = country
    return p


def iter_blocks(root: Tag):
    """本文要素を文書順に（見出し / 段落 / リスト項目 / 表の行）列挙する。"""
    for el in root.find_all(["h1", "h2", "h3", "h4", "h5", "h6", "strong", "b", "p", "li", "tr", "a"]):
        yield el


def parse_division_sections(root: Tag) -> tuple[dict[str, list[dict]], dict[str, list[str]], dict[str, str]]:
    """見出しでディビジョンを切り替えながら、順位付きの行（結果）・順位なしの名前（出場者）・スコアカードURLを集める。"""
    results: dict[str, list[dict]] = {}
    entrants: dict[str, list[str]] = {}
    scorecards: dict[str, str] = {}
    current: str | None = None
    seen: set[int] = set()

    for el in iter_blocks(root):
        if id(el) in seen:
            continue
        text = clean(el.get_text(" "))
        if not text:
            continue

        if el.name == "a":
            href = el.get("href") or ""
            if re.search(r"score\s*-?card", text + " " + href, re.I):
                div = detect_division(text) or current
                if div and div not in scorecards:
                    scorecards[div] = urljoin(BASE, href)
            continue

        is_heading = el.name in ("h1", "h2", "h3", "h4", "h5", "h6", "strong", "b") or (
            el.name == "p" and len(text) < 60 and not PLACING_RE.match(text)
        )
        if is_heading:
            div = detect_division(text)
            if div:
                current = div
                continue
        if current is None or el.name in ("h1", "h2", "h3", "h4", "h5", "h6", "strong", "b"):
            continue

        if el.name == "tr":
            cells = [clean(td.get_text(" ")) for td in el.find_all(["td", "th"])]
            if len(cells) >= 2 and re.fullmatch(r"\d{1,2}", cells[0]):
                p = {"place": int(cells[0]), "athlete": cells[1]}
                for c in cells[2:]:
                    if re.fullmatch(r"\d{1,3}", c):
                        p["score"] = int(c)
                results.setdefault(current, []).append(p)
            continue

        # <p> に <br> 区切りで複数行入っているケースに対応
        lines = [clean(s) for s in el.get_text("\n").split("\n") if clean(s)]
        for line in lines:
            p = parse_placing_line(line)
            if p:
                results.setdefault(current, []).append(p)
            elif el.name == "li" and len(line) < 50 and re.fullmatch(r"[A-Za-zÀ-ÿ'’.\- ]+", line):
                entrants.setdefault(current, []).append(line)
        for child in el.find_all(True):
            seen.add(id(child))

    for div, ps in results.items():
        uniq: dict[str, dict] = {}
        for p in ps:
            uniq.setdefault(p["athlete"].lower(), p)
        results[div] = sorted(uniq.values(), key=lambda p: p["place"])
    return results, entrants, scorecards


def labeled_field(root: Tag, *labels: str) -> str | None:
    """「Label: 値」形式の短い要素（またはラベル要素の次の兄弟）から値を取り出す。"""
    pat = re.compile(r"^\s*(?:%s)\s*[:：]\s*(.*)$" % "|".join(map(re.escape, labels)), re.I)
    for el in root.find_all(["p", "li", "div", "span", "dd", "dt", "td", "th", "strong", "b"]):
        text = clean(el.get_text(" "))
        if not text or len(text) > 200:
            continue
        m = pat.match(text)
        if not m:
            continue
        value = m[1].strip()
        if not value:  # <dt>Location:</dt><dd>値</dd> のようにラベルと値が分かれている場合
            sib = el.find_next_sibling()
            value = clean(sib.get_text(" ")) if sib else ""
        if value:
            return value
    return None


# --------------------------------------------------------------------------- pages

def parse_schedule(html: str, base_url: str) -> list[str]:
    soup = BeautifulSoup(html, "html.parser")
    urls = []
    for a in soup.find_all("a", href=True):
        url = urljoin(base_url, a["href"]).split("#")[0]
        if urlparse(url).netloc.endswith("ifbbpro.com") and CONTEST_LINK.search(urlparse(url).path):
            if url not in urls:
                urls.append(url)
    return urls


def parse_contest(html: str, url: str) -> dict | None:
    soup = BeautifulSoup(html, "html.parser")
    for junk in soup(["script", "style", "nav", "footer", "header", "form"]):
        junk.decompose()
    root = soup.find("main") or soup.find("article") or soup.body or soup
    h1 = root.find("h1") or soup.find("title")
    if not h1:
        return None
    name = re.sub(r"\s*[|–-]\s*IFBB Pro.*$", "", clean(h1.get_text(" ")), flags=re.I)
    text = clean(root.get_text(" "))

    start, end = parse_dates(text)
    if not start:
        print(f"  no date found: {url}", file=sys.stderr)
        return None

    city = country = None
    loc = labeled_field(root, "location", "venue", "city")
    if loc:
        city, country = parse_location(loc)
    promoter = labeled_field(root, "promoter", "promoted by")

    results, entrants, scorecards = parse_division_sections(root)
    divisions = set(results) | set(entrants) | set(scorecards)
    div_text = labeled_field(root, "divisions", "division")
    if div_text:
        for part in re.split(r"[,/|•·]|\band\b", div_text):
            d = detect_division(part)
            if d:
                divisions.add(d)

    contest = {
        "id": f"{start[:4]}-{slug_from_url(url)}" if not slug_from_url(url).startswith(start[:4]) else slug_from_url(url),
        "name": name,
        "date": start,
        "url": url,
        "olympiaQualifier": bool(re.search(r"olympia\s+qualifier|qualif\w*\s+for\s+(the\s+)?olympia", text, re.I)),
        "divisions": sorted(divisions),
    }
    if end:
        contest["endDate"] = end
    if city:
        contest["city"] = city
    if country:
        contest["country"] = country
    if promoter:
        contest["promoter"] = promoter
    if results:
        contest["results"] = [
            {"division": d, "placings": ps, **({"scorecardUrl": scorecards[d]} if d in scorecards else {})}
            for d, ps in results.items()
        ]
        # 結果は無いがスコアカードだけあるディビジョン
        for d, sc in scorecards.items():
            if d not in results:
                contest["results"].append({"division": d, "placings": [], "scorecardUrl": sc})
    elif entrants:
        contest["entrants"] = {d: sorted(set(n)) for d, n in entrants.items()}
    return contest


# --------------------------------------------------------------------------- main

def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", type=Path, default=OUT)
    ap.add_argument("--delay", type=float, default=2.0, help="リクエスト間隔（秒）")
    ap.add_argument("--limit", type=int, default=0, help="取得する大会数の上限（0=無制限）")
    ap.add_argument("--offline", action="store_true", help="cache/ のみ使用し通信しない")
    ap.add_argument("--refresh", action="store_true", help="キャッシュを無視して再取得")
    ap.add_argument("--schedule-url", action="append", help="スケジュールページURL（複数可）")
    args = ap.parse_args()

    f = Fetcher(args.delay, args.offline, args.refresh)
    contest_urls: list[str] = []
    for su in args.schedule_url or SCHEDULE_URLS:
        html = f.get(su, max_age_days=0.5)
        if html:
            contest_urls += [u for u in parse_schedule(html, su) if u not in contest_urls]
    print(f"found {len(contest_urls)} contest links")
    if args.limit:
        contest_urls = contest_urls[: args.limit]

    today = date.today().isoformat()
    contests = []
    for i, url in enumerate(contest_urls, 1):
        print(f"[{i}/{len(contest_urls)}] {url}")
        # 結果確定済みの過去大会はキャッシュを長く使い、直近・今後の大会は毎回更新する
        html = f.get(url, max_age_days=1)
        if not html:
            continue
        c = parse_contest(html, url)
        if c:
            contests.append(c)
            n = sum(len(r["placings"]) for r in c.get("results", []))
            print(f"    {c['date']} {c['name']} | divisions={len(c['divisions'])} placings={n}")

    if not contests:
        sys.exit("大会を1件も取得できませんでした。ネットワーク、または公式サイトのHTML構造の変更を確認してください。")

    # 既存データとマージ（公式スケジュールから消えた過去大会も残す）
    merged = {}
    if args.out.exists():
        old = json.loads(args.out.read_text(encoding="utf-8"))
        if old.get("source") == "scraped":
            merged = {c["id"]: c for c in old["contests"]}
    for c in contests:
        merged[c["id"]] = c

    data = {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "source": "scraped",
        "contests": sorted(merged.values(), key=lambda c: c["date"]),
    }
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    with_results = sum(1 for c in data["contests"] if c.get("results"))
    print(f"wrote {len(data['contests'])} contests ({with_results} with results, today={today}) -> {args.out}")


if __name__ == "__main__":
    main()
