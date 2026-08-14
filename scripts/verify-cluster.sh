#!/usr/bin/env bash
# verify-cluster.sh — B1 集群验收辅助脚本（B2 会扩展为幂等/全量验收）
# 用法：在控制节点上，以 kubeadm-admin 身份、KUBECONFIG 指向 admin.conf 运行。
# 语义：任何关键检查失败 → exit 1；全部通过 → exit 0。本脚本只做验证，不做任何改动。

set -euo pipefail

: "${KUBECONFIG:?需要设置 KUBECONFIG（通常 /etc/kubernetes/admin.conf）}"
if ! command -v kubectl >/dev/null 2>&1; then
  echo "缺少 kubectl"; exit 1
fi

fail=0
note(){ printf '== %s\n' "$*"; }
check(){ if "$@"; then note "OK: $*"; else echo "FAIL: $*"; fail=1; fi; }

note "1. 节点状态（全部 Ready）"
nodes=$(kubectl get nodes --no-headers)
echo "$nodes"
ready=$(echo "$nodes" | grep -c ' Ready ' || true)
total=$(echo "$nodes" | wc -l | tr -d ' ')
check [ "$total" -gt 0 ]
check [ "$ready" -eq "$total" ]

note "2. 系统 Pod 状态（Running 或 Completed，无 Error/CrashLoop）"
pods=$(kubectl get pods -A --no-headers)
echo "$pods" | awk '{print $1,$2,$3,$4}'
if echo "$pods" | grep -E 'Error|CrashLoop|ImagePullBackOff|Pending' ; then
  echo "存在异常 Pod"; fail=1
else
  note "系统 Pod 正常"
fi

note "3. Calico 组件就绪（Tigerastatus）"
if kubectl get tigerastatus --no-headers >/dev/null 2>&1; then
  kubectl get tigerastatus
  if ! kubectl get tigerastatus --no-headers | awk '$4=="True" && $4!=""' | grep -q .; then
    echo "Calico 组件未全部 Available"; fail=1
  fi
else
  echo "未找到 tigerastatus（CNI 可能未安装）"; fail=1
fi

note "4. 集群 Service / CoreDNS"
check kubectl get svc -n kube-system kube-dns >/dev/null
kube_dns_ip=$(kubectl get svc -n kube-system kube-dns -o jsonpath='{.spec.clusterIP}')
echo "CoreDNS clusterIP=$kube_dns_ip"

note "5. DNS 解析验证（临时 Pod，固定 busybox tag + 自动清理）"
DNS_IMG="busybox:1.36"
kubectl delete pod dns-test --ignore-not-found --wait=false >/dev/null 2>&1 || true
dns_test=$(kubectl run dns-test -n default \
  --image="$DNS_IMG" --restart=Never --rm -i --command -- nslookup kubernetes.default.svc \
  >/dev/null 2>&1 && echo OK || echo FAIL)
kubectl delete pod dns-test --ignore-not-found >/dev/null 2>&1 || true
echo "DNS test: $dns_test"
[ "$dns_test" = "OK" ] || { fail=1; }

note "验证结果汇总"
if [ "$fail" -eq 0 ]; then
  echo "集群验收：全部通过（B1 结构 + 运行态健康）。"
else
  echo "存在失败项，详见上方检查点。"
  exit 1
fi
