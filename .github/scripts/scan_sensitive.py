#!/usr/bin/env python3
"""敏感字段与危险示例扫描（B0 门禁，无外部依赖，可单元测试）。

扫描范围：仓库内全部 `.md` / `.yml` / `.yaml` / `.ini` / `.cfg` / `.toml` / `.txt` /
`.env*` 文件（跳过 `.git/`、`.github/scripts/` 自身与允许清单文件——脚本与允许清单属于 PR
审查对象，不允许在其中存放真实凭据）。

规则：本文档与 `docs/security-boundaries.md` 第 1/7 节保持一致。受检内容包括：
- kubeadm bootstrap Token 形状（官方格式 `[a-z0-9]{6}.[a-z0-9]{16}`）；
- `gpgcheck=0` / `repo_gpgcheck=0`（含空格变体）；
- 明文 `ansible_password` / `ansible_ssh_pass`（Inventory / vars / 命令行）；
- 私钥块（RSA / EC / DSA / OpenSSH / PKCS#8 / 加密私钥）；
- kubeconfig 内嵌凭据数据（`token:` / `certificate-*-data:` + 长 base64 形状）；
- haproxy `stats auth 用户:明文口令`（非占位符）；
- SSH / scp / rsync 命令行连接到 RFC 1918 私有地址（启发式，见 security-boundaries.md 第 7 节）；
- 一般 `password:` / `passwd:` 明文赋值（忽略布尔值 `yes/no/true/false` 与安全占位符）。

说明：
- Token 形状、SSH/RFC1918 等规则是**泄露启发式检测**，不是凭据有效性检测；真实凭据可能经过
  变量拼接、base64、跨行拆分等绕过——这些不在 B0 承诺内，见 security-boundaries.md 第 7 节。
- Inventory 变量中的 IP 本身不是凭据，不扫描 `ansible_host=10.x`（避免与合法私有实验网段冲突）。

允许清单 `.github/scan-allowlist.txt`：`文件相对路径::整行完整匹配的正则::原因`。
只允许按「文件 + 整行」精确豁免；禁止目录级宽泛排除；允许清单自身在加载时校验（字段数、
路径存在、原因非空、拒绝明显全匹配正则），防止允许清单成为绕过入口。
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT_DIR = Path(__file__).resolve().parent
ALLOWLIST_FILE = ROOT / ".github" / "scan-allowlist.txt"

SKIP_PARTS = {".git", ".github", "node_modules", ".venv", "venv", "dist", "artifacts"}

# 仅扫描这些扩展名；.github 整体跳过因此脚本自身不会误报
SCAN_SUFFIXES = (".md", ".yml", ".yaml", ".ini", ".cfg", ".toml", ".txt", ".env")
SCAN_PREFIXES = (".env",)

PRIVATE_IP = (
    r"(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}"
    r"|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}"
    r"|192\.168\.\d{1,3}\.\d{1,3})"
)

# 明显全匹配/过宽正则黑名单：允许清单不得用这些绕过
FORBIDDEN_ALLOW_REGEX = {
    ".*", "^.*$", ".+", "^.+$", "^.*", ".*$", ".*.*", ".*?",
}


def is_placeholder(value: str) -> bool:
    """值是否为安全占位符/引用（<...>，${...}，{{ ... }}，!vault |，lookup(...)，布尔字面量）。"""
    v = value.strip().strip('"\'')
    if not v:
        return True
    if v.lower() in {"yes", "no", "true", "false"}:
        return True
    if v.startswith(("<", "${", "{{", "!vault", "lookup(", "!")):
        return True
    return False


# (名称, 正则, 说明, 是否需要值级占位符判断)
MATCHERS: list[tuple[str, re.Pattern, str, bool]] = [
    (
        "kubeadm-token",
        re.compile(r"\b[a-z0-9]{6}\.[a-z0-9]{16}\b"),
        "疑似 kubeadm bootstrap Token 形状（泄露启发式）",
        False,
    ),
    (
        "gpgcheck-off",
        re.compile(r"(?:repo_)?gpgcheck\s*=\s*0", re.IGNORECASE),
        "关闭软件仓库签名校验",
        False,
    ),
    (
        "ansible-password",
        re.compile(
            r"ansible_(?:password|ssh_pass)\s*[:=]\s*(?:\"([^\"]+)\"|'([^']+)'|(\S+))",
            re.IGNORECASE,
        ),
        "Ansible 明文口令",
        True,
    ),
    (
        "private-key",
        re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
        "私钥块（RSA/EC/DSA/OpenSSH/PKCS#8/加密）",
        False,
    ),
    (
        "kubeconfig-data",
        re.compile(
            r"\b(?:token|client-key-data|client-certificate-data|certificate-authority-data)"
            r"\s*:\s*[A-Za-z0-9+/=_-]{16,}"
        ),
        "kubeconfig / 配置文件内嵌凭据数据（token、certificate-*-data）",
        False,
    ),
    (
        "haproxy-stats-auth",
        re.compile(r"stats\s+auth\s+\S+:(?!<)[^#\s][^\s]*"),
        "HAProxy stats 明文口令",
        False,
    ),
    (
        "ssh-private-ip",
        re.compile(r"\b(?:scp|ssh|rsync)\s+[^\n]*@(?:" + PRIVATE_IP + r")\b"),
        "SSH/scp/rsync 命令行连接到 RFC 1918 私有地址（泄露启发式）",
        False,
    ),
    (
        "plain-password",
        re.compile(
            r"\b(?:password|passwd)\s*[:=]\s*(?:\"([^\"]+)\"|'([^']+)'|(\S+))",
            re.IGNORECASE,
        ),
        "疑似明文口令赋值",
        True,
    ),
]


def load_allowlist() -> list[tuple[str, re.Pattern, str]]:
    """加载允许清单并做自保护校验：字段数、路径存在、原因非空、拒绝明显过宽正则。"""
    entries: list[tuple[str, re.Pattern, str]] = []
    if not ALLOWLIST_FILE.exists():
        return entries
    problems: list[str] = []
    for lineno, raw in enumerate(ALLOWLIST_FILE.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("::", 2)
        if len(parts) != 3:
            problems.append(f"allowlist 行 {lineno} 字段数不为 3: {raw[:80]!r}")
            continue
        path, regex, reason = parts
        if not regex or regex in FORBIDDEN_ALLOW_REGEX or len(regex) < 3:
            problems.append(f"allowlist 行 {lineno} 正则过宽或非法: {regex!r}")
            continue
        try:
            compiled = re.compile(regex)
        except re.error as exc:
            problems.append(f"allowlist 行 {lineno} 正则错误: {exc}")
            continue
        if not reason.strip():
            problems.append(f"allowlist 行 {lineno} 缺少原因")
            continue
        if not (ROOT / path).exists():
            problems.append(f"allowlist 行 {lineno} 路径不存在: {path!r}")
            continue
        entries.append((path, compiled, reason))
    if problems:
        print("allowlist 自保护校验失败:")
        print("\n".join(problems))
        sys.exit(2)
    return entries


def scan_text(path_rel: str, text: str, allowlist: list[tuple[str, re.Pattern, str]]) -> list[str]:
    """对一段文本执行全部扫描规则，返回未豁免的命中行列表（含定位）。"""
    hits: list[str] = []
    for lineno, line in enumerate(text.splitlines(), 1):
        for name, regex, desc, value_based in MATCHERS:
            m = regex.search(line)
            if not m:
                continue
            if value_based:
                value = m.group(1) or m.group(2) or m.group(3) or ""
                if is_placeholder(value):
                    continue
            exempt = False
            for allow_path, allow_re, _reason in allowlist:
                if allow_path == path_rel and allow_re.fullmatch(line):
                    exempt = True
                    break
            if not exempt:
                hits.append(f"{path_rel}:{lineno} [{name}] {desc}: {line.strip()[:90]!r}")
    return hits


def main() -> int:
    allowlist = load_allowlist()
    hits: list[str] = []
    files = sorted(p for p in ROOT.rglob("*") if p.is_file())
    scanned = 0
    for path in files:
        rel = path.relative_to(ROOT)
        if any(part in SKIP_PARTS for part in rel.parts):
            continue
        if path.resolve().parent == SCRIPT_DIR or path == ALLOWLIST_FILE:
            continue
        name = path.name
        if not (path.suffix in SCAN_SUFFIXES or name.startswith(SCAN_PREFIXES)):
            continue
        scanned += 1
        text = path.read_text(encoding="utf-8", errors="replace")
        hits.extend(scan_text(str(rel), text, allowlist))

    if hits:
        print("\n".join(hits))
        print(
            f"\n敏感扫描失败：{len(hits)} 处命中；如需豁免，编辑 {ALLOWLIST_FILE.name} "
            "并以「文件+整行正则+原因」精确允许"
        )
        return 1
    print(f"敏感扫描通过（扫描 {scanned} 个文件；allowlist 条目 {len(allowlist)} 条）")
    return 0


if __name__ == "__main__":
    sys.exit(main())