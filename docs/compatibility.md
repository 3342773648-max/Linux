# 兼容矩阵（B0）

> 本文档是仓库的**文档级兼容合同**：定义第一条正式支持的集群交付组合，以及各组件版本状态的判定标准。
> 各条目的官方来源与查询日期见文末[来源表](#来源表查询日-2026-08-14)。查询日：**2026-08-14**。

## 状态含义

| 状态 | 含义 |
| --- | --- |
| 已确认（推荐） | 经官方来源核实、版本组合一致，作为 B1 自动化实现的**首个验收目标**。B0 阶段未在真实多节点环境安装验收，「已确认」指官方版本组合与文档一致性验证 |
| 计划验证 | 已列入后续里程碑，尚未在本项目实验环境完成安装与验收 |
| 历史参考 | 仅存在于历史教程的学习材料，不用于当前重建路线 |
| 不支持 | 明确排除在支持范围之外 |

## 第一条支持路径（已确认）

| 组件 | 版本 | 状态 | 官方来源 |
| --- | --- | --- | --- |
| Linux 发行版 | Ubuntu 24.04 LTS（Noble，x86_64） | 已确认 | kubeadm 安装文档（Debian 系；要求 glibc） |
| Kubernetes | 1.36（固定 patch **1.36.2**，2026-06-09 发布，EOL 2027-06-28） | 已确认 | kubernetes.io/releases |
| kubeadm / kubelet / kubectl | 1.36.2 同位对齐 | 已确认 | install-kubeadm、version-skew-policy |
| 容器运行时 | containerd **2.3 LTS**（2.3.0+，2026-04-30 发布，EOL 2028-04-30） | 已确认 | containerd.io/releases 官方兼容矩阵 |
| cgroup 驱动 | systemd（kubelet 与 containerd 双向一致），cgroup v2 | 已确认 | container-runtimes |
| CNI | Calico **v3.32.1**（2026-06-26 发布） | 已确认 | projectcalico/calico releases |
| Ansible Core | **2.21.x**（查询日最新 2.21.3，2026-08-10 发布；EOL 2027-11） | 已确认 | docs.ansible.com release_and_maintenance |
| 控制平面拓扑 | 单控制平面 + N Worker | 已确认 | 见[控制平面与 HA](#控制平面与-ha) |

选择理由：Ubuntu 24.04 是 kubeadm 官方安装文档覆盖的 Debian 系发行版，也是 containerd
官方自动化测试的首选平台；Kubernetes 1.36 是当前维护周期内支持期最长的 minor（约 10 个月）；
containerd 2.3 LTS 与 1.36 在官方兼容矩阵内且支持期到 2028-04，避开 2026-09 到期的 1.7 系；
Calico 维护活跃且支持 NetworkPolicy。该组合同时排除了历史教程中的 Docker 18、K8s 1.16/1.18、
Flannel 和阿里云 YUM 源等过期路径。

## Linux 发行版

| 发行版 | 状态 | 说明 |
| --- | --- | --- |
| Ubuntu 24.04 LTS（x86_64） | 已确认 | 第一条支持路径；要求 glibc |
| Rocky Linux 9.x | 计划验证 | RHEL 系第二条路径，承接历史教程的 CentOS 7 背景 |
| Ubuntu 22.04 LTS / Debian 12 | 计划验证 | 官方支持，暂不作为首个验收目标 |
| CentOS 7 / 其他 EOL 发行版 | 历史参考 | 历史教程平台，官方已 EOL，不用于当前路线 |
| Alpine 等无 glibc 发行版 | 不支持 | kubeadm 二进制为动态链接，依赖 glibc |

## Kubernetes 版本与组件关系

- 本项目只使用**受官方维护**的 minor。查询日（2026-08-14）官方维护最新 3 个 minor：**1.36 / 1.35 / 1.34**；
  1.33 已于 2026-06-28 EOL。
- 第一条路径固定 **1.36.2**；kubeadm、kubelet、kubectl 三者同位对齐（kubeadm 不支持跨 minor 安装/升级）。
- 版本偏差上限（version-skew-policy，页面最后更新 2026-04-14）：
  - kubelet 不得新于 kube-apiserver，可比其老最多 **3** 个 minor；
  - kubectl 与 kube-apiserver 偏差不超过 **±1** 个 minor；
  - kube-controller-manager / kube-scheduler 与 apiserver 同位或老 **1** 个 minor；
  - HA 集群内多个 kube-apiserver 之间偏差不超过 1 个 minor。

## containerd 与 cgroup

- 第一条路径使用 **containerd 2.3 LTS**。官方兼容矩阵（containerd.io/releases，查询日 2026-08-14）：

| Kubernetes | 支持的 containerd |
| --- | --- |
| 1.36 | 2.3.0+、2.2.0+ |
| 1.35 | 2.2.0+、2.1.5+、1.7.28+ |
| 1.34 | 2.1.3+、2.0.6+、1.7.28+、1.6.39+ |
| 1.33 | 2.1.0+、2.0.4+、1.7.24+、1.6.36+ |

- **cgroup 驱动必须为 systemd**：kubeadm 自 v1.22 起默认将 kubelet 的 `cgroupDriver` 设为
  systemd；containerd 侧在 `/etc/containerd/config.toml` 中配置（cgroup v2 环境推荐 systemd）。
- 配置路径差异（container-runtimes，查询日 2026-08-14）：
  - containerd **1.x**：`[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options]` → `SystemdCgroup = true`
  - containerd **2.x**：`[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options]` → `SystemdCgroup = true`
- **为什么不用 containerd 1.7 系**：1.7 支持期到 2026-09 结束；且 1.y 不支持 RuntimeConfig CRI RPC，
  Kubernetes 1.36 起 kubelet 可自动探测 cgroup 驱动，到 1.38 将取消回退行为，旧版 containerd 与新版
  kubelet 会失配。当前路线固定 2.x（参见[升级路径](#升级路径)）。

## 内核、硬件与系统要求

第一条路径的节点要求（官方来源 + 实验取值）：

| 项 | 要求 |
| --- | --- |
| CPU 架构 | x86_64（glibc 发行版） |
| 内存 | 控制平面 ≥ 2GB（官方下限），实验环境建议 ≥ 4GB；Worker ≥ 2GB |
| CPU 数量 | 控制平面 ≥ 2（官方下限），Worker ≥ 2 |
| 磁盘 | 实验环境建议 ≥ 30GB，版本拉取与 etcd 预留充足空间（正式下限由 B1 预检确认） |
| Swap | 节点必须关闭 Swap（kubelet 默认不允许） |
| 时间同步 | chrony / systemd-timesyncd / NTP，集群内一致 |
| 内核模块 | 容器运行时使用的 `overlay`；网络实现按需 `br_netfilter`（B1 预检按组件确定） |
| sysctl | 官方必需：`net.ipv4.ip_forward = 1`（`/etc/sysctl.d/k8s.conf` 持久化） |
| 网络 | 节点间全互通；唯一 hostname、MAC、product_uuid |

> 历史教程中的 `net.bridge.bridge-nf-call-iptables` 属 flannel 时代的 sysctl，当前官方
> container-runtimes 页面不再作为必需项列出，B1 预检按所选网络实现（Calico）的官方文档配置。

## CNI

| CNI | 版本 | 状态 | 说明 |
| --- | --- | --- | --- |
| Calico | v3.32.1 | 已确认 | 支持 NetworkPolicy；kubeadm 不安装默认 CNI，需集群创建后由 operator 安装 |
| Flannel | — | 历史参考 | 历史教程采用；维护活跃度低，不支持 NetworkPolicy，当前路线不采用 |
| Cilium 等 | — | 计划验证 | 暂不承诺，待第一条路径稳定后评估 |

## 控制平面与 HA

| 拓扑 | 状态 | 说明 |
| --- | --- | --- |
| 单控制平面 + N Worker | 已确认 | B1 首个验收拓扑 |
| 3 控制平面 HA（kube-vip 或外部 LB + 满足 etcd quorum） | 计划验证 | B3 阶段形成多节点演练证据 |
| Keepalived + HAProxy 手写配置 | 历史参考 | 教程采用 PASS 密码与手工复制证书的做法，当前路线不推荐 |
| 外部 etcd / 混合云多控制面 | 不支持 | 超出本项目 Day 0/1 范围 |

## 升级路径

- kubeadm 升级**不允许跨 minor**；每个 minor 内先升级到该系列最新 patch，再进入下一 minor。
- 官方推荐升级顺序：kube-apiserver → kube-controller-manager / kube-scheduler → kubelet（逐节点 drained）。
- 查询日 EOL 日历：1.36.2（EOL 2027-06-28）、1.35.6（EOL 2027-02-28）、1.34.9（EOL 2026-10-27）。
- 本项目升级策略：跟随官方维护窗口滚动，B1 起每个新 minor 先在实验环境完成验证并更新本矩阵。
- B1 的 `upgrade.yml` 与回滚策略属于 B3 范围，不在 B0 承诺。

## 待验证项与 B1 前置

- 真实多节点安装与验收（Node Ready、CoreDNS、Calico、Service/DNS、Pod 调度）→ B1。
- Ubuntu 24.04 上 containerd 2.3 deb 包与 1.36.2 组合的真实验收 → B1。
- Rocky Linux 9.x 路径、HA 拓扑、跨 minor 升级演练 → B3。
- 国内网络环境下 registry.k8s.io 与 Calico 镜像的拉取策略 → 见 [lab-environment.md](./lab-environment.md)。

## 来源表（查询日 2026-08-14）

| 事实 | 来源 | 查询日 |
| --- | --- | --- |
| Kubernetes 维护窗口与 EOL 日历 | https://kubernetes.io/releases/ | 2026-08-14 |
| 版本偏差策略 | https://kubernetes.io/releases/version-skew-policy/（页面更新 2026-04-14） | 2026-08-14 |
| kubeadm 支持发行版、安装前提、glibc 依赖 | https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/ | 2026-08-14 |
| containerd cgroup / SystemdCgroup / RuntimeConfig CRI RPC | https://kubernetes.io/docs/setup/production-environment/container-runtimes/ | 2026-08-14 |
| containerd 版本状态与 K8s 兼容矩阵 | https://containerd.io/releases/ | 2026-08-14 |
| Calico 发布版本 | https://github.com/projectcalico/calico/releases | 2026-08-14 |
| Ansible Core 生命周期与 Python 要求 | https://docs.ansible.com/ansible/latest/reference_appendices/release_and_maintenance.html | 2026-08-14 |
| Ansible Core 最新补丁版本 | https://pypi.org/project/ansible-core/ | 2026-08-14 |

> 维护窗口会随时间滚动：任何新安装/升级前，请按查询当日官方页面复核本矩阵，不要因为本文档的
> 「已确认」状态而跳过复核。本矩阵的四态标记与 README「完成标准」保持一致：在 B1 真实验收前，
> 本仓库不宣称生产级交付能力。
