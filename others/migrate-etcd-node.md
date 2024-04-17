# How to migrate a etcd node?

Distinguish between etcd v2 and v3, the example versions in this article are v3.2.11 and v3.5.4

Distinguish between etcd http node and https node.

```
10.18.10.3 (removed)
10.18.10.4 
10.18.10.5 

10.18.10.6 (added)

```


### HTTPS NODE
---

1. Remake certificates

```

```


2. Check etcd cluster status

```
# v2 

./etcdctl --endpoints https://127.0.0.1:2379 --ca-file=/etc/kubernetes/pki/ca.crt --cert-file=/etc/kubernetes/pki/etcd_client.crt --key-file=/etc/kubernetes/pki/etcd_client.key member list

# v3 

ETCDCTL_API=3 ./etcdctl --endpoints https://10.18.10.3:2379,https://10.18.10.4:2379,https://10.18.10.5:2379 --ca-file=/etc/kubernetes/pki/ca.crt --cert-file=/etc/kubernetes/pki/etcd_client.crt --key-file=/etc/kubernetes/pki/etcd_client.key endpoint status --write-out=table

```

3. Remove the old node

```
./etcdctl --endpoints  https://127.0.0.1:2379 member remove <ENDPOINT-ID>

```


4. Add the new node

```
# v2

./etcdctl --endpoints https://127.0.0.1:2379 member add etcd3 https://10.18.10.6:2380

# v3

ETCDCTL_API=3 ./etcdctl --endpoints http://127.0.0.1:2379 member add etcd3 --peer-urls=http://10.18.10.6:2380

```

5. Install the new node

```

```


6. Sync others etcd nodes


### HTTP NODE
---




