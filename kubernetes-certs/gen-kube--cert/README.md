##### kubernetes证书
kubeadm 在创建群集时，将生成证书过期完全封装了，ca证书有效期为10年，其它证书有效时为1年   


/etc/kubernetes/pki  
/etc/kubernetes/pki/etcd

22 个证书文件   
```conf
|-- apiserver.crt
|-- apiserver-etcd-client.crt
|-- apiserver-etcd-client.key
|-- apiserver.key
|-- apiserver-kubelet-client.crt
|-- apiserver-kubelet-client.key
|-- ca.crt
|-- ca.key
|-- etcd
|   |-- ca.crt
|   |-- ca.key
|   |-- healthcheck-client.crt
|   |-- healthcheck-client.key
|   |-- peer.crt
|   |-- peer.key
|   |-- server.crt
|   `-- server.key
|-- front-proxy-ca.crt
|-- front-proxy-ca.key
|-- front-proxy-client.crt
|-- front-proxy-client.key
|-- sa.key
|-- sa.pub

```

这里采用 cfssl 工具分解生成证书的步骤   
##### Kubernetes 集群根证书CA(Kubernetes集群组件的证书签发机构)：ca.key & ca.crt 有效期为10年 87600h      
ca.json
```json
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "ca": {
    "expiry": "87600h"
  }
}
```

```shell
# 生成 ca.crt 和 ca.key  
# mv ca.pem ca.crt && mv ca-key.pem ca.key
# /etc/kubernetes/pki/ca.crt
# /etc/kubernetes/pki/ca.key
cfssl gencert -initca ca.json | cfssljson -bare ca && mv ca.pem ca.crt && mv ca-key.pem ca.key
```

##### kube-apiserver 组件持有的服务端证书 
config.json 
```json
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
        "usages": [
            "signing",
            "key encipherment",
            "server auth",
            "client auth"
        ],
        "expiry": "87600h"
      }
    }
  }
}
```


apiserver.json   
在hosts字段添加master节点的ip和 kubernetes的dns的service ip(默认: 10.96.0.1)
```json
{
    "CN": "kube-apiserver",
    "hosts": [
      "172.20.20.249",
      "10.96.0.1",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"     
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    }
}
```

```shell 
# /etc/kubernetes/pki/apiserver.crt
# /etc/kubernetes/pki/apiserver.key
cfssl gencert -ca=ca.crt -ca-key=ca.key -config=config.json -profile=kubernetes  apiserver.json | \ 
cfssljson -bare apiserver && mv apiserver-key.pem apiserver.key && mv apiserver.pem apiserver.crt
```

##### kubelet 组件持有的客户端证书, 用作 kube-apiserver 主动向 kubelet 发起请求时的客户端认证
apiserver-kubelet-client.json
```json
{
  "CN": "kube-apiserver-kubelet-client",
  "hosts": [""],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "system:masters"
    }
  ]
}
```

```shell
# /etc/kubernetes/pki/apiserver-kubelet-client.crt
# /etc/kubernetes/pki/apiserver-kubelet-client.key
cfssl gencert -ca=ca.crt -ca-key=ca.key -config=config.json -profile=kubernetes \ 
apiserver-kubelet-client.json | cfssljson -bare apiserver-kubelet-client \
&& mv apiserver-kubelet-client-key.pem apiserver-kubelet-client.key \
&& mv apiserver-kubelet-client.pem apiserver-kubelet-client.crt
```

注意：

    Kubernetes集群组件之间的交互是双向的, kubelet 既需要主动访问 kube-apiserver, kube-apiserver 也需要主动向 kubelet 发起请求, 所以双方都需要有自己的根证书以及使用该根证书签发的服务端证书和客户端证书.
    在 kube-apiserver 中, 一般明确指定用于 https 访问的服务端证书和带有CN 用户名信息的客户端证书. 而在 kubelet 的启动配置中, 一般只指定了 ca 根证书, 而没有明确指定用于 https 访问的服务端证书。

##### 汇聚层证书
kube-apiserver 的另一种访问方式就是使用 kubectl proxy 来代理访问, 而该证书就是用来支持SSL代理访问的。    



###### kube-apiserver 代理根证书(客户端证书)
用在requestheader-client-ca-file配置选项中, kube-apiserver 使用该证书来验证客户端证书是否为自己所签发    
front-proxy-ca.json
```json
{
  "CN": "kubernetes",
  "key": {
    "algo": "rsa",
    "size": 2048
  }
}
```

```shell
# /etc/kubernetes/pki/front-proxy-ca.crt
# /etc/kubernetes/pki/front-proxy-ca.key
cfssl gencert -initca front-proxy-ca.json | cfssljson -bare front-proxy-ca  && mv front-proxy-ca.pem front-proxy-ca.crt && mv front-proxy-ca-key.pem front-proxy-ca.key
```

front-proxy-client.json
```json
{
  "CN": "front-proxy-client",
  "hosts": [""],
  "key": {
    "algo": "rsa",
    "size": 2048
  }
}
```

代理端使用的客户端证书, 用作代用户与 kube-apiserver 认证
```shell
# /etc/kubernetes/pki/front-proxy-client.crt
# /etc/kubernetes/pki/front-proxy-client.key
cfssl gencert -ca=front-proxy-ca.crt -ca-key=front-proxy-ca.key -config=config.json \
-profile=kubernetes  front-proxy-client.json | cfssljson -bare front-proxy-client \
&& mv front-proxy-client-key.pem front-proxy-client.key \
&& mv front-proxy-client.pem front-proxy-client.crt
```

##### Service Account 秘钥
这组的密钥对儿仅提供给 kube-controller-manager 使用.      
kube-controller-manager 通过 sa.key 对 token 进行签名, master 节点通过公钥 sa.pub 进行签名的验证    

```shell 
# /etc/kubernetes/pki/sa.key
# /etc/kubernetes/pki/sa.pub
openssl genrsa -out sa.key 1024  &&   openssl rsa -in sa.key -pubout -out sa.pub
```



##### etcd 集群证书
###### etcd 集群根证书
etcd集群所用到的证书都保存在/etc/kubernetes/pki/etcd 下 
```shell
#|-- etcd
#|   |-- ca.crt
#|   |-- ca.key
#|   |-- healthcheck-client.crt
#|   |-- healthcheck-client.key
#|   |-- peer.crt
#|   |-- peer.key
#|   |-- server.crt
#|   `-- server.key
mkdir etcd && cd etcd
```
etcd-server.json    
在hosts中添加etcd节点的ip   
```json
{
  "CN": "etcd",
  "hosts": [
    "127.0.0.1",
    "10.0.116.97",
    "10.0.116.98",
    "10.0.116.99"
  ],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "ShenZhen",
      "L": "ShenZhen",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
```

etcd-config.json
```json
{
    "signing": {
        "default": {
            "expiry": "87600h"
        },
        "profiles": {
            "server": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth"
                ]
            },
            "client": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
```
###### etcd server 证书
```shell
cfssl gencert -ca=ca.crt -ca-key=ca.key -config=etcd-config.json -profile=server  etcd-server.json | \ 
cfssljson -bare etcd-server && mv etcd-server-key.pem etcd-server.key && mv etcd-server.pem etcd-server.crt
cp -p  etcd-server.key  etcd/server.key  && cp -p etcd-server.crt etcd/server.crt
```

###### etcd peer 证书
```shell 
cp etcd-server.json  etcd-member.json

cfssl gencert -ca=ca.crt -ca-key=ca.key -config=etcd-config.json -profile=peer  etcd-member.json | \ 
cfssljson -bare etcd-member && mv etcd-member-key.pem etcd-member.key && mv etcd-member.pem etcd-member.crt
cp -p  etcd-member.key  etcd/peer.key  && cp -p etcd-member.crt etcd/peer.crt
```

###### etcd client 证书
etcd-client.json
```json
{
    "CN": "client",
    "hosts": [""],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
    {
      "C": "CN",
      "ST": "ShenZhen",
      "L": "ShenZhen",
      "O": "k8s",
      "OU": "System"
    }
    ]
}
```

```shell 
cfssl gencert -ca=ca.crt -ca-key=ca.key -config=etcd-config.json -profile=client  etcd-client.json | \ 
cfssljson -bare etcd-client && mv etcd-client-key.pem etcd-client.key && mv etcd-client.pem etcd-client.crt
cp -p  etcd-client.key  etcd/healthcheck-client.key  && cp -p etcd-member.crt etcd/healthcheck-client.crt
```

cfssl 安装
```shell
wget https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
chmod +x cfssl_linux-amd64
cp -p cfssl_linux-amd64 /usr/local/bin/cfssl

wget https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
chmod +x cfssljson_linux-amd64
cp -p cfssljson_linux-amd64 /usr/local/bin/cfssljson

wget https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x cfssl-certinfo_linux-amd64
cp -p cfssl-certinfo_linux-amd64 /usr/local/bin/cfssl-certinfo
```