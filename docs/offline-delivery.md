# 离线交付手册（P1：离线/受限网络场景交付）

- 目标：在无外网环境仅凭镜像产物与内网 registry 完成集群交付 + Day2 套件
- 环境基线：kubeadm 1.36.2 + containerd 2.3.3 + Calico 3.32.1（Ubuntu 24.04，arm64）
- 真实验收：2026-08-16，`bootstrap-day2`（Lima arm64 vz 单节点），模拟断网（iptables 阻断出站 443、保留内网 registry）
- 约束：镜像 tar / registry 存储 / 凭据不入库；本手册与 `scripts/offline/` 入库

## 1. 交付链总览

```text
在线机                         传输介质(离线)               离线机
───────────────────────        ────────────────          ────────────────
kubeadm 控制面+Calico+Day2      USB/内网文件服务            本地 containerd
  镜像已在本地 containerd  ──►  镜像 tar 包  ────────────►  ctr import（直接注入）
  export-images.sh                                   import-images.sh
                                registry 数据              local registry
  registry-load.sh  ─────────►  （入库于内网）  ─────────►  127.0.0.1:5000
                                                        （或内网互相可达地址）
                                                          containerd mirrors
                                                          → kubelet/pod 自动命中
```

## 2. 脚本说明（scripts/offline/）

| 脚本 | 阶段 | 作用 |
| --- | --- | --- |
| `images-list.txt` | 清单 | 27 个固定版本镜像（实际运行版本，非 kubeadm 默认 1.36.3） |
| `export-images.sh` | 在线 | 批量 `ctr i export` 为单镜像 tar（digest 容忍、3 次重试） |
| `import-images.sh` | 离线 | 批量 `ctr i import` + 对齐清单校验 |
| `setup-local-registry.sh` | 离线 | 安装 registry 2.8.3 二进制 + systemd 服务 + **cri config_path 指向 certs.d** + hosts.toml mirrors |
| `registry-load.sh` | 在线/离线 | 把本地镜像经 registry HTTP API 载入 local registry（单平台、保原 tag） |
| `mirror-day2.sh` | 离线 | 批量载入 Day2 套件镜像（ingress/local-path/monitoring） |
| `verify-offline.sh` | 验收 | 断网检测 + registry 可达 + 镜像齐备 + kubeadm 工具链 |

## 3. 执行步骤

### 3.1 在线机准备（一次性）

```bash
# 在已部署集群的控制面节点（或任意含镜像的在线机）
cd scripts/offline
./export-images.sh k8s.io ./out/20260816     # 导出 tar 到 out/
# 把 out/ 拷贝到离线机（USB / 内网文件服务器）
```

### 3.2 离线机准备

```bash
# 1) 注入镜像（tar → 本地 containerd）
./import-images.sh ./out/20260816

# 2) 起 local registry + 配置 mirrors（自动装 registry 二进制、设 config_path、写 hosts.toml）
./setup-local-registry.sh 127.0.0.1:5000 linux/arm64

# 3) 把 Day2 套件镜像也载入 registry（kubelet 拉取自动命中内网）
./mirror-day2.sh 127.0.0.1:5000
```

### 3.3 模拟断网 + 验收

```bash
# 阻断出站 443（保留内网 registry 可达）
iptables -A OUTPUT -p tcp --dport 443 -j DROP

# 验收（应全绿）
./verify-offline.sh 127.0.0.1:5000

# 恢复（验收后）
iptables -D OUTPUT -p tcp --dport 443 -j DROP
```

### 3.4 断网下从零集群（kubeadm）

- 镜像已全量在本地 containerd / 内网 registry；kubeadm init 流程不变，
  kubelet 经 mirrors 拉取命中内网
- 控制面镜像版本必须与 images-list.txt 一致（1.36.2，勿用 `kubeadm config images list` 默认 1.36.3）

## 4. 真实验收证据（2026-08-16，bootstrap-day2）

1. **export**：24/27 镜像成功导出 tar（node-exporter 例外：quay 上游 manifest 悬空层，见 images-list.txt 注释）
2. **registry 载入**：busybox:1.36 经 registry API 载入 → 删本地引用 → 从 127.0.0.1:5000 拉回 → 容器运行输出 `OFFLINE_REGISTRY_OK`
3. **Day2 批量载入**：11/12 成功（ingress-nginx controller/certgen、metrics-server、kube-state-metrics、grafana、sidecar、prometheus 系、local-path）；node-exporter 上游缺陷所致（如实标注）
4. **模拟断网**：`iptables -A OUTPUT -p tcp --dport 443 -j DROP` 后：
   - 无代理 `curl https://registry.k8s.io/v2/` → **000（连接失败）**；内网 registry `{}` 可达
   - `verify-offline.sh` 全绿（443 阻断识别 OK、registry 可达、27 镜像就绪、kubeadm/kubelet/ctr OK）
   - **断网下 kubelet CRI 拉取**：删除本地 `docker.io/library/busybox:1.36` 引用 → 新建 Deployment → pod **1/1 Running**，日志 `OFFLINE_PULL_OK`（镜像唯一来源 = 本地 registry）
   - 集群功能不依赖公网：ingress `curl Host: echo.day2.example` → **200 OK**；`kubectl top node` 正常

## 5. 已知限制（如实标注）

- **node-exporter `v1.12.1-distroless`**：上游 quay 该 tag 的 arm64 manifest 引用了 registry 端缺失的层（2026-08-16 实测），`ctr export`/`registry-load` 均无法处理；离线侧需从近源镜像站拉取完整 variant 或选用其他镜像。**已记入 images-list.txt 注释**，属上游问题、不影响集群运行。
- **`ctr` CLI 不走 CRI mirrors**：`ctr i pull` 仍直连公网（certs.d 是 CRI 配置，仅 kubelet/kubeadm 使用）。离线验收以 kubelet 拉取为准（已实测通过）；如确需 ctr 走 mirrors，加 `--hosts-dir /etc/containerd/certs.d`。
- **mirror fallback（fail-open 语义）**：hosts.toml 的 `server` 指向原上游、`[host."http://内网"]` 为 mirror——containerd 语义为 mirror 优先、upstream fallback。本验收的 fail-closed 条件为「公网不可达」，此场景下无 fallback 路径（已实测负向：registry down + 443 DROP → pull 失败）。若需「公网可达也不 fallback」的严格 authoritative 模式，需将 `server` 改为内网地址——属多节点生产阶段演进项（见 `docs/changes/2026-08-16-p1-review-feedback.md`）。
- **skip_verify=true（lab-only）**：当前 registry 为明文 HTTP（127.0.0.1:5000），无 TLS 可验证。生产部署应改用 TLS + CA（`skip_verify = false`）或网络隔离。
- **registry 2.8.3 安全债务**：distribution 2.8.3 存在已知安全公告（GHSA-6pjf-3r9x-m592 等），仅用于本 lab 验收（单节点、内网、匿名）；**不作为生产 registry 基线**，上线前需评估升级。
- **单架构**：镜像按 arm64 **单平台**载入/导出（原多平台 index 的 arm64 单架构重发布，非原 index 原样镜像）；x86_64 离线链未重放（离线链与架构无关，B2 已覆盖 x86_64 在线交付）。
- **模拟断网**：iptables 阻断出站 443（非真断物理链路），精确模拟「无公网、有内网」。
- **registry 单机**：127.0.0.1 为 per-node local registry；多节点离线环境应部署 shared internal registry（内网 IP/DNS + TLS/认证），所有节点 hosts.toml 指向同一地址。
- **镜像验收粒度**：verify-offline.sh 为「repo 级匹配 + digest 容忍」的轻量 preflight；完整 manifest digest + platform + CRI pull 校验（offline-image-lock）属 P2 演进项。

## 6. 未来演进（AgentChat Step 5 审查建议）

1. **P1**：x86_64 重放（证明方案非 arm64 特例）
2. **P1**：多节点并发 + 重启场景验证
3. **P1**：registry TLS + 认证（admin/node profile 拆分：node 只给 pull+resolve）
4. **P2**：offline-image-lock.json（统一 source of truth + digest/platform 校验）
5. **P2**：镜像签名/供应链验证（cosign/SBOM/provenance + tar sha256sum）
6. **P3**：multi-arch index 支持 + OCI artifact 全面兼容
7. **P3**：registry GC/存储生命周期 + blob 并发上传优化

审查反馈全文见 `docs/changes/2026-08-16-p1-review-feedback.md`。
