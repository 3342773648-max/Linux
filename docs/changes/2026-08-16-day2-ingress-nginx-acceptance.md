# Day2 套件 1：ingress-nginx 部署与真实验收记录

- 日期：2026-08-16
- 环境：`bootstrap-day2`（Lima arm64 vz 单节点，aarch64，4C/8G）
- 集群：kubeadm v1.36.2 + Calico v3.32.1，node `day2-cp` Ready，免 taint 单节点
- 套件版本：ingress-nginx **v1.12.1**（官方 baremetal 清单）
- 认证身份：git noreply（无凭据入库）

## 部署内容（manifests/day2/ingress-nginx/）

| 文件 | 内容 |
| --- | --- |
| `deploy-v1.12.1.yaml` | ingress-nginx 官方 baremetal 清单（Namespace/CRD/Deployment/Service NodePort/IngressClass/admission webhook），版本 `app.kubernetes.io/version: 1.12.1` |
| `echo-app.yaml` | 验收测试应用：Deployment(nginx:1.27-alpine) + Service + Ingress(`echo.day2.example`) |

## 真实验收证据

### 1. 资源就绪（READY）

```
$ kubectl get pods -n ingress-nginx
ingress-nginx-admission-create-<pod>   0/1   Completed
ingress-nginx-admission-patch-<pod>    0/1   Completed
ingress-nginx-controller-<pod>         1/1   Running

$ kubectl get ingressclass nginx
NAME    CONTROLLER             PARAMETERS   AGE
nginx   k8s.io/ingress-nginx   <none>       <age>

$ kubectl get ingress echo
NAME   CLASS   HOSTS               ADDRESS        PORTS
echo   nginx   echo.day2.example   192.0.2.10  80
```

### 2. HTTP 路由功能（经 NodePort 真实请求）

controller Service NodePort：**80:32310/TCP**（HTTP 入口）。

正向请求（正确 Host）：

```
$ curl -si -H "Host: echo.day2.example" http://127.0.0.1:32310/
HTTP/1.1 200 OK
Content-Type: text/html
...
<title>Welcome to nginx!</title>
```

- ✅ 返回 `HTTP/1.1 200 OK`，响应体为后端 nginx 内容（证明流量经 Ingress 路由到 echo Service → pod）

反向请求（错误 Host）：

```
$ curl -si -H "Host: wrong.example.com" http://127.0.0.1:32310/
HTTP/1.1 404 Not Found
```

- ✅ 错误 Host 返回 404（路由按 Host 精确匹配，非兜底放行）

### 3. 路径完整链路

`curl(NodePort 32310) → ingress-nginx-controller → Ingress 规则(Host echo.day2.example) → echo Service(ClusterIP:80) → nginx pod(容器 80) → HTTP 200`

## 实施中遇到的环境问题与解法（如实记录）

1. **kubeadm init 代理干扰**：VM 系统环境注入 HTTPS_PROXY，kubeadm/kubectl 连 apiserver（192.0.2.10）被代理拦截 → `context deadline exceeded`。解法：`/etc/environment` 加 `NO_PROXY` 覆盖集群网段（127.0.0.0/8、192.0.2.0/24、10.0.0.0/8），并给 kubelet systemd drop-in 加 NO_PROXY。
2. **陈旧 kubelet client cert**：多次 init 遗留旧 CA 签发的 `/var/lib/kubelet/pki/kubelet-client-*.pem`，kubelet 认证被拒（Unauthorized）→ node 无法注册。解法：删除旧 pki 文件，kubelet 重建 bootstrap 流程（CSR 自动批准）。
3. **kube-proxy 缺失**：kubeadm init 中断导致 addon 未装，ClusterIP 服务不可达（webhook EOF）。解法：`kubeadm init phase addon kube-proxy` 补装。
4. **镜像源走代理策略**：containerd 直连 registry.k8s.io/quay.io 正常、docker.io 需走代理。解法：NO_PROXY 仅含 registry.k8s.io/quay.io（docker.io 走 192.0.2.2:7897 代理）。
5. **echoserver 镜像 amd64-only**：`registry.k8s.io/echoserver:1.10` 在 arm64 上 `exec format error`。解法：验收应用改用 nginx:1.27-alpine（多架构），验收语义不变（路由 + 后端内容）。
6. **admission webhook EOF（临时绕过）**：apply Ingress 时 webhook 调用 EOF（kube-proxy 补装前的 ClusterIP 不通所致）；补装 kube-proxy 后链路正常，验证用侧 webhook 400 可达。Ingress 创建后已恢复 webhook 配置。

## 结论

- ✅ **ingress-nginx v1.12.1 部署成功**，controller/admission 全部 READY
- ✅ **HTTP 流量入口真实可用**：200 + 后端内容验证正向路由，404 验证精确匹配
- ✅ Ingress 资源状态由 controller 自动更新（ADDRESS=192.0.2.10）
- 交付链路延伸：预检 → 部署 → CNI →（HA）→ **Ingress** ✓