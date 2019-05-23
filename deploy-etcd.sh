DAYS=36500
NODE_COUNT=100
VERSION=v3.3.13

source ./cluster-info

dir_local=`pwd`

mkdir ~/.etcd-config
rm ~/.etcd-config/pki -rf
cd ~/.etcd-config

mkdir pki

openssl genrsa -out pki/ca.key 2048
openssl req -x509 -new -nodes -key pki/ca.key -subj "/C=CN/ST=Zhejiang/L=Hangzhou/O=etcd/OU=HKDW/CN=etcd/emailAddress=xuanlubin@worken.cn" -days $DAYS -out pki/ca.crt


NODE_LST=
#define master node
for i in $(seq 1 3)
do
        NODE_LST=$NODE_LST"""DNS.$i = k8s-master-$i.cloud.worken.net
"""
done
#define worker node
for i in $(seq 1 100)
do
	NODE_LST=$NODE_LST"""DNS.$((i+4)) = k8s-node-$i
"""
done 

cat > etcd-ca.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn
    
[ dn ]
C = CN
ST = Zhejiang
L = Hangzhou
O = etcd
OU = HKDW
CN = etcd
    
[ req_ext ]
subjectAltName = @alt_names
    
[ alt_names ]
IP.1  = 127.0.0.1
DNS.0 = cloud.worken.net
$NODE_LST

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

openssl genrsa -out pki/etcd.key 2048

openssl req -new -key pki/etcd.key -out pki/etcd.csr -config etcd-ca.conf

openssl x509 -req -in pki/etcd.csr -CA pki/ca.crt -CAkey pki/ca.key \
-CAcreateserial -out pki/etcd.crt -days $DAYS \
-extensions v3_ext -extfile etcd-ca.conf

cat > etcd.service <<EOF
[Unit]
Description=etcd server
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
Type=notify
WorkingDirectory=/var/lib/etcd/
EnvironmentFile=-/etc/etcd/etcd.conf
ExecStart=/usr/local/bin/etcd
NotifyAccess=all
Restart=always
RestartSec=5s
LimitNOFILE=40000

[Install]
WantedBy=multi-user.target
EOF



ips=('' $CP0_IP $CP1_IP $CP2_IP)


if [ ! -f "etcd-"$VERSION ]; then
  rm etcd-$VERSION-linux-amd64* -f
  wget --no-check-certificate https://github.com/etcd-io/etcd/releases/download/$VERSION/etcd-$VERSION-linux-amd64.tar.gz
  tar -zxvf etcd-$VERSION-linux-amd64.tar.gz
  mv etcd-$VERSION-linux-amd64/etcd etcd-$VERSION
  mv etcd-$VERSION-linux-amd64/etcdctl etcdctl
fi


#deploy etcd master
for i in $(seq 1 3)
do
ip=k8s-master-${i}.cloud.worken.net
ssh $ip "rm /etc/etcd/* -rf; mkdir /var/lib/etcd/ -p; mkdir -p /etc/etcd/pki; mkdir /data1/etcd-data -p; rm /var/lib/etcd/* -rf; rm /data1/etcd-data/* -rf"
scp etcd-$VERSION $ip:/usr/local/bin/etcd
scp etcd.service   		   $ip:/usr/lib/systemd/system/etcd.service
scp $dir_local/install-etcd-config.sh         $ip:/etc/etcd/install-etcd-config.sh
scp pki/ca.crt     		   $ip:/etc/etcd/pki/ca.crt
scp pki/etcd.crt   		   $ip:/etc/etcd/pki/etcd.crt
scp pki/etcd.key   		   $ip:/etc/etcd/pki/etcd.key

ssh $ip "
  sh /etc/etcd/install-etcd-config.sh $i
  systemctl daemon-reload
  systemctl enable etcd
  systemctl start etcd
  systemctl status etcd
"
done
exit 0
