#!/bin/bash


# parameters
cluster_name=
master_ip=
apiserver_secure_port=6443
container_data_root="/data"
cluster_dns="172.16.40.1"
k8s_version="1.18.4"


# constants
KUBE_CONFIG_FILE="/etc/sysconfig/kubeconfig"
APISERVER_CA_PATH="/etc/kubernetes/pki"
CLUSTER_DOMAIN="cluster.local"


for arg in "$@"
do
  case $arg in
    --cluster-name=*)
      cluster_name="${arg#*=}"
      ;;
    --master-ip=*)
      master_ip="${arg#*=}"
      ;;
    --apiserver-secure-port=*)
      apiserver_secure_port="${arg#*=}"
      ;;
    --container-data-root=*)
      container_data_root="${arg#*=}"
      ;;
    --cluster-dns=*)
      cluster_dns="${arg#*=}"
      ;;
    --k8s-version=*)
      k8s_version="${arg#*=}"
      ;;
    *)
      print_help
      exit 0
      ;;
  esac
done


function command_exists ()
{
  command -v "$@" > /dev/null 2>&1
}

function service_exists ()
{
  systemctl list-unit-files | grep $1 > /dev/null 2>&1
}

function print_help() {
  echo -e "
  \033[0;33mParameters explanation:

  --cluster-name                   [required]  cluster name, such as my-k8s
  --master-ip                      [required]  master ip
  --apiserver-secure-port          [optional]  apiserver secure port, default 6443
  --container-data-root            [optional]  the storage path of pod and container, default /data
  --cluster-dns                    [optional]  CoreDNA Service IP, default 172.16.40.1
  \033[0m
  "
}


# step 01 : check linux kernel version

echo -e "\033[36m[INFO] STEP 01: Check linux kernel version and curl/wget tools...\033[0m"
kernel_version=$(uname -r)
if [ -z "$kernel_version" ]; then
  echo -e "\033[31m[ERROR] Get kernel version error, kernel must be 3.10.0 at minimum\033[0m"
  exit 1
fi

kernel_parts_tmp=(${kernel_version//-/ })
kernel_parts=(${kernel_parts_tmp[0]//./ })
if [ ${kernel_parts[0]} -lt 3 ]; then
  echo -e "\033[31m[ERROR] Kernel version must be 3.10.0 at minimum, current version is ${kernel_parts_tmp[0]}\033[0m"
  exit 1
fi
if [ ${kernel_parts[0]} -eq 3 ] && [ ${kernel_parts[1]} -lt 10 ]; then
  echo -e "\033[31m[ERROR] Kernel version must be 3.10.0 at minimum, current version is ${kernel_parts_tmp[0]}\033[0m"
  exit 1
fi

if ! command_exists curl; then
  yum install -y curl
fi
if ! command_exists wget; then
  yum install -y wget
fi
echo -e "\033[32m[OK] Check kernel OK, current kernel version is ${kernel_parts_tmp[0]}\033[0m"



# step 02 : check parameters

if [ -z $cluster_name ]; then
  echo -e "\033[31m[ERROR] --cluster-name is absent.\033[0m"
  exit 1
fi

if [ -z $master_ip ]; then
  echo -e "\033[31m[ERROR] --master-ip is absent.\033[0m"
  exit 1
fi


# step 03 : configure sysctl

echo -e "\033[36m[INFO] STEP 03: Configure sysctl\033[0m"

if [ $(grep -c KubeProdOps /etc/sysctl.conf) -eq 0 ]; then
  echo "# set by KubeProdOps
net.ipv4.neigh.default.gc_thresh1 = 512
net.ipv4.neigh.default.gc_thresh2 = 1024
net.ipv4.neigh.default.gc_thresh3 = 2048
net.ipv4.ip_forward = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_tw_recycle = 0
fs.inotify.max_user_watches = 1048576
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.tcp_syncookies = 1
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 85535
net.ipv4.tcp_rmem=4096 87382 67108864
net.ipv4.tcp_wmem=4096 87380 67108864
net.core.rmem_max=134217728
net.core.wmem_max=134217728" >> /etc/sysctl.conf
  sysctl -p 
fi


# step 04 : generate kubeconfig

echo -e "\033[36m[INFO] STEP 04: Generate kubeconfig...\033[0m"

mkdir -p $(dirname ${KUBE_CONFIG_FILE})
mkdir -p ${APISERVER_CA_PATH}
if [ ! -f /tmp/ca.crt ]; then
	echo -e "\033[31m[ERROR] File /tmp/ca.crt does not exist. Please check whether generate_ca_and_etcd_certificates.sh is executed.\033[0m"
	exit 1
fi
mv /tmp/ca.crt ${APISERVER_CA_PATH}

token=`echo ${cluster_name} | base64`
echo "apiVersion: v1
clusters:
- cluster:
    certificate-authority: ${APISERVER_CA_PATH}/ca.crt
    server: https://${master_ip}:${apiserver_secure_port}
  name: default
contexts:
- context:
    cluster: default
    user: k8s-node
  name: default
current-context: default
kind: Config
preferences: {}
users:
- name: k8s-node
  user:
    token: ${token}" > ${KUBE_CONFIG_FILE}


# step 05 : add DNS server into resolv.conf

echo -e "\033[36m[INFO] STEP 05: Add DNS server into resolv.conf...\033[0m"

cluster_dns_search="default.svc.${CLUSTER_DOMAIN} svc.${CLUSTER_DOMAIN} ${CLUSTER_DOMAIN}"
host_self_dns=
host_self_dns_p=0

while IFS='' read -r line || [[ -n "$line" ]]; do
  name_tmp=$(echo $line | cut -f1 -d ' ')
  value_tmp=$(echo $line | cut -f2- -d ' ')
  if [ ${name_tmp} == "nameserver" ]; then
    if [ ${value_tmp} != ${cluster_dns} ]; then
      host_self_dns[${host_self_dns_p}]="$line"
      let host_self_dns_p++
    fi
  elif [ ${name_tmp} == "search" ]; then
    if [ ${cluster_dns_search} != ${value_tmp} ]; then
      host_self_dns[${host_self_dns_p}]="$line"
      let host_self_dns_p++
    fi
  else
    host_self_dns[${host_self_dns_p}]="$line"
    let host_self_dns_p++
  fi
done < /etc/resolv.conf

set -e
chattr -i /etc/resolv.conf
sed -i -e "/cluster.local/d" /etc/resolv.conf
echo "search ${cluster_dns_search}" > /etc/resolv.conf
echo "nameserver ${cluster_dns}" >> /etc/resolv.conf
for i in "${host_self_dns[@]}"
do
  echo $i >> /etc/resolv.conf
done
set +e


# step 06 : download kubernetes-node-linux-amd64.tar.gz and docker-19.03.14.tgz

echo -e "\033[36m[INFO] STEP 06: Download kubernetes-node-linux-amd64.tar.gz and docker-19.03.14.tgz...\033[0m"

if [ ! -f "/tmp/kubernetes-node-linux-amd64.tar.gz" ]; then
  wget https://dl.k8s.io/v${k8s_version}/kubernetes-node-linux-amd64.tar.gz -P /tmp 
fi
tar -zxvf /tmp/kubernetes-node-linux-amd64.tar.gz -C /tmp
cp -rf /tmp/kubernetes/node/bin/kube* /usr/local/bin/


if [ ! -f "/tmp/docker.tgz" ]; then
  wget https://download.docker.com/linux/static/stable/x86_64/docker-19.03.14.tgz -O /tmp/docker.tgz
fi
tar -zxvf /tmp/docker.tgz -C /tmp
cp -rf /tmp/docker/* /usr/local/bin/


# step 07 : install docker

echo -e "\033[36m[INFO] STEP 07: Install docker...\033[0m"

if command_exists docker ; then
  echo -e "\033[36m[INFO] docker command already exists on this system.\033[0m"
  echo -e "\033[36m/etc/sysconfig/docker and /lib/systemd/system/docker.service files will be reset.\033[0m"
  echo -e "\033[36mYou may press Ctrl+C now to abort this script.\033[0m"
  echo -e "\033[36mwaiting for 10 seconds...\033[0m"
  sleep 10
fi

if service_exists docker; then
  systemctl stop docker
fi

echo "# /usr/lib/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target firewalld.service
Wants=network-online.target

[Service]
Type=notify
EnvironmentFile=/etc/sysconfig/docker
ExecStart=/usr/local/bin/dockerd \$DOCKER_OPTS \\
\$DOCKER_STORAGE_OPTIONS \\
\$DOCKER_NETWORK_OPTIONS \\
\$DOCKER_LOG_LEVEL
ExecReload=/bin/kill -s HUP \$MAINPID
ExecStartPost=/usr/sbin/iptables -P FORWARD ACCEPT

MountFlags=slave
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity
TimeoutStartSec=0
Delegate=yes
KillMode=process
Restart=always

[Install]
WantedBy=multi-user.target" > /usr/lib/systemd/system/docker.service

mkdir -p ${container_data_root}/docker
echo "DOCKER_OPTS=\"--log-level=warn --storage-driver=overlay2 --userland-proxy=false --log-opt max-size=1g --log-opt max-file=5\"
DOCKER_STORAGE_OPTIONS=\"--data-root ${container_data_root}/docker\"
DOCKER_LOG_LEVEL=\"--log-level warn\"
" > /etc/sysconfig/docker

systemctl start docker
systemctl enable docker
sleep 8
systemctl status -l docker


# step 08 : install kube-proxy

echo -e "\033[36m[INFO] STEP 08: Install kube-proxy...\033[0m"

if service_exists kube-proxy; then
  systemctl stop kube-proxy
fi

echo "[Unit]
Description=kube-proxy

[Service]
EnvironmentFile=/etc/sysconfig/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \$API_SERVERS \\
          \$KUBE_PROXY_OPTS
Restart=always

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/kube-proxy.service

echo "# configure file for kube-proxy
# --api-servers
API_SERVERS='--kubeconfig=${KUBE_CONFIG_FILE}'
# other parameters
KUBE_PROXY_OPTS='-masquerade-all=true --proxy-mode=iptables --conntrack-max-per-core=100000'
" > /etc/sysconfig/kube-proxy

systemctl daemon-reload
systemctl start kube-proxy
systemctl enable kube-proxy
sleep 5
systemctl status -l kube-proxy


# step 09 : install kubelet

echo -e "\033[36m[INFO] STEP 09: Install kubelet...\033[0m"

if service_exists kubelet; then
  systemctl stop kubelet
fi

echo "[Unit]
Description=kubelet
After=docker.service

[Service]
EnvironmentFile=/etc/sysconfig/kubelet
ExecStart=/usr/local/bin/kubelet \$API_SERVERS \\
          \$CLUSTER_DNS \\
          \$CLUSTER_DOMAIN \\
          \$ROOT_DIR \\
          \$HOSTNAME_OVERRIDE \\
          \$KUBELET_OPTS \\
          \$KUBECONFIG
Restart=always
StartLimitInterval=0

[Install]
WantedBy=multi-user.target
" > /lib/systemd/system/kubelet.service

mkdir -p ${container_data_root}/k8s
echo "# configure file for kubelet
# --api-servers
API_SERVERS='--kubeconfig=${KUBE_CONFIG_FILE}'
# --cluster-dns
CLUSTER_DNS='--cluster-dns=${cluster_dns}'
# --cluster-domain
CLUSTER_DOMAIN='--cluster-domain=${CLUSTER_DOMAIN}'
# --root-dir
ROOT_DIR='--root-dir=${container_data_root}/k8s'
# other parameters
KUBELET_OPTS='--anonymous-auth=false \\ 
--client-ca-file=${APISERVER_CA_PATH}/ca.crt \\ 
--authentication-token-webhook=true \\ 
--read-only-port=0 \\ 
--max-pods=70 \\ 
--allowed-unsafe-sysctls=\"net.*,kernel.shm*,kernel.msg*,fs.mqueue.*\" --fail-swap-on=false'
" > /etc/sysconfig/kubelet

systemctl daemon-reload
systemctl start kubelet
systemctl enable kubelet
sleep 5
systemctl status -l kubelet


# step 10 : configure kubectl

echo -e "\033[36m[INFO] STEP 10: Configure kubectl...\033[0m"

if [ $(grep -c kubeconfig ~/.bashrc) -eq 0 ]; then
  echo "alias kubectl='kubectl --kubeconfig ${KUBE_CONFIG_FILE}'" >> ~/.bashrc
  source ~/.bashrc
fi






















