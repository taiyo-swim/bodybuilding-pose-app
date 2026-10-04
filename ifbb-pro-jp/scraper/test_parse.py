"""パーサーの簡易テスト（通信なし）: python test_parse.py"""
from scrape import parse_contest, parse_dates, parse_location, parse_placing_line, parse_schedule

HTML = """<html><body><header><a href="/contest/ignored/">x</a></header><main>
<h1>2026 Example Pro | IFBB Pro League</h1>
<p>Date: March 6-7, 2026</p><p>Location: Columbus, OH</p><p>Promoter: Example Promotions</p>
<p>Olympia Qualifier</p>
<h3>Men's Open</h3>
<ol><li>1. JOHN DOE (USA)</li><li>2nd Jane-Paul Roe</li><li>3 - Kenji Tanaka (Japan)</li></ol>
<a href="/wp-content/uploads/mens-open-scorecard.pdf">Men's Open Scorecard</a>
<h3>Bikini</h3>
<p>1. Anna Smith<br>2. Maria Lopez</p>
<h3>Classic Physique</h3>
<table><tr><th>Place</th><th>Name</th><th>Score</th></tr>
<tr><td>1</td><td>Alex Example</td><td>5</td></tr><tr><td>2</td><td>Bob Example</td><td>11</td></tr></table>
</main></body></html>"""


def main() -> None:
    c = parse_contest(HTML, "https://ifbbpro.com/contest/2026-example-pro/")
    assert c, "parse failed"
    assert c["id"] == "2026-example-pro", c["id"]
    assert c["name"] == "2026 Example Pro", c["name"]
    assert (c["date"], c.get("endDate")) == ("2026-03-06", "2026-03-07"), c
    assert (c.get("city"), c.get("country")) == ("Columbus", "US"), c
    assert c.get("promoter") == "Example Promotions", c.get("promoter")
    assert c["olympiaQualifier"]
    r = {x["division"]: x for x in c["results"]}
    assert [p["athlete"] for p in r["mens-open"]["placings"]] == ["John Doe", "Jane-Paul Roe", "Kenji Tanaka"], r["mens-open"]
    assert r["mens-open"]["placings"][2]["country"] == "JP"
    assert r["mens-open"]["scorecardUrl"].endswith("mens-open-scorecard.pdf")
    assert [p["athlete"] for p in r["bikini"]["placings"]] == ["Anna Smith", "Maria Lopez"], r["bikini"]
    assert r["classic-physique"]["placings"][1] == {"place": 2, "athlete": "Bob Example", "score": 11}

    assert parse_dates("Sep 26 - Oct 1, 2026") == ("2026-09-26", "2026-10-01")
    assert parse_location("Madrid, Spain") == ("Madrid", "ES")
    assert parse_placing_line("Pro Card Winner") is None
    assert parse_schedule(
        '<a href="/contest/a/">a</a><a href="https://ifbbpro.com/contest/b">b</a><a href="/news/x/">n</a>',
        "https://ifbbpro.com/schedule/",
    ) == ["https://ifbbpro.com/contest/a/", "https://ifbbpro.com/contest/b"]
    print("all parser tests passed")


if __name__ == "__main__":
    main()
