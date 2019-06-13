#!/bin/bash

function check_parm()
{
  if [ "${2}" == "" ]; then
    echo -n "${1}"
    return 1
  else
    return 0
  fi
}

if [ -f ./cluster-info ]; then
	source ./cluster-info 
fi

check_parm "Enter the VIP: " ${VIP}
if [ $? -eq 1 ]; then
	read VIP
fi
check_parm "Enter the Net Interface: " ${NET_IF}
if [ $? -eq 1 ]; then
	read NET_IF
fi
check_parm "Enter the cluster CIDR: " ${CIDR}
if [ $? -eq 1 ]; then
	read CIDR
fi

declare -A IPS=()

for i in 0 1 2; do
  host="k8s-master-"$((i+1))
  echo $host
  IPS[$i]=""`ping $host  -c1 | grep PING | awk '{ print $3 }' | sed 's/[()]//g'`
done


echo """
cluster-info:
  master-01:        ${IPS[0]}
  master-02:        ${IPS[1]}
  master-03:        ${IPS[2]}
  VIP:              ${VIP}
  Net Interface:    ${NET_IF}
  CIDR:             ${CIDR}
"""
echo -n 'Please print "yes" to continue or "no" to cancel: '
read AGREE
while [ "${AGREE}" != "yes" ]; do
	if [ "${AGREE}" == "no" ]; then
		exit 0;
	else
		echo -n 'Please print "yes" to continue or "no" to cancel: '
		read AGREE
	fi
done

mkdir -p ~/ikube/tls

PRIORITY=(100 50 50)
STATE=("MASTER" "BACKUP" "BACKUP")
HEALTH_CHECK=""
for index in 0 1 2; do
  HEALTH_CHECK=${HEALTH_CHECK}"""
    real_server ${IPS[$index]} 8443 {
        weight 1
        SSL_GET {
            url {
              path /healthz
              status_code 200
            }
            connect_timeout 3
            nb_get_retry 3
            delay_before_retry 3
        }
    }
"""
done


cat > ~/ikube/haproxy.cfg << EOF
global
    log         127.0.0.1 local2
    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon
    stats socket /var/lib/haproxy/stats

defaults
    mode                    tcp
    log                     global
    option                  tcplog
    option                  dontlognull
    option                  redispatch
    retries                 3
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout check           10s
    maxconn                 3000

listen stats
    mode   http
    bind :10086
    stats   enable
    stats   uri     /admin?stats
    stats   auth    admin:admin
    stats   admin   if TRUE
    
frontend  k8s_https *:8443
    mode      tcp
    maxconn      2000
    default_backend     https_sri
    
backend https_sri
    balance      roundrobin
    server master1-api ${IPS[0]}:6443  check inter 10000 fall 2 rise 2 weight 1
    server master2-api ${IPS[1]}:6443  check inter 10000 fall 2 rise 2 weight 1
    server master3-api ${IPS[2]}:6443  check inter 10000 fall 2 rise 2 weight 1
EOF

cat > ~/ikube/check_haproxy.sh << EOF
#!/bin/bash
A=\`ps -C haproxy --no-header |wc -l\`
if [ \$A -eq 0 ];then
/etc/init.d/keepalived stop
fi
EOF


for index in 0 1 2; do
  ip=${IPS[${index}]}
  echo "install "$ip
  cat > ~/ikube/keepalived-${index}.conf << EOF
global_defs {
   router_id LVS_DEVEL_${index}
}
vrrp_instance VI_1 {
    state ${STATE[${index}]}
    interface ${NET_IF}
    virtual_router_id 80
    priority ${PRIORITY[${index}]}
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass just0kk
    }
    virtual_ipaddress {
        ${VIP}
    }
}
virtual_server ${VIP} 8443 {
    delay_loop 6
    lb_algo loadbalance
    lb_kind DR
    net_mask 255.255.255.0
    persistence_timeout 0
    protocol TCP
${HEALTH_CHECK}
}
EOF
  scp ~/ikube/haproxy.cfg ${ip}:/etc/haproxy/
  scp ~/ikube/keepalived-${index}.conf ${ip}:/etc/keepalived/keepalived.conf
  ssh ${ip} "
    systemctl enable haproxy
    systemctl restart haproxy
    systemctl enable keepalived
    systemctl restart keepalived"
done

for index in 0 1 2;do
  ip=${IPS[${index}]}
  echo "清理k8s环境--->"$ip
  ssh $ip "
      kubeadm reset -f;
      rm -rf /var/lib/cni;
      rm -rf /var/lib/kubelet;
      rm -rf /etc/cni;
      rm -rf /etc/kubernetes;
      rm ~/.kube -rf;
      mkdir -p /etc/kubernetes/pki/etcd;
      mkdir -p ~/.kube/; 
      ipvsadm --clear;
      ifconfig cni0 down;
      ifconfig flannel.1 down;
      ifconfig docker0 down;
      ip link delete flannel.1;
      ip link delete cni0;
  "
  echo "分发etcd证书--->"$ip
  scp ~/.etcd-config/pki/ca.crt $ip:/etc/kubernetes/pki/etcd/ca.crt
  scp ~/.etcd-config/pki/etcd.crt $ip:/etc/kubernetes/pki/etcd/etcd.crt
  scp ~/.etcd-config/pki/etcd.key $ip:/etc/kubernetes/pki/etcd/etcd.key
done


echo """
apiVersion: kubeadm.k8s.io/v1beta1
kind: ClusterConfiguration
kubernetesVersion: v1.14.2
imageRepository: hub.worken.cn
certificatesDir: /etc/kubernetes/pki
controlPlaneEndpoint: "${VIP}:8443"
clusterName: hkdw-k8s
apiServer:
  certSANs:
  - ${VIP}
networking:
  dnsDomain: cluster.local
  podSubnet: 10.244.0.0/16
  serviceSubnet: ${CIDR}
controllerManager:
  extraArgs:
    address: 0.0.0.0
scheduler:
  extraArgs:
    address: 0.0.0.0
etcd:
  external:
    endpoints:
    - https://k8s-master-1:2379
    - https://k8s-master-2:2379
    - https://k8s-master-3:2379
    caFile: /etc/kubernetes/pki/etcd/ca.crt
    certFile: /etc/kubernetes/pki/etcd/etcd.crt
    keyFile: /etc/kubernetes/pki/etcd/etcd.key
dns:
   type: CoreDNS
   imageRepository: coredns
   imageTag: 1.5.0
---
apiVersion: kubeproxy.config.k8s.io/v1alpha1
kind: KubeProxyConfiguration
mode: ipvs
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
""" > /etc/kubernetes/kubeadm-config.yaml



kubeadm init --config /etc/kubernetes/kubeadm-config.yaml
mkdir -p $HOME/.kube
cp -f /etc/kubernetes/admin.conf ${HOME}/.kube/config

kubectl apply -f addon/

JOIN_CMD=`kubeadm token create --print-join-command`

for index in 1 2; do
  ip=${IPS[${index}]}
  scp /etc/kubernetes/pki/ca.crt $ip:/etc/kubernetes/pki/ca.crt
  scp /etc/kubernetes/pki/ca.key $ip:/etc/kubernetes/pki/ca.key
  scp /etc/kubernetes/pki/sa.key $ip:/etc/kubernetes/pki/sa.key
  scp /etc/kubernetes/pki/sa.pub $ip:/etc/kubernetes/pki/sa.pub
  scp /etc/kubernetes/pki/front-proxy-ca.crt $ip:/etc/kubernetes/pki/front-proxy-ca.crt
  scp /etc/kubernetes/pki/front-proxy-ca.key $ip:/etc/kubernetes/pki/front-proxy-ca.key
  scp /etc/kubernetes/admin.conf $ip:/etc/kubernetes/admin.conf
  scp /etc/kubernetes/admin.conf $ip:~/.kube/config
  ssh ${ip} "${JOIN_CMD} --experimental-control-plane"
done
