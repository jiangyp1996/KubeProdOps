#!/bin/bash


cluster_name=
distribute_target=
etcd_ip_list=
master_ip_list=
worker_ip_list=

CERT_STORAGE_PATH="/etc/kubernetes/pki/"


function print_help() {
  echo -e "
  \033[0;33m====== distribute ca.key and ca.crt to ETCD or MASTER or WORKER ======

  Parameters explanation:

  --cluster-name         [required]  kubernetes cluster name.
  --distribution-target  [required]  etcd, master and worker. You can select one or all, separated by commas.
  --etcd-ip-list         [optional]  If etcd is one of your distribution targets, please list etcd IPs, separated by commas.
  --master-ip-list		 [optional]  If master is one of your distribution targets, please list master IPs, separated by commas.
  --worker-ip-list       [optional]  If worker is one of your distribution targets, please list worker IPs, separated by commas.

  For example: 

  bash distribute_ca_cert.sh --cluster-name=my-k8s --distribute-target=etcd,master --etcd-ip-list=192.168.18.3 --master-ip-list=192.168.18.3,192.168.18.4
  "
}


for arg in "$@"
do
  case $arg in
    --cluster-name=*)
      cluster_name="${arg#*=}"
      ;;
    --distribute-target=*)
      distribute_target="${arg#*=}"
      ;;
    --etcd-ip-list=*)
      etcd_ip_list="${arg#*=}"
      ;;
    --master-ip-list=*)
      master_ip_list="${arg#*=}"
      ;;
    --worker-ip-list=*)
      worker_ip_list="${arg#*=}"
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

if [ -z $distribute_target ]; then
  echo -e "\033[31m[ERROR] --distribute-target is absent, do nothing.\033[0m"
  exit 1
fi


# step 02 : distribute ca cert

function distribute() {
  if [ -n $1 ]; then
  	echo "=== distribute ca.cart to $2"
    IFS="," read -ra ip_list <<< $1
    for ip in ${ip_list[@]}
    do
      ssh ${ip} -q -o PreferredAuthentications=publickey -o StrictHostKeyChecking=no mkdir -p ${CERT_STORAGE_PATH}
      scp ./${cluster_name}/ca/ca.crt root@${ip}:${CERT_STORAGE_PATH}
    done
  fi
}

IFS="," read -ra distribute_target_list <<< ${distribute_target}
for target in ${distribute_target_list[@]}
do 
  echo "=== current target is : ${target}" 
  if [ $target == "etcd" ]; then
  	distribute ${etcd_ip_list} ${target}
  elif [ $target == "master" ]; then
  	distribute ${master_ip_list} ${target}
  elif [ $target == "worker" ]; then
  	distribute ${worker_ip_list} ${target}
  fi
done






