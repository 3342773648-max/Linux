#!/usr/bin/env bash
# P1 离线交付链：部署 local registry + 配置 containerd mirrors
#
# 用法：
#   ./setup-local-registry.sh [REG] [PLATFORM]
#     REG       local registry 地址（默认 127.0.0.1:5000）
#     PLATFORM  本机架构（默认 linux/arm64）
#
# 行为（幂等，可重跑）：
#   1. 若无 registry 二进制，从 GitHub release 下载 distribution/registry 并安装
#   2. 生成 systemd 服务（registry serve /etc/registry/config.yml，监听 REG）
#   3. 配置 containerd 的 /etc/containerd/certs.d/ hosts.toml：
#      registry.k8s.io / quay.io / docker.io / rancher → 该 REG（pull/resolve/push）
#   4. daemon-reload + restart containerd
#
# 注：镜像 tar、registry 存储不入库；脚本入库。
#
# 实测环境（bootstrap-day2）：bootstrap 无 docker，registry 以二进制 + systemd 运行
#   （distribution v2.8.3，linux/arm64），containerd v2.3.3 config_path 方式生效。

set -euo pipefail

REG="${1:-127.0.0.1:5000}"
PLATFORM="${2:-linux/arm64}"
REG_VER="2.8.3"
ARCH="${PLATFORM##*/}"

echo "==> 1/4 安装 registry 二进制（若缺失）"
if command -v registry >/dev/null 2>&1; then
  echo "  已安装: $(registry --version 2>&1 | head -1)"
else
  echo "  下载 distribution/registry v${REG_VER} ${ARCH}..."
  curl -fsSL --max-time 120 \
    "https://github.com/distribution/distribution/releases/download/v${REG_VER}/registry_${REG_VER}_${ARCH}.tar.gz" \
    | tar xz -C /tmp registry
  mv /tmp/registry /usr/local/bin/registry && chmod +x /usr/local/bin/registry
  echo "  安装完成: $(registry --version 2>&1 | head -1)"
fi

echo "==> 2/4 生成 systemd 服务（/etc/registry/config.yml）"
mkdir -p /etc/registry /var/lib/registry
cat > /etc/registry/config.yml <<EOF
version: 0.1
log:
  level: info
storage:
  filesystem:
    rootdirectory: /var/lib/registry
http:
  addr: ${REG}
  headers:
    Access-Control-Allow-Origin: ['*']
EOF

cat > /etc/systemd/system/local-registry.service <<EOF
[Unit]
Description=Local OCI Registry (P1 offline delivery chain)
After=network.target

[Service]
ExecStart=/usr/local/bin/registry serve /etc/registry/config.yml
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now local-registry 2>/dev/null || true
sleep 1
if curl -s --max-time 3 "http://${REG}/v2/" >/dev/null 2>&1; then
  echo "  [OK] local-registry active (${REG})"
else
  echo "  [WARN] local-registry 未响应，检查: systemctl status local-registry" >&2
fi

echo "==> 3/4 配置 containerd mirrors（${REG} 作为 registry.k8s.io/quay.io/docker.io/rancher 上游）"
# 关键：启用 config_path（containerd CRI 由此读取 certs.d/hosts.toml）。
# 只改 cri.images 段（位于 [plugins.'io.containerd.cri.v1.images'.registry] 下），
# 避免误伤 nri.plugin_config_path 与 transfer.config_path。
python3 - <<'PYEOF'
import re
p = "/etc/containerd/config.toml"
s = open(p).read()
# 定位 cri 段内的 config_path（行首 6 空格缩进，紧随 cri registry 段）
cri_section = "io.containerd.cri.v1.images"
marker = f"[plugins.'{cri_section}'.registry]"
if marker in s:
    seg, rest = s.split(marker, 1)
    # 段内第一个 config_path 行（格式:      config_path = '...' 或 "..."）
    def repl(m):
        return re.sub(r"config_path = ['\"][^'\"]*['\"]", 'config_path = "/etc/containerd/certs.d"', m.group(0), count=1)
    # 精确到下一个 [plugins. 之前
    next_sec = re.search(r"\n\s*\[plugins\.", rest)
    scope = rest[:next_sec.start()] if next_sec else rest
    fixed = re.sub(r"config_path = [^#\n]*", 'config_path = "/etc/containerd/certs.d"', scope, count=1)
    open(p, "w").write(seg + marker + fixed + rest[next_sec.start():] if next_sec else seg + marker + fixed)
    print("  [OK] cri.images.registry.config_path -> /etc/containerd/certs.d")
else:
    print("  [WARN] 未找到 cri registry 段，手动检查 config.toml")
PYEOF

mkdir -p "/etc/containerd/certs.d/${REG}"
for src in registry.k8s.io quay.io docker.io rancher; do
  cat > "/etc/containerd/certs.d/${src}/hosts.toml" <<EOF
server = "https://${src}"

[host."http://${REG}"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF
done
echo "  已写入: /etc/containerd/certs.d/{registry.k8s.io,quay.io,docker.io,rancher}/hosts.toml"

echo "==> 4/4 重启 containerd 使镜像源生效"
systemctl daemon-reload
systemctl restart containerd
if systemctl is-active containerd >/dev/null 2>&1; then
  echo "  [OK] containerd active"
else
  echo "  [WARN] containerd 重启失败，检查: journalctl -u containerd --no-pager -n 20" >&2
  exit 1
fi

echo "==> 完成。离线交付链 registry + mirrors 就绪"
echo "    用 registry-load.sh 载入镜像后，containerd 拉取将优先走 ${REG}"