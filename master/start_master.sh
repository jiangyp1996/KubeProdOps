#!/bin/bash

# STEP 02: check arguments

# STEP 03: check host IP

# STEP 04: download and decompress installation package

# STEP 06: add DNS server into resolv.conf 

# STEP 07: add hostname and IP address to /etc/hosts

# STEP 12: start kube-apiserver

# STEP 13: start kube-controller-manager

# STEP 14: start kube-scheduler

# STEP 14: create cluster role、cluster role binding、canary deployment


# parameters 
etcd_servers=
etcd_prefix=/
service_cluster_ip_range=
cluster_dns=
cluster_name=
insecure_bind_address=127.0.0.1
apiserver_insecure_port=8080
apiserver_secure_port=6443
kubernetes_version=1.18.14
master_ip=



# constants
APISERVER_CA_PATH="/etc/kubernetes/pki"
APISERVER_AUTH_PATH="/etc/kubernetes/auth"



print_help() {
  echo -e "
  \033[0;33mParameters explanation:

  --cluster-nodes      [required]  etcd cluster peer nodes
  --data-path          [required]  etcd data storage root path
  --etcd_version       [required]  etcd version, default 3.5.4\033[0m
  "
}

command_exists ()
{
  command -v "$@" > /dev/null 2>&1
}



for arg in "$@"
do
  case $arg in
    --etcd-servers=*)
      etcd_servers="${arg#*=}"
      ;;
    --etcd-prefix=*)
      etcd_prefix="${arg#*=}"
      ;;
    --service-cluster-ip-range=*)
      service_cluster_ip_range="${arg#*=}"
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
			

cluster_domain=${cluster_name}.cluster.local



# step 01 : check arguments

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


# STEP 03: download and decompress installation package

# https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.18.md#server-binaries-6

wget -P /tmp https://domeos-script.bjcnc.scs.sohucs.com/jiang/kubeProdOps/master.tar.gz

tar -zxvf /tmp/master.tar.gz -C /tmp --no-same-owner

cp /tmp/master/kube* /usr/bin/

rm -rf /tmp/master /tmp/master.tar.gz


# STEP 04: CA

mkdir -p $APISERVER_CA_PATH
mkdir -p $APISERVER_AUTH_PATH

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
DNS.4 = kubernetes.default.svc.${cluster_domain}
IP.1 = 172.16.0.1 
IP.2 = 127.0.0.1
IP.3 = ${master_ip}
" > master_ssl.conf

openssl genrsa -out apiserver.key 2048
openssl req -new -key apiserver.key -config master_ssl.cnf -subj "/CN=${master_ip}" -out apiserver.csr
openssl x509 -req -in apiserver.csr -CA ca.crt -CAkey ca.key -CAcreateserial -days 36500 -extensions v3_req -extfile master_ssl.cnf -out apiserver.crt

mv ca.key $APISERVER_CA_PATH
mv ca.crt $APISERVER_CA_PATH
mv master_ssl.conf $APISERVER_CA_PATH
mv apiserver.key $APISERVER_CA_PATH
mv apiserver.csr $APISERVER_CA_PATH
mv apiserver.crt $APISERVER_CA_PATH



# STEP 05: start kube-apiserver

# STEP 06: start kube-controller-manager

# STEP 07: start kube-scheduler






















