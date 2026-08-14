# 实验环境合同（B0）

> 本文件定义仓库内所有集群交付演练的**实验环境规则**：拓扑最小化、文档地址、网络/资源前提、
> 销毁与凭据清理边界、以及脱敏与 Git 排除要求。实验环境结论不得表述为生产环境结论。
> 与 [security-boundaries.md](./security-boundaries.md) 配套使用。

## 1. 地址与命名规则

- 文档与示例一律使用 **RFC 5737 文档地址**，禁止出现真实节点地址：

| 网段 | 用途 |
| --- | --- |
| 192.0.2.0/24 | 单控制平面实验（借自现有教程命名习惯） |
| 198.51.100.0/24 | 三控制平面 HA 实验 |
| 203.0.113.0/24 | 保留，不用于拓扑示例 |

- 主机名使用 `cp1`、`cp2`、`cp3`、`node1`…`nodeN` 这类中性名称，不绑定真实域名。
- 所有 Token、证书哈希、密码、密钥必须以 `<UPPER_SNAKE_CASE>` 占位符出现，例如
  `<BOOTSTRAP_TOKEN>`、`sha256:<CA_CERT_HASH>`、`<KEEPALIVED_AUTH_PASS>`、
  `<HAPROXY_STATS_PASSWORD>`、`<CERTIFICATE_KEY>`。

## 2. 最小拓扑

### 2.1 单控制平面（B1 首个验收拓扑）

```text
              ┌───────────────────────┐
              │   Ansible 控制节点     │   本机或独立 VM，Python 3.12+ / Ansible Core 2.21.x
              └───────────┬───────────┘
                          │ SSH（最小权限，密钥认证）
        ┌─────────────────┴─────────────────┐
        │                                   │
┌───────▼────────┐                  ┌───────▼────────┐
│   cp1 (192.0.2.11) │                  │  node1 (192.0.2.12)  │
│   control-plane    │                  │  worker             │
└──────────────────┘                  └──────────────────┘
   kube-apiserver / etcd / controller-manager / scheduler
   containerd 2.3 LTS + Calico
```

- 最少 **2 个节点**（1 控制平面 + 1 Worker）即可完成安装链路验收；预算允许时再加 1 个 Worker。
- 控制平面 ≥ 2 vCPU / ≥ 4GB RAM；Worker ≥ 2 vCPU / ≥ 2GB RAM；磁盘 ≥ 30GB。
- 不允许在控制平面上运行 Worker 负载（taint 保持默认）。

### 2.2 三控制平面 HA（计划验证，B3 目标）

```text
                       ┌──────────────────────┐
                       │  kube-vip (VIP) 或外部 LB │  198.51.100.14:6443
                       └──────────┬───────────┘
              ┌───────────────────┼───────────────────┐
        ┌─────▼─────┐      ┌─────▼─────┐      ┌─────▼─────┐
        │ cp1       │      │ cp2       │      │ cp3       │
        │ 198.51.100.11 │   │ 198.51.100.12 │   │ 198.51.100.13 │
        └───────────┘      └───────────┘      └───────────┘
              └───────────────────┼───────────────────┘
                            ┌────▼────┐
                            │ node1..N │
                            └─────────┘
```

- 控制平面数量必须满足 **etcd quorum**（3 个控制平面容忍 1 个故障；2 个不满足，禁止使用）。
- B0 阶段 HA 只做拓扑与前提确认，**不实现** HA 自动化（属 B1/B3）。
- Keepalived + HAProxy 手工方案仅作历史参考（见 `使用kubeadm搭建高可用的K8s集群.md`），
  当前路线优先 kube-vip 或云 LB。

## 3. 虚拟机与资源前提

- 虚拟化：QEMU/KVM、VMware、VirtualBox 或等价；每节点独立 VM。
- 操作系统镜像：Ubuntu 24.04 LTS Server（x86_64）官方镜像（含校验和验证）。
- 节点要求（与兼容矩阵一致）：Swap 关闭、时间同步、唯一 hostname/MAC/product_uuid、
  `net.ipv4.ip_forward=1`。
- 快照策略：安装前为每个节点建干净快照，便于失败后快速还原，避免反复 reset。

## 4. 网络、DNS 与命名解析

- 节点间二层/三层互通；SSH 端口 22 放行给控制节点与运维主机（最小来源）。
- Kubernetes 需放行的端口（按官方文档）：API Server 6443、etcd 2379-2380、
  kubelet 10250、kube-scheduler 10259、kube-controller-manager 10257；NodePort 30000-32767。
- 生产/共享网络放行规则见 [security-boundaries.md](./security-boundaries.md)。
- DNS：集群内部使用 CoreDNS（`cluster.local`）；节点解析建议走内部 DNS 或 `/etc/hosts`
  （使用 RFC 5737 地址）。
- NTP：chrony 指向可信时间源，所有节点时间一致后再进行证书申请与 join。

## 5. 代理与镜像拉取前提

- 默认镜像仓库 **registry.k8s.io**（kubeadm 默认）与其他官方镜像可能受网络环境影响。
- 国内/受限网络的选择（按优先级）：
  1. 配置合规的镜像加速器/代理（在 containerd `config.toml` 配置 registry mirror）；
  2. 离线路径：在有网络的节点上 `ctr images export` 预拉镜像，导入目标节点
     （`ctr images import`），所有镜像按 digest 固定版本；
  3. 不建议直接改用第三方容器镜像仓库地址，除非其来源、签名与版本可核验。
- 软件包仓库（apt / pkgs.k8s.io）必须保持**官方源 + 签名校验开启**，禁止 `gpgcheck=0` 或
  等价关闭验证的做法。
- 代理环境变量导致的访问例外必须记录在本节，属于实验环境变量，不属于生产配置。

## 6. 凭据、证书与敏感产物

join 与交接阶段涉及以下敏感产物，**必须现场生成、短时有效、安全通道传输**：

| 敏感项 | 生成与有效期要求 | 存放边界 |
| --- | --- | --- |
| kubeadm bootstrap Token | `kubeadm token create` 现场生成，TTL ≤ 24h（默认），用后即删 | 只进入命令输出，不入文件 |
| certificate-key（控制平面 join） | `kubeadm init` / `kubeadm certs certificate-key` 现场生成 | 安全通道传递，用后即删 |
| discovery-token-ca-cert-hash | 现场从 init 输出获取 | 与 Token 同生命周期 |
| kubeconfig（admin / super-admin） | 集群创建后生成 | 留在控制节点 `$HOME/.kube`，不复制进仓库 |
| PKI 证书与私钥 | `kubeadm init` 生成 | 留在 `/etc/kubernetes/pki`，绝不入 Git |
| 执行日志 | `tee` 到 `artifacts/` 或直接丢弃 | 入 Git 前必须脱敏 |

**Git 排除**（详见根目录 `.gitignore` 与 [security-boundaries.md](./security-boundaries.md)）：
`*.kubeconfig`、`**/admin.conf`、`**/pki/**`、`*.crt`、`*.key`、`*.csr`、`*.pem`、
token 文件、certificate-key 文件、Inventory 明文凭据、`artifacts/` 实验产物与日志。

## 7. 环境销毁、reset 与凭据清理边界

- 演练结束或失败需要重建时，首选**从快照还原**；其次 `kubeadm reset`。
- `kubeadm reset` 边界：清掉节点上的 kubelet 状态、容器运行时数据与 `/etc/kubernetes`，
  但**不会**删除随发行版安装的软件包；如需完全还原，应销毁 VM 而不是仅 reset。
- 凭据清理：销毁前删除控制节点上的 join Token（`kubeadm token delete`）、certificate-key、
  以及任何临时 scp 的文件；删除 `$HOME/.kube` 中非必要的 kubeconfig。
- 环境销毁后，必须再次执行 [scan_sensitive](../.github/scripts/scan_sensitive.py) 确认仓库无泄漏。
- 每次演练的结论记录在 `docs/changes/` 的 change record 中，注明环境为隔离实验，
  **不把隔离实验结果表述为生产环境结论**。

## 8. 职责边界

- 本仓库：Day 0/1 集群创建与交付、验收、脱敏证据、集群交接。
- 运行期运维（Linux / Kubernetes）与 Day 2 管理分别属于 `devops-automation` 与
  `aiops-platform`；实验数据如需进入运行期平台，走正常交接通道，凭据不跨仓库复制。
