# Day2 套件 2：local-path-provisioner 部署与真实验收记录

- 日期：2026-08-16
- 环境：`bootstrap-day2`（Lima arm64 vz 单节点，aarch64，4C/8G）
- 集群：kubeadm v1.36.2 + Calico v3.32.1，node `day2-cp` Ready，免 taint 单节点
- 套件版本：local-path-provisioner **v0.0.31**（Rancher 官方清单）
- 认证身份：git noreply（无凭据入库）

## 部署内容（manifests/day2/local-path/）

| 文件 | 内容 |
| --- | --- |
| `deploy-v0.0.31.yaml` | Rancher 官方清单（Namespace/SA/RBAC/Deployment/ConfigMap/StorageClass），镜像 `rancher/local-path-provisioner:v0.0.31` |
| `storage-writer.yaml` | 验收：PVC(1Gi, local-path) + Writer Pod（写入 `/mnt/data/persist.txt`） |
| `storage-reader.yaml` | 验收：Reader Pod（同 PVC 读回 `persist.txt`，验证持久化） |

## 真实验收证据

### 1. StorageClass 就绪 + 动态供给（Bound）

```
$ kubectl get sc
NAME         PROVISIONER          RECLAIMPOLICY   VOLUMEBINDINGMODE
local-path   rancher.io/local-path   Delete        WaitForFirstConsumer

$ kubectl get pvc day2-pvc
NAME       STATUS   CAPACITY   ACCESS MODES   STORAGECLASS
day2-pvc   Bound    1Gi        RWO            local-path

$ kubectl get pv
NAME                                       CAPACITY   RECLAIMPOLICY   STATUS
pvc-6a908887-74cb-4d86-9f8b-d5f26529dbdc   1Gi        Delete          Bound
```

- ✅ PVC 提交后由 local-path 动态创建 PV 并 **Bound**（WaitForFirstConsumer：Pod 调度后真正供给）

### 2. 写入 + Pod 删除 + 读回（持久化闭环）

Writer Pod（写入后 Completed）：

```
$ kubectl logs day2-writer
drwxrwxrwx  2 root  root  4096 .   ..
-rw-r--r--  1 root  root    23 persist.txt
```

删除 writer → 用 Reader Pod 挂载**同一 PVC** 读回：

```
$ kubectl delete pod day2-writer
$ kubectl logs day2-reader
day2-storage-persisted
READ_OK
```

- ✅ **数据在 Pod 生命周期之外持久留存**（写入 → Pod 删除 → 同 PVC 重新挂载 → 数据可读）

### 3. 回收策略（Delete）

```
$ kubectl delete pvc day2-pvc
$ kubectl get pv
No resources found
```

- ✅ PVC 删除后 PV 被 **Delete** 回收（local-path 关联数据目录清理）

## 结论

- ✅ local-path-provisioner v0.0.31 部署成功，StorageClass 就绪
- ✅ **动态供给 + 持久化 + 回收的完整存储生命周期真实验证**
- 交付链路延伸：预检 → 部署 → CNI → Ingress → **Storage** ✓
