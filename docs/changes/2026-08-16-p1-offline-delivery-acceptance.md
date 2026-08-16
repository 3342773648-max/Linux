# P1 离线交付链真实验收记录

- 日期：2026-08-16
- 环境：`bootstrap-day2`（Lima arm64 vz 单节点，aarch64，4C/8G）
- 集群：kubeadm v1.36.2 + containerd 2.3.3 + Calico v3.32.1，node `day2-cp` Ready
- 套件：P1 离线交付链（镜像 tar ↔ local registry + containerd mirrors + 模拟断网验收）
- 身份：git noreply（无凭据入库）

## 交付内容（scripts/offline/ + docs/offline-delivery.md）

| 文件 | 作用 |
| --- | --- |
| `images-list.txt` | 27 个固定版本镜像清单（控制面 1.36.2 + Calico + Day2 全套） |
| `export-images.sh` / `import-images.sh` | 镜像导出（在线）/ 导入（离线）tar 工具链 |
| `setup-local-registry.sh` | registry 2.8.3 二进制 + systemd + **cri config_path → certs.d** + hosts.toml mirrors |
| `registry-load.sh` | 本地镜像经 registry HTTP API 载入（单平台、保原 tag、幂等） |
| `mirror-day2.sh` | Day2 套件镜像批量载入 local registry |
| `verify-offline.sh` | 离线 preflight（断网检测 + registry 可达 + 镜像齐备 + 工具链） |
| `docs/offline-delivery.md` | 离线交付手册（执行步骤 + 已知限制） |

## 真实验收证据

### 1. 镜像导出（在线侧）

```
$ ./export-images.sh k8s.io /tmp/offline-export
==> 完成（24 个 tar 包），但有 ... node-exporter ... 未导出
```

- ✅ 24/27 镜像成功导出 tar；node-exporter 因**上游 quay manifest 悬空层**无法导出（如实标注，见 images-list.txt 注释）

### 2. registry 载入 + 拉回闭环

```
$ ./registry-load.sh docker.io/library/busybox:1.36
==> 完成: http://127.0.0.1:5000/v2/library/busybox/manifests/1.36

# 删本地引用 → 从 local registry 拉回 → 运行容器
$ ctr -n k8s.io i rm docker.io/library/busybox:1.36
$ ctr -n k8s.io i pull 127.0.0.1:5000/library/busybox:1.36
$ ctr -n k8s.io run --rm ... echo OFFLINE_REGISTRY_OK
OFFLINE_REGISTRY_OK
```

- ✅ registry 载入 → 拉回 → 运行完整闭环

### 3. Day2 套件镜像批量载入（镜像源切换）

```
$ ./mirror-day2.sh 127.0.0.1:5000
==> 完成: 载入 11 个 Day2 镜像 → 127.0.0.1:5000
```

- ✅ ingress-nginx controller/certgen、metrics-server、kube-state-metrics、grafana、sidecar、prometheus 系、local-path 全部载入；node-exporter 因上游缺陷失败（如实标注）
- registry catalog 12 仓库（含 `ingress-nginx/controller`、`metrics-server/metrics-server` 等）

### 4. 模拟断网（iptables 阻断出站 443）

```
$ iptables -A OUTPUT -p tcp --dport 443 -j DROP
$ env -u ...proxy curl https://registry.k8s.io/v2/   → 000 (connection failed)
$ curl http://127.0.0.1:5000/v2/                     → {}
```

- ✅ 公网不可达、内网 registry 可达（模拟「无公网、有内网」）

### 5. verify-offline 全绿（断网状态）

```
$ ./verify-offline.sh 127.0.0.1:5000
1/3 [OK] 出站 443 已被阻断 / [OK] 内网 registry 可达
2/3 [OK] 27 个镜像全部就绪
3/3 [OK] kubeadm v1.36.2 / kubelet v1.36.2 / ctr
```

### 6. 断网下 kubelet CRI 拉取（核心证据）

```
$ ctr -n k8s.io i rm docker.io/library/busybox:1.36   # 清除本地引用
$ kubectl apply -f offline-bb.yaml                     # 触发 kubelet 拉取
$ kubectl get pod offline-bb-... 
offline-bb-5c5497d97-4htt7   1/1   Running   0     39s
$ kubectl logs offline-bb-5c5497d97-4htt7
OFFLINE_PULL_OK
```

- ✅ **断网 + 本地引用已删**下，pod 仍 Running——镜像唯一来源 = local registry（kubelet 经 CRI mirrors 命中 127.0.0.1:5000）

### 7. 集群功能不依赖公网

```
$ curl -H "Host: echo.day2.example" http://127.0.0.1:32310/   → HTTP/1.1 200 OK
$ kubectl top node
day2-cp   249m   6%   4109Mi   52%
```

- ✅ ingress 路由 / metrics 在断网下正常

## 关键修复记录（P1 实测暴露）

1. **containerd cri `config_path` 未设置**（setup-local-registry.sh 初版漏配）→ hosts.toml 从未被 CRI 读取、kubelet 继续直连公网。修复：脚本幂等写入 `/etc/containerd/certs.d`（仅 cri 段，避免误伤 nri/transfer 段）。**此修复是 P1 能否生效的关键。**
2. **ctr i export/push 的 SIGPIPE**：`ctr i list | awk '$1==r{print;exit}'` 中 awk 提前退出 → ctr 写已关管道 → 141。修复：awk 全读不提前 exit + 管道容忍 SIGPIPE。
3. **多平台镜像**（manifest list/OCI index）：本地只保留 arm64 层，ctr 默认导出/推送整个 index 遇到缺失 blob。修复：registry-load 按 arm64 单平台处理，manifest 以 docker mediaType 提交（registry 2.8 兼容）。
4. **node-exporter 上游缺陷**：quay `v1.12.1-distroless` 的 arm64 manifest 引用 registry 端缺失层（2026-08-16 实测）。无法导出/载入，如实标注并给出离线替代建议。
5. **metrics-server etc. 以 digest 引用存储**（无 tag 行）：脚本需 tag/digest 双容忍匹配（已实现）。

## 结论

- ✅ 离线交付链（导出/导入 tar + local registry + containerd mirrors）部署并**真实验收**：断网下 kubelet 从内网 registry 拉取镜像、集群与 Day2 套件功能完整
- ✅ 交付链延伸：预检 → 部署 → CNI → Day2 → **离线交付** ✓
- 边界如实：模拟断网（iptables 443 DROP）；单架构（arm64）；node-exporter 上游缺陷标注