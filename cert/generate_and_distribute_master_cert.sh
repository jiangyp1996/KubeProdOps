#!/bin/bash


cluster_name=
master_servers_ip=
vip=
cluster_domain="cluster.local"


CERT_STORAGE_PATH="/etc/kubernetes/pki/"


function print_help() {
  echo -e "
  \033[0;33m ====== Generate and distribute master and ca cert ======

  Parameters explanation:

  --cluster-name       [required]  kubernetes cluster name. In the current directory, create a new folder with this --cluster-name to store certificates 
  --master-servers-ip  [required]  master servers' ip list, separeted by commas such as 10.0.0.1,10.0.0.2,10.0.0.3
  --vip                [optional]  vitual IP, usually used when deploying a highly available master. If vip is absent, --master-servers-ip has only one ip.
  --cluster-domain     [optional]  kubernetes cluster-domain, default cluster.local

  
  For examply: 

  /bin/sh generate_and_distribute_master_cert.sh --cluster-name=my-k8s --master-servers-ip=10.18.10.1,10.18.10.2 --vip=10.18.10.100 \033[0m
  "
}


for arg in "$@"
do
  case $arg in
    --master-servers-ip=*)
      master_servers_ip="${arg#*=}"
      ;;
    --cluster-name=*)
      cluster_name="${arg#*=}"
      ;;
    --vip=*)
      vip="${arg#*=}"
      ;;
    --cluster-domain=*)
      cluster_domain="${arg#*=}"
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

if [ -z $master_servers_ip ]; then
  echo -e "\033[31m[ERROR] --master-servers-ip is absent.\033[0m"
  exit 1
fi

IFS="," read -ra master_servers_ip_list <<< ${master_servers_ip}
master_count=0
cert_alt_names_ips=""

for ip in ${master_servers_ip_list[@]}
do
  master_count=$((master_count+1))
  cert_alt_names_ips+="IP.$((master_count+2)) = $ip\n"
done

if [ -z $vip ]; then
  if [ $master_count > 1 ]; then
    echo -e "\033[31m[ERROR] --vip is absent, but you have transferred at least two master ip.\033[0m"
    exit 1
  elif [ $master_count == 0 ]; then
    echo -e "\033[31m[ERROR] --vip is absent, but you have transferred zero master ip.\033[0m"
    exit 1
  else
    vip=${master_servers_ip}
  fi
else
  master_count=$((master_count+1))
  cert_alt_names_ips+="IP.$((master_count+2)) = $vip\n"
fi
echo "=== step 01 : [check parameters] Completed! "


# step 02 : generate master cert

if [ ! -f ./${cluster_name}/master/lock ]; then
  mkdir -p ${cluster_name}/master

  echo -e "ts = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
O = Personal
CN = ${vip}

[ req_ext ]
subjectAltName = @alt_names


[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.${cluster_domain}
IP.1 = 172.16.0.1 
IP.2 = 127.0.0.1
${cert_alt_names_ips}

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
" > ./${cluster_name}/master/master_ssl.conf

  openssl genrsa -out ./${cluster_name}/master/apiserver.key 2048
  openssl req -new -key ./${cluster_name}/master/apiserver.key -config ./${cluster_name}/master/master_ssl.conf -out ./${cluster_name}/master/apiserver.csr
  openssl x509 -req -in ./${cluster_name}/master/apiserver.csr -CA ./${cluster_name}/ca/ca.crt -CAkey ./${cluster_name}/ca/ca.key -CAcreateserial -out ./${cluster_name}/master/apiserver.crt -days 36500 -extensions v3_ext -extfile ./${cluster_name}/master/master_ssl.conf

  echo "This is a lock file to prevent you from repeatedly creating master certificates." > ./${cluster_name}/master/lock
  echo "=== step 02 : [generate master cert] Completed! "
else
  echo "=== step 02 : [generate master cert] Master certificates have already existed! Skip the distribution step!"
  exit 0
fi


# step 03 : distribute master cert

for ip in ${master_servers_ip_list[@]}
do
  ssh ${ip} -q -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no mkdir -p ${CERT_STORAGE_PATH}
  scp ./${cluster_name}/ca/ca.crt ./${cluster_name}/master/apiserver.key ./${cluster_name}/master/apiserver.crt ./${cluster_name}/etcd/etcd_client.key ./${cluster_name}/etcd/etcd_client.crt root@${ip}:${CERT_STORAGE_PATH}
done
echo "=== step 03 : [distribute master cert] Completed! "






