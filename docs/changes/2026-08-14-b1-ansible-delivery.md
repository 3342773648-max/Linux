# Change Record: B1 真实 Ansible 交付结构

- 日期：2026-08-14
- 范围：`kubernetes-cluster-bootstrap` / B1（`inventory/`、`roles/`、`playbooks/`、`scripts/`、CI 语法门禁、文档同步）
- 基线 commit：`7c73977`（docs(bootstrap): apply ChatGPT review fixes to B0 baseline）
- 前置：B0「兼容矩阵与安全基线」已完成（`984ddc5` + `7c73977`）
- 相关文档：`docs/compatibility.md`、`docs/security-boundaries.md`、`docs/lab-environment.md`、README、CHANGELOG

## 背景

B0 完成兼容矩阵、实验环境合同、安全基线、历史教程治理与 CI 门禁，但仓库尚无任何可执行的
Ansible 交付结构。B1 的目标是把「官方兼容确认」转化为**真实的自动化骨架与执行逻辑**：
`inventory/`、`roles/`、`playbooks/`、`scripts/verify-cluster.sh`，并让 CI 对它们做语法级门禁。
**B1 不宣称真实多节点验收**——那属于 B2；HA 与升级执行属于 B3。

## 首条支持路径（继承 B0）

Ubuntu 24.04 LTS + Kubernetes 1.36.2 + kubeadm/kubelet/kubectl 1.36.2 + containerd 2.3 LTS
（systemd cgroup, cgroup v2）+ Calico v3.32.1 + Ansible Core 2.21.3（本机验证），单控制平面拓扑。

关键官方依据（查询日 2026-08-14）：

- kubeadm 配置 API v1beta4：https://kubernetes.io/docs/reference/config-api/kubeadm-config.v1beta4/
  （ClusterConfiguration `networking.podSubnet/serviceSubnet/dnsDomain`、`controlPlaneEndpoint`、
  `imageRepository`；KubeletConfiguration apiVersion `kubelet.config.k8s.io/v1beta1` +
  `cgroupDriver: systemd`；extraArgs 为结构化 `[{name, value}]`）
- kubeadm 安装与组件:https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- kubeadm init 输出 / upload-certs / certificate-key：https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/high-availability/
  （`--config` 与 `--certificate-key` 不能混用；证书密钥 2h 过期）
- containerd CRI 配置（2.x 路径）：https://github.com/containerd/containerd/blob/main/docs/cri/config.md
  （[plugins.'io.containerd.cri.v1.runtime'.containerd.runtimes.runc.options] SystemdCgroup = true）
- Calico v3.32.1（tigera-operator 路径）：https://docs.tigera.io/calico/latest/getting-started/kubernetes/quickstart
  （CRD → tigera-operator.yaml → custom-resources.yaml → git tigerastatus）

## 设计要点（ChatGPT 推理，`ac-6a7f1ef6b179fd05ea5aa2bb`）

采纳的关键决策：

1. **Inventory**：`inventory/hosts.yml` 逻辑分组（`k8s_cluster` / `control_plane` / `worker` /
   预留 `etcd` 继承 control_plane）；变量集中 `group_vars/all.yml`（版本锚点、网络 CIDR、SSH、
   token/Cert TTL）；host_vars 示例用 RFC 5737 地址。
2. **Role 边界严格**：preflight / containerd / kubeadm / control_plane / worker / cni /
   load_balancer（B3 占位）；不放一个巨型 kubernetes role。
3. **持久化语义**：swap 注释 `/etc/fstab`；内核模块写 `/etc/modules-load.d/k8s.conf`；
   sysctl 写 `/etc/sysctl.d/k8s.conf`；重启后不还原。
4. **凭据安全**：token / certificate-key 由控制平面现场生成、短时有效、`no_log`；经
   hostvars 传递，不写 inventory / Git / CI artifact；不把明文密码写入 inventory（SSH 密钥认证）。
5. **CNI 边界**：只在 `control_plane[0]` 装 Calico（避免 HA 多 CP 重复安装）；等待
   `tigerastatus` 全 True，而非仅看 pod Running。
6. **reset**：复用 role 的 `tasks_from: reset.yml`，不清除 OS/SSH/apt 配置（快照还原仍是首选）。
7. **upgrade**：B1 仅骨架，显式 pin 目标版、禁止 latest、不跨 minor。
8. **CI**：新增 `ansible-playbook --syntax-check` 与 `ansible-inventory` 门禁。

## 文件级改动清单

| 文件 | 改动 |
|---|---|
| `inventory/hosts.yml` | 新增：逻辑分组示例（RFC 5737 地址） |
| `inventory/host_vars/cp-01.yml` | 新增：CP 示例（192.0.2.10） |
| `inventory/host_vars/worker-01.yml` | 新增：worker 示例（192.0.2.20） |
| `inventory/group_vars/all.yml` | 新增：版本锚点、网络、SSH、token/Cert TTL、仓库源变量 |
| `roles/preflight/` | 新增：OS 断言、swap 持久化、内核模块、sysctl、文件系统提示、chrony、/etc/hosts |
| `roles/containerd/` | 新增：Docker 官方源 + containerd.io 2.3 安装 + SystemdCgroup 配置 + hold |
| `roles/kubeadm/` | 新增：pkgs.k8s.io 源 + kubelet/kubeadm/kubectl 锚点 + 版本断言 + hold |
| `roles/control_plane/` | 新增：kubeadm init（v1beta4）+ upload-certs + 注册 join 凭据（no_log）+ reset |
| `roles/worker/` | 新增：kubeadm join（凭据来自 first CP hostvars）+ reset |
| `roles/cni/` | 新增：Calico tigera-operator（CRD→operator→custom-resources→wait tigerastatus） |
| `roles/load_balancer/` | 新增：B3 占位（不做 HA/LB） |
| `playbooks/site.yml` | 新增：全部装配（preflight/containerd/kubeadm → first CP → worker → cni） |
| `playbooks/reset.yml` | 新增：逆向卸载（worker → CP → 运行时），复用 role reset |
| `playbooks/upgrade.yml` | 新增：升级骨架（B3 执行，显式 pin、不跨 minor） |
| `scripts/verify-cluster.sh` | 新增：验收辅助（nodes/pods/Calico/DNS，退出码语义，B2 扩展） |
| `.github/workflows/ci.yml` | 修改：增加 syntax-check + inventory 门禁 |
| README / CHANGELOG / 本 change record | 更新/新增 |

## 验证命令（已本地通过）

```bash
python3 -m venv /tmp/ansible-venv \
  && /tmp/ansible-venv/bin/pip install 'ansible-core>=2.21,<2.22'
/tmp/ansible-venv/bin/ansible-playbook -i inventory/hosts.yml playbooks/site.yml --syntax-check
/tmp/ansible-venv/bin/ansible-playbook -i inventory/hosts.yml playbooks/reset.yml --syntax-check
/tmp/ansible-venv/bin/ansible-playbook -i inventory/hosts.yml playbooks/upgrade.yml --syntax-check
/tmp/ansible-venv/bin/ansible-inventory -i inventory/hosts.yml --graph
python3 .github/scripts/check_markdown_links.py
python3 .github/scripts/check_markdown_style.py
python3 .github/scripts/scan_sensitive.py
python3 -m unittest discover -s .github/scripts -p "test_*.py"
```

## 审查修正（2026-08-14，ChatGPT 交叉审查）

实施后经 ChatGPT 审查（`ac-6a7f282fed20f3b7bcd03d13`）：结构 PASS，发现 4 项阻塞级正确性问题
与多项高价值 P1，全部修复：

- **P0 cgroupDriver**：固定为 `"systemd"`（B0 兼容矩阵仅支持 systemd cgroup + cgroup v2），
  移除无关的 cgroupfs 分支。
- **P0 重跑分支**：修正 `kubeadm init phase upload-certs` 的职责误解——它只生成 certificate-key，
  不生成 CP join 命令；正确的链为 upload-certs → 提取 key → `kubeadm token create
  --print-join-command --certificate-key <KEY>`（已按官方 kubeadm-token 文档核实）。
- **P0 cert-key 提取**：必须绑定 `--certificate-key` 参数（裸 `[a-f0-9]{64}` 可能命中 CA hash），
  并提供独立 64-hex 行回退。
- **P0 join 命令生成**：改为 `kubeadm token create --ttl <TTL> --print-join-command`
  （单行输出），不再解析 `kubeadm init` 的人类可读多行输出（含 `\` 续行，格式不稳）。
- **P1 `join_token_ttl` 真正传入 `--ttl`**，不依赖 kubeadm 默认值；`certificate_key_ttl`
  明确为文档性说明（kubeadm 固定 2h，无控制参数）。
- **P1 扫描器覆盖 `.j2` 模板**：`scan_sensitive.py` 增加 `.j2` 后缀 + 回归测试
  （真实 token 写入 .j2 必须被扫到）。
- **P1 kubectl 版本断言**：`kubectl version --client -o jsonpath` + assert 与锚点一致
  （与 kubeadm 断言对称）。
- **P1 reset 收窄**：iptables 仅清理 filter/nat 表（去掉 mangle），并注明仅适用专用实验节点。
- **P1 Calico CRD**：改用 `kubectl apply --server-side`（避免大 CRD 清单 request 超限）。
- **P1 verify-cluster.sh**：DNS 测试固定 `busybox:1.36` tag、`--restart=Never`、执行前后清理
  dns-test Pod。
- **P1 python3-debian**：加入 preflight apt 依赖（`deb822_repository` 目标端依赖）。
- **P1 fact caching**：`ansible.cfg` 明确 `fact_caching = memory`，join 凭据不落磁盘缓存。

## 剩余限制与 B1 声明边界

- **不是真实验收**：所有 tasks 仅通过语法校验；未在任何真实 Ubuntu 24.04 + K8s 1.36.2
  集群上执行。真实多节点部署、幂等复跑、reset 可重复属 B2。
- **join 凭据在 play 内可见**：`no_log` 防泄露到日志，但 hostvars 作用域内（`control_plane[0]`）
  可见，短时 token 到期自动失效。
- **Calico 安装依赖公网拉取 manifest 与镜像**：国内网络需按 `docs/lab-environment.md` 的镜像
  策略处理，B1 未做镜像缓存。
- **`/etc/hosts` 仅 localhost + 本机名**：节点间解析依赖 CoreDNS 与 `control_plane_endpoint`
  （B1 单 CP 下由 node_ip 承担）；多网卡/多节点的 BGP IP 选择依赖 Calico `IP_AUTODETECTION`,B2 验收。

## B2 准入条件

1. 真实单控制平面 + Worker 安装验收（Node Ready、CoreDNS、Calico、Service/DNS、Pod 调度）；
2. 第二次执行幂等、`kubeadm reset` 可重复；
3. cgroup v2 / systemd 实际生效（reboot 后仍成立）；kubelet 稳定。
