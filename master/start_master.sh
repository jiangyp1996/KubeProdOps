#!/bin/bash


# parameters 
etcd_servers=
service_cluster_ip_range=172.16.0.0/13
flannel_network=172.24.0.0/13
cluster_dns=
cluster_name="my-k8s"
insecure_bind_address=127.0.0.1
apiserver_insecure_port=8080
apiserver_secure_port=6443
kubernetes_version=1.18.14
master_ip=



# constants
APISERVER_CA_PATH="/etc/kubernetes/pki"
APISERVER_AUTH_PATH="/etc/kubernetes/auth"
CLUSTER_DOMAIN="cluster.local"



function print_help() {
  echo -e "
  \033[0;33mParameters explanation:

  --cluster-nodes      [required]  etcd cluster peer nodes
  --data-path          [required]  etcd data storage root path
  --etcd_version       [required]  etcd version, default 3.5.4\033[0m
  "
}

function command_exists ()
{
  command -v "$@" > /dev/null 2>&1
}

function service_exists ()
{
  systemctl list-unit-files | grep $1 > /dev/null 2>&1
}



for arg in "$@"
do
  case $arg in
    --etcd-servers=*)
      etcd_servers="${arg#*=}"
      ;;
    --service-cluster-ip-range=*)
      service_cluster_ip_range="${arg#*=}"
      ;;
    --flannel-network=*)
      flannel_network="${arg#*=}"
      ;;
    --cluster-dns=*)
      cluster_dns="${arg#*=}"
      ;;
    --cluster-name=*)
      cluster_name="${arg#*=}"
      ;;
    --apiserver_insecure_port=*)
      apiserver_insecure_port="${arg#*=}"
      ;;
    --apiserver-secure-port=*)
      apiserver_secure_port="${arg#*=}"
      ;;
    --insecure-bind-address=*)
      insecure_bind_address="${arg#*=}"
      ;;
    --kubernetes-version=*)
      kubernetes_version="${arg#*=}"
      ;;
    --master-ip=*)
      master_ip="${arg#*=}"
      ;;
    *)
      print_help
      exit 0
      ;;
  esac
done



# step 01 : check arguments

if [ -z "$etcd_servers" ]; then
  echo -e "\033[31m[ERROR] --etcd-servers is absent\033[0m"
  exit 1
fi

if [[ -z $master_ip ]]; then
  echo -e "\033[31m[ERROR] --master-ip is absent\033[0m"
  exit 1
fi


# step 02 : check if master_ip belong to this host

host_ips=(`ip addr show | grep inet | grep -v inet6 | grep brd | awk '{print $2}' | cut -f1 -d '/'`)
if [ -z "$host_ips" ]; then
  echo -e "\033[31m[ERROR] get host ip address error\033[0m"
  exit 1
fi

master_ip_exist=false
for ip in ${host_ips[@]}
do
  if [[ $ip == $master_ip ]]; then
    master_ip_exist=true
    break
  fi
done

if [[ $master_ip_exist == false ]]; then
  echo -e "\033[31m[ERROR] --master-ip does not belong to this host\033[0m"
  exit 1
fi


# STEP 03: download and decompress kubernetes server installation package

# https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.18.md#server-binaries-6

wget -P /tmp https://domeos-script.bjcnc.scs.sohucs.com/jiang/kubeProdOps/master.tar.gz

tar -zxvf /tmp/master.tar.gz -C /tmp --no-same-owner

mv /tmp/master/kube* /usr/bin/



# STEP 04: generate CA files

mkdir -p $APISERVER_CA_PATH

openssl genrsa -out ca.key 2048
openssl req -x509 -new -nodes -key ca.key -subj "/CN=${master_ip}" -days 36500 -out ca.crt

echo "[ req ]
req_extensions = v3_req
distinguished_name  = req_distinguished_name
[ req_distinguished_name ]


# Extensions to add to a certificate request
[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName=@alt_names


[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.${CLUSTER_DOMAIN}
IP.1 = 172.16.0.1 
IP.2 = 127.0.0.1
IP.3 = ${master_ip}
" > master_ssl.cnf

openssl genrsa -out apiserver.key 2048
openssl req -new -key apiserver.key -config master_ssl.cnf -subj "/CN=${master_ip}" -out apiserver.csr
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 36500 -extensions v3_req -extfile master_ssl.cnf -out apiserver.crt

mv ca.key ca.crt master_ssl.cnf apiserver.key apiserver.csr apiserver.crt ${APISERVER_CA_PATH}


# STEP 05: generate the token.csv file

mkdir -p ${APISERVER_AUTH_PATH}

token=`echo $cluster_name | base64`
echo $token,k8s-node,0 > ${APISERVER_AUTH_PATH}/token.csv



# STEP 06: configure and start kube-apiserver by systemd

echo -e "\033[36m[INFO] STEP 12: Start kube-apiserver...\033[0m"
if service_exists kube-apiserver; then
  systemctl stop kube-apiserver
fi

echo "[Unit]
Description=kube-apiserver
After=network.target
After=network-online.target
Wants=network-online.target

[Service]
EnvironmentFile=/etc/sysconfig/kube-apiserver
ExecStart=/usr/bin/kube-apiserver \$ETCD_SERVERS \\
          \$SERVICE_CLUSTER_IP_RANGE \\
          \$INSECURE_BIND_ADDRESS \\
          \$INSECURE_PORT \\
          \$SECURE_PORT \\
          \$KUBE_APISERVER_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/kube-apiserver.service


KUBE_APISERVER_OPTS="--client-ca-file=${APISERVER_CA_PATH}/ca.crt --tls-private-key-file=${APISERVER_CA_PATH}/apiserver.key --tls-cert-file=${APISERVER_CA_PATH}/apiserver.crt --service-account-key-file=${APISERVER_CA_PATH}/apiserver.crt --token-auth-file=${APISERVER_AUTH_PATH}/token.csv"

echo "# configure file for kube-apiserver

# --etcd-servers
ETCD_SERVERS='--etcd-servers=${etcd_servers}'
# --service-cluster-ip-range
SERVICE_CLUSTER_IP_RANGE='--service-cluster-ip-range=${service_cluster_ip_range}'
# other parameters
KUBE_APISERVER_OPTS='${KUBE_APISERVER_OPTS} --kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP --kubelet-client-certificate=${APISERVER_CA_PATH}/apiserver.crt --kubelet-client-key=${APISERVER_CA_PATH}/apiserver.key'
# --insecure-bind-address
INSECURE_BIND_ADDRESS='--insecure-bind-address=${insecure_bind_address}'
# --insecure-port
INSECURE_PORT='--insecure-port=${apiserver_insecure_port}'
# --secure-port
SECURE_PORT='--secure-port=${apiserver_secure_port}'
" > /etc/sysconfig/kube-apiserver

systemctl daemon-reload
systemctl start kube-apiserver
systemctl enable kube-apiserver
sleep 8
systemctl status -l kube-apiserver


# STEP 07: configure and start kube-controller-manager by systemd

echo -e "\033[36m[INFO] STEP 13: Start kube-controller-manager...\033[0m"
if service_exists kube-controller; then
  systemctl stop kube-controller
fi

echo "[Unit]
Description=kube-controller-manager
After=kube-apiserver.service
Wants=kube-apiserver.service

[Service]
EnvironmentFile=/etc/sysconfig/kube-controller-manager
ExecStart=/usr/bin/kube-controller-manager \$KUBE_MASTER \\
          \$KUBE_CONTROLLER_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/kube-controller-manager.service

echo "# configure file for kube-controller-manager

# --master
KUBE_MASTER='--master=http://127.0.0.1:${apiserver_insecure_port}'

# other parameters
KUBE_CONTROLLER_OPTS='--root-ca-file=${APISERVER_CA_PATH}/ca.crt --service-account-private-key-file=${APISERVER_CA_PATH}/apiserver.key'
" > /etc/sysconfig/kube-controller-manager

systemctl daemon-reload
systemctl start kube-controller-manager
systemctl enable kube-controller-manager
sleep 5
systemctl status -l kube-controller-manager


# STEP 08: configure and start kube-scheduler by systemd

echo -e "\033[36m[INFO] STEP 14: Start kube-scheduler...\033[0m"
if service_exists kube-scheduler; then
  systemctl stop kube-scheduler
fi

echo "[Unit]
Description=kube-scheduler
After=kube-apiserver.service
Wants=kube-apiserver.service

[Service]
EnvironmentFile=/etc/sysconfig/kube-scheduler
ExecStart=/usr/bin/kube-scheduler \$KUBE_MASTER \\
          \$KUBE_SCHEDULER_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/kube-scheduler.service

echo "# configure file for kube-scheduler
# --master
KUBE_MASTER='--master=http://127.0.0.1:${apiserver_insecure_port}'

# other parameters
KUBE_SCHEDULER_OPTS=''
" > /etc/sysconfig/kube-scheduler

systemctl daemon-reload
systemctl start kube-scheduler
systemctl enable kube-scheduler
sleep 5
systemctl status -l kube-scheduler


# STEP 09: create cluster role、cluster role binding

single_etcd_server=$(echo ${etcd_servers} | cut -f1 -d ',')
curl -L ${single_etcd_server}/v2/keys/flannel/network/config -XPUT -d value="{\"Network\": \"${flannel_network}\", \"SubnetLen\": 22, \"Backend\": {\"Type\": \"vxlan\", \"VNI\": 1}}"
cat <<EOF | kubectl -s http://127.0.0.1:${apiserver_insecure_port} apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: cluster-admin
rules:
- apiGroups:
  - '*'
  resources:
  - '*'
  verbs:
  - '*'
- nonResourceURLs:
  - '*'
  verbs:
  - '*'
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  annotations:
    rbac.authorization.kubernetes.io/autoupdate: "true"
  labels:
    kubernetes.io/bootstrapping: rbac-defaults
  name: cluster-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- apiGroup: rbac.authorization.k8s.io
  kind: Group
  name: system:masters
- kind: ServiceAccount
  name: default
  namespace: kube-system
- apiGroup: rbac.authorization.k8s.io
  kind: User
  name: k8s-node
EOF





















