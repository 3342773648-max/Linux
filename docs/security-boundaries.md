# 安全基线（B0）

> 本文档定义仓库内集群交付相关的**安全边界与禁止项**，是 README「安全与兼容性警示」与
> [lab-environment.md](./lab-environment.md) 的正式展开。所有示例命令中的占位符
> （`<BOOTSTRAP_TOKEN>`、`sha256:<CA_CERT_HASH>` 等）一律不得替换为真实值提交到仓库。
> 扫描器规则见 `.github/scripts/scan_sensitive.py`，允许清单机制见文末。

## 1. 绝对禁止项

以下行为在任何阶段都不允许作为推荐路径出现，也不得写入当前执行手册：

| 禁止项 | 说明 |
| --- | --- |
| 无条件关闭防火墙 | `systemctl stop firewalld` / `ufw disable` + 不做端口收敛。只允许按官方文档**放行最小端口** |
| 无条件关闭 SELinux / AppArmor | `setenforce 0` 且不保留策略。应配置为 enforcing + 放行必要策略 |
| 关闭软件仓库签名验证 | `gpgcheck=0`、`repo_gpgcheck=0` 或删除 gpgkey 校验（此为**危险示例**，仅用于说明，见允许清单） |
| 固定 kubeadm Token / 证书哈希 | 示例中 `--token <BOOTSTRAP_TOKEN>` 与 `--discovery-token-ca-cert-hash sha256:<CA_CERT_HASH>` 均为占位符，真实值必须由当前集群现场生成 |
| 固定 Keepalived / HAProxy 口令 | `auth_pass <KEEPALIVED_AUTH_PASS>`、`stats auth admin:<HAPROXY_STATS_PASSWORD>` 必须占位；B1 起 HA 不在配置文件中写口令 |
| 固定 SSH 密码并写入 Inventory | `ansible_password` 明文写在 `inventory/`、`group_vars/`、`host_vars/` 或 Playbook `vars` 中 |
| 提交私钥 / 证书 / kubeconfig | `.key`、`.crt`、`.pem`、`admin.conf`、`*.kubeconfig` 全部排除在 Git 之外 |
| 直接执行未经验证的远程脚本 | `curl <url> | sh`、未固定版本与校验和的第三方脚本 |

> 本节「危险示例」仅用于说明禁止项，由扫描器允许清单按文件+行精确豁免（见第 7 节）；
> 不允许通过新增其他危险示例来反复触发豁免。

## 2. join 凭据生命周期

- bootstrap Token、certificate-key、discovery-token-ca-cert-hash 全部**现场生成、短时有效**：
  - Token 默认 TTL 24h，演练结束后 `kubeadm token delete`；
  - certificate-key 用后即删，不落盘；
  - join 命令通过安全通道（SSH 会话、二次加密传输）送达目标节点，不通过明文聊天/邮件。
- ImagePullSecret、registry 凭据同样使用 Secret 注入，不写入 Inventory 或文档。

## 3. 端口与 SSH 最小权限

| 范围 | 要求 |
| --- | --- |
| 防火墙 | 只放行官方端口：6443（apiserver）、2379-2380（etcd，仅控制平面间）、10250（kubelet）、10257/10259（controller-manager/scheduler）、30000-32767（NodePort）；SSH 22 仅对管理来源放行 |
| SSH 认证 | 优先密钥认证；禁止 root 直接密码登录；SSH 端口与来源 CIDR 收敛 |
| host key 校验 | 首次连接通过 `ssh-keyscan` + 指纹比对登记，禁止 `StrictHostKeyChecking=no` 或 `AutoAddPolicy` 式的自动接受 |
| 管理账号 | 专用运维账号 + `sudo` 最小提权；root 免密 sudo 不用于常规操作 |

## 4. 镜像、软件包与外部脚本校验

- **软件包仓库**：apt / pkgs.k8s.io 官方源，签名验证保持开启（Ubuntu 使用 releases 校验 +
  signed-by keyring；RHEL 系 `gpgcheck=1`）。
- **容器镜像**：按 tag 固定 + 记录 digest（`ctr images pull` 后以 digest 导出/导入）；
  首选 `registry.k8s.io` 官方镜像，镜像加速器与离线导入方案见 lab-environment.md。
- **外部脚本 / 模板**：只采用固定版本与可核验来源（官方仓库 tag 而非 `master`/`latest`），
  下载后先校验 checksum / 签名再执行；禁止 `curl | sh` 一键执行。
- **Calico / CNI 清单**：从官方 `v3.32.x` release 获取并用固定版本，不用 `master` 分支 URL。

## 5. 日志与证据脱敏

- 执行日志入 Git 前必须脱敏：Token、certificate-key、证书、`client-key-data`、明文密码、
  真实节点地址一律替换占位符或删除。
- 验收证据（`kubectl get nodes -o wide` 等）如需归档，IP 列使用文档地址或打码。
- `artifacts/` 目录默认 `gitignore`；只有经过脱敏的摘要允许入仓库。

## 6. `.gitignore` 规则（仓库根目录，随本基线维护）

```text
# Kubernetes / kubeadm 敏感产物
*.kubeconfig
kubeconfig
.kube/
**/admin.conf
**/super-admin.conf
**/pki/
*.crt
*.key
*.csr
*.pem
*.token
join-command.txt
certificate-key.txt

# Ansible 凭据与 Inventory Secret
inventory/**/secrets.yml
inventory/**/vault.yml
vault_pass*
*.vault
.ansible-vault

# 实验产物与日志
artifacts/
logs/
*.log

# 开发与 IDE
__pycache__/
.venv/
venv/
node_modules/
.DS_Store
*.swp
```

规则由 B0 落地为根目录 `.gitignore`，后续新增敏感文件类型时同步更新本文档与 `.gitignore`。

## 7. 扫描与允许清单机制

- 仓库 CI 执行 `.github/scripts/scan_sensitive.py`，扫描范围：全部被 Git 跟踪的 `.md` /
  `.yml` / `.yaml` / `.ini` / `.cfg` / `.txt` / `.env*`（`.github/scripts/` 与允许清单自身除外，
  它们属于 PR 审查对象）。
- 扫描项：kubeadm Token 形状、`gpgcheck=0`/`repo_gpgcheck=0` 变体、明文 `ansible_password` /
  `ansible_ssh_pass`、私钥块（RSA/EC/DSA/OpenSSH/加密私钥）、kubeconfig 证书数据
  （`certificate-authority-data` / `client-certificate-data` / `client-key-data` + 长 base64）、
  haproxy `stats auth` 明文口令、SSH/scp 到 RFC 1918 私有地址、cloud-init 明文密码。
- **允许清单** `.github/scan-allowlist.txt`：每条 `文件路径::精确匹配整行内容的正则::原因`，
  只允许精确命中（锚定整行），禁止按目录宽泛排除。允许清单的变更在 PR 中可见并可审查；
  安全文档讨论禁止项时优先用占位符，仅在确需展示字面危险示例时使用允许清单。
- 本文件第 1 节「关闭仓库签名校验」的字面示例即通过该机制豁免（带明确原因）。

## 8. 边界声明

- 本基线约束仓库内交付流程与文档，不替代组织级安全策略；生产环境还需考虑等保、密钥管理
  服务（KMS）、审计与合规要求。
- B0 阶段不涉及真实凭据；若 B1 起使用真实实验环境，凭据存储与轮换策略另行纳入 change record。
