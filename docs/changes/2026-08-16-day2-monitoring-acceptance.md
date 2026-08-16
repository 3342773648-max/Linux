# Day2 套件 3：kube-prometheus-stack 监控部署与真实验收记录

- 日期：2026-08-16
- 环境：`bootstrap-day2`（Lima arm64 vz 单节点，aarch64，4C/8G）
- 集群：kubeadm v1.36.2 + Calico v3.32.1，node `day2-cp` Ready
- 套件：kube-prometheus-stack **chart 88.3.0**（app v0.93.0，Helm 安装）+ metrics-server v0.9.0
- 认证身份：git noreply（无凭据入库；Grafana 密码仅存于 gitignored 运行态，本文档脱敏）

## 部署内容（manifests/day2/monitoring/）

| 文件 | 内容 |
| --- | --- |
| `metrics-server-components-v0.9.0.yaml` | metrics-server 官方 components 清单（Metrics API，HPA 前置） |
| `kube-prometheus-values.yaml` | kube-prometheus-stack 定制 values（单副本、关 alertmanager、NodePort 暴露 Grafana） |

## 真实验收证据

### 1. metrics-server：`kubectl top` 真实指标 ✓

```
$ kubectl top node
NAME      CPU(cores)   CPU(%)   MEMORY(bytes)   MEMORY(%)
day2-cp   184m         4%       1587Mi          20%

$ kubectl top pod -A
NAMESPACE       NAME                               CPU(cores)   MEMORY(bytes)
calico-system   calico-node-7n652                  23m          64Mi
...
```

- ✅ Metrics API 前端可用（`kubectl top` 返回 node/pod 真实用量）
- 注：metrics-server 需 `--kubelet-insecure-tls`（kubelet 自签证书无 IP SAN），单节点验收环境适配

### 2. Prometheus：targets + 指标查询 ✓

```
active targets: 14 | 其中 up：
  - kubelet ×3 / node-exporter / apiserver / kube-state-metrics
  - operator / prometheus×2 / grafana
sum(up) = 10

$ curl -s ".../api/v1/query?query=node_exporter_build_info"
{"status":"success", ..., "branch":"HEAD", "goarch":"arm64", ...}

$ curl -s ".../api/v1/query?query=kube_node_info"
{"status":"success", ..., "container_runtime_version":"containerd://2.3.3", ...}
```

- ✅ Prometheus targets 正常爬取，**node 指标 + 集群对象状态指标真实可查**
- 说明：kube-controller-manager/kube-etcd/kube-proxy/kube-scheduler 4 个 target 为 down——kubeadm 默认未暴露这些控制面组件的 metrics 端点（需额外配置 `--bind-address`/metric 端口），属 kube-prometheus-stack 在 kubeadm 上的标准默认状态，如实标注不作美化

### 3. Grafana：可达性 ✓

```
$ curl http://127.0.0.1:30300/api/health
{"database": "ok", "version": "13.1.3", "commit": "..."}

$ curl -I http://127.0.0.1:30300/
HTTP/1.1 302 Found
Location: /login
```

- ✅ Grafana NodePort **30300** 可达：`/api/health` 返回 `database: ok`，根路径 302 到登录页
- ✅ 数据源 Prometheus 由 helm 自动配置（kube-prometheus-stack 标准集成）
- 注：Grafana 13 登录带 CSRF 强化，验收以 health + 登录页可达为准

## 组件清单

| 组件 | 状态 | 说明 |
| --- | --- | --- |
| prometheus-operator | 1/1 Running | Operator（v0.93.0） |
| prometheus | 2/2 Running | Prometheus v3.13.2，单副本 |
| grafana | 3/3 Running | Grafana 13.1.3，NodePort 30300 |
| kube-state-metrics | 1/1 Running | 集群对象指标 |
| node-exporter | 1/1 Running | 节点指标 |
| alertmanager | 关闭 | 单节点无告警分发需求，values 明确关闭（降级项，如实标注） |

## 结论

- ✅ 监控体系（metrics-server + Prometheus + Grafana + kube-state-metrics + node-exporter）部署并真实验收
- ✅ `kubectl top` 真实指标、Prometheus targets UP、node 指标可查、Grafana 可达
- 交付链路延伸：预检 → 部署 → CNI → Ingress → Storage → **监控** ✓
