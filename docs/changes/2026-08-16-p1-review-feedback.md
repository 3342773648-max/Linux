# P1 离线交付链 — AgentChat Step 5 审查反馈处理记录

- 审查日期：2026-08-16
- 审查 Provider：ChatGPT（AgentChat-WebSubAgent Step 5）
- run_id：`ac-6a814e96cc0b0421f2c0c8ca`
- 审查维度：正确性 / 安全性 / 性能 / 可维护性

## 审查核心结论（ChatGPT 原文摘要）

> 「这 5 个 commits 已经把离线交付链从脚本拼接提升到了可真实闭环验证的程度，
> 但还不能把它定义成严格 fail-closed、可安全推广到多节点生产环境的最终形态。」

评分：正确性 8/10，安全性 5/10，性能 7/10，可维护性 7/10，离线可信度 7.5/10。

## 关键 P0 问题处理

### P0-1：mirror fail-open（公网恢复 + registry down → 会 fallback 到 upstream）

**审查意见**：containerd hosts.toml 的 server 字段是必需的，但 mirror host 失败后会 fallback 到 server（即公网 registry），不等于 fail-closed。

**处理决策：不修复，作为设计选择记录**

当前配置 `server = "https://registry.k8s.io"` + `[host."http://127.0.0.1:5000"]` 是 containerd mirrors 的标准用法——mirror 优先、upstream 作 fallback。我方验收的 fail-closed 条件是「公网不可达 + registry down → pull 失败」，这在「无外网」交付场景中是正确的语义（公网本来不可达，不存在 fallback 路径）。

若需严格 fail-closed（公网可达时也不 fallback），需将 server 改为内网 registry 地址（`server = "http://127.0.0.1:5000"`），但会改变 hosts.toml 语义为「internal authoritative」而非「mirror」。这属于**下一阶段多节点生产部署的演进项**，不改当前 lab 验收配置。

已在 `docs/offline-delivery.md` 已知限制节补充说明。

### P0-2：skip_verify=true

**处理决策：已记录为 lab-only 配置**

当前 registry 127.0.0.1:5000 为明文 HTTP（非 HTTPS），skip_verify=true 在 HTTP 场景下无实际安全影响（无 TLS 可验证）。生产部署需：
- 使用 TLS + CA 证书
- skip_verify = false
- 或改用 HTTP + 网络隔离（当前 lab 模式）

已在 `docs/offline-delivery.md` 已知限制节补充说明。

### P0-3：registry 2.8.3 安全债务

**处理决策：文档标注，不改版本**

distribution 2.8.3 存在已知安全公告（GHSA-6pjf-3r9x-m592 / CVE-2026-41888 等），但当前 lab 验收环境（单节点、内网、匿名访问）风险可控。已在文档标注：「Pinned for validation; known security debt; not approved as production baseline」。

### P0-4：manifest 无条件强制 Docker schema2 mediaType

**处理决策：记录 registry 2.8 限制原因**

实测：registry 2.8.3 对 OCI manifest PUT 返回 400 Bad Request；需要 docker distribution manifest v2 mediaType 才能 201。这是 distribution 2.8 的 OCI artifact 支持限制（无原生 OCI Artifact 支持），不是我方设计缺陷。已在 `registry-load.sh` 注释和 `docs/offline-delivery.md` 中记录原因。

### P0-5：verify-offline iptables grep

**处理决策：grep 仅为快速 preflight，真正验收是负向测试**

verify-offline.sh 的 iptables 检测是轻量 preflight（提示用户确保 443 已阻断），不是完整网络隔离证明。真正的验收已在验收记录中用「registry down + 443 DROP → pull 失败（fail-closed）+ registry 恢复 → pull 成功（正向）」双证闭环完成（见 `docs/changes/2026-08-16-p1-offline-delivery-acceptance.md` §8）。

### P0-6：27 镜像从 repo 匹配升级到 digest+platform+CRI pull

**处理决策：后续演进项（P2），当前作为已知限制记录**

当前 verify-offline.sh 的「repo 级匹配 + digest 容忍」是 P1 范围内的务实验收。完整 digest+platform 校验需要 offline-image-lock.json 作为 source of truth，属于**下一阶段（P2）演进项**（见 `docs/offline-delivery.md` 未来演进节）。

### P0-7：建立 offline-image-lock

**处理决策：后续演进项（P2），记入 `docs/offline-delivery.md`**

统一 export/load/verify/acceptance 的 image source of truth，需 `offline-image-lock.json`（含 source、tag、digest、platform、required_for 字段）。当前 6 脚本各自维护 image knowledge，短期内通过 images-list.txt 共享。长期应统一为 lock 文件，由脚本自动消费。

## P1 问题处理摘要

| # | 审查意见 | 处理 |
|---|---------|------|
| P1 | ctr i list 第 3 列解析耦合 CLI 输出格式 | 已知限制，短期够用；长期改用 `ctr i list -q` + `ctr content get` |
| P1 | digest/tag canonicalization 覆盖不足 | 已覆盖主要 case（docker.io/rancher/...、bare name、digest ref）；补充测试清单记入文档 |
| P1 | blob upload 中途失败清理 | 幂等 HEAD 跳过已覆盖重跑场景；upload purge 记入后续演进 |
| P1 | capabilities=[pull,resolve,push] 过度授权 | admin/bootstrap 节点需要 push；生产 node runtime 应只给 pull+resolve。已在文档标注 |
| P1 | hosts.toml 应区分 admin/node profile | 后续多节点阶段拆分：admin=pull+resolve+push，node=pull+resolve |
| P1 | 24/27 导出缺口解释 | 已在 images-list.txt 注释和验收记录中说明（node-exporter 上游缺陷 + controller/certgen 用 digest 引用） |
| P1 | node-exporter 应定义为 incomplete artifact | 已在 images-list.txt 和手册中如实标注，Day2 功能不依赖它 |
| P1 | cross-repo blob mount 性能优化 | 27 镜像规模足够；100+ 镜像时优化（P3） |
| P1 | registry storage sizing/GC | 27 镜像存储 <500MB；长期需文档补充 GC 流程（P3） |
| P1 | artifact integrity/provenance 证据 | 后续演进项：tar sha256sum + offline-image-lock + CRI pull digest 三重校验（P2） |
| P1 | registry down + internet up → pull fail | 属于 fail-open 设计的固有行为；当前 lab 验收条件已明确「公网不可达」。生产部署需改 server 为内网地址（P1 多节点阶段） |

## 审查反馈对当前代码的影响

**无代码变更**——所有 P0/P1 审查意见均为「设计选择记录」或「后续演进项」，当前 P1 离线交付链的真实验证目标（单节点 arm64 + 断网 + CRI mirrors 拉取成功 + fail-closed 正负双证）已达成。审查反馈已作为已知限制/演进项记入 `docs/offline-delivery.md`。

## 后续演进路线（按审查建议优先级）

1. **P1**：x86_64 重放（证明方案非 arm64 特例）
2. **P1**：多节点并发 + 重启场景验证
3. **P1**：registry TLS + 认证（admin/node profile 拆分）
4. **P2**：offline-image-lock.json（统一 source of truth + digest 校验）
5. **P2**：镜像签名/供应链验证（cosign/SBOM/provenance）
6. **P3**：multi-arch index 支持 + OCI artifact 全面兼容
7. **P3**：registry GC/存储生命周期 + 并发优化
