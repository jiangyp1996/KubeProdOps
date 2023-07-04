#!/bin/bash


# STEP 01: check arguments
# STEP 02: get local node ip and check it with cluster-nodes
# STEP 03: Download and place etcd + etcdctl
# STEP 04: configure and start etcd
 

AVAILABLE_ETCD_VERSION=("3.2.11" "3.5.4")
ETCD_VERSION="3.5.4"
ETCD_INSTALL_PATH="/usr/sbin/etcd"
CLUSTER_TOKEN="etcd-cluster"
NAME_PREFIX="kubeEtcd"
PEER_PORT=4010
CLIENT_PORT=4012
ETCD_OPTS=""



function command_exists ()
{
  command -v "$@" > /dev/null 2>&1
}

function help ()
{
  echo "
Usage:
  start_etcd.sh [options]
  start_etcd.sh [command]

Available Commands:
  help   show the help information about start_etcd.sh.

Options:
  --cluster-nodes    (REQUIRED) a comma-delimited list of node ips in the cluster, includes current node ip (e.g. 0.0.0.1,0.0.0.2,0.0.0.3).
  --client-port      port to listen on for client traffic (default $CLIENT_PORT).
  --data-path        path to the data directory (default /var/lib/etcd).
  --etcd-version     etcd version, supported version: ${AVAILABLE_ETCD_VERSION[@]} (default $ETCD_VERSION).
  --peer-port        port to listen on for peer traffic (default $PEER_PORT).
"
}

if [[ "$1" =~ "help" ]] || [ -z "$1" ]; then
  help
  exit 1
fi



# STEP 01: check arguments
echo -e "\033[36m[INFO] STEP 01: Check input arguments...\033[0m"
OPTS=$(getopt -o : --long cluster-nodes:,client-port:,data-path:,etcd-version:,peer-port: -- "$@")

if [ $? != 0 ]; then
  echo -e "\033[31m[ERROR] start_etcd.sh argument is illegal\033[0m"
fi

eval set -- "$OPTS"

cluster_nodes=
cluster_nodes_array=
client_port=
data_path=
etcd_version=
peer_port=
while true ; do
  case "$1" in
    --cluster-nodes) cluster_nodes=$2; shift 2;;
    --client-port) client_port=$2; shift 2;;
    --data-path) data_path=$2; shift 2;;
    --etcd-version) etcd_version=$2; shift 2;;
    --peer-port) peer_port=$2; shift 2;;
    --) shift; break;;
  esac
done

if [ -z "$cluster_nodes" ]; then
  echo -e "\033[31m[ERROR] --cluster-nodes is absent\033[0m"
  exit 1
else
  echo "--cluster-nodes: $cluster_nodes"
fi

if [ -z "$client_port" ]; then
  echo -e "\033[36m[INFO] --clint-port is absent, default '$CLIENT_PORT'\033[0m"
  client_port=$CLIENT_PORT
else
  echo "--client-port: $clint_port"
fi

if [ -z "$data_path" ]; then
  echo -e "\033[36m[INFO] --data-path is absent, default '/var/lib/etcd'\033[0m"
  data_path="/var/lib/etcd"
else
  echo "--data-path: $data_path"
fi

if [ -z "$etcd_version" ]; then
  echo -e "\033[36m[INFO] --etcd-version is absent, default '$ETCD_VERSION'\033[0m"
  etcd_version=$ETCD_VERSION
else
  available="false"
  for i in ${AVAILABLE_ETCD_VERSION[@]} ; do
    if [ "$i" == "$etcd_version" ]; then
      available="true"
      break
    fi
  done
  if [ "$available" == "true" ]; then
    echo "--etcd-version: $etcd_version"
  else
    echo -e "\033[31m[ERROR] this shell script does not provide ETCD $etcd_version package, you have to configure etcd cluster by yourself.\033[0m"
    exit 1
  fi
fi

if [ -z "$peer_port" ]; then
  echo -e "\033[36m[INFO] --peer-port is absent, default '$PEER_PORT'\033[0m"
  peer_port=$PEER_PORT
else
  echo "--peer-port: $peer_port"
fi
echo -e "\033[32m[OK] start_etcd.sh arguments are legal\033[0m"


# STEP 02: get local node ip and check it with cluster-nodes
echo -e "\033[36m[INFO] STEP 02: Get and check local node IP address...\033[0m"
local_ips=(`ip addr show | grep inet | grep -v inet6 | grep brd | awk '{print $2}' | cut -f1 -d '/'`)
if [ -z "$local_ips" ]; then
  echo -e "\033[31m[ERROR] Get local IP address error\033[0m"
  exit 1
fi

local_ip=
cluster_nodes_array=(${cluster_nodes//,/ })
available="false"
node_id=0
for i in ${cluster_nodes_array[@]} ; do
  for localip in ${local_ips[@]} ; do
    if [ "$i" == "$localip" ]; then
      available="true"
      local_ip=$i
      break
    fi
  done
  let node_id++
done

if [ "$available" == "false" ]; then
  echo -e "\033[31m[ERROR] local node($local_ip) is not a part of --cluster-nodes($cluster_nodes)\033[0m"
  exit 1
else
  echo "\033[36m[INFO] Use local node IP address: $local_ip\033[0m"
fi


# STEP 03: deal with etcd and etcdctl
echo -e "\033[36m[INFO] STEP 03: Deal with etcd and etcdctl...\033[0m"
mkdir -p $data_path
mkdir -p $ETCD_INSTALL_PATH/$etcd_version
chmod +x /tmp/etcd
chmod +x /tmp/etcdctl
mv /tmp/etcd $ETCD_INSTALL_PATH/$etcd_version/
mv /tmp/etcdctl $ETCD_INSTALL_PATH/$etcd_version/
ln -fsn $ETCD_INSTALL_PATH/$etcd_version $ETCD_INSTALL_PATH/current


# STEP 04: configure and start etcd
echo -e "\033[36m[INFO] STEP 04: Configure and start etcd...\033[0m"
format_cluster_nodes=
node_id_p=0
for i in ${cluster_nodes_array[@]} ; do
  format_cluster_nodes="$format_cluster_nodes,$NAME_PREFIX$node_id_p=http://$i:$peer_port"
  let node_id_p++
done
format_cluster_nodes=$(echo $format_cluster_nodes | sed -e 's/,//')

if command_exists systemctl ; then
  mkdir -p /etc/sysconfig
  systemctl stop etcd
  echo "# configure file for etcd.service
# -name
ETCD_NODE_NAME='-name $NAME_PREFIX$node_id'
# -initial-advertise-peer-urls
INITIAL_ADVERTISE_PEER_URLS='-initial-advertise-peer-urls http://$local_ip:$peer_port'
# -listen-peer-urls
LISTEN_PEER_URLS='-listen-peer-urls http://0.0.0.0:$peer_port'
# -advertise-client-urls
ADVERTISE_CLIENT_URLS='-advertise-client-urls http://$local_ip:$client_port'
# -listen-client-urls
LISTEN_CLIENT_URLS='-listen-client-urls http://0.0.0.0:$client_port'
# -initial-cluster-token
INITIAL_CLUSTER_TOKEN='-initial-cluster-token $CLUSTER_TOKEN'
# -initial-cluster
INITIAL_CLUSTER='-initial-cluster $format_cluster_nodes'
# -initial-cluster-state
INITIAL_CLUSTER_STATE='-initial-cluster-state new'
# -data-dir
DATA_DIR='-data-dir $data_path'
# other parameters
ETCD_OPTS='$ETCD_OPTS'
" > /etc/sysconfig/etcd
echo "[Unit]
Description=ETCD
[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/etcd
ExecStart=$ETCD_INSTALL_PATH/current/etcd \$ETCD_NODE_NAME \\
          \$INITIAL_ADVERTISE_PEER_URLS \\
          \$LISTEN_PEER_URLS \\
          \$ADVERTISE_CLIENT_URLS \\
          \$LISTEN_CLIENT_URLS \\
          \$INITIAL_CLUSTER_TOKEN \\
          \$INITIAL_CLUSTER \\
          \$INITIAL_CLUSTER_STATE \\
          \$DATA_DIR \\
          \$ETCD_OPTS
Restart=always
[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/etcd.service
  systemctl daemon-reload
  systemctl enable etcd
  set -e
  systemctl start etcd
  echo -e "\033[32m[OK] start etcd\033[0m"
  set +e
else
  echo -e "\033[31m[ERROR] There is no systemctl in this host, please install it.\033[0m"
fi
