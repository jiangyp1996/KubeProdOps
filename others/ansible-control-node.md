## Configure Ansible Control Node

### Install ansible

1. configure yum repo if you are in china

```
cd /etc/yum.repos.d/
wget http://mirrors.aliyun.com/repo/epel-7.repo
```

2. installation


```
# ansible 2.9.27

yum install -y epel-release
yum install -y ansible
```


### SSH configuration

In your control node, using command "ssh-keygen -t rsa" to generate ssh private and public key.

Append the public key content into your target host's /root/.ssh/authorized_keys file.

