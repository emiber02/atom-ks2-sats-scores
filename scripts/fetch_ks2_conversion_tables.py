"""Download the official GOV.UK 2025 KS2 scaled score conversion tables and write them as a seed CSV.

Usage: python scripts/fetch_ks2_conversion_tables.py > seeds/ks2_scaled_score_conversion.csv

Raw scores with "No scaled score" (0-2) are written with an empty scaled_score.
"""
import csv
import html
import re
import sys
import urllib.request

SOURCE_YEAR = 2025
URL = (
    "https://www.gov.uk/government/publications/key-stage-2-tests-2025-scaled-scores/"
    "2025-key-stage-2-scaled-score-conversion-tables"
)
TEST_CODES = {
    "English grammar, punctuation and spelling": "ENGLISH_GPS",
    "English reading": "ENGLISH_READING",
    "Mathematics": "MATHS",
}


def strip(fragment: str) -> str:
    return html.unescape(re.sub(r"<[^>]+>", "", fragment)).strip()


def main() -> None:
    page = urllib.request.urlopen(URL).read().decode("utf-8")
    headings = [(m.start(), strip(m.group(1))) for m in re.finditer(r"<h[23][^>]*>(.*?)</h[23]>", page, re.S)]
    out = csv.writer(sys.stdout, lineterminator="\n")
    out.writerow(["source_year", "test_code", "raw_score", "max_raw_score", "scaled_score"])
    for table in re.finditer(r"<table.*?</table>", page, re.S):
        heading = [h for pos, h in headings if pos < table.start()][-1]
        code = TEST_CODES[heading]
        rows = []
        for tr in re.findall(r"<tr>(.*?)</tr>", table.group(0), re.S)[1:]:
            raw, scaled = [strip(c) for c in re.findall(r"<t[dh][^>]*>(.*?)</t[dh]>", tr, re.S)]
            lo, _, hi = raw.partition("-")
            for r in range(int(lo), int(hi or lo) + 1):
                rows.append((r, "" if not scaled.isdigit() else int(scaled)))
        max_raw = max(r for r, _ in rows)
        for r, s in rows:
            out.writerow([SOURCE_YEAR, code, r, max_raw, s])


if __name__ == "__main__":
    main()
