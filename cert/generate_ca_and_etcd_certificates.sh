#!/bin/bash

cluster_name=
master_ip=
etcd_servers_ip=


function print_help() {
  echo -e "
  \033[0;33mParameters explanation:

  --cluster-name       [required]  kubernetes cluster name. In the current directory, create a new folder with this --cluster-name to store CA and ETCD certificates.
  --master-ip          [required]  kubernetes master ip. 
  --etcd-servers-ip    [required]  etcd servers' ip list, separeted by commas such as 10.0.0.1,10.0.0.2,10.0.0.3\033[0m
  "
}


for arg in "$@"
do
  case $arg in
    --etcd-servers-ip=*)
      etcd_servers_ip="${arg#*=}"
      ;;
    --cluster-name=*)
      cluster_name="${arg#*=}"
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


# check parameters

if [ -z $cluster_name ]; then
  echo -e "\033[31m[ERROR] --cluster-name is absent, it's an important classfied path name to store your ca cert files in your localhost.\033[0m"
  exit 1
fi

if [ -z $master_ip ]; then
  echo -e "\033[31m[ERROR] --master-ip is absent.\033[0m"
  exit 1
fi

if [ -z $etcd_servers_ip ]; then
  echo -e "\033[31m[ERROR] --etcd-servers-ip is absent.\033[0m"
  exit 1
fi


# generate cert files

etcd_servers_ip_list=$(echo ${etcd_servers_ip} | awk -F= '{print $2}' | tr ',' '\n')

if [ ! -f ./${cluster_name}/lock ]; then
  mkdir -p ${cluster_name}/ca
  mkdir -p ${cluster_name}/etcd

  # step 1 : generate ca files
  openssl genrsa -out ./${cluster_name}/ca/ca.key 2048
  openssl req -x509 -new -nodes -key ./${cluster_name}/ca/ca.key -subj "/CN=${master_ip}" -days 36500 -out ./${cluster_name}/ca/ca.crt

  # step 2 : generate etcd files

  echo "[ req ]
req_extensions = v3_req
distinguished_name  = req_distinguished_name
[ req_distinguished_name ]

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName=@alt_names

[ alt_names ]
" > ./${cluster_name}/etcd/etcd_ssl.cnf

  index=1
  for ip in ${etcd_servers_ip_list}
  do
    echo "IP.$index = $ip" >> ./${cluster_name}/etcd/etcd_ssl.cnf
    ((index++))
  done

  openssl genrsa -out ./${cluster_name}/etcd/etcd_server.key 2048
  openssl req -new -key ./${cluster_name}/etcd/etcd_server.key -config ./${cluster_name}/etcd/etcd_ssl.conf -subj "/CN=etcd-server" -out ./${cluster_name}/etcd/etcd_server.csr
  openssl x509 -req -in ./${cluster_name}/etcd/etcd_server.csr -CA ./${cluster_name}/ca/ca.crt -CAkey ./${cluster_name}/ca/ca.key -CAcreateserial -days 36500 -extensions v3_req -extfile ./${cluster_name}/etcd/etcd_ssl.conf -out ./${cluster_name}/etcd/etcd_server.crt

  openssl genrsa -out ./${cluster_name}/etcd/etcd_client.key 2048
  openssl req -new -key ./${cluster_name}/etcd/etcd_client.key -config ./${cluster_name}/etcd/etcd_ssl.conf -subj "/CN=etcd-client" -out ./${cluster_name}/etcd/etcd_client.csr
  openssl x509 -req -in ./${cluster_name}/etcd/etcd_client.csr -CA ./${cluster_name}/ca/ca.crt -CAkey ./${cluster_name}/ca/ca.key -CAcreateserial -days 36500 -extensions v3_req -extfile ./${cluster_name}/etcd/etcd_ssl.conf -out ./${cluster_name}/etcd/etcd_client.crt

  echo "" > ./${cluster_name}/lock
fi


# sent to remote ip

CERT_STORAGE_PATH="/etc/kubernetes/pki/"
for ip in ${etcd_servers_ip_list}
do
  ssh ${ip} -q -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no mkdir -p ${CERT_STORAGE_PATH}
  scp ./${cluster_name}/ca/ca.crt ./${cluster_name}/etcd/etcd_server.key ./${cluster_name}/etcd/etcd_server.crt root@${ip}:${CERT_STORAGE_PATH}
done

ssh ${master_ip} -q -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no mkdir -p ${CERT_STORAGE_PATH}
scp ./${cluster_name}/ca/ca.crt ./${cluster_name}/etcd/etcd_client.key ./${cluster_name}/etcd/etcd_client.crt root@${master_ip}:${CERT_STORAGE_PATH}





