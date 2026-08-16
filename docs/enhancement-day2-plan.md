# Enhancement Plan: Day 2 可运维套件补齐（bootstrap）

- 状态：**方案评审中（未开工，等待中枢确认）**
- 目标：把「集群交付」延伸为「交付 + Day2 可运维」，为 K8s/云原生运维岗求职竞争力叙事服务
- 交付链延伸：预检 → 部署 → CNI →（HA）→ **Ingress / Storage / 监控**
- 仓库 HEAD：`cd05d8b`（本方案尚未产生任何 commit，未 push）

## 1. 方案摘要

### 套件选型（均为交付内容扩展，不新增平台功能；版本固定、真实验收）

| 套件 | 选型 | Day2 价值叙事 |
| --- | --- | --- |
| Ingress | `ingress-nginx`（ingress-nginx-controller + echo 测试应用） | HTTP 流量入口，运维岗事实标准 |
| Storage | `local-path-provisioner`（Rancher 官方） | StorageClass 动态供给 + PVC 持久化验证，适配本地盘环境 |
| 监控 | `metrics-server`（Metrics API，HPA 前置）+ `kube-prometheus-stack` 轻量子集（prometheus + grafana + alertmanager + node-exporter + kube-state-metrics） | 集群可观测性核心叙事；若资源不足则如实降级为 metrics-server + Prometheus + node-exporter 并标注 |

### 验收方式（每条「已验证」都真实执行）

- **Ingress**：部署 controller → 部署 echo 应用 → 创建 Ingress → 经 NodePort 访问，验证 HTTP 200 + 响应体来自后端 → 记录路由证据。
- **Storage**：部署 provisioner → `kubectl get sc` StorageClass ready → 创建 PVC + Pod 写入文件 → 删除 Pod 重建 → 验证数据仍在（动态供给 + 持久化闭环）。
- **监控**：`kubectl top node/pod` 有真实指标 → Prometheus targets UP → Grafana 登录页可达 → 查询 node 指标 → 记录版本与探活证据。

### 实验环境（需要新建 VM，不动其他项目 VM）

- Bootstrap 原 VM（cp-x86/worker-x86、cp-01/worker-01）已清理；当前宿主仅存其他项目的 `e5-deploy-1/2`（x86_64 QEMU），按约束不可动。
- 推荐：**新建 1 台 Lima `arm64 vz` 单节点 `bootstrap-day2`**（独立网段、移除 control-plane taint 承载工作负载）。
  - 理由：vz 原生虚拟化，kube-prometheus-stack 收敛可行（x86_64 QEMU 已被 e5 占用 2 进程 + TCG 慢）；Day2 套件与架构无关，验收架构如实记录（arm64 单节点），x86_64 已在 B2 交付基线（`f8342b6`/`d1a0cac`）验证。
- 兜底备选：kind v0.32.0 + Docker 29.5.2（本机 arm64 已就绪）——非 kubeadm 交付链，验收叙事弱，仅作降级兜底。

### Commit 划分（noreply 身份，每套件一个 commit）

1. `feat(day2): ingress-nginx deployment + acceptance` — `manifests/day2/ingress-nginx/` + 验收记录
2. `feat(day2): local-path-provisioner storage + acceptance` — `manifests/day2/local-path/` + PVC 持久化证据
3. `feat(day2): monitoring stack (metrics-server + kube-prometheus-stack) + acceptance`
4. `docs(day2): README Day2 套件一节 + CHANGELOG + Obsidian 同步`（交付链延伸说明）

## 2. 当前进度

- [x] 环境核实：kind v0.32.0 + Docker 29.5.2 可用；bootstrap 原 VM 已清理；e5-deploy-1/2 不可动
- [x] 方案成型（选型、验收方式、VM 方案、commit 划分）
- [x] 方案回报（已通过对话回报 3 次，含本落盘文件）
- [ ] 3 个确认点得到中枢批复
- [ ] 新建 `bootstrap-day2` VM + `site.yml` 部署
- [ ] ingress-nginx 部署 + 验收（commit 1）
- [ ] local-path-provisioner 部署 + PVC 验收（commit 2）
- [ ] 监控栈部署 + 指标验收（commit 3）
- [ ] README/CHANGELOG/Obsidian 同步 + 推送（commit 4）
- [ ] 回报 commit SHAs + 验收证据

**已确认事项**：方案摘要与验收方式（本文件第 1 节）已含在历次对话回报中，中枢可据此核验。

## 3. 需要中枢的下一步指示

开工需中枢批复以下 3 点（任一回复即视为按推荐执行）：

1. **实验 VM**：确认新建 `bootstrap-day2`（Lima arm64 vz 单节点，独立网段、不碰其他项目 VM）；或改选 kind 兜底。
2. **落盘结构**：确认 `manifests/day2/`（ingress-nginx / local-path / monitoring 三个子目录）方案。
3. **监控降级许可**：确认资源不足时允许降级为 metrics-server + Prometheus + node-exporter 轻量方案并如实标注。

收到批复后预计 **~1-1.5 小时**交付：4 个 noreply commit + 验收证据（HTTP 200、PVC 数据留存、指标真实可查）+ README/CHANGELOG/Obsidian 同步 + 回报 commit SHAs。
