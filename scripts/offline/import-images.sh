#!/usr/bin/env bash
# P1 离线交付链：镜像导入（离线机执行）
#
# 用法：
#   ./import-images.sh [输入目录]
#     输入目录  包含 export-images.sh 产出的 *.tar 包（默认 ./out/<date>）
#
# 行为：
#   遍历输入目录中的 .tar，逐个 `ctr -n k8s.io i import` 导入本地 containerd。
#   导入完成后用 images-list.txt 核对齐备；缺哪个打印出来。
#
# 注：tar 不入库（体积/分发另走 U盘/内网文件服务器）；此脚本与清单入库。

set -euo pipefail

IN_DIR="${1:-$PWD/out}"
LIST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_LIST="$LIST_DIR/images-list.txt"

command -v ctr >/dev/null 2>&1 || { echo "错误: 需要 containerd 的 ctr 命令" >&2; exit 1; }

shopt -s nullglob
tars=("$IN_DIR"/*.tar)
if [ "${#tars[@]}" -eq 0 ]; then
  echo "错误: $IN_DIR 下没有 .tar 包（先跑 export-images.sh）" >&2
  exit 1
fi

echo "==> 导入目录: $IN_DIR (${#tars[@]} 个 tar)"
for t in "${tars[@]}"; do
  echo "==> 导入: $(basename "$t")"
  ctr -n k8s.io i import "$t" >/dev/null 2>&1 || echo "!! 导入失败: $t" >&2
done

echo "==> 核对清单..."
missing=0
while IFS= read -r img; do
  [[ -z "$img" || "$img" == \#* ]] && continue
  if ! ctr -n k8s.io i list -q | grep -qx "$img"; then
    echo "!! 仍缺失: $img" >&2
    missing=1
  fi
done < "$IMAGE_LIST"

if [ "$missing" -ne 0 ]; then
  echo "==> 导入完成但清单未齐，请补充缺失 tar" >&2
  exit 1
fi

echo "==> 清单全部就绪（$(grep -vE '^#|^$' "$IMAGE_LIST" | wc -l | tr -d ' ') 个镜像）"