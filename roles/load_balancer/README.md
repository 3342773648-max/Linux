# load_balancer role（B1 占位）

B1 阶段为单控制平面，不使用任何负载均衡器。本目录是 HA Load Balancer（B3 范围）的占位位置。

B3 扩展方向（基于 B0 兼容矩阵）：
* kube-vip 作为控制平面 VIP（推荐，满足 etcd quorum）。
* 若手写 Keepalived + HAProxy：口令必须用变量注入/Secret，禁止明文写入 Git（B0 安全基线）。

当前状态：占位，无可执行步骤。
