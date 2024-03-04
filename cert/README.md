# Certificate

1. Generate CA cert

```
bash generate_ca_cert.sh --cluster-name=my-k8s --vip=10.18.10.100
```

2. Generate and distribute ETCD and CA cert

```
bash generate_and_distribute_etcd_cert.sh --cluster-name=my-k8s --etcd-servers-ip=10.18.10.1,10.18.10.2,10.18.10.3
```

3. Generate and distribute MASTER and CA cert

```
bash generate_and_distribute_master_cert.sh --cluster-name=my-k8s --master-servers-ip=10.18.10.1,10.18.10.2 --vip=10.18.10.100
```