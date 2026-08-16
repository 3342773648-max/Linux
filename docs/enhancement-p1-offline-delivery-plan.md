# Enhancement Plan: P1 离线交付链完善（bootstrap）

- 状态：**✅ 已批复开工，并已完成交付**（4 commits 已推送，2026-08-16；验收证据见 `docs/changes/2026-08-16-p1-offline-delivery-acceptance.md`，手册见 `docs/offline-delivery.md`）
- 目标：把「在线交付 + Day2」延伸为「**离线/受限网络场景交付**」——在无外网环境仅凭镜像仓库与离线产物完成集群交付 + Day2
- 参考：团队 kind fork PR #4234（offline mirror registry 思路），本方案针对 kubeadm 交付链落地
- 交付链扩展：预检 → 部署 → CNI →（HA）→ Ingress / Storage / 监控 → **离线交付链**

## 1. 方案摘要

### 离线交付链设计（三层产物，均版本固定、清单化）

| 层 | 产物 | 来源 | 落盘位置（待批复） |
| --- | --- | --- | --- |
| 1 镜像 | 交付所需全部容器镜像 **tar 包**（`ctr images export` 或 `docker save`） | kubeadm 控制面镜像、Calico、ingress/local-path/monitoring 各组件的固定版本镜像 | `manifests/offline/images/`（清单 yaml + 导出脚本；tar 不入库，避免仓库膨胀） |
| 2 Helm chart | kube-prometheus-stack 等 chart 的**离线包**（`helm pull` 产物） | prometheus-community 等仓库 | `manifests/offline/charts/`（.tgz 或版本锁定 values） |
| 3 kubeadm 离线包 | kubeadm/kubelet/kubectl + containerd **deb 包镜像** | pkgs.k8s.io / apt 本地镜像；或受限网络 apt mirror | `playbooks/roles/offline/`（ansible role，源可切换） |

### 离线镜像仓库（核心假设）

- 受限网络内自建 **local registry**（`registry:2`，或复用镜像导出/导入 `docker registry` 离线方式）；
- containerd 配置 `registry.mirrors`/`config_path` 指向 local registry，`NO_PROXY` 放行内网 registry；
- 交付机（离线侧）执行「导出」：在线环境 `kubeadm config images list` 取控制面镜像清单 → 逐一 `ctr images export`（或通过 local registry `push`）；
- 目标机（离线侧）执行「导入」：`ctr images import` 到本地 containerd，再从 local registry pull 其余（Calico/套件）镜像。

### 与现有交付链集成（复用，不新造平台功能）

- **Ansible 复用**：在 `site.yml` 基础上新增 `roles/offline/`（镜像导入 + registry 配置 + 源切换），通过 `group_vars` 的 `offline_mode: true|false` 分支——在线/离线同一套 playbook 入口；
- **preflight 扩展**：离线模式下 check「local registry 可达 + 必需镜像清单齐全」，缺哪个报哪个；
- **Day2 复用**：ingress/local-path/monitoring 的 manifest 不重写，仅把镜像源替换为 local registry 版本（`image` 字段或 values 覆盖）。

### 可验收（真实验证，如实标注断网边界）

- 主验收：**模拟断网**——用 systemd 网络命名空间/CGroup 或 `iptables` 阻断目标机出站（保留内网 registry 可达），从零完成集群 up + ingress + storage；
- 「已验证」边界如实：完整模拟断网（非真断物理网卡）；监控套件如镜像量大/下载受限，允许降级为 metrics-server + Prometheus + node-exporter（沿用 Day2 已证降级许可）并标注；
- 记录：离线模式下 `kubeconfig`/token 与在线一致的验收证据，证明「离线仅影响镜像获取，不影响 join 与运行」。

### Commit 划分（noreply 身份，每层一个 commit）

1. `feat(offline): kubeadm image list + export/import 脚本与离线 preflight` — `roles/offline/` 或 `scripts/offline/`
2. `feat(offline): local registry 配置 + containerd mirrors 落地（在线/离线分支）`
3. `feat(offline): Day2 套件离线镜像清单与 chart 离线包（ingress/local-path/monitoring 镜像源切换）`
4. `docs(offline): 离线交付手册 + README/CHANGELOG 同步 + 模拟断网验收记录`

## 2. 边界与约束

- **身份/纪律**：git noreply；真实 IP/凭据不入库（RFC 5737 + gitignored local.yml）；镜像 tar 与密码不入库（体积/安全双因）。
- **VM 复用**：沿用 `bootstrap-day2`（arm64 vz 单节点）做模拟断网验收，不新建 VM、不动其他项目 VM（e5-deploy-1/2 等）。
- **断网边界如实**：验收为「模拟断网」（iptables/网断 registry 留通），文档明示；不做真断物理链路（无第二物理网卡环境）。
- **工程量评估**：约 **3–4 小时**（含镜像导出/导入试错、registry 落地、模拟断网重放、文档）；若离线包体积大（kube-prometheus 全家桶镜像 ~2–3GB），优先只带监控降级子集，节流镜像量。
- **验证边界**：单架构（arm64，沿用 Day2 VM）；x86_64 不重放（已在 B2 基线验证，离线链与架构无关）。

## 3. 轻量替代（若离线链太重）

- **镜像内置 + 文档化离线步骤**：不建 local registry，把「必需镜像 tar + `ctr images import` + containerd mirrors 指向本地文件」成套成 `scripts/offline/` 二脚本（export.sh / import.sh），离线手册只讲「先在在线机出包、再到离线机导入」，注册中心环节可省略；
- 在批复中二选一：**完整链（registry 模拟断网重放）** 或 **轻量链（镜像内置 + 文档化）**，后者工程量约减半（~1.5–2 小时）。

## 4. 当前进度与待批复

- [x] 环境核实：`bootstrap-day2` 在用（近 `registry.k8s.io/quay.io` 直连、`docker.io` 走代理——离线模拟需注意区分「走代理」与「断网」的测试边界）
- [x] 方案成型（三层产物、链集成、模拟断网验收、commit 划分）
- [ ] 中枢批复：完整链 vs 轻量链；监控镜像是否允许只带降级子集
- [ ] 离线产物清单与脚本落地（commit 1–2）
- [ ] Day2 套件镜像源切换（commit 3）
- [ ] 模拟断网重放 + 验收记录 + README/CHANGELOG（commit 4）

**已确认事项**：Day2 的降级许可（监控可降级为 metrics-server + Prometheus + node-exporter 并如实标注）沿用；VM 不动其他项目。

收到批复后预计 **3–4 小时**（完整链）交付：4 个 noreply commit + 模拟断网验收证据（集群 up + ingress + storage；监控按批复降级）+ 离线交付手册 + 回报 commit SHAs。
