### Operate a highly avaliable Kubernetes cluster in Prod

- How to install Kubernetes in prod ? 
- How to migrate a etcd node ?
- How to migrate a master node ?
- How to upgrade kubelet from http to https ?
- How to upgrade etcd from http to https ?

# Install Kubernetes


## Preparations

- A center control node with ansible and ssh
- Clone this project to your center control node, then do the following


## Environment

- Operating System and version: Red Hat Enterprise Linux Server release 7.9
- Kernel: 3.10.0-1160.15.2.el7.x86_64
- Kubernetes version: 1.18.14
- Etcd version: 3.5.4
- Docker version: 19.03.14
- Flannel version: 0.22.3
- CodeDNS version: 1.10.1


## Certificate

Generate CA, Master and etcd certificates, and distribute them to the corresponding target hosts.

### 1. Generate CA cert

- Generate ca.key and ca.crt. 

```
sh ./cert/generate_ca_cert.sh --cluster-name=my-k8s --vip=10.18.10.100
```

### 2. Generate and distribute etcd and CA cert

- Generate etcd_server.key, etcd_server.crt, etcd_client.key and etcd_client.crt
- Distribute ca.crt, etcd_server.key and etcd_server.crt to etcd hosts

```
sh ./cert/generate_and_distribute_etcd_cert.sh --cluster-name=my-k8s --etcd-servers-ip=10.18.10.3,10.18.10.4,10.18.10.5
```

### 3. Generate and distribute Master and CA cert

- Generate apiserver.key and apiserver.crt
- Distribute ca.crt, apiserver.key, apiserver.crt, etcd_client.key and etcd_client.crt to master hosts
```
sh ./cert/generate_and_distribute_master_cert.sh --cluster-name=my-k8s --master-servers-ip=10.18.10.1,10.18.10.2 --vip=10.18.10.100
```


## Install etcd

- Reference : [Hardware recommendations](https://etcd.io/docs/v3.3/op-guide/hardware/)

```
ansible-playbook -i ./etcd/inventory/etcd-inventory.ini ./etcd/install_etcd.yml
```


## Install Master

- Highly Available Kubernetes. We need at least two master hosts and a vip.
- This shell scripts will download master installation package from [https://dl.k8s.io/v1.18.14/kubernetes-server-linux-amd64.tar.gz](https://dl.k8s.io/v1.18.14/kubernetes-server-linux-amd64.tar.gz), if the machine’s network does not allow it, please download it in advance.

```
ansible-playbook -i ./master/inventory/master-inventory.ini ./master/install_master.yml
```


## Install HAProxy and Keepalived

```
yum install -y haproxy
yum install -y keepalived

# And then configure them as your wish.
```


## Install Worker

- worker-inventory.ini parameters explanation
	- apiserver_secure_port : HAProxy proxy port, used to connect the worker to the master
	- cluster_dns : coredns service clusterIP
- This shell scripts will download worker installation package from [https://dl.k8s.io/v1.18.14/kubernetes-node-linux-amd64.tar.gz](https://dl.k8s.io/v1.18.14/kubernetes-node-linux-amd64.tar.gz) and docker installation package from [https://download.docker.com/linux/static/stable/x86_64/docker-19.03.14.tgz](https://download.docker.com/linux/static/stable/x86_64/docker-19.03.14.tgz), if the machine’s network does not allow them, please download them in advance.


```
ansible-playbook -i ./worker/worker-inventory.ini ./worker/install_worker.yml
```

## Install Flannel

1. Download kube-flannel.yml from [github flannel releases](https://github.com/flannel-io/flannel/releases) to worker node.

2. Change the Network value of ConfigMap, such as 172.24.0.0/13 in this project example.

> You can refer to others/kube-flannel.yml in this project.

3. kubectl apply -f kube-flannel.yml

## Install CoreDNS

1. Refer to [coredns.yaml.sed](https://github.com/coredns/deployment/blob/master/kubernetes/coredns.yaml.sed) or this project's others/install-coredns.yml 

2. Change ConfigMap data

3. Change Service clusterIP, such as 172.16.40.1 in this project example

4. kubectl apply -f install-coredns.yml

# Others

1. Migrate master node
2. Migrate etcd node
3. Upgrade kubelet from http to https
4. Upgrade etcd from http to https





