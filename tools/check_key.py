"""Report whether .env holds a usable GEMINI_API_KEY - without ever printing it.

Exit codes
  0  key present
  3  .env file missing
  4  key missing or empty
"""
import re
import sys
from pathlib import Path


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(".env")
    if not path.exists():
        print(f"  MISS no .env file at {path}")
        return 3

    key = ""
    text = path.read_text(encoding="utf-8-sig", errors="replace")
    for line in text.splitlines():
        m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$", line)
        if m and m.group(1).upper() == "GEMINI_API_KEY":
            key = m.group(2).strip().strip('"').strip("'")

    if not key:
        print(f"  MISS GEMINI_API_KEY is empty in {path.name}")
        return 4

    prefix = key[:3]
    note = ""
    if prefix.startswith("AQ."):
        note = " (current Google format)"
    elif prefix.startswith("AIza"):
        note = " (older Google format)"
    print(f"  OK   GEMINI_API_KEY present: {len(key)} characters, starts '{prefix}'{note}")
    print("       (the value itself is never printed)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
