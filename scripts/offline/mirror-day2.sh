#!/usr/bin/env bash
# P1 离线交付链：批量把 Day2 套件镜像载入 local registry（镜像源切换）
#
# 用法：
#   ./mirror-day2.sh [registry]
#     [registry] local registry 地址（默认 127.0.0.1:5000）
#
# 行为：
#   遍历 images-list.txt 中的 Day2 段（标注 # --- Day2 --- 的镜像），
#   逐个调用同目录 registry-load.sh 载入 local registry。
#   containerd mirrors 已指向该 registry（setup-local-registry.sh），
#   kubelet 拉取将自动命中内网——manifest 无需改写即完成镜像源切换。
#
# 注：脚本入库；registry 存储/镜像不入库。

set -euo pipefail

REG="${1:-127.0.0.1:5000}"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$DIR/images-list.txt"

command -v ctr >/dev/null 2>&1 || { echo "错误: 需要 ctr" >&2; exit 1; }

echo "==> Day2 套件镜像批量载入 $REG（ingress-nginx / local-path / monitoring）"
count=0
in_day2=0
while IFS= read -r line; do
  # 段标记：# --- Day2
  if [[ "$line" == \#*"-- Day2"* ]]; then
    in_day2=1
    continue
  fi
  [[ -z "$line" || "$line" == \#* ]] && continue
  if [ "$in_day2" -eq 1 ]; then
    # 直接以清单中的 tag 引用调用 registry-load（内部解析本地 digest 并保留 tag 提交）
    # 本地可能只有 digest 引用（无 tag 行）——先确认该 repo 本地存在
    repo_part="${line%%:*}"
    if ! ctr -n k8s.io i list -q 2>/dev/null | grep -qE "^$repo_part(:|@)"; then
      echo "  [skip] 本地无 $line（未部署该镜像？）"
      continue
    fi
    echo "==> 载入 $line"
    "$DIR/registry-load.sh" "$line" "$REG" || echo "  [FAIL] $line" >&2
    count=$((count+1))
  fi
done < "$LIST"

echo "==> 完成: 载入 $count 个 Day2 镜像 → $REG"
echo "    containerd mirrors 已生效，kubelet/pod 拉取将命中内网 registry（无需改 manifest）"