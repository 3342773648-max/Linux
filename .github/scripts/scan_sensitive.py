#!/usr/bin/env python3
"""敏感字段与危险示例扫描（B0 门禁，无外部依赖）。

扫描范围：仓库内全部 `.md` / `.yml` / `.yaml` / `.ini` / `.cfg` / `.toml` / `.txt` /
`.env*` 文件（跳过 `.git/`、`.github/scripts/` 自身与允许清单文件——脚本与允许清单属于 PR
审查对象，不允许在其中存放真实凭据）。

规则：本文档与 `docs/security-boundaries.md` 第 1/7 节保持一致。受检内容包括：
- kubeadm bootstrap Token 形状（官方格式 `[a-z0-9]{6}.[a-z0-9]{16}`）；
- `gpgcheck=0` / `repo_gpgcheck=0`（含空格变体）；
- 明文 `ansible_password` / `ansible_ssh_pass`（Inventory / vars / 命令行）；
- 私钥块（RSA / EC / DSA / OpenSSH / 加密私钥）；
- kubeconfig 证书数据（certificate-*-data + 长 base64）；
- haproxy `stats auth 用户:明文口令`（非占位符）；
- SSH / scp / rsync 到 RFC 1918 私有节点地址、`ansible_host` 私有 IP；
- 一般 `password:` / `passwd:` 明文赋值（非占位符）。

允许清单 `.github/scan-allowlist.txt`：`文件相对路径::整行完整匹配的正则::原因`。
只允许按「文件 + 整行」精确豁免；禁止目录级宽泛排除。危险示例必须短小、带原因、可审查。
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

# (名称, 正则, 说明)
PRIVATE_IP = r"(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3})"

PATTERNS: list[tuple[str, re.Pattern, str]] = [
    (
        "kubeadm-token",
        re.compile(r"\b[a-z0-9]{6}\.[a-z0-9]{16}\b"),
        "疑似 kubeadm bootstrap Token（官方形状）",
    ),
    (
        "gpgcheck-off",
        re.compile(r"(?:repo_)?gpgcheck\s*=\s*0", re.IGNORECASE),
        "关闭软件仓库签名校验",
    ),
    (
        "ansible-password",
        re.compile(r"ansible_(?:password|ssh_pass)\s*[:=]\s*(?:\"([^\"]+)\"|'([^']+)'|(\S+))"),
        "Ansible 明文口令",
    ),
    (
        "private-key",
        re.compile(r"-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----"),
        "私钥块",
    ),
    (
        "kubeconfig-data",
        re.compile(r"(?:certificate-authority-data|client-certificate-data|client-key-data)\s*:\s*[A-Za-z0-9+/=_-]{40,}"),
        "kubeconfig 内嵌证书/密钥数据",
    ),
    (
        "haproxy-stats-auth",
        re.compile(r"stats\s+auth\s+\S+:(?!<)[^#\s][^\s]*"),
        "HAProxy stats 明文口令",
    ),
    (
        "ssh-private-ip",
        re.compile(r"\b(?:scp|ssh|rsync)\s+[^\n]*@(?:" + PRIVATE_IP + r")\b"),
        "SSH/scp 连接到 RFC 1918 私有节点地址",
    ),
    (
        "ansible-host-private-ip",
        re.compile(r"ansible_host\s*[:=]\s*" + PRIVATE_IP + r"\b"),
        "Inventory 中 ansible_host 使用私有节点地址",
    ),
    (
        "plain-password",
        re.compile(r"\b(?:password|passwd)\s*[:=]\s*(?:\"([^\"]+)\"|'([^']+)'|(\S+))"),
        "疑似明文口令赋值",
    ),
]


def load_allowlist() -> list[tuple[str, re.Pattern, str]]:
    entries: list[tuple[str, re.Pattern, str]] = []
    if not ALLOWLIST_FILE.exists():
        return entries
    for lineno, raw in enumerate(
        ALLOWLIST_FILE.read_text(encoding="utf-8").splitlines(), 1
    ):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("::", 2)
        if len(parts) != 3:
            print(f"allowlist 格式错误 {ALLOWLIST_FILE}:{lineno}: {raw!r}")
            sys.exit(2)
        path, regex, reason = parts
        try:
            compiled = re.compile(regex)
        except re.error as exc:
            print(f"allowlist 正则错误 {ALLOWLIST_FILE}:{lineno}: {exc}")
            sys.exit(2)
        if not reason.strip():
            print(f"allowlist 缺少原因 {ALLOWLIST_FILE}:{lineno}")
            sys.exit(2)
        entries.append((path, compiled, reason))
    return entries


def main() -> int:
    allowlist = load_allowlist()
    hits: list[str] = []
    allow_used: list[str] = []

    files = sorted(p for p in ROOT.rglob("*") if p.is_file())
    for path in files:
        rel_parts = path.relative_to(ROOT).parts
        if any(part in SKIP_PARTS for part in rel_parts):
            continue
        name = path.name
        if not (path.suffix in SCAN_SUFFIXES or name.startswith(SCAN_PREFIXES)):
            continue
        if path.resolve().parent == SCRIPT_DIR:
            continue
        if path == ALLOWLIST_FILE:
            continue

        text = path.read_text(encoding="utf-8", errors="replace")
        for lineno, line in enumerate(text.splitlines(), 1):
            for label, regex, desc in PATTERNS:
                if not regex.search(line):
                    continue
                # 允许清单：整行完全匹配才豁免
                exempt = False
                for allow_path, allow_re, reason in allowlist:
                    if allow_path == str(path.relative_to(ROOT)) and allow_re.fullmatch(line):
                        allow_used.append(f"{path.relative_to(ROOT)}:{lineno} [{label}] {reason}")
                        exempt = True
                        break
                if not exempt:
                    hits.append(f"{path.relative_to(ROOT)}:{lineno} [{label}] {desc}: {line.strip()[:90]!r}")

    for line in allow_used:
        print(f"[allow] {line}")
    if hits:
        print("\n".join(hits))
        print(f"\n敏感扫描失败：{len(hits)} 处命中；如需豁免，编辑 {ALLOWLIST_FILE.name} 并以整行正则精确允许")
        return 1
    print(f"敏感扫描通过（扫描文件数大于等于 {len(files)}，实际按扩展名过滤；allowlist 命中 {len(allow_used)} 条）")
    return 0


if __name__ == "__main__":
    sys.exit(main())