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
  新增「历史版本清单」表（CentOS 7、Docker 18.x、K8s 1.16/1.18、阿里云源、Flannel 等标记为
  历史参考），修复章节编号、行尾空白与格式问题；教程不再作为当前执行手册。
- **README**：`当前状态` 更新为 B0 完成；`文档入口` 增加三份 B0 文档并明确教程为历史；
  B0 路线标记为已完成；`完成标准` 保持“未满足”语义（多节点验收仍属 B1+）。
- **CI**：在原有 Markdown 链接检查基础上增加 Markdown 格式检查与敏感字段扫描。

### Security

- 明确 join 凭据（Token / certificate-key / CA 哈希）现场生成、短时有效、安全通道传输；
  仓库内不存在可复用凭据与真实节点地址。
- 明确软件仓库与容器镜像的签名/校验要求，禁止关闭软件仓库签名验证与未固定版本的外部脚本。

## [旧版本]

- 2026-04-20 起的历史提交（教程文档、README、LICENSE、链接检查 CI）未按本文件归档；
  相关内容已由 `docs/compatibility.md` 与 change record 承接描述。
