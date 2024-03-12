#!/bin/bash


cluster_name=
etcd_servers_ip=

CERT_STORAGE_PATH="/etc/kubernetes/pki/"


function print_help() {
  echo -e "
  \033[0;33m ====== Generate and distribute etcd and ca cert ======

  Parameters explanation:

  --cluster-name       [required]  kubernetes cluster name. In the current directory, create a new folder with this --cluster-name to store certificates 
  --etcd-servers-ip    [required]  etcd servers' ip list, separeted by commas such as 10.0.0.1,10.0.0.2,10.0.0.3


  For example:

  /bin/sh generate_and_distribute_etcd_cert.sh --cluster-name=my-k8s --etcd-servers-ip=10.18.10.3,10.18.10.4,10.18.10.35 \033[0m
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
    *)
      print_help
      exit 0
      ;;
  esac
done


# step 01 : check parameters

if [ -z $cluster_name ]; then
  echo -e "\033[31m[ERROR] --cluster-name is absent, it's an important classfied path name to store your ca cert files in your localhost.\033[0m"
  exit 1
fi

if [ ! -d $cluster_name ]; then
  echo -e "\033[31m[ERROR] The directory of $cluster_name does not exist.\033[0m"
  exit 1 
fi

if [ -z $etcd_servers_ip ]; then
  echo -e "\033[31m[ERROR] --etcd-servers-ip is absent.\033[0m"
  exit 1
fi
echo "=== step 01 : [check parameters] Completed! "


# step 02 : generate etcd cert

IFS="," read -ra etcd_servers_ip_list <<< ${etcd_servers_ip}

if [ ! -f ./${cluster_name}/etcd/lock ]; then
  mkdir -p ${cluster_name}/etcd

  etcd_alt_names=""
  ip_count=1
  for ip in ${etcd_servers_ip_list[@]}; do
    etcd_alt_names+="IP.$((ip_count+1)) = $ip\n"
    ip_count=$((ip_count+1))
  done

  echo -e "[ req ]
req_extensions = v3_req
distinguished_name  = req_distinguished_name
[ req_distinguished_name ]

[ v3_req ]
basicConstraints = CA:FALSE
keyUsage = nonRepudiation, digitalSignature, keyEncipherment
subjectAltName=@alt_names

[ alt_names ]
IP.1 = 127.0.0.1
${etcd_alt_names}
" > ./${cluster_name}/etcd/etcd_ssl.conf


  openssl genrsa -out ./${cluster_name}/etcd/etcd_server.key 2048
  openssl req -new -key ./${cluster_name}/etcd/etcd_server.key -config ./${cluster_name}/etcd/etcd_ssl.conf -subj "/CN=etcd-server" -out ./${cluster_name}/etcd/etcd_server.csr
  openssl x509 -req -in ./${cluster_name}/etcd/etcd_server.csr -CA ./${cluster_name}/ca/ca.crt -CAkey ./${cluster_name}/ca/ca.key -CAcreateserial -days 36500 -extensions v3_req -extfile ./${cluster_name}/etcd/etcd_ssl.conf -out ./${cluster_name}/etcd/etcd_server.crt

  openssl genrsa -out ./${cluster_name}/etcd/etcd_client.key 2048
  openssl req -new -key ./${cluster_name}/etcd/etcd_client.key -config ./${cluster_name}/etcd/etcd_ssl.conf -subj "/CN=etcd-client" -out ./${cluster_name}/etcd/etcd_client.csr
  openssl x509 -req -in ./${cluster_name}/etcd/etcd_client.csr -CA ./${cluster_name}/ca/ca.crt -CAkey ./${cluster_name}/ca/ca.key -CAcreateserial -days 36500 -extensions v3_req -extfile ./${cluster_name}/etcd/etcd_ssl.conf -out ./${cluster_name}/etcd/etcd_client.crt

  echo "This is a lock file to prevent you from repeatedly creating etcd certificates." > ./${cluster_name}/etcd/lock
  echo "=== step 02 : [generate etcd cert] Completed! "
else
  echo "=== step 02 : [generate etcd cert] Etcd certificates have already existed! Skip the distribution step!"
  exit 0
fi


# step 03 : distribute etcd cert

for ip in ${etcd_servers_ip_list[@]}
do
  ssh ${ip} -q -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no mkdir -p ${CERT_STORAGE_PATH}
  scp ./${cluster_name}/ca/ca.crt ./${cluster_name}/etcd/etcd_server.key ./${cluster_name}/etcd/etcd_server.crt root@${ip}:${CERT_STORAGE_PATH}
done
echo "=== step 03 : [distribute etcd cert] Completed! "
















