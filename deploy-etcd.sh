DAYS=36500
NODE_COUNT=100

mkdir /etc/etcd/pki -p
cd /etc/etcd/pki
openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/C=CN/ST=Zhejiang/L=Hangzhou/O=etcd/OU=HKDW/CN=etcd/emailAddress=xuanlubin@worken.cn" -days $DAYS -out ca.crt




NODE_LST=
#define master node
for i in $(seq 1 3)
do
        NODE_LST=$NODE_LST"""DNS.$i = k8s-master-$i
"""
done
#define worker node
for i in $(seq 1 100)
do
	NODE_LST=$NODE_LST"""DNS.$((i+4)) = k8s-node-$i
"""
done 

echo $NODE_LST

cat > ../etcd-ca.conf <<EOF
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
$NODE_LST

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF

openssl genrsa -out etcd.key 2048

openssl req -new -key etcd.key -out etcd.csr -config ../etcd-ca.conf

openssl x509 -req -in etcd.csr -CA ca.crt -CAkey ca.key \
-CAcreateserial -out etcd.crt -days $DAYS \
-extensions v3_ext -extfile ../etcd-ca.conf


