#!/usr/bin/env bash
# P1 离线交付链：把本地 containerd 中的镜像载入 local registry（registry API 直传）
#
# 用法：
#   ./registry-load.sh <镜像名> [registry]
#     <镜像名>  本地 containerd 中的完整镜像引用（如 registry.k8s.io/pause:3.10.2
#               或 docker.io/library/busybox:1.36）
#     [registry] local registry 地址（默认 127.0.0.1:5000）
#
# 行为：
#   - 解析镜像顶层 manifest 的 digest（ctr i list 第 3 列）
#   - 取其 arm64 子 manifest（离线目标架构），上传 layer/config blob，
#     再以 docker mediaType 提交 manifest（registry 2.8 需 docker v2 标记）
#   - 幂等：blob 已存在则跳过
#
# 为什么不用 `ctr i push`：containerd 默认推整个多平台 OCI index，
#   distribution registry 需 index 引用的所有平台 blob 先上传（本地只保留 arm64 层），
#   导致 "blob unknown to registry"。本脚本只处理当前架构，规避该问题。
#
# 注：脚本入库；registry 存储/镜像不入库。

set -euo pipefail

IMG="${1:?用法: registry-load.sh <镜像名> [registry]}"
REG="${2:-127.0.0.1:5000}"
NS="k8s.io"

command -v ctr >/dev/null 2>&1 || { echo "错误: 需要 ctr" >&2; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "错误: 需要 python3（registry 直传）" >&2; exit 1; }

# 从 ctr i list 解析 digest：第 3 列为 manifest digest。
# 输入可能是 tag 引用（docker.io/x:1.2）或 digest 引用（x@sha256:...）。
parse_digest() {
  local ref="$1"
  if [[ "$ref" == *"@"* ]]; then
    echo "${ref##*@}" | sed 's/^sha256://'
    return 0
  fi
  # 注意：ctr i list 输出可能很大；awk 若提前 exit，ctr 写已关管道触发 SIGPIPE（141）。
  # 这里不提前 exit（awk 全读），并对管道容忍 SIGPIPE。
  { ctr -n "$NS" i list 2>/dev/null || true; } \
    | awk -v r="$ref" '$1==r {print $3; found=1} END {if (found) exit 0; exit 1}' \
    | sed 's/^sha256://' || true
}
DIGEST="$(parse_digest "$IMG")"
if [ -z "$DIGEST" ]; then
  echo "错误: 本地 containerd 无镜像 $IMG（ctr -n $NS i list 未命中）" >&2
  echo "  （先 pull 该镜像，或把镜像名写全：registry 前缀 + tag/digest）" >&2
  exit 1
fi
echo "==> $IMG digest=$DIGEST"

# repo 名：registry 内路径（保留 / 结构；docker.io/ 官方镜像映射 library/，其余保留原路径）
REPO="${IMG%@*}"            # 去 digest 部分
if [[ "$REPO" == docker.io/* ]]; then
  REPO="${REPO#docker.io/}"          # docker.io/rancher/local-path... → rancher/local-path...
  if [[ "$REPO" != *"/"* ]]; then
    REPO="library/${REPO}"           # docker.io/busybox → library/busybox
  fi
elif [[ "$REPO" == *"/"* ]]; then
  REPO="${REPO#*/}"         # registry.k8s.io/x/y → x/y
else
  REPO="library/${REPO}"    # 裸镜像名（如 busybox）
fi
REPO="${REPO%%:*}"          # 去 tag

echo "==> 载入 -> $REG/$REPO (digest=$DIGEST)"

python3 - "$DIGEST" "$REG" "$REPO" "$NS" <<'PYEOF'
import json, subprocess, sys, urllib.request, urllib.error
digest, reg, repo, ns = sys.argv[1:5]
REG = f"http://{reg}"

def cget(dig):
    return subprocess.run(["ctr", "-n", ns, "content", "get", dig], capture_output=True).stdout

def req(method, url, data=None, ctype=None):
    r = urllib.request.Request(url, data=data, method=method)
    if ctype:
        r.add_header("Content-Type", ctype)
    try:
        resp = urllib.request.urlopen(r, timeout=120)
        return resp.status, dict(resp.headers)
    except urllib.error.HTTPError as e:
        return e.code, dict(e.headers)

top = json.loads(cget("sha256:" + digest))
# 顶层若是 index/manifest list → 选 linux/arm64 子 manifest
if "manifests" in top:
    if top.get("mediaType") == "application/vnd.oci.image.index.v1+json" or "manifests" in top:
        arm = [m for m in top["manifests"] if m.get("platform", {}).get("architecture") == "arm64"]
        if not arm:
            print("!! 无 arm64 子 manifest"); sys.exit(1)
        mani = json.loads(cget(arm[0]["digest"]))
    else:
        mani = top
else:
    mani = top

# 上传 config + layers（HEAD 幂等跳过）
objs = [mani["config"]["digest"]] + [l["digest"] for l in mani.get("layers", [])]
for d in objs:
    st, _ = req("HEAD", f"{REG}/v2/{repo}/blobs/{d}")
    if st == 200:
        print(f"  [skip] {d[:16]}")
        continue
    st, h = req("POST", f"{REG}/v2/{repo}/blobs/uploads/")
    loc = h.get("Location")
    st, _ = req("PUT", f"{loc}&digest={d}", cget(d), "application/octet-stream")
    if st not in (201, 202):
        print(f"!! blob {d[:16]} 上传失败: {st}"); sys.exit(1)
    print(f"  [ok] blob {d[:16]}")

# manifest：docker mediaType 提交（registry 2.8 兼容 OCI schema）。
# tag 取原镜像 tag（若无则用 digest 作不可变引用），保证 kubelet 按 tag resolve 命中。
ORIG_TAG=""
if [[ "$IMG" == *":"* && "$IMG" != *"@"* ]]; then
  ORIG_TAG="${IMG##*:}"
elif [[ "$IMG" == *"@"* ]]; then
  ORIG_TAG=""
fi
if [ -n "$ORIG_TAG" ]; then
  M_TAG="$ORIG_TAG"
else
  M_TAG="$digest"
fi
st, _ = req("PUT", f"{REG}/v2/{repo}/manifests/{M_TAG}",
            json.dumps(mani_d).encode(),
            "application/vnd.docker.distribution.manifest.v2+json")
if st != 201:
    print(f"!! manifest 提交失败: {st}"); sys.exit(1)
print(f"==> 完成: {REG}/v2/{repo}/manifests/{M_TAG}")
PYEOF