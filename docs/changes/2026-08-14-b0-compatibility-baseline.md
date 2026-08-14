# Change Record: B0 兼容矩阵与安全基线

- 日期：2026-08-14
- 范围：`kubernetes-cluster-bootstrap` / B0（兼容矩阵、实验环境合同、安全基线、历史教程治理、最小 CI）
- 基线 commit：`05d8569`（docs(bootstrap): clarify cluster delivery scope and legacy risks）
- 相关文档：`docs/compatibility.md`、`docs/lab-environment.md`、`docs/security-boundaries.md`、
  `CHANGELOG.md`、`.gitignore`

## 背景

仓库此前只有三篇历史教程（CentOS 7 + Docker 18.06 + Kubernetes 1.16/1.18 + Flannel + 阿里云
镜像源）、README 路线和 Markdown 链接 CI，没有可执行的 `inventory/`、`roles/`、`playbooks/`。
B0 的目标是建立可信的版本、安全与实验环境合同，并以门禁保证后续内容不回归，**不提前实现
B1 的完整 Ansible 自动化**，不宣称生产级能力。

## 第一条支持路径（用户已确认）

Ubuntu 24.04 LTS + Kubernetes 1.36.2 + kubeadm/kubelet/kubectl 1.36.2 + containerd 2.3 LTS
（systemd cgroup 驱动，cgroup v2）+ Calico v3.32.1 + Ansible Core 2.21.x，单控制平面为
B1 首个验收拓扑；Rocky Linux 9.x 与三控制平面 HA（kube-vip）列为计划验证。

官方依据（查询日 2026-08-14）：

- Kubernetes 维护窗口/EOL：https://kubernetes.io/releases/ （1.36 维护至 2027-06-28）
- 版本偏差策略：https://kubernetes.io/releases/version-skew-policy/ （kubelet ≤3 minor 旧于 apiserver、kubectl ±1）
- kubeadm 安装前提：https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
- containerd cgroup/CRI RPC：https://kubernetes.io/docs/setup/production-environment/container-runtimes/
- containerd 兼容矩阵：https://containerd.io/releases/ （K8s 1.36 → containerd 2.3.0+/2.2.0+）
- Calico：https://github.com/projectcalico/calico/releases （v3.32.1）
- Ansible Core：https://docs.ansible.com/ansible/latest/reference_appendices/release_and_maintenance.html
  （2.21：GA 2026-05 / EOL 2027-11；控制节点 Python 3.12–3.14）与 https://pypi.org/project/ansible-core/ （2.21.3）

## 文件级改动清单

| 文件 | 改动 |
|---|---|
| `docs/compatibility.md` | 新增：兼容矩阵（发行版、K8s minor、组件版本关系、containerd/cgroup、内核硬件、CNI、单控制面/HA、升级路径、四态与来源表） |
| `docs/lab-environment.md` | 新增：实验环境合同（RFC 5737 地址、两种最小拓扑、网络/DNS/NTP/端口/代理/镜像前提、销毁与凭据清理、脱敏与 Git 排除） |
| `docs/security-boundaries.md` | 新增：安全基线（绝对禁止项、join 凭据生命周期、最小端口/SSH 权限、host key 校验、校验方式、`.gitignore` 规则、扫描允许清单机制） |
| `.gitignore` | 新增：kubeconfig、证书/私钥、Token、Inventory Secret、实验日志排除规则 |
| `.github/workflows/ci.yml` | Markdown 链接检查外新增格式检查与敏感字段/危险示例扫描步骤 |
| `.github/scripts/check_markdown_style.py` | 新增：无依赖 Markdown 格式门禁 |
| `.github/scripts/scan_sensitive.py` | 新增：敏感字段与危险示例扫描器 |
| `.github/scan-allowlist.txt` | 新增：扫描允许清单（仅 3 条文件+整行级豁免，均为文档「危险示例」说明） |
| `使用kubeadm快速部署一个K8s集群.md` | 新增「历史版本清单」；清理行尾空白/空行/EOF |
| `使用kubeadm搭建高可用的K8s集群.md` | 新增「历史版本清单」；修复 `## ` 空标题与章节编号（9/10）、清理格式 |
| `Ansible自动化部署K8S集群.md` | 新增「历史版本清单」；清理行尾空白、fence 外 tab、U+200B |
| `README.md` | 当前状态更新为 B0 完成；文档入口增加三份 B0 文档；B0 路线标记完成 |
| `CHANGELOG.md` | 新增：Unreleased 区段（Added/Changed/Security） |

## 验证命令与结果

```bash
python .github/scripts/check_markdown_links.py      # 通过：All internal markdown links OK
python .github/scripts/check_markdown_style.py      # 通过：Markdown 格式检查通过
python .github/scripts/scan_sensitive.py            # 通过：allowlist 命中 3 条，无未豁免命中
git status --short                                  # 仅本任务新增/修改文件，无用户并行改动
```

详细输出见 CI 运行记录（push 后 GitHub Actions）。

## 已清理的风险与保留的历史内容

- 已清理：正式文档与 CI 中无关闭签名校验的配置（除安全文档被允许清单豁免的「禁止项说明」）、
  无明文 `ansible_password`、无字面 kubeadm Token、无私钥/kubeconfig 数据、无 RFC 1918 节点地址；
  教程章节编号与格式问题修复；空标题删除。
- 保留为「历史参考」：CentOS 7、Docker 18.06、K8s 1.16/1.18、阿里云 YUM 源、
  registry.aliyuncs.com/google_containers、coreos/flannel master URL、Keepalived+HAProxy 方案、
  lizhenliang/ansible-install-k8s——全部以「历史版本清单」表格明确标记，不构成当前推荐路径。

## 剩余限制（明确不宣称已完成）

- B0 未做真实多节点安装验收；「已确认」指官方版本组合与文档一致性验证，真实验收属 B1。
- Ubuntu 24.04 上 containerd 2.3 deb 包 + K8s 1.36.2 的具体行为、Calico 在中国网络环境的镜像
  拉取策略均待 B1 实验验证。
- Rocky Linux 9.x、三控制平面 HA（kube-vip）、跨 minor 升级演练未纳入 B0 承诺。
- markdown 风格门禁为「基础格式」级（行尾空白/空行/标题/fence/EOF），未做全文句法级 lint。

## 风险与回滚

- 版本窗口随时间滚动：`docs/compatibility.md` 的来源表已标注查询日，任何安装/升级前必须复核。
- 允许清单目前只有 3 条、全部带原因注释；后续新增豁免必须保持「文件+整行+原因」格式，
  禁止目录级排除——该约束由 `scan_sensitive.py` 的 allowlist 校验强制执行。
- 回滚：`git revert` 本提交；`docs/`、`.gitignore`、CI 脚本相互独立，可单独撤除。

## B1 前置条件

1. 按 `docs/compatibility.md` 的第一条支持路径搭建实验环境（见 `docs/lab-environment.md`）；
2. 实现 `inventory/`、`group_vars/`、`roles/`、`playbooks/` 的最小交付结构；
3. 单控制平面 + Worker 完成真实安装验收（Node Ready、CoreDNS、Calico、Service/DNS、Pod 调度）；
4. 第二次执行幂等、reset 可重复；
5. 验收证据脱敏归档，凭据不落入 Git（由 `.gitignore` 与 CI 扫描守护）；
6. 验证「命令成功」之外的运行时真实状态：cgroup v2 / systemd 驱动实际生效（reboot 后仍成立）、
   kubelet 稳定、containerd CRI 正常、Pod sandbox 创建/删除正常；
7. join 凭据生命周期、最小 SSH 权限与 become 边界落实为自动化控制措施，不因「一次跑通」回退。

## 审查修正（2026-08-14，ChatGPT 交叉审查）

实施初版经 ChatGPT 审查（结论：PASS WITH REQUIRED FIXES），已按 4 项必改与高价值 P1 项修正：

- **状态语义**：「已确认」→「已确认（官方兼容，未实机验证）」，新增「官方兼容 → 项目选定 →
  实机验证」三层模型；1.36.2 / 2.21.3 明确为「B1 首次验收锚点」，锚点 ≠ 当前最新 patch。
- **完整性**：补 kube-proxy 版本偏差；升级顺序修正为 apiserver → controller-manager/scheduler
  （彼此无强制先后）→ kubelet（逐节点 drain）；Swap 增加 `swapon --show` 验证标准；
  containerd 2.4 明确为「计划验证（未发布）」；Alpine 表述改为 glibc 或兼容层要求。
- **安全性**：端口表升为「端口 + 方向 + 作用域」；禁止项措辞改为「禁止作为安装前置条件」；
  `.gitignore` 声明为误提交缓解措施而非 secret 隔离。
- **扫描器**：占位符感知（忽略 `<...>`/`${VAR}`/`{{...}}`/`!vault`/`lookup()`/布尔值）；
  增加 kubeconfig `token:` 检测；移除 `ansible_host` RFC1918 误报模式；允许清单自保护
  （拒绝 `.*` 宽泛正则、校验路径存在）；新增 `test_scan_sensitive.py` 正例/反例回归测试，
  CI 增加 unittest 步骤。
- **历史治理**：三篇教程增加英文 `DO NOT USE FOR CURRENT DEPLOYMENT` 横幅并链接
  `docs/compatibility.md`，降低搜索引擎/全文搜索误用风险。

审查修正后验证命令（本地全部通过）：`check_markdown_links.py`、`check_markdown_style.py`、
`scan_sensitive.py`、`python -m unittest discover -s .github/scripts -p "test_*.py"`。
