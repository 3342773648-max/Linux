#!/usr/bin/env bash
# P1 离线交付链：镜像导出（在线机执行）
#
# 用法：
#   ./export-images.sh [namespace] [输出目录]
#     namespace   containerd namespace（默认 k8s.io，kubeadm/CRI 使用）
#     输出目录    归档输出位置（默认 ./out/<date>）
#
# 行为：
#   读取同目录 images-list.txt 中的镜像清单，逐个从本机 containerd
#   导出为单文件 tar（<safe-name>.tar），写入输出目录。
#   若本机缺某镜像，报错列出（可先在本机跑一遍确保齐备）。
#
# 注：镜像本身（tar）不入库——体积与分发另走 U 盘/内网文件服务器；
#     清单 images-list.txt 入库以便版本追踪。

set -euo pipefail

NAMESPACE="${1:-k8s.io}"
OUT_DIR="${2:-out/$(date +%Y%m%d)}"
LIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_LIST="$LIST_DIR/images-list.txt"

command -v ctr >/dev/null 2>&1 || { echo "错误: 需要 containerd 的 ctr 命令" >&2; exit 1; }

# 镜像匹配：ctr list 中同一镜像可能以带 @sha256 digest 的形式存在（无明文 tag），
# 此处用「去掉 digest 后缀的 tag 前缀」做匹配，容忍 registry 源前缀差异（docker.io 等）。
image_loaded() {
  local ref="$1" base dig loaded
  base="${ref%%@sha256:*}"
  if ctr -n "$NAMESPACE" i list -q | grep -qx "$ref"; then
    return 0
  fi
  # 兼容 digest 形式：registry.k8s.io/x:v1.2@sha256:... 与 docker.io/ghcr.io 前缀差异
  while IFS= read -r loaded; do
    dig="${loaded%%@sha256:*}"
    if [ "$dig" = "$base" ] || [ "${dig#docker.io/}" = "${base#docker.io/}" ] || [ "${dig#ghcr.io/}" = "${base#ghcr.io/}" ]; then
      return 0
    fi
  done < <(ctr -n "$NAMESPACE" i list -q | grep '@sha256:')
  return 1
}

mkdir -p "$OUT_DIR"
echo "==> 导出目标: $OUT_DIR (namespace=$NAMESPACE)"

missing=0
exported=0
skipped=""
while IFS= read -r img; do
  # 跳过空行与注释
  [[ -z "$img" || "$img" == \#* ]] && continue
  out_name="$(echo "$img" | tr '/:@' '_')"
  out_file="$OUT_DIR/$out_name.tar"
  if image_loaded "$img"; then
    if [ -f "$out_file" ]; then
      echo "==> 已存在，跳过: $img"
      exported=$((exported+1))
    else
      # 小概率瞬时导出失败（多 blob 镜像 race），重试 3 次
      for attempt in 1 2 3; do
        ctr -n "$NAMESPACE" i export "$out_file" "$img" >/dev/null 2>&1 \
          && break \
          || { echo "  (第 $attempt 次失败，重试) $img" >&2; rm -f "$out_file"; }
      done
      if [ ! -s "$out_file" ]; then
        # 不再整体失败：记录跳过项，离线侧可用内网 registry 拉取兜底
        echo "!! 导出失败(已记入跳过): $img" >&2
        skipped="$skipped $img"
      else
        exported=$((exported+1))
      fi
    fi
  else
    echo "!! 缺失镜像(已记入跳过): $img" >&2
    skipped="$skipped $img"
  fi
done < "$IMAGE_LIST"

if [ -n "$skipped" ]; then
  echo "==> 完成（$exported 个 tar 包），但有 $skipped 未导出:" >&2
  for s in $skipped; do echo "    [跳过] $s" >&2; done
  echo "    离线侧需通过内网 registry 拉取这些镜像（registry 端数据完整即可）。" >&2
fi

echo "==> 导出目录: $OUT_DIR"
echo "    ← 将 $OUT_DIR 拷贝到离线机（U盘/内网文件服务器），再执行 import-images.sh"