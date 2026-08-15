# Changelog

本项目遵循 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，
版本号将在第一个可交付基线（B4 tag）时按 [Semantic Versioning](https://semver.org/lang/zh-CN/) 引入。

## [Unreleased]

### Added

- `docs/compatibility.md`：第一条正式支持路径（Ubuntu 24.04 LTS + Kubernetes 1.36.2 +
  kubeadm/kubelet/kubectl 1.36.2 + containerd 2.3 LTS + Calico v3.32.x + Ansible Core 2.21），
  含版本偏差策略、containerd/cgroup、内核与硬件要求、CNI、单控制平面与 HA 状态、
  升级路径与四态（已确认/计划验证/历史参考/不支持）定义，全部标注官方来源与查询日（2026-08-14）。
- `docs/lab-environment.md`：实验环境合同——RFC 5737 文档地址、单控制平面与三控制平面最小拓扑、
  虚拟机/网络/DNS/NTP/端口/代理/镜像前提、销毁与 reset 边界、凭据与日志脱敏要求。
- `docs/security-boundaries.md`：安全基线——绝对禁止项（关闭防火墙/SELinux、关闭签名校验、
  固定 Token/口令/密码等）、join 凭据生命周期、最小端口与最小 SSH 权限、host key 校验、
  镜像/软件包/外部脚本校验、`.gitignore` 规则与扫描允许清单机制。
- `.gitignore`：kubeconfig、证书、Token、Inventory Secret、实验日志等敏感产物排除规则。
- `.github/scripts/check_markdown_style.py`：无依赖的 Markdown 格式门禁（行尾空白、空行、
  标题格式、fence 配对、CRLF/U+200B）。
- `.github/scripts/scan_sensitive.py` 与 `.github/scan-allowlist.txt`：敏感字段与危险示例
  扫描（kubeadm Token 形状、关闭仓库签名校验标记、明文 `ansible_password`、私钥、kubeconfig 数据、
  HAProxy 明文口令、RFC 1918 节点地址、明文密码赋值），允许清单按「文件+整行正则」精确豁免。
- `CHANGELOG.md` 与 `docs/changes/2026-08-14-b0-compatibility-baseline.md`：变更记录。

### Changed

- **历史教程治理**：三篇教程（单节点 1.18 / HA 1.16 / Ansible 二进制 1.16）首屏警示强化，
  新增英文 `DO NOT USE FOR CURRENT DEPLOYMENT` 横幅并链接到 `docs/compatibility.md`；
  新增「历史版本清单」表（CentOS 7、Docker 18.x、K8s 1.16/1.18、阿里云源、Flannel 等标记为
  历史参考），修复章节编号、行尾空白与格式问题；教程不再作为当前执行手册。
- **README**：`当前状态` 更新为 B0 完成并注明「官方兼容确认（未实机验证）」；`文档入口`
  增加三份 B0 文档并明确教程为历史；B0 路线标记为已完成；`完成标准` 保持“未满足”语义。
- **CI**：在原有 Markdown 链接检查基础上增加 Markdown 格式检查、敏感字段扫描与
  扫描器正例/反例回归测试。
- **兼容矩阵语义修正**（2026-08-14，ChatGPT 审查后）：「已确认」改为「已确认（官方兼容，
  未实机验证）」，增加「官方兼容 → 项目选定 → 实机验证」三层说明；补 kube-proxy 版本偏差；
  升级顺序改为「apiserver → controller-manager/scheduler（彼此无强制先后）→ kubelet
  （逐节点 drain）」；Swap 增加验证标准；containerd 2.4 明确为「计划验证（未发布）」；
  Alpine 表述改为「默认不纳入支持范围；kubeadm 要求 glibc 或兼容层」。
- **安全基线**：端口表升级为「端口 + 方向 + 作用域」；禁止项措辞改为「禁止将关闭
  firewall / SELinux / AppArmor 作为安装前置条件」；`.gitignore` 增加「误提交缓解措施，
  不是 secret 隔离」声明；扫描项说明对齐扫描器改进（占位符感知、PKCS#8、kubeconfig token）。
- **扫描器重构**（`scan_sensitive.py`）：支持值级占位符感知（忽略 `<PASSWORD>`、`${VAR}`、
  `{{ vault_password }}`、`!vault`、`lookup(...)`、布尔字面量）；增加 `token:` /
  `client-key-data` 等 kubeconfig 凭据形状检测；移除 `ansible_host` RFC1918 模式（IP 本身
  不是凭据）；允许清单自保护校验（拒绝 `.*` 等宽泛正则、校验路径存在性与原因非空）；
  新增 `test_scan_sensitive.py` 正例/反例回归测试。

### Added

- **B1 真实 Ansible 交付结构**（2026-08-14，结构就绪，未真实验收）：
  - `inventory/`：逻辑分组（k8s_cluster/control_plane/worker，预留 etcd）+ `group_vars/all.yml`
    （版本锚点、网络 CIDR、SSH、token/Cert TTL）+ RFC 5737 host_vars；
  - `roles/`：`preflight`、`containerd`、`kubeadm`、`control_plane`、`worker`、`cni`、`load_balancer`（B3 占位）；
  - `playbooks/`：`site.yml`、`reset.yml`、`upgrade.yml`（升级为 B3 骨架，显式 pin、不跨 minor）；
  - `scripts/verify-cluster.sh`：验收辅助脚本（nodes/pods/Calico/DNS，退出码语义）；
  - `ansible.cfg`：roles_path/inventory/host_key_checking 配置；
  - CI 新增 `ansible` 任务（ansible-core 2.21 + syntax-check + inventory graph）。

### Changed

- **README**：`当前状态` 增加 B1 结构就绪声明；`重建路线` B1 标记「结构已就绪，真实验收属 B2」。
- **CHANGELOG / change record**：新增 B1 变更记录。

### Added

- **B2 真实环境验收与幂等交付**（2026-08-15，见 `docs/changes/2026-08-15-b2-real-cluster-acceptance.md`）：
  - 在真实 Ubuntu 24.04 LTS 双节点（Lima arm64，1 CP + 1 worker）完成 `site.yml` 全量部署；
  - `verify-cluster.sh` 全量验收通过（Node Ready / Pod / Calico Tigerastatus / CoreDNS / DNS 解析）；
  - 二次重跑幂等（changed=0）；`reset.yml` → 重建 → 再验收再幂等闭环验证；
  - containerd handler 增加 `daemon_reload`（代理 drop-in 生效）；certificate-key 提取改用
    `stdout_lines | select(match)` 鲁棒解析；CNI 任务补 `NO_PROXY` 并改本地 get_url 清单；
    deb822/legacy 源清理不再误删 `docker-stable.sources`；`config.toml`/GPG 用 `creates` 幂等；
    `verify-cluster.sh` 修正 tigerastatus 列号与 busybox 全限定 DNS 名。

### Added

- **B2 x86_64 回归验收**（2026-08-15，见 `docs/changes/2026-08-15-b2-x8664-regression.md`）：
  - 在 Ubuntu 24.04 amd64 双节点（QEMU 模拟 x86_64，1 CP + 1 worker）重放 B2 全矩阵：
    首次 `site.yml` → `verify-cluster.sh` 全绿 → 二次幂等 changed=0 → `reset.yml` →
    重建 → 再 verify → 再幂等 changed=0，全部通过；
  - 修复 x86_64 暴露的两个预置问题：`deb822_repository` 后补条件 apt 缓存刷新
    （`when: docker_repo_state.changed`，保持幂等）；检测并移除 Ubuntu amd64 cloud image
    预置的 CRI-disabled `/etc/containerd/config.toml`（此前 `creates` 守卫生效导致跳过生成）。
  - 解锁 B3（HA / 多控制平面 / etcd quorum / 升级演练）。

### Changed

- **README**：B2 小节补充 x86_64 回归完成声明（含 change record 链接）。
- **inventory**：新增 `hosts-x86.yml`（RFC 5737 示例）与 `host_vars/cp-x86.yml`、
  `host_vars/worker-x86.yml` 示例；真实连接仍在 gitignored `host_vars/*/local.yml`（目录形式）。

### Changed

- **README**：`当前状态` 增加 B2 完成声明；B1 路线的真实验收项标记为 B2 完成，
  新增「B2（当前里程碑）」验收清单；B2 路线标记为已完成。
- **CHANGELOG / change record**：新增 B2 变更记录；`site.yml` 汇总提示指向 B2 change record。

### Security

- 明确 join 凭据（Token / certificate-key / CA 哈希）现场生成、短时有效、安全通道传输；
  仓库内不存在可复用凭据与真实节点地址（B0 基线延续至 B1 自动化骨架）。
- 明确软件仓库与容器镜像的签名/校验要求，禁止关闭软件仓库签名验证与未固定版本的外部脚本（B0）。
- **B1**：join token / certificate-key 现场生成、短时有效、`no_log`，不写入 inventory / Git / CI artifact；
  明文密码不入 inventory（SSH 密钥认证，B0 安全基线延续）。

## [旧版本]

- 2026-04-20 起的历史提交（教程文档、README、LICENSE、链接检查 CI）未按本文件归档；
  相关内容已由 `docs/compatibility.md` 与 change record 承接描述。
