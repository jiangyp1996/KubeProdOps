### Summary

- Jump server
- Three Linux machines 

>You need a Jump server for management and at least three Linux machines for k8s installation.

### Jump server

- ansible v2.3.1.0
>If you have installed a higher version, please modify the YAML file syntax partly.

### Linux machines

- linux : Red Hat Enterprise Linux Server release 7.9
- kernel : 3.10.0-1160.15.2.el7.x86_64
- [Hardware guidelines for administering etcd clusters](https://etcd.io/docs/v3.5/op-guide/hardware/)
> Don't forget to configure Jump server ssh public key.