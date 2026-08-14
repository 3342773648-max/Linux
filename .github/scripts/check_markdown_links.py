#!/usr/bin/env python3
"""校验仓库内所有 Markdown 的内部相对链接是否有效。"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINK_RE = re.compile(r"\[[^\]]*\]\(([^)]+)\)")

errors = []
for md in sorted(ROOT.rglob("*.md")):
    if ".github" in md.parts:
        continue
    text = md.read_text(encoding="utf-8", errors="replace")
    for target in LINK_RE.findall(text):
        target = target.strip()
        if not target or target.startswith(("http://", "https://", "mailto:", "#")):
            continue
        path_part = target.split("#", 1)[0]
        resolved = (md.parent / path_part).resolve()
        if not resolved.exists():
            errors.append(f"{md.relative_to(ROOT)} -> {target}")

if errors:
    print("\n".join(errors))
    sys.exit(1)
print("All internal markdown links OK")