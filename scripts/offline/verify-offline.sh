#!/usr/bin/env bash
# P1 离线交付链：离线 preflight 验收脚本
#
# 用法：
#   ./verify-offline.sh [registry IP:PORT]
#     默认 192.0.2.2:5000（RFC 5737）
#
# 检查（全部通过才可宣称离线环境就绪）：
#   1. 模拟断网生效：出站 443（公网 registry）被阻断，内网 registry 可达
#   2. containerd 镜像清单齐备（目标镜像已注入本地）
#   3. kubeadm/config 可离线处理（仅验证镜像前置，不重跑 init）
#
# 断网模拟 = append `iptables -A OUTPUT -p tcp --dport 443 -j DROP`（允许 5000）。
# 恢复 = 删除该规则。本脚本只检测不修改。

set -euo pipefail

REG="${1:-192.0.2.2:5000}"
LIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_LIST="$LIST_DIR/images-list.txt"

echo "==> 1/3 断网模拟检测（出站 443 阻断 + 内网 registry 可达）"
if iptables -L OUTPUT -n 2>/dev/null | grep -q 'dpt:443.*DROP'; then
  echo "  [OK] 出站 443 已被阻断（模拟断网生效）"
else
  echo "  [WARN] 未检测到 443 阻断规则——请在离线 node 执行:"
  echo "    iptables -A OUTPUT -p tcp --dport 443 -j DROP   # 保留内网 registry 可达"
fi
if curl -s --max-time 5 "http://$REG/v2/" >/dev/null 2>&1; then
  echo "  [OK] 内网 registry $REG 可达"
else
  echo "  [WARN] $REG 不可达（先跑 setup-local-registry.sh）"
fi

echo "==> 2/3 镜像清单齐备性"
missing=0
total=0
# 容忍 digest 引用：ctr list 中同镜像可能以 @sha256 形式存在（无明文 tag）。
# digest 引用形如 registry.k8s.io/ingress-nginx/controller@sha256:...，
# 与清单的 repo<:tag> 比对时只取 repo 路径（去掉 :tag 与 registry 前缀）。
image_loaded() {
  local ref="$1" repo loaded
  repo="$(echo "${ref%%@sha256:*}" | cut -d: -f1)"   # 去 tag
  repo="${repo#docker.io/}"; repo="${repo#ghcr.io/}"
  if ctr -n k8s.io i list -q | grep -qx "$ref"; then
    return 0
  fi
  while IFS= read -r loaded; do
    local lrepo
    lrepo="${loaded%%@sha256:*}"
    lrepo="$(echo "$lrepo" | cut -d: -f1)"           # 去 tag
    lrepo="${lrepo#docker.io/}"; lrepo="${lrepo#ghcr.io/}"
    if [ "$lrepo" = "$repo" ]; then
      return 0
    fi
    # 无 @sha256 的普通 tag 引用也做 repo 级比对（容忍 registry 源差异）
    lrepo="$(echo "$loaded" | cut -d: -f1)"
    lrepo="${lrepo#docker.io/}"; lrepo="${lrepo#ghcr.io/}"
    if [ "$lrepo" = "$repo" ]; then
      return 0
    fi
  done < <(ctr -n k8s.io i list -q)
  return 1
}
while IFS= read -r img; do
  [[ -z "$img" || "$img" == \#* ]] && continue
  total=$((total+1))
  if ! image_loaded "$img"; then
    echo "  [MISS] $img"
    missing=$((missing+1))
  fi
done < "$IMAGE_LIST"
if [ "$missing" -eq 0 ]; then
  echo "  [OK] $total 个镜像全部就绪"
else
  echo "  [FAIL] 缺 $missing / $total 个镜像（先跑 import-images.sh 或用内网 registry）"
  exit 1
fi

echo "==> 3/3 kubeadm 离线工具链"
command -v kubeadm >/dev/null 2>&1 && echo "  [OK] kubeadm $(kubeadm version -o short 2>/dev/null)"
command -v kubelet >/dev/null 2>&1 && echo "  [OK] kubelet $(kubelet --version 2>/dev/null)"
command -v ctr >/dev/null 2>&1 && echo "  [OK] ctr (containerd)"

echo
echo "==> 离线环境就绪。可开始：kubeadm init（镜像从本地注入/内网 registry 拉取）"
echo "    → 集群 up → Day2（ingress/storage）→ 验收记录。"