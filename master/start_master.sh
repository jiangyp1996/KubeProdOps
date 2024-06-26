#!/bin/bash


# parameters 
etcd_servers_ip=
master_ip=

service_cluster_ip_range=172.16.0.0/13
flannel_network_ip_range=172.24.0.0/13
cluster_name="my-k8s"
apiserver_insecure_bind_address=127.0.0.1
apiserver_insecure_port=8080
apiserver_secure_port=6443
kubernetes_version=1.18.14
apiserver_count=2


# constants
APISERVER_CA_PATH="/etc/kubernetes/pki"
APISERVER_AUTH_PATH="/etc/kubernetes/auth"
CLUSTER_DOMAIN="cluster.local"

ETCD_CLIENT_PORT="2379"
SINGLE_MASTER_AND_GEN_CERT_BY_ITSELF="false"



function print_help() {
  echo -e "
  \033[0;33m
  Parameters explanation:

  --etcd-servers-ip                [required]  etcd cluster client ip
  --master-ip                      [optional]  master ip
  --service-cluster-ip-range       [optional]  apiserver parameter --service-cluster-ip-range, default 172.16.0.0/13
  --flannel-network-ip-range       [optional]  cluster pod ip range, default 172.24.0.0/13
  --cluster-name                   [optional]  cluster name, default my-k8s
  --apiserver-count                [optional]  apiserver count, default 2


  For example:

  /bin/sh start_master.sh --master-ip=10.18.10.1 --etcd-servers-ip=10.18.10.3,10.18.10.4,10.18.10.5 \033[0m
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
    --etcd-servers-ip=*)
      etcd_servers_ip="${arg#*=}"
      ;;
    --service-cluster-ip-range=*)
      service_cluster_ip_range="${arg#*=}"
      ;;
    --flannel-network-ip-range=*)
      flannel_network_ip_range="${arg#*=}"
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
    --apiserver-insecure-bind-address=*)
      apiserver_insecure_bind_address="${arg#*=}"
      ;;
    --kubernetes-version=*)
      kubernetes_version="${arg#*=}"
      ;;
    --master-ip=*)
      master_ip="${arg#*=}"
      ;;
    --apiserver-count=*)
      apiserver_count="${arg#*=}"
      ;;
    *)
      print_help
      exit 0
      ;;
  esac
done



# step 01 : check parameters

etcd_servers=""

if [ -z "$etcd_servers_ip" ]; then
  echo -e "\033[31m[ERROR] --etcd-servers-ip is absent\033[0m"
  exit 1
else
  # TODO etcd_servers wrapper
  IFS="," read -ra etcd_servers_ip_list <<< ${etcd_servers_ip}
  for ip in ${etcd_servers_ip_list[@]}
  do
    etcd_servers+="https://${ip}:${ETCD_CLIENT_PORT},"
  done
  etcd_servers=${etcd_servers%?}
fi


# step 02 : check if master_ip belong to this host

if [ $SINGLE_MASTER_AND_GEN_CERT_BY_ITSELF == "true" ]; then
  if [[ -z "$master_ip" ]]; then
    echo -e "\033[31m[ERROR] --master-ip is absent\033[0m"
    exit 1
  fi

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

  mkdir -p $APISERVER_CA_PATH

  openssl genrsa -out ca.key 2048
  openssl req -x509 -new -nodes -key ca.key -subj "/CN=${master_ip}" -days 36500 -out ca.crt

  echo "ts = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
O = Personal
CN = ${master_ip}

[ req_ext ]
subjectAltName = @alt_names


[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.${CLUSTER_DOMAIN}
IP.1 = 172.16.0.1 
IP.2 = 127.0.0.1
IP.3 = ${master_ip}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
" > ${APISERVER_CA_PATH}/master_ssl.cnf

  openssl genrsa -out ${APISERVER_CA_PATH}/apiserver.key 2048
  openssl req -new -key ${APISERVER_CA_PATH}/apiserver.key -config ${APISERVER_CA_PATH}/master_ssl.cnf -out ${APISERVER_CA_PATH}/apiserver.csr
  openssl x509 -req -in ${APISERVER_CA_PATH}/apiserver.csr -CA ${APISERVER_CA_PATH}/ca.crt -CAkey ${APISERVER_CA_PATH}/ca.key -CAcreateserial -out ${APISERVER_CA_PATH}/apiserver.crt -days 36500 -extensions v3_ext -extfile ${APISERVER_CA_PATH}/master_ssl.cnf
fi


# step 03: download and decompress kubernetes server installation package

# https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.18.md#server-binaries-6

wget -P /tmp https://dl.k8s.io/v1.18.14/kubernetes-server-linux-amd64.tar.gz

tar -zxvf /tmp/kubernetes-server-linux-amd64.tar.gz -C /tmp --no-same-owner

mv /tmp/kubernetes/server/bin/kube-apiserver /usr/local/bin/
mv /tmp/kubernetes/server/bin/kube-controller-manager /usr/local/bin/
mv /tmp/kubernetes/server/bin/kube-scheduler /usr/local/bin/
mv /tmp/kubernetes/server/bin/kubectl /usr/local/bin/


# step 05: generate the token.csv file

mkdir -p ${APISERVER_AUTH_PATH}

token=`echo $cluster_name | base64`
echo $token,k8s-node,0 > ${APISERVER_AUTH_PATH}/token.csv



# step 06: configure and start kube-apiserver by systemd

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
ExecStart=/usr/local/bin/kube-apiserver \$ETCD_SERVERS \\
          \$SERVICE_CLUSTER_IP_RANGE \\
          \$INSECURE_BIND_ADDRESS \\
          \$INSECURE_PORT \\
          \$SECURE_PORT \\
          \$KUBE_APISERVER_OPTS \\
          \$ETCD_CA_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/kube-apiserver.service


echo "# configure file for kube-apiserver

# --etcd-servers
ETCD_SERVERS='--etcd-servers=${etcd_servers}'
# --service-cluster-ip-range
SERVICE_CLUSTER_IP_RANGE='--service-cluster-ip-range=${service_cluster_ip_range}'
# --insecure-bind-address
INSECURE_BIND_ADDRESS='--insecure-bind-address=${apiserver_insecure_bind_address}'
# --insecure-port
INSECURE_PORT='--insecure-port=${apiserver_insecure_port}'
# --secure-port
SECURE_PORT='--secure-port=${apiserver_secure_port}'
# other parameters
KUBE_APISERVER_OPTS='--client-ca-file=${APISERVER_CA_PATH}/ca.crt --tls-private-key-file=${APISERVER_CA_PATH}/apiserver.key --tls-cert-file=${APISERVER_CA_PATH}/apiserver.crt --service-account-key-file=${APISERVER_CA_PATH}/apiserver.crt \\
--token-auth-file=${APISERVER_AUTH_PATH}/token.csv --kubelet-preferred-address-types=InternalIP,Hostname,InternalDNS,ExternalDNS,ExternalIP \\ 
--kubelet-client-certificate=${APISERVER_CA_PATH}/apiserver.crt --kubelet-client-key=${APISERVER_CA_PATH}/apiserver.key --apiserver-count=${apiserver_count}'
# etcd ca parameters
ETCD_CA_OPTS='--etcd-cafile=${APISERVER_CA_PATH}/ca.crt --etcd-certfile=${APISERVER_CA_PATH}/etcd_client.crt --etcd-keyfile=${APISERVER_CA_PATH}/etcd_client.key'
" > /etc/sysconfig/kube-apiserver

systemctl daemon-reload
systemctl start kube-apiserver
systemctl enable kube-apiserver
sleep 8
systemctl status -l kube-apiserver


# step 07: configure and start kube-controller-manager by systemd

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
ExecStart=/usr/local/bin/kube-controller-manager \$KUBE_MASTER \\
          \$KUBE_CONTROLLER_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/kube-controller-manager.service

echo "# configure file for kube-controller-manager

# --master
KUBE_MASTER='--master=http://${apiserver_insecure_bind_address}:${apiserver_insecure_port}'

# other parameters
KUBE_CONTROLLER_OPTS='--root-ca-file=${APISERVER_CA_PATH}/ca.crt --service-account-private-key-file=${APISERVER_CA_PATH}/apiserver.key --allocate-node-cidrs=true --cluster-cidr=${flannel_network_ip_range}'
" > /etc/sysconfig/kube-controller-manager

systemctl daemon-reload
systemctl start kube-controller-manager
systemctl enable kube-controller-manager
sleep 5
systemctl status -l kube-controller-manager


# step 08: configure and start kube-scheduler by systemd

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
ExecStart=/usr/local/bin/kube-scheduler \$KUBE_MASTER \\
          \$KUBE_SCHEDULER_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /usr/lib/systemd/system/kube-scheduler.service

echo "# configure file for kube-scheduler
# --master
KUBE_MASTER='--master=http://${apiserver_insecure_bind_address}:${apiserver_insecure_port}'

# other parameters
KUBE_SCHEDULER_OPTS=''
" > /etc/sysconfig/kube-scheduler

systemctl daemon-reload
systemctl start kube-scheduler
systemctl enable kube-scheduler
sleep 5
systemctl status -l kube-scheduler


# step 09: create cluster role、cluster role binding

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





















