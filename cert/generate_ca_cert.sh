#!/bin/bash


cluster_name=
master_ip=


function print_help() {
  echo -e "
  \033[0;33m====== Generate ca.key and ca.crt ======

  Parameters explanation:

  --cluster-name       [required]  kubernetes cluster name. In the current directory, create a new folder to store CA certificates.
  --vip                [required]  kubernetes master vip. 
  "
}


for arg in "$@"
do
  case $arg in
    --cluster-name=*)
      cluster_name="${arg#*=}"
      ;;
    --vip=*)
      vip="${arg#*=}"
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

if [ -z $vip ]; then
  echo -e "\033[31m[ERROR] --vip is absent.\033[0m"
  exit 1
fi


# step 02 : generate ca cert

if [ ! -f ./${cluster_name}/lock ]; then
  mkdir -p ${cluster_name}/ca

  openssl genrsa -out ./${cluster_name}/ca/ca.key 2048
  openssl req -x509 -new -nodes -key ./${cluster_name}/ca/ca.key -subj "/CN=${vip}" -days 36500 -out ./${cluster_name}/ca/ca.crt

  echo "This is a lock file to prevent you from repeatedly creating ca certificates." > ./${cluster_name}/lock
fi











