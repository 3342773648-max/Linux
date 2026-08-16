# Kubernetes Cluster Bootstrap

[![CI](https://github.com/guiyi-labs/kubernetes-cluster-bootstrap/actions/workflows/ci.yml/badge.svg)](https://github.com/guiyi-labs/kubernetes-cluster-bootstrap/actions/workflows/ci.yml)
![Kubernetes](https://img.shields.io/badge/Kubernetes-kubeadm-326CE5?logo=kubernetes&logoColor=white)
![Ansible](https://img.shields.io/badge/Ansible-automation-EE0000?logo=ansible&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-cluster%20delivery-FCC624?logo=linux&logoColor=black)

> 基于 kubeadm 与 Ansible 的 Kubernetes 集群交付与引导实践。

## 项目定位

本仓库只负责 Kubernetes 的 **Day 0 / Day 1 交付**：从 Linux 节点预检、容器运行时和 kubeadm
安装，到控制平面、Worker、CNI、HA 入口和安装后验收。最终输出可交接的集群配置与验收报告，
供其他平台注册和使用。

```text
主机预检 → containerd → kubeadm init/join → CNI / HA → 集群验收 → 交付 kubeconfig
```

## 与相关项目的边界

| 阶段 | 仓库 | 负责什么 |
|---|---|---|
| Day 0/1 | `kubernetes-cluster-bootstrap`（本仓库） | 创建集群、节点加入、CNI、控制平面高可用和交付验收 |
| Linux 运行期 | [`devops-automation`](https://github.com/guiyi-labs/devops-automation) | SSH 主机、systemd、进程、磁盘、批量任务、备份和主机监控 |
| Kubernetes 运行期 | [`aiops-platform`](https://github.com/guiyi-labs/aiops-platform) | 多集群、工作负载、可观测、诊断、事故响应和受控修复 |

本仓库不提供长期监控、AIOps、事故响应、Pod / Deployment 管理面板或通用 Web 运维控制台。
集群创建完成后，使用验收结果和 kubeconfig 将集群交给运行期平台；真实 kubeconfig 永不提交到 Git。

## 当前状态

B0「兼容矩阵与安全基线」于 **2026-08-14** 完成：

- 已确立**官方兼容确认（未实机验证）**的集群交付组合：Ubuntu 24.04 LTS + Kubernetes 1.36 + containerd 2.3 LTS + Calico + Ansible Core 2.21，详见 [`docs/compatibility.md`](./docs/compatibility.md)；
- 三篇历史教程均标注为**历史材料**，与当前重建路线解耦；
- 新增实验环境合同（[`docs/lab-environment.md`](./docs/lab-environment.md)）与安全基线（[`docs/security-boundaries.md`](./docs/security-boundaries.md)）；
- 新增 `.gitignore` 覆盖 Kubernetes、Ansible 与实验日志敏感产物；
- CI 扩展为 Markdown 链接检查 + 格式检查 + 敏感字段/危险示例扫描 + 扫描器回归测试（正例/反例）；
- 仓库扫描不到可复用 Token、明文密码、私钥或真实节点地址，危险示例仅以明确允许清单豁免、可审查。

> B0 是文档与门禁阶段，**不宣称已完成真实多节点安装验收**；「已确认」仅指官方版本组合
> 与文档一致性确认，真实验收属 B1；多节点验收与完整 Ansible 自动化属于
> [B1-B4](#重建路线) 后续里程碑。

B1「真实 Ansible 交付结构」**实施已就绪**（2026-08-14）：

- `inventory/`（示例分组 + group_vars + RFC 5737 host_vars）；
- `roles/`（preflight/containerd/kubeadm/control_plane/worker/cni/load_balancer 占位）；
- `playbooks/`（site / reset / upgrade）；`scripts/verify-cluster.sh`；
- CI 已加 `ansible-playbook --syntax-check` 与 `ansible-inventory` 门禁。

> B1 交付的是**真实的自动化骨架与执行逻辑**，通过 Ansible 语法校验；真实验收属 B2。

B2「真实环境验收与幂等交付」**已完成**（2026-08-15，见 [`docs/changes/2026-08-15-b2-real-cluster-acceptance.md`](./docs/changes/2026-08-15-b2-real-cluster-acceptance.md)）：

- 在真实 Ubuntu 24.04 LTS 双节点（1 CP + 1 worker，Lima arm64）完成 `site.yml` 全量部署；
- `verify-cluster.sh` 全量验收通过：节点 2/2 Ready、系统 Pod 正常、Calico Tigerastatus 全 True、集群 DNS 解析 OK；
- 二次重跑全量幂等（changed=0）；
- `reset.yml` 拆集群 → `site.yml` 重建 → 再验收再幂等，证明可重复交付；
- 真实环境暴露并修复：containerd 代理 daemon-reload、certificate-key 提取鲁棒化、CNI 任务 NO_PROXY、
  CNI 本地清单化、多处幂等缺口、reset 后重建目录补齐。

> 部署输出即真实集群可运行；验收证据、修复记录与 host_vars 连接说明见 B2 change record。
>
> **B2 x86_64 回归已完成**（同日，见 [`docs/changes/2026-08-15-b2-x8664-regression.md`](./docs/changes/2026-08-15-b2-x8664-regression.md)）：
> B0 声明的首条路径 x86_64 在 QEMU 模拟 Ubuntu 24.04 amd64 双节点重放同矩阵
> （首次部署 → verify 全绿 → 二次幂等 changed=0 → reset → 重建 → 再 verify → 再幂等），
> 并修复两个 x86_64 特有预置问题（apt 缓存未刷新、cloud image 预置 CRI-disabled 的 containerd 配置）。

Day2「交付 + 可运维」套件**已完成**（2026-08-16，见 [`docs/changes/2026-08-16-day2-ingress-nginx-acceptance.md`](./docs/changes/2026-08-16-day2-ingress-nginx-acceptance.md) 等）：

- **Ingress**：ingress-nginx v1.12.1，HTTP 流量入口真实可用（200 + 后端内容、404 精确匹配）；
- **存储**：local-path-provisioner v0.0.31，StorageClass 动态供给 + PVC 持久化闭环（写入 → Pod 删除 → 读回）真实验证；
- **监控**：metrics-server v0.9.0（`kubectl top` 真实指标）+ kube-prometheus-stack（Prometheus/Grafana/kube-state-metrics/node-exporter），目标 UP + 指标可查 + Grafana 可达；
- 全部在 `bootstrap-day2`（Lima arm64 vz 单节点，kubeadm 1.36.2 + Calico v3.32.1）真实验收，manifest 落 `manifests/day2/`，验收证据落 `docs/changes/`。

> Day2 套件是交付内容的扩展（不新增平台能力），交付链延伸为：
> 预检 → 部署 → CNI →（HA）→ **Ingress → 存储 → 监控**。

P1「离线交付链」**已完成**（2026-08-16，见 [`docs/changes/2026-08-16-p1-offline-delivery-acceptance.md`](./docs/changes/2026-08-16-p1-offline-delivery-acceptance.md)）：

- **镜像 tar 工具链**（`scripts/offline/`）：export-images / import-images，27 个固定版本镜像（控制面 + Calico + Day2 全套）在线导出、离线导入；
- **local registry + containerd mirrors**：registry 2.8.3 二进制 + systemd，cri `config_path` 指向 certs.d，hosts.toml 将 registry.k8s.io/quay.io/docker.io/rancher 镜像源指向内网（**修复了 config_path 未设置导致 mirrors 不生效的关键缺陷**）；
- **Day2 镜像源切换**：mirror-day2.sh 批量载入套件镜像，kubelet 无需改 manifest 即命中内网；
- **模拟断网真实验收**：iptables 阻断出站 443（保留内网 registry）→ `verify-offline.sh` 全绿 → 断网下 kubelet 从 local registry 拉取 busybox 并 Running → ingress 200 / kubectl top 正常；
- 边界如实：模拟断网（非真断物理链路）、单架构（arm64）、node-exporter 上游 manifest 悬空层缺陷已标注。
- 手册见 [`docs/offline-delivery.md`](./docs/offline-delivery.md)。

> 离线交付链延伸交付场景：预检 → 部署 → CNI →（HA）→ Ingress → 存储 → 监控 → **离线交付**。

## 文档入口

| 文档 | 当前用途 |
|---|---|
| [兼容矩阵](./docs/compatibility.md) | B0：第一条支持路径、版本关系、HA 与升级状态（**当前文档**） |
| [实验环境合同](./docs/lab-environment.md) | B0：拓扑、网络/镜像前提、销毁与脱敏规则（**当前文档**） |
| [安全基线](./docs/security-boundaries.md) | B0：禁止项、凭据生命周期、端口/SSH 与 .gitignore 规则（**当前文档**） |
| [SECURITY.md](./SECURITY.md) | 开源门面：Supported Versions / 漏洞上报 / 凭据与供应链控制 / 双架构验收边界 |
| [CONTRIBUTING.md](./CONTRIBUTING.md) | 开源门面：贡献前置、门禁、代码约定、PR 工作流 |
| [Day2 Ingress 验收](./docs/changes/2026-08-16-day2-ingress-nginx-acceptance.md) | Day2：ingress-nginx v1.12.1 部署与 HTTP 路由验收 |
| [Day2 存储验收](./docs/changes/2026-08-16-day2-local-path-acceptance.md) | Day2：local-path 动态供给 + PVC 持久化闭环验收 |
| [Day2 监控验收](./docs/changes/2026-08-16-day2-monitoring-acceptance.md) | Day2：metrics-server + kube-prometheus-stack 指标验收 |
| [P1 离线交付验收](./docs/changes/2026-08-16-p1-offline-delivery-acceptance.md) | P1：离线交付链（镜像 tar + local registry + 模拟断网）真实验收 |
| [离线交付手册](./docs/offline-delivery.md) | P1：离线/受限网络场景交付执行手册 |
| [kubeadm 单节点部署](./使用kubeadm快速部署一个K8s集群.md) | 历史教程：学习与测试环境的手动部署复盘 |
| [kubeadm 高可用部署](./使用kubeadm搭建高可用的K8s集群.md) | 历史教程：HA 拓扑和组件配置复盘 |
| [Ansible 自动化部署](./Ansible自动化部署K8S集群.md) | 历史教程：Ansible 概念、Inventory 和 Playbook 学习参考 |

### B1（当前执行结构，未真实验收）

| 项目 | 状态 |
| --- | --- |
| `inventory/`（分组 + group_vars + host_vars，RFC 5737 示例） | ✅ 已建 |
| `roles/`（preflight/containerd/kubeadm/control_plane/worker/cni/load_balancer） | ✅ 已建 |
| `playbooks/`（site / reset / upgrade） | ✅ 已建（syntax 校验通过） |
| `scripts/verify-cluster.sh` | ✅ 已建（验收辅助，B2 扩展） |
| CI 语法门禁（ansible-playbook syntax-check + inventory） | ✅ 已加 |
| 真实单控制平面 + Worker 验收 | ✅ 已完成（B2，2026-08-15） |

### B2（当前里程碑：真实环境验收与幂等交付）

| 项目 | 状态 |
| --- | --- |
| 真实 Ubuntu 24.04 LTS 双节点 site.yml 全量部署 | ✅ 完成（1 CP 192.168.104.1 + 1 worker 192.168.104.3，Lima） |
| `verify-cluster.sh` 全量验收（Node Ready / Pod / Calico / DNS） | ✅ 节点 2/2 Ready、Tigerastatus 全 True、DNS OK |
| 二次重跑幂等（changed=0） | ✅ 达成 |
| `reset.yml` 拆集群 → `site.yml` 重建 → 再验收再幂等 | ✅ 达成（可重复交付闭环） |
| 真实环境问题修复（代理 reload / cert-key 提取 / NO_PROXY / 本地清单 / 幂等缺口） | ✅ 全部入库，详见 B2 change record |

> B2 交付的条目在**真实可运行集群**上完成验收，证据与细节见
> [`docs/changes/2026-08-15-b2-real-cluster-acceptance.md`](./docs/changes/2026-08-15-b2-real-cluster-acceptance.md)。

旧教程中的 Kubernetes、Docker、操作系统和镜像版本均属历史参考，**不得**按旧文档执行；
执行前必须根据 [`docs/compatibility.md`](./docs/compatibility.md) 复核。

## 安全与兼容性警示

仓库中的三篇教程是历史实践记录，不是当前生产部署脚本。执行任何命令前，必须根据目标
发行版、Kubernetes 版本、容器运行时、CNI 和组织安全基线重新验证：

- 不要复用文档中的 kubeadm Token、证书哈希、Keepalived 密钥或 SSH 凭据；join 命令必须由当前集群现场生成。
- 不要为了绕过问题而关闭防火墙 / SELinux，或把 YUM 仓库签名校验改为关闭；只放行必要端口并保留安全校验。
- CentOS 7、Docker 18.x 和 Kubernetes 1.16/1.18 仅代表历史环境，当前重建路线优先使用受支持的 Linux、containerd 和 Kubernetes 版本。
- 真实 kubeconfig、证书、Token、执行日志和节点地址不得提交到 Git。

## 重建路线

### ~~B0：兼容矩阵与安全清理~~（已完成 2026-08-14）

- ✅ 固定首个支持路径：Ubuntu 24.04 + K8s 1.36.2 + containerd 2.3 + Calico + Ansible Core 2.21（[`docs/compatibility.md`](./docs/compatibility.md)）
- ✅ 实验环境合同与销毁边界（[`docs/lab-environment.md`](./docs/lab-environment.md)）
- ✅ 安全基线、凭据生命周期与 `.gitignore`（[`docs/security-boundaries.md`](./docs/security-boundaries.md)）
- ✅ 历史教程治理：三篇教程标注为历史材料，旧版本标记为「历史参考」
- ✅ CI 扩展：链接检查 + 格式检查 + 敏感字段/危险示例扫描

### ~~B1：真实 Ansible 交付结构~~（结构已就绪 2026-08-14，真实验收属 B2）

```text
inventory/
group_vars/
roles/
  preflight/
  containerd/
  kubeadm/
  control_plane/
  worker/
  cni/
  load_balancer/
playbooks/
  site.yml
  reset.yml
  upgrade.yml
scripts/
  verify-cluster.sh
```

- ✅ `inventory/`、`roles/`、`playbooks/`、`scripts/` 结构与配置已建；
- ✅ `ansible-playbook --syntax-check`（site/reset/upgrade）与 `ansible-inventory` 门禁通过；
- ✅ **真实单控制平面 + Worker 安装验收（Node Ready、CoreDNS、Calico、Service/DNS、Pod 调度）见 B2（已完成）**；
- ✅ 幂等复跑与 reset 可重复见 B2（已完成）。

先支持一条可信路径，再扩展系统版本和网络插件，不同时维护多套未验证脚本。

### ~~B2：幂等与验收~~（已完成 2026-08-15）

- ✅ Ansible 第二次执行无不必要变更（changed=0，实测）；
- ✅ 节点预检包含 CPU、内存、磁盘、时间同步、Swap、内核模块、端口和网络连通性；
- ✅ 安装后验证 Node Ready、CoreDNS、CNI、Service、DNS 和基础 Pod 调度（`verify-cluster.sh` 全绿）；
- ✅ 支持 reset / cleanup，不污染下一次演练（`reset.yml` → `site.yml` 重建闭环验证）；
- ✅ 记录修复、失败原因与验收证据（[B2 change record](./docs/changes/2026-08-15-b2-real-cluster-acceptance.md)）。

### D（Day2 可运维套件，已完成 2026-08-16）

交付内容扩展：集群就绪后的 Day2 运维入口，全部清单落 `manifests/day2/`、验收证据落 `docs/changes/`，在 `bootstrap-day2`（arm64 vz 单节点）真实验收：

- ✅ **Ingress**：ingress-nginx v1.12.1（baremetal 清单），`curl` 经 NodePort 验证 200 + 后端内容、错误 Host 404；
- ✅ **存储**：local-path-provisioner v0.0.31，StorageClass 动态供给 + PVC 写入 → Pod 删除 → 同 PVC 读回 → Delete 回收闭环；
- ✅ **监控**：metrics-server v0.9.0（`kubectl top` node/pod 真实指标）+ kube-prometheus-stack chart 88.3.0（Prometheus targets 10 up、Grafana 13.1.3 health OK）；
- ⚠️ 如实标注：alertmanager 关闭（单节点无告警分发）；4 个控制面 metrics target 默认 down（kubeadm 未暴露端点）；Grafana 密码入 gitignored 本地 values。

### P1（离线交付链，已完成 2026-08-16）

受限/无外网场景交付能力，脚本落 `scripts/offline/`、手册落 `docs/offline-delivery.md`、验收落 `docs/changes/2026-08-16-p1-offline-delivery-acceptance.md`：

- ✅ **镜像 tar 工具链**：export-images（在线导出 27 个固定版本镜像）/ import-images（离线导入），digest 容忍 + SIGPIPE 修复；
- ✅ **local registry + containerd mirrors**：registry 2.8.3 二进制 + systemd + cri `config_path` → certs.d + hosts.toml（registry.k8s.io/quay.io/docker.io/rancher → 内网）；**修复 config_path 未设置导致 mirrors 不生效**；
- ✅ **Day2 镜像源切换**：mirror-day2.sh 批量载入 11/12 套件镜像（node-exporter 上游缺陷如实标注），kubelet 免改 manifest 命中内网；
- ✅ **模拟断网验收**：iptables 443 DROP（保留内网）→ verify-offline 全绿 → 断网下 kubelet 从 local registry 拉取镜像 pod Running → ingress 200 / kubectl top 正常。

### B3：HA 与升级证据

- 高可用模式使用满足 etcd quorum 的控制平面数量；
- HAProxy / Keepalived 配置使用 Secret 或变量注入；
- 验证控制平面单节点故障后的 API 可用性；
- 固定 Kubernetes 升级和回滚策略，不在同一批次混入未经验证的跨大版本升级；
- 形成可复现的多节点虚拟机演练报告。

### B4：工程交付

- `ansible-lint`、YAML lint、Playbook syntax check 和 Markdown link check 纳入 CI；
- 记录无密钥的脱敏执行日志；
- 发布兼容矩阵、安装手册、reset 手册和故障排查入口；
- 通过 tag 发布一个真实可复现的 bootstrap baseline；
- 将 kubeconfig、证书、Token 和节点运行日志排除在仓库之外。

## 完成标准

只有同时满足以下条件，才能把仓库描述为“可复现集群交付”：

- [ ] 至少一个 Linux 发行版和一个 Kubernetes 版本有明确兼容声明；
- [ ] 存在可执行的 Ansible inventory、roles 和 playbooks；
- [ ] 新环境安装成功，第二次执行保持幂等；
- [ ] 单节点和 HA 模式都有安装后验收；
- [ ] reset / cleanup 可重复执行；
- [ ] CI 能发现 YAML、Playbook 和文档链接问题；
- [ ] 文档中不存在可直接使用的真实凭据或硬编码集群 Token；
- [ ] 结果有脱敏日志、版本 tag 和交接说明。

在这些条件满足前，本仓库定位为 Kubernetes 部署学习与方案沉淀，不宣称生产级交付能力。
