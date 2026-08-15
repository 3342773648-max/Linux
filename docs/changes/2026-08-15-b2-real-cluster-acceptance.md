# Change Record: B2 真实环境验收与幂等交付

- 日期：2026-08-15
- 范围：`kubernetes-cluster-bootstrap` / B2（`roles/` 执行修复、`scripts/verify-cluster.sh` 验收、真实双节点集群）
- 前置：B1「真实 Ansible 交付结构」已完成（`761b2c7`，CI 全绿 31812878362）+ 本地修复 `662d512`、`9e36ef9`
- 相关文档：`docs/compatibility.md`、`docs/security-boundaries.md`、`docs/lab-environment.md`、`docs/changes/2026-08-14-b1-ansible-delivery.md`

## 背景

B1 交付了可执行的 Ansible 结构，但**未做真实环境验收**（明示属 B2）。B2 的目标：
在真实 Ubuntu 24.04 LTS 双节点（1 CP + 1 worker）上完成：

1. `site.yml` 完整部署（preflight → containerd → kubeadm 工具 → kubeadm init → worker join → Calico CNI）
2. `scripts/verify-cluster.sh` 全量验收通过
3. 二次重跑幂等（changed=0）
4. `reset.yml` 拆集群 → 再次 `site.yml` 重建 → 再次验收，证明可重复交付

## 实验环境（B0 lab-environment.md 合同内）

- 宿主机：macOS（arm64），Lima 2.2.0 虚拟化（`--network lima:user-v2` 共享网段）
- 节点：cp-01=192.168.104.1（limactl SSH 转发 127.0.0.1:65273）、worker-01=192.168.104.3（127.0.0.1:65282）
- 经 HTTP 代理 127.0.0.1:7897 访问外网；容器镜像仓库直连超时 → containerd 走代理拉取
- 版本：K8s 1.36.2、containerd 2.3 LTS（Docker 官方 apt，suite 用发行版代号 noble）、Calico v3.32.1
- 真实连接配置在 `inventory/host_vars/<host>/local.yml`（gitignored，含真实 IP/密钥路径）

> 说明：`local.yml` 内为**真实实验室地址**（本机 127.0.0.1 转发端口），按 security-boundaries.md 的
> 约定不入库；仓库默认 `group_vars/all.yml` 仅含 RFC 5737 示例地址。

## 执行中修复（真实环境暴露的问题）

### P0：kubeadm init 拉镜像失败 → containerd 代理未生效

- 现象：`kubeadm init` 预检拉 `registry.k8s.io/kube-apiserver` 直连超时（europe-west2-docker.pkg.dev i/o timeout）
- 根因：代理 drop-in 写入后 handler `systemd: restarted` **未先 `daemon-reload`**，Environment 未加载
- 修复：`roles/containerd/handlers/main.yml` 增加 `daemon_reload: true`

### P0：certificate-key 提取脆弱（regex_search 崩）

- 现象：`regex_search('--certificate-key\s+...')` 无匹配时抛 NoneType 异常；后 `regex_findall` 在
  if/else 求值中空序列报错
- 修复：`roles/control_plane/tasks/main.yml` 改为 `stdout_lines | map('trim') | select('match','^[a-f0-9]{64}$') | first`
  —— kubeduam upload-certs 输出格式为独立 64-hex 行，`select` 对空结果零异常，且绑定 `--certificate-key`
  的参数仍由 `token create --certificate-key` 使用（CA hash 不会误命中）

### P1：CNI 任务 HTTPS_PROXY 污染集群 API 请求

- 现象：CNI `kubectl apply` 带 `HTTPS_PROXY` 时把指向 `192.168.104.1:6443` 的请求也走代理 → openapi 超时
- 修复：`roles/cni/tasks/main.yml` 追加 `NO_PROXY`（含 control_plane_endpoint 的 IP）

### P1：CNI 重跑网络抖动即失败 → 改本地清单

- 现象：二次重跑时 raw.githubusercontent.com 拉取瞬时 EOF → apply 中断
- 修复：CRD / tigera-operator 清单先 `get_url` 到 `/etc/kubernetes/`，再 apply 本地文件；apply 用
  `changed_when` 依据 `'unchanged' not in stdout`，CRD server-side apply 声明式幂等（`changed_when: false`）

### P1：幂等性缺口（重跑 changed≠0）

- `移除旧版 Docker apt 源` loop 含 `stable.sources`，会删掉 deb822 刚生成的 `docker-stable.sources` →
  每次重跑「删了又建」；改为仅清理 legacy `.list`
- `containerd config default | tee` 每次覆盖 config.toml 使 SystemdCgroup replace 恒 changed →
  加 `args: creates:` 仅首次生成
- GPG key 任务多余 `changed_when: true` 移除（`creates` 已足够）

### P1：reset 后重建失败

- 现象：`reset.yml` 后 `/etc/kubernetes` 被清空，重建时模板任务报 `Destination directory does not exist`
- 修复：control_plane 角色增加「确保 /etc/kubernetes 目录存在」任务

### P1：verify-cluster.sh 修正

- tigerastatus awk `$4`（DEGRADED 列）→ `$2`（AVAILABLE 列）；`note` 文本内 `$2` 在 `set -u` 下展开报错
- busybox `nslookup` 不走 search domain → 用全限定名 `kubernetes.default.svc.cluster.local`

## 验收证据（全部真实运行）

| 检查点 | 结果 |
|---|---|
| `site.yml` 首次部署（双节点） | ✅ ok=61 changed=8（首次，含 init/join/CNI） |
| `verify-cluster.sh` 全量 | ✅ 节点 2/2 Ready、系统 Pod 正常、Tigerastatus 全 True、DNS OK |
| 二次重跑幂等 | ✅ changed=0（cp-01 ok=60 / worker-01 ok=44） |
| `reset.yml` 拆集群 | ✅ 两节点脱离集群、kubelet inactive |
| 拆后 `site.yml` 重建 | ✅ 全新 init 成功 |
| 重建后 verify + 幂等 | ✅ verify 全绿 + changed=0 |

运行态事实（最后验收时刻）：cp-01 / lima-worker-01 均 Ready v1.36.2，containerd 2.3.3；
calico-system 与 kube-system 全部 Running；`kubectl get nodes` 2 节点 Ready。

## 遗留与后续

- B3（HA 多控制平面、cert 轮换、升级演练）未在本轮触碰
- 快照还原仍是实验环境复原的首选（reset 后重建为兜底验证）
- host_vars local.yml 需在真实验收时按节点 IP/端口重新生成（gitignored）
## 审查修正（AgentChat Step2 search / Step5 review）

- Step2 search（`ac-6a7fd479b8c5c594b4578690`）：权威实践与本轮修复一致——NO_PROXY 需含
  内部 CIDR/API endpoint、幂等用 `creates`/`changed_when`、upload-certs 提取 certificate-key、
  reset 需清理 `/etc/kubernetes` 等目录。
- Step5 review（`ac-6a7fd509203cdb1fa1ba188f`）：**P0=0，无阻断项**。3 个 P1 处置如下：

| P1 | 处置 |
|---|---|
| certificate-key 仅按「独立 64-hex 行」识别，存在理论误命中 | upstream 命令固定为 `kubeadm init phase upload-certs --upload-certs`，输出结构受控且被 B0 版本锚定（K8s 1.36.2）；提取结果经 `assert`（length==64）兜底 |
| `first` 无匹配时失败语义 | `校验 join 凭据齐全` assert 已拒空值（join 命令与 cert-key 缺失即 fail，不静默） |
| reset→rebuild 完整收敛需 E2E 证据 | 本轮已实测：`reset.yml` 拆集群 → `site.yml` 重建成功 → `verify-cluster.sh` 全绿 → 二次重跑 changed=0 |

- no_log 链核验：`kubeadm init`、`upload-certs`、`token create`、join 命令、cert-key 提取、join 变量
  注册全部 `no_log: true`；普通状态任务保持可观察（符合 security-boundaries.md 原则）。
