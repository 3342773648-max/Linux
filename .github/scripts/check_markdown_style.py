#!/usr/bin/env python3
"""Markdown 基础格式门禁（无外部依赖，确定性规则）。

规则：
- 不允许行尾空白（fence 内适用同一规则）；
- 不允许连续 3 行以上空行（fence 内同样检查）；
- ATX 标题 `#` 后必须有空格；不允许空标题（fence 外）；
- fence 必须成对；fence 信息串只允许字母数字与 `._-+`；
- 不允许 CRLF 与零宽空格（U+200B）；
- 不允许 tab（fence 内的作为代码示例的 tab 豁免，fence 外报错）；
- 文件必须以单个换行结尾，不允许末尾多余空行。

如果误报让真实内容无法表达，先修内容，不要放宽规则（规则文件本身在 PR 中可见）。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEADING_RE = re.compile(r"^(#{1,6})(.*)$")
FENCE_RE = re.compile(r"^```\s*(.*)$")

errors: list[str] = []


def check_file(path: Path) -> None:
    rel = path.relative_to(ROOT)
    text = path.read_text(encoding="utf-8", errors="replace")

    if "\r" in text:
        errors.append(f"{rel}: 包含 CRLF，请使用 LF 换行")
    if "\u200b" in text:
        errors.append(f"{rel}: 包含零宽空格 U+200B")

    # 统一去掉末尾空白行后逐行检查
    tail = text[len(text.rstrip("\n")) :]
    if tail == "":
        errors.append(f"{rel}: 文件未以换行结尾")
    elif tail != "\n":
        errors.append(f"{rel}: 文件末尾存在多余空行")
    stripped = text.rstrip("\n")
    lines = stripped.split("\n")

    in_fence = False
    blank_run = 0
    fences: list[int] = []

    for idx, raw in enumerate(lines, 1):
        if raw.startswith("```"):
            in_fence = not in_fence
            fences.append(idx)
            m = FENCE_RE.match(raw)
            if m:
                info = m.group(1).strip()
                if not re.fullmatch(r"[A-Za-z0-9._+\-]{0,32}", info):
                    errors.append(f"{rel}:{idx}: fence 信息串不合法: {info!r}")
            continue

        # 行尾空白（fence 内外一致）
        if raw != raw.rstrip():
            errors.append(f"{rel}:{idx}: 行尾存在空白")

        if in_fence:
            blank_run = 0
            # fence 内：仅检查 tab？不报，作为代码示例保留
            continue

        # fence 外
        if "\t" in raw:
            errors.append(f"{rel}:{idx}: 行内存在 tab（请改用空格）")

        if raw.strip() == "":
            blank_run += 1
            if blank_run >= 3:
                errors.append(f"{rel}:{idx}: 连续 3 行以上空行")
        else:
            blank_run = 0

        m = HEADING_RE.match(raw)
        if m:
            hashes, rest = m.group(1), m.group(2)
            if rest == "":
                errors.append(f"{rel}:{idx}: 空标题（{hashes} 后无内容）")
            elif not rest.startswith(" "):
                errors.append(f"{rel}:{idx}: 标题缺少空格: {raw[:40]!r}")

    if in_fence:
        errors.append(f"{rel}: fence 未闭合（``` 数量为奇数，位置: {fences})")
    elif len(fences) % 2:
        errors.append(f"{rel}: fence 数量为奇数（位置: {fences})")


def main() -> int:
    for md in sorted(ROOT.rglob("*.md")):
        if ".git" in md.parts:
            continue
        check_file(md)
    if errors:
        print("\n".join(errors))
        print(f"\nMarkdown 格式检查失败：{len(errors)} 处")
        return 1
    print("Markdown 格式检查通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())