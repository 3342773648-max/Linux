#!/usr/bin/env python3
"""scan_sensitive 正例/反例回归测试（stdlib unittest，无第三方依赖）。

运行：python -m unittest discover -s .github/scripts -p "test_*.py" -v
目的：验证扫描器「确实能识别声称能识别的东西」且不放过安全占位符；同时加载真实
允许清单做自保护校验（条目数、路径存在性）。
"""
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import scan_sensitive as ss

ALLOW_SECURITY_ROW = [
    (
        "docs/security-boundaries.md",
        re.compile(r"\| 关闭软件仓库签名验证 \|.*"),
        "test-only",
    )
]

SAMPLE_ALLOW = [("fixtures/allow.md", re.compile(r"gpgcheck.*=\s*0.*allow"), "test")]


class ScanPositiveTest(unittest.TestCase):
    """应命中的泄露/危险示例。"""

    CASES = [
        "abcdef.0123456789abcdef",  # kubeadm token 形状（6+16）
        "--token 1a2b3c.0123456789abcdef",  # join 命令内 token
        "ansible_password: RealSecret123",
        "ansible_ssh_pass = hunter2",
        "-----BEGIN PRIVATE KEY-----",  # PKCS#8
        "-----BEGIN RSA PRIVATE KEY-----",
        "-----BEGIN EC PRIVATE KEY-----",
        "-----BEGIN OPENSSH PRIVATE KEY-----",
        "token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0",
        "client-key-data: ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmn",
        "stats auth admin:changeMe123",
        "ssh root@192.168.1.10 uptime",
        "scp file.txt ops@10.0.0.5:/tmp",
        'rsync -av data root@172.16.5.5:/srv',
        "password: SuperSecret!",
        "passwd: s3cret-value",
        "gpgcheck=0",
        "repo_gpgcheck = 0",
    ]

    def test_each_case_is_flagged(self):
        allowlist: list = []
        for case in self.CASES:
            with self.subTest(case=case):
                hits = ss.scan_text("fixtures/positive.md", case + "\n", allowlist)
                self.assertTrue(hits, f"应命中但未命中: {case!r}")


class ScanNegativeTest(unittest.TestCase):
    """安全占位符 / 合法内容不应命中。"""

    CASES = [
        "--token <BOOTSTRAP_TOKEN>",
        "--discovery-token-ca-cert-hash sha256:<CA_CERT_HASH>",
        "ansible_password: <PASSWORD>",
        "ansible_password: ${VAULT_PASSWORD}",
        "ansible_password: {{ vault_password }}",
        "ansible_password: !vault |",
        "ansible_password: lookup('env','SECRET')",
        "password: yes",
        "password: false",
        "stats auth admin:<HAPROXY_STATS_PASSWORD>",
        "auth_pass <KEEPALIVED_AUTH_PASS>",
        "ssh root@192.0.2.11",  # RFC 5737 文档地址
        "ssh -i ~/.ssh/id_ed25519 ops@example.org",
        "kubeadm token create --print-join-command",  # 命令而非 token 值
        "token 默认 TTL 24 小时",
        "curl https://example.com/install.sh | sh  # 示例占位",
        "ansible_user=ops",  # 用户名不是口令
        "ansible_private_key_file=~/.ssh/id_ed25519",  # 密钥路径而非口令
    ]

    def test_each_case_is_clean(self):
        allowlist: list = []
        for case in self.CASES:
            with self.subTest(case=case):
                hits = ss.scan_text("fixtures/negative.md", case + "\n", allowlist)
                self.assertEqual(hits, [], f"误报: {case!r} -> {hits}")


class AllowlistScenarioTest(unittest.TestCase):
    """安全文档中允许清单精确豁免「整行」的场景。"""

    def test_allowlisted_row_is_exempt_but_other_rows_are_not(self):
        row = "| 关闭软件仓库签名验证 | `gpgcheck=0`、`repo_gpgcheck=0` 或删除 gpgkey 校验（危险示例，见允许清单） |"
        hits = ss.scan_text("docs/security-boundaries.md", row + "\n", ALLOW_SECURITY_ROW)
        self.assertEqual(hits, [])
        # 被豁免的行必须整行完全匹配，其他含 gpgcheck=0 的行仍应命中
        other = "echo gpgcheck=0 > /etc/yum.repos.d/bad.repo"
        hits = ss.scan_text("docs/security-boundaries.md", other + "\n", ALLOW_SECURITY_ROW)
        self.assertEqual(len(hits), 1)
        self.assertIn("gpgcheck-off", hits[0])

    def test_placeholder_value_not_flagged_even_without_allowlist(self):
        line = "ansible_password: {{ vault_password }}"
        self.assertEqual(ss.scan_text("x.yml", line + "\n", []), [])


class RealAllowlistProbeTest(unittest.TestCase):
    """加载真实允许清单：条目数>=3、路径全部存在、正则可编译（自保护）。"""

    def test_real_allowlist_loads_and_paths_exist(self):
        entries = ss.load_allowlist()
        self.assertGreaterEqual(len(entries), 3)
        for path, regex, reason in entries:
            with self.subTest(path=path):
                self.assertTrue((ss.ROOT / path).exists(), f"allowlist 路径不存在: {path}")
                self.assertTrue(reason.strip())


if __name__ == "__main__":
    unittest.main(verbosity=2)