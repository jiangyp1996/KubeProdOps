# How to migrate a master node?

### Case 1

If you don't want to change vip, just need:

1. Install a new master node with previous certificates
2. Install haproxy and keepalived
3. Stop the old master node

### Case 2

If you need to change a new vip, you need:

1. Generate new certificates
2. Execute master, haproxy and keepalived installation steps in your new hosts
3. Sync all worker nodes' /etc/sysconfig/kubeconfig file 

