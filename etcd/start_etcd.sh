#!/bin/bash


# parameters 
cluster_nodes=
data_path=/data
etcd_version=3.5.4

# constants
ETCD_INSTALLATION_PATH="/usr/sbin/etcd"
CLUSTER_TOKEN="etcd-cluster"
NAME_PREFIX="kubeEtcd"
CLIENT_PORT=2379
PEER_PORT=2380
ETCD_OPTS="--enable-v2=true --cert-file=/etc/kubernetes/pki/etcd_server.crt --key-file=/etc/kubernetes/pki/etcd_server.key --trusted-ca-file=/etc/kubernetes/pki/ca.crt --client-cert-auth=true --peer-cert-file=/etc/kubernetes/pki/etcd_server.crt --peer-key-file=/etc/kubernetes/pki/etcd_server.key --peer-trusted-ca-file=/etc/kubernetes/pki/ca.crt --peer-client-cert-auth=true"


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
		--cluster-nodes=*)
      cluster_nodes="${arg#*=}"
      ;;
    --data-path=*)
      data_path="${arg#*=}"
      ;;
    --etcd-version=*)
      etcd_version="${arg#*=}"
      ;;
    *)
      print_help
      exit 0
      ;;
    esac
done


# step 01: check parameters

if [ -z "$cluster_nodes" ]; then
  echo -e "\033[31m[ERROR] --cluster-nodes is absent\033[0m"
  exit 1
else
  echo "--cluster-nodes: $cluster_nodes"
fi

mkdir -p ${root_dir}/etcd


# step 02: check if local IP is in cluster_nodes

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
done

if [ "$available" == "false" ]; then
  echo -e "\033[31m[ERROR] local node($local_ip) is not a part of --cluster-nodes($cluster_nodes)\033[0m"
  exit 1
fi

for i in ${cluster_nodes_array[@]} ; do
  if [ "$i" == "$local_ip" ]; then
    break
  fi
  let node_id++
done


# step 03: process etcd and etcdctl binary package

mkdir -p ${ETCD_INSTALLATION_PATH}/${etcd_version}
chmod +x /tmp/etcd
chmod +x /tmp/etcdctl
mv /tmp/etcd* ${ETCD_INSTALLATION_PATH}/${etcd_version}/
ln -fsn ${ETCD_INSTALLATION_PATH}/${etcd_version} ${ETCD_INSTALLATION_PATH}/current


# step 04: start etcd

format_cluster_nodes=
node_id_index=0
for i in ${cluster_nodes_array[@]} ; do
  format_cluster_nodes="${format_cluster_nodes},${NAME_PREFIX}${node_id_index}=https://${i}:${PEER_PORT}"
  let node_id_index++
done
format_cluster_nodes=$(echo ${format_cluster_nodes} | sed -e 's/,//')

if command_exists systemctl ; then
  mkdir -p /etc/sysconfig
  systemctl stop etcd
  echo "# configure file for etcd.service
# -name
ETCD_NODE_NAME='-name ${NAME_PREFIX}${node_id}'
# -initial-advertise-peer-urls
INITIAL_ADVERTISE_PEER_URLS='-initial-advertise-peer-urls https://${local_ip}:${PEER_PORT}'
# -listen-peer-urls
LISTEN_PEER_URLS='-listen-peer-urls https://0.0.0.0:${PEER_PORT}'
# -advertise-client-urls
ADVERTISE_CLIENT_URLS='-advertise-client-urls https://${local_ip}:${CLIENT_PORT}'
# -listen-client-urls
LISTEN_CLIENT_URLS='-listen-client-urls https://0.0.0.0:${CLIENT_PORT}'
# -initial-cluster-token
INITIAL_CLUSTER_TOKEN='-initial-cluster-token ${CLUSTER_TOKEN}'
# -initial-cluster
INITIAL_CLUSTER='-initial-cluster ${format_cluster_nodes}'
# -initial-cluster-state
INITIAL_CLUSTER_STATE='-initial-cluster-state new'
# -data-dir
DATA_DIR='-data-dir ${data_path}'
# other parameters
ETCD_OPTS='${ETCD_OPTS}'
" > /etc/sysconfig/etcd

  echo "[Unit]
Description=ETCD
[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/etcd
ExecStart=$ETCD_INSTALLATION_PATH/current/etcd \$ETCD_NODE_NAME \\
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

