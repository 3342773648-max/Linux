
# kubeadm 高可用集群部署（历史实践）

> **安全与兼容性警示**：本文仅用于学习和实验环境复盘，使用的是历史 CentOS 7、Docker 18.x
> 和 Kubernetes 1.16 路径，不能直接作为生产部署脚本。文档中的地址、Token、证书哈希和
> Keepalived 密钥均为占位示例；不要无条件关闭防火墙 / SELinux 或关闭仓库签名校验。

## 历史版本清单

本文所有组件与来源均属**历史参考**，当前支持路径以 [`docs/compatibility.md`](./docs/compatibility.md) 为准：

| 组件 | 本文版本 | 状态（2026-08-14） |
| --- | --- | --- |
| 操作系统 | CentOS 7.x（已 EOL） | 历史参考 |
| 容器运行时 | Docker 18.06.1（dockershim 自 1.24 移除） | 历史参考 → 当前为 containerd |
| Kubernetes | 1.16.3（EOL 2020-09-02） | 历史参考 → 当前为 1.36 |
| kubeadm 配置 API | kubeadm.k8s.io/v1beta1 | 历史参考 → 当前配置沿用官方 v1beta4 及以上 |
| HA 入口 | Keepalived＋HAProxy（PASS 口令、手工复制证书） | 历史参考 → kube-vip / 云 LB 为计划验证 |
| 控制平面 join | scp 复制 PKI + `--control-plane` 固定示例 | 历史参考 → certificate-key 现场生成、安全通道传输 |
| 软件源 | 阿里云 YUM 源 | 历史参考 → 当前为官方源 + 签名校验 |
| 镜像仓库 | registry.aliyuncs.com/google_containers | 历史参考 → 当前默认 registry.k8s.io |
| CNI | flannel（`coreos/flannel` master URL） | 历史参考 → 当前首选 Calico |

kubeadm 是官方社区推出的一个用于快速部署 Kubernetes 集群的工具。

这个工具能通过两条指令完成一个kubernetes集群的部署：

```
# 创建一个 Master 节点
$ kubeadm init

# 将一个 Node 节点加入到当前集群中
$ kubeadm join <Master节点的IP和端口 >
```

## 1. 安装要求

在开始之前，部署Kubernetes集群机器需要满足以下几个条件：

- 一台或多台机器，操作系统 CentOS7.x-86_x64
- 硬件配置：2GB或更多RAM，2个CPU或更多CPU，硬盘30GB或更多
- 可以访问外网，需要拉取镜像，如果服务器不能上网，需要提前下载镜像并导入节点
- 禁止swap分区

## 2. 准备环境

| 角色          | IP             |
| ------------- | -------------- |
| master1       | 198.51.100.11 |
| master2       | 198.51.100.12 |
| node1         | 198.51.100.13 |
| VIP（虚拟ip） | 198.51.100.14 |

```
# 先检查安全策略；根据当前 Kubernetes/CNI 文档只放行必要端口。
firewall-cmd --list-all
getenforce

# 关闭swap
swapoff -a  # 临时
sed -ri 's/.*swap.*/#&/' /etc/fstab    # 永久

# 根据规划设置主机名
hostnamectl set-hostname <hostname>

# 在master添加hosts
cat >> /etc/hosts << EOF
198.51.100.14    master.k8s.io   k8s-vip
198.51.100.11    master01.k8s.io master1
198.51.100.12    master02.k8s.io master2
198.51.100.13    node01.k8s.io   node1
EOF

# 将桥接的IPv4流量传递到iptables的链
cat > /etc/sysctl.d/k8s.conf << EOF
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system  # 生效

# 时间同步
yum install ntpdate -y
ntpdate time.windows.com
```


## 3. 所有master节点部署keepalived

### 3.1 安装相关包和keepalived

```
yum install -y conntrack-tools libseccomp libtool-ltdl

yum install -y keepalived
```

### 3.2配置master节点

master1节点配置

```
cat > /etc/keepalived/keepalived.conf <<EOF
! Configuration File for keepalived

global_defs {
   router_id k8s
}

vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 3
    weight -2
    fall 10
    rise 2
}

vrrp_instance VI_1 {
    state MASTER
    interface ens33
    virtual_router_id 51
    priority 250
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass <KEEPALIVED_AUTH_PASS>
    }
    virtual_ipaddress {
        198.51.100.14
    }
    track_script {
        check_haproxy
    }

}
EOF
```

master2节点配置

```
cat > /etc/keepalived/keepalived.conf <<EOF
! Configuration File for keepalived

global_defs {
   router_id k8s
}

vrrp_script check_haproxy {
    script "killall -0 haproxy"
    interval 3
    weight -2
    fall 10
    rise 2
}

vrrp_instance VI_1 {
    state BACKUP
    interface ens33
    virtual_router_id 51
    priority 200
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass <KEEPALIVED_AUTH_PASS>
    }
    virtual_ipaddress {
        198.51.100.14
    }
    track_script {
        check_haproxy
    }

}
EOF
```

### 3.3 启动和检查

在两台master节点都执行

```
# 启动keepalived
$ systemctl start keepalived.service
设置开机启动
$ systemctl enable keepalived.service
# 查看启动状态
$ systemctl status keepalived.service
```

启动后查看master1的网卡信息

```
ip a s ens33
```


## 4. 部署haproxy

### 4.1 安装

```
yum install -y haproxy
```

### 4.2 配置

两台master节点的配置均相同，配置中声明了后端代理的两个master节点服务器，指定了haproxy运行的端口为16443等，因此16443端口为集群的入口

```
cat > /etc/haproxy/haproxy.cfg << EOF
#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    # to have these messages end up in /var/log/haproxy.log you will
    # need to:
    # 1) configure syslog to accept network log events.  This is done
    #    by adding the '-r' option to the SYSLOGD_OPTIONS in
    #    /etc/sysconfig/syslog
    # 2) configure local2 events to go to the /var/log/haproxy.log
    #   file. A line like the following can be added to
    #   /etc/sysconfig/syslog
    #
    #    local2.*                       /var/log/haproxy.log
    #
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats
#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000
#---------------------------------------------------------------------
# kubernetes apiserver frontend which proxys to the backends
#---------------------------------------------------------------------
frontend kubernetes-apiserver
    mode                 tcp
    bind                 *:16443
    option               tcplog
    default_backend      kubernetes-apiserver
#---------------------------------------------------------------------
# round robin balancing between the various backends
#---------------------------------------------------------------------
backend kubernetes-apiserver
    mode        tcp
    balance     roundrobin
    server      master01.k8s.io   198.51.100.11:6443 check
    server      master02.k8s.io   198.51.100.12:6443 check
#---------------------------------------------------------------------
# collection haproxy statistics message
#---------------------------------------------------------------------
listen stats
    bind                 *:1080
    stats auth           admin:<HAPROXY_STATS_PASSWORD>
    stats refresh        5s
    stats realm          HAProxy\ Statistics
    stats uri            /admin?stats
EOF
```

### 4.3 启动和检查

两台master都启动

```
# 设置开机启动
$ systemctl enable haproxy
# 开启haproxy
$ systemctl start haproxy
# 查看启动状态
$ systemctl status haproxy
```

检查端口

```
netstat -lntup|grep haproxy
```


## 5. 所有节点安装Docker/kubeadm/kubelet

Kubernetes默认CRI（容器运行时）为Docker，因此先安装Docker。

### 5.1 安装Docker

```
$ wget <CONTAINER_RUNTIME_REPOSITORY_FILE> -O /etc/yum.repos.d/docker-ce.repo
$ yum -y install docker-ce-18.06.1.ce-3.el7
$ systemctl enable docker && systemctl start docker
$ docker --version
Docker version 18.06.1-ce, build e68fc7a
```

```
$ cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": ["<REGISTRY_MIRROR_URL>"]
}
EOF
```

### 5.2 添加阿里云YUM软件源

```
$ cat > /etc/yum.repos.d/kubernetes.repo << EOF
[kubernetes]
name=Kubernetes
baseurl=https://mirrors.aliyun.com/kubernetes/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://mirrors.aliyun.com/kubernetes/yum/doc/yum-key.gpg https://mirrors.aliyun.com/kubernetes/yum/doc/rpm-package-key.gpg
EOF
```

### 5.3 安装kubeadm，kubelet和kubectl

由于版本更新频繁，这里指定版本号部署：

```
$ yum install -y kubelet-1.16.3 kubeadm-1.16.3 kubectl-1.16.3
$ systemctl enable kubelet
```


## 6. 部署Kubernetes Master

### 6.1 创建kubeadm配置文件

在具有vip的master上操作，这里为master1

```
$ mkdir /usr/local/kubernetes/manifests -p

$ cd /usr/local/kubernetes/manifests/

$ vi kubeadm-config.yaml

apiServer:
  certSANs:
    - master1
    - master2
    - master.k8s.io
    - 198.51.100.14
    - 198.51.100.11
    - 198.51.100.12
    - 127.0.0.1
  extraArgs:
    authorization-mode: Node,RBAC
  timeoutForControlPlane: 4m0s
apiVersion: kubeadm.k8s.io/v1beta1
certificatesDir: /etc/kubernetes/pki
clusterName: kubernetes
controlPlaneEndpoint: "master.k8s.io:16443"
controllerManager: {}
dns:
  type: CoreDNS
etcd:
  local:
    dataDir: /var/lib/etcd
imageRepository: registry.aliyuncs.com/google_containers
kind: ClusterConfiguration
kubernetesVersion: v1.16.3
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: 10.1.0.0/16
scheduler: {}
```


### 6.2 在master1节点执行

```
$ kubeadm init --config kubeadm-config.yaml
```


按照提示配置环境变量，使用kubectl工具：

```bash
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config
$ kubectl get nodes
$ kubectl get pods -n kube-system
```


**按照提示保存当前环境生成的 join 命令；下面只展示参数形状：**

```bash
kubeadm join master.k8s.io:16443 --token <BOOTSTRAP_TOKEN> \
    --discovery-token-ca-cert-hash sha256:<CA_CERT_HASH> \
    --control-plane
```

查看集群状态

```bash
kubectl get cs

kubectl get pods -n kube-system
```


## 7.安装集群网络

从官方地址获取到flannel的yaml，在master1上执行

```bash
mkdir flannel
cd flannel
wget -c https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
```


安装flannel网络

```bash
kubectl apply -f kube-flannel.yml
```

检查

```bash
kubectl get pods -n kube-system
```


## 8、master2节点加入集群

### 8.1 复制密钥及相关文件

从 master1 复制密钥及相关文件到 master2。该做法只作为历史记录，当前推荐使用
`kubeadm join --control-plane` 的证书密钥流程，并通过安全通道传输临时凭据。

```bash
# ssh root@198.51.100.12 mkdir -p /etc/kubernetes/pki/etcd

# scp /etc/kubernetes/admin.conf root@198.51.100.12:/etc/kubernetes

# scp /etc/kubernetes/pki/{ca.*,sa.*,front-proxy-ca.*} root@198.51.100.12:/etc/kubernetes/pki

# scp /etc/kubernetes/pki/etcd/ca.* root@198.51.100.12:/etc/kubernetes/pki/etcd
```

### 8.2 master2加入集群

执行在master1上init后输出的join命令,需要带上参数`--control-plane`表示把master控制节点加入集群

```
kubeadm join master.k8s.io:16443 --token <BOOTSTRAP_TOKEN>     --discovery-token-ca-cert-hash sha256:<CA_CERT_HASH> --control-plane
```

检查状态

```
kubectl get node

kubectl get pods --all-namespaces
```


## 9. 加入 Worker 节点

在node1上执行

向集群添加新节点，执行在kubeadm init输出的kubeadm join命令：

```
kubeadm join master.k8s.io:16443 --token <BOOTSTRAP_TOKEN>     --discovery-token-ca-cert-hash sha256:<CA_CERT_HASH>
```

**集群网络重新安装，因为添加了新的node节点**

检查状态

```
kubectl get node

kubectl get pods --all-namespaces
```


## 10. 测试集群

> 本节属于历史路径演示；当前验收流程见 README「重建路线」与 `docs/lab-environment.md`。

在Kubernetes集群中创建一个pod，验证是否正常运行：

```
$ kubectl create deployment nginx --image=nginx
$ kubectl expose deployment nginx --port=80 --type=NodePort
$ kubectl get pod,svc
```

访问地址：http://NodeIP:Port
