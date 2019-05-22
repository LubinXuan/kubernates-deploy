ip=`/sbin/ifconfig -a|grep inet|grep -v 127.0.0.1|grep 192.168|grep -v inet6|awk '{print $2}'|tr -d "addr:"`
host=`hostname`
echo $ip $host
cat > /etc/etcd/etcd.conf <<EOF
# [Member Flags]
# ETCD_ELECTION_TIMEOUT=1000
# ETCD_HEARTBEAT_INTERVAL=100
# 指定etcd的数据目录
ETCD_NAME=k8s-master-$1
ETCD_DATA_DIR=/data1/etcd-data
# [Cluster Flags]
# ETCD_AUTO_COMPACTION_RETENTIO:N=0
ETCD_INITIAL_CLUSTER_STATE=new
ETCD_ADVERTISE_CLIENT_URLS=https://$host:2379
ETCD_INITIAL_ADVERTISE_PEER_URLS=https://$host:2380
ETCD_LISTEN_CLIENT_URLS=https://$ip:2379,https://127.0.0.1:2379
ETCD_INITIAL_CLUSTER_TOKEN=etcd-cluster
ETCD_LISTEN_PEER_URLS=https://$ip:2380
ETCD_DISCOVERY_SRV="cloud.worken.net"

# [Proxy Flags]
ETCD_PROXY=off

# [Security flags]
# ETCD_CLIENT_CERT_AUTH=
# ETCD_PEER_CLIENT_CERT_AUTH=
# 指定etcd的公钥证书和私钥
ETCD_TRUSTED_CA_FILE=/etc/etcd/pki/ca.crt
ETCD_CERT_FILE=/etc/etcd/pki/etcd.crt
ETCD_KEY_FILE=/etc/etcd/pki/etcd.key
# 指定etcd的Peers通信的公钥证书和私钥
ETCD_PEER_TRUSTED_CA_FILE=/etc/etcd/pki/ca.crt
ETCD_PEER_CERT_FILE=/etc/etcd/pki/etcd.crt
ETCD_PEER_KEY_FILE=/etc/etcd/pki/etcd.key

# [Profiling flags]
# ETCD_METRICS={{ etcd_metrics }}
EOF
cat /etc/etcd/etcd.conf
