"""動作確認用のサンプルデータ（架空の大会・選手）を生成する。

    python sample_data.py   # -> ../web/public/data/contests.json

実在の大会・選手と誤認されないよう、名前はすべて "Sample" / "Demo" を含む架空のものにしている。
"""
import json
import random
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

OUT = Path(__file__).resolve().parent.parent / "web" / "public" / "data" / "contests.json"

DIVS = ["mens-open", "212", "classic-physique", "mens-physique", "womens-physique",
        "figure", "fitness", "wellness", "bikini", "womens-bodybuilding"]
MALE = {"mens-open", "212", "classic-physique", "mens-physique"}
CITIES = [("Tokyo", "JP"), ("Osaka", "JP"), ("Columbus", "US"), ("Las Vegas", "US"), ("Tampa", "US"),
          ("Toronto", "CA"), ("Madrid", "ES"), ("Rome", "IT"), ("London", "GB"), ("Dubai", "AE"),
          ("Seoul", "KR"), ("Sydney", "AU"), ("Sao Paulo", "BR"), ("Mexico City", "MX"), ("Prague", "CZ"),
          ("Bangkok", "TH"), ("Warsaw", "PL"), ("Kuwait City", "KW")]
COUNTRIES = ["US", "US", "US", "JP", "JP", "CA", "BR", "MX", "GB", "ES", "IT", "KR", "AU", "AE", "PL", "CZ", "TH", "DE"]


def main() -> None:
    rnd = random.Random(42)
    pools = {d: [(f"Sample {'Athlete' if d in MALE else 'Competitor'} {d.upper()}-{i:02d}",
                  rnd.choice(COUNTRIES)) for i in range(1, 21)] for d in DIVS}

    contests = []
    day = date(2026, 1, 10)
    n = 0
    while day < date(2027, 3, 1):
        city, cc = rnd.choice(CITIES)
        n += 1
        divs = ["mens-open", "classic-physique", "mens-physique", "bikini"] + rnd.sample(DIVS[4:], rnd.randint(0, 4))
        if rnd.random() < 0.5:
            divs.append("212")
        divs = sorted(set(divs), key=DIVS.index)
        name = f"Demo {city} Pro #{n}"
        cid = f"{day.year}-demo-{city.lower().replace(' ', '-')}-pro-{n}"
        c = {
            "id": cid, "name": name, "date": day.isoformat(), "city": city, "country": cc,
            "promoter": "Sample Promotions", "olympiaQualifier": rnd.random() < 0.6, "divisions": divs,
        }
        if rnd.random() < 0.2:
            c["endDate"] = (day + timedelta(days=1)).isoformat()
        fields = {d: rnd.sample(pools[d], rnd.randint(5, 14)) for d in divs}
        if day < date(2026, 9, 25):
            c["results"] = [{
                "division": d,
                "placings": [{"place": i + 1, "athlete": a, "country": co, "score": (i + 1) * 5 + rnd.randint(-2, 2)}
                             for i, (a, co) in enumerate(f)],
            } for d, f in fields.items()]
        elif day < date(2026, 12, 1):
            c["entrants"] = {d: sorted(a for a, _ in f) for d, f in fields.items()}
        contests.append(c)
        day += timedelta(days=rnd.choice([3, 5, 7, 7, 7, 10]))

    data = {"generatedAt": datetime.now(timezone.utc).isoformat(), "source": "sample", "contests": contests}
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"wrote {len(contests)} contests -> {OUT}")


if __name__ == "__main__":
    main()
