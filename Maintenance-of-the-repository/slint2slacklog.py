#!/usr/bin/env python3.11
import re
from datetime import datetime

# Fix common weekday typos
WEEKDAY_FIX = {
    "Wedesday": "Wednesday",
    "Teusday": "Tuesday",
    "Thurday": "Thursday"
}

# Regex for weekday-date lines, e.g., "Sunday 16 March 2025"
weekday_date_re = re.compile(
    r"^(?P<weekday>[A-Za-z]+)\s+(?P<day>\d{1,2}|O\d)\s+(?P<month>[A-Za-z]+)(?:\s+(?P<year>\d{4}))?"
)

# Regex for "Packages in the repository on 12 July 2022"
packages_re = re.compile(r"^Packages in the repository on (\d{1,2}) (\w+) (\d{4})")

# Regex to detect package lines ending in .txz or .tgz
package_line_re = re.compile(r"^[A-Za-z0-9._+-]+-\d.*\.(txz|tgz)$")

CURRENT_YEAR = datetime.now().year

def normalize_date_line(line: str) -> str | None:
    line = line.strip()

    # Fix weekday typos
    for bad, good in WEEKDAY_FIX.items():
        if line.startswith(bad):
            line = line.replace(bad, good, 1)

    # Match standard weekday date lines like "Sunday March 16 2025"
    m = weekday_date_re.match(line)
    if m:
        weekday, day, month, year = m.groups()
        if day.startswith("O"):
            day = day.replace("O", "0")
        year = year or str(CURRENT_YEAR)
        try:
            # Build a datetime object
            d = datetime.strptime(f"{day} {month} {year}", "%d %B %Y")
            # Return with full timestamp and UTC
            return d.strftime("%a %b %d 00:00:00 UTC %Y")
        except ValueError:
            return None

    # Match "Packages in the repository on 12 July 2022"
    m = packages_re.match(line)
    if m:
        day, month, year = m.groups()
        try:
            d = datetime.strptime(f"{day} {month} {year}", "%d %B %Y")
            return d.strftime("%a %b %d 00:00:00 UTC %Y")
        except ValueError:
            return None

    return None



def convert(infile, outfile):
    with open(infile, "r", encoding="utf-8", errors="ignore") as fin, \
         open(outfile, "w", encoding="utf-8") as fout:

        for raw_line in fin:
            line = raw_line.strip()

            # Normalize date headers
            norm = normalize_date_line(line)
            if norm:
                fout.write(norm + "\n")
                continue

            # Detect bare package names
            if package_line_re.match(line):
                fout.write(f"  {line}:  Added.\n")
                continue

            # Default: write back unchanged
            fout.write(raw_line)

if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} ChangeLog.txt CleanChangeLog.txt")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
