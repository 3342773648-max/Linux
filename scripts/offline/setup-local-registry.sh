#!/usr/bin/env bash
# P1 离线交付链：部署 local registry 并让 containerd 走内网镜像源
#
# 用法：
#   ./setup-local-registry.sh [registry:2 版本] [registry IP:PORT]
#     默认 registry:2.8（arm64 多架构），默认 192.0.2.2:5000（RFC 5737 文档地址，
#     实际部署时按真实内网地址覆盖，或从 gitignored local.yml / env 读取）
#
# 行为（幂等）：
#   1. 起一个 registry:2 容器（docker run，若宿主无 docker 则提示改用
#      ctr + 静态 pod 方式——离线交付链要求目标节点本身先在 bootstrap 阶段有 docker
#      或直接复用任意内网已有的 registry）
#   2. 写 containerd 镜像源镜像表（config_path 指向 /etc/containerd/certs.d/<reg>/hosts.toml，
#      所有 registry.k8s.io / quay.io / docker.io / rancher 均 mirror 到本 registry）
#   3. daemon-reload 重启 containerd
#
# 注：registry 容器/数据不入库；脚本入库、密码不入库。断网验收 = iptables 阻断
#     除本 registry 外的出站（见 verify-offline.sh / 离线手册）。

set -euo pipefail

REG="${1:-192.0.2.2:5000}"
REG_VER="${2:-2.8}"

command -v docker >/dev/null 2>&1 || {
  echo "错误: 需要 docker 来运行 registry:2 容器（或用已有内网 registry 替换 REG）" >&2
  echo "      若目标节点无 docker，可先跑 export/import 直接注入 containerd,再手动起 registry。" >&2
  exit 1
}

echo "==> 1/3 启动 local registry $REG (registry:$REG_VER)"
if ! docker ps --format '{{.Names}}' | grep -qx local-registry; then
  docker run -d --name local-registry -p "${REG##*:}:5000" \
    -v local-registry-data:/var/lib/registry \
    --restart=unless-stopped "registry:$REG_VER" >/dev/null
fi
docker ps --filter name=local-registry --format '{{.Names}} {{.Status}}'

echo "==> 2/3 配置 containerd mirrors -> $REG"
mkdir -p "/etc/containerd/certs.d/$REG"
for src in registry.k8s.io quay.io docker.io rancher; do
  cat > "/etc/containerd/certs.d/$src/hosts.toml" <<EOF
server = "https://$src"

[host."http://$REG"]
  capabilities = ["pull", "resolve"]
  skip_verify = true
EOF
done

echo "==> 3/3 重启 containerd 使镜像源生效"
systemctl daemon-reload
systemctl restart containerd

echo "==> 完成。离线机 containerd 拉取 registry.k8s.io/quay.io/docker.io/rancher 镜像时"
echo "    优先走内网 $REG；断网验收见 verify-offline.sh 与 docs/offline-delivery.md"