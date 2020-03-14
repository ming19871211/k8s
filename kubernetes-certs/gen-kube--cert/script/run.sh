#!/bin/bash

#### 安装 cfssl
if [ "$1" = "cfssl" ];then
    rm cfssl* -f

    wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
    chmod +x cfssl_linux-amd64
    cp -pf cfssl_linux-amd64 /usr/local/bin/cfssl

    wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
    chmod +x cfssljson_linux-amd64
    cp -pf cfssljson_linux-amd64 /usr/local/bin/cfssljson

    wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
    chmod +x cfssl-certinfo_linux-amd64
    cp -pf cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
fi

if [ ! -f "/usr/local/bin/cfssl" ]; then
echo "/usr//local/bin/cfssl 不存在，异常退出!"
exit 1
fi

if [ ! -f "/usr/local/bin/cfssljson" ]; then
echo "/usr/local/bin/cfssljson 不存在，异常退出!"
exit 1
fi

cfssl gencert -initca ca.json | cfssljson -bare ca && mv ca.pem ca.crt && mv ca-key.pem ca.key
cfssl gencert -initca front-proxy-ca.json | cfssljson -bare front-proxy-ca  && mv front-proxy-ca.pem front-proxy-ca.crt && mv front-proxy-ca-key.pem front-proxy-ca.key
cfssl gencert -ca=ca.crt -ca-key=ca.key -config=config.json -profile=kubernetes  apiserver.json | cfssljson -bare apiserver && mv apiserver-key.pem apiserver.key && mv apiserver.pem apiserver.crt
cfssl gencert -ca=ca.crt -ca-key=ca.key -config=config.json -profile=kubernetes  apiserver-kubelet-client.json | cfssljson -bare apiserver-kubelet-client  && mv apiserver-kubelet-client-key.pem apiserver-kubelet-client.key && mv apiserver-kubelet-client.pem apiserver-kubelet-client.crt
cfssl gencert -ca=front-proxy-ca.crt -ca-key=front-proxy-ca.key -config=config.json -profile=kubernetes  front-proxy-client.json | cfssljson -bare front-proxy-client && mv front-proxy-client-key.pem front-proxy-client.key && mv front-proxy-client.pem front-proxy-client.crt
openssl genrsa -out sa.key 1024  &&   openssl rsa -in sa.key -pubout -out sa.pub

#### 生成etcd证书
mkdir -p etcd
cp -fp ca.crt ca.key etcd/

cfssl gencert -ca=ca.crt -ca-key=ca.key -config=etcd-config.json -profile=server etcd-server.json | \
cfssljson -bare etcd-server && mv etcd-server-key.pem etcd-server.key && mv etcd-server.pem etcd-server.crt
cp -fp  etcd-server.key  etcd/server.key  && cp -fp etcd-server.crt etcd/server.crt

cp -fp etcd-server.json  etcd-member.json
cfssl gencert -ca=ca.crt -ca-key=ca.key -config=etcd-config.json -profile=peer  etcd-member.json | \
cfssljson -bare etcd-member && mv etcd-member-key.pem etcd-member.key && mv etcd-member.pem etcd-member.crt
cp -fp  etcd-member.key  etcd/peer.key  && cp -fp etcd-member.crt etcd/peer.crt

cfssl gencert -ca=ca.crt -ca-key=ca.key -config=etcd-config.json -profile=client  etcd-client.json | \
cfssljson -bare etcd-client && mv etcd-client-key.pem etcd-client.key && mv etcd-client.pem etcd-client.crt
cp -fp  etcd-client.key  etcd/healthcheck-client.key  && cp -fp etcd-member.crt etcd/healthcheck-client.crt

cfssl gencert -ca=ca.crt -ca-key=ca.key -config=etcd-config.json -profile=client  apiserver-etcd-client.json | \
cfssljson -bare apiserver-etcd-client && mv apiserver-etcd-client-key.pem apiserver-etcd-client.key && mv apiserver-etcd-client.pem apiserver-etcd-client.crt