# Install HAProxy and Keepalived


## HAProxy

#### 1. Download

```
yum install -y haproxy
```

#### 2. Configure

```
vi /etc/haproxy/haproxy.cfg
```

You can refer to the following.

```
#---------------------------------------------------------------------
# Example configuration for a possible web application.  See the
# full configuration options online.
#
#   http://haproxy.1wt.eu/download/1.4/doc/configuration.txt
#
#---------------------------------------------------------------------

#---------------------------------------------------------------------
# Global settings
#---------------------------------------------------------------------
global
    # to have these messages end up in /var/log/haproxy.log you will
    # need to:
    #
    # 1) configure syslog to accept network log events.  This is done
    #    by adding the '-r' option to the SYSLOGD_OPTIONS in
    #    /etc/sysconfig/syslog
    #
    # 2) configure local2 events to go to the /var/log/haproxy.log
    #   file. A line like the following can be added to
    #   /etc/sysconfig/syslog
    #
    #    local2.*                       /var/log/haproxy.log
    #
    log         127.0.0.1 local2

    chroot      /var/lib/haproxy
    pidfile     /var/run/haproxy.pid
    maxconn     4000
    user        haproxy
    group       haproxy
    daemon

    # turn on stats unix socket
    stats socket /var/lib/haproxy/stats

#---------------------------------------------------------------------
# common defaults that all the 'listen' and 'backend' sections will
# use if not designated in their block
#---------------------------------------------------------------------
defaults
    mode                    http
    log                     global
    option                  httplog
    option                  dontlognull
    option http-server-close
    option forwardfor       except 127.0.0.0/8
    option                  redispatch
    retries                 3
    timeout http-request    10s
    timeout queue           1m
    timeout connect         10s
    timeout client          1m
    timeout server          1m
    timeout http-keep-alive 10s
    timeout check           10s
    maxconn                 3000

#---------------------------------------------------------------------
# main frontend which proxys to the backends
#---------------------------------------------------------------------
#frontend  main *:5000
#    acl url_static       path_beg       -i /static /images /javascript /stylesheets
#    acl url_static       path_end       -i .jpg .gif .png .css .js

#    use_backend static          if url_static
#    default_backend             app

#---------------------------------------------------------------------
# static backend for serving up images, stylesheets and such
#---------------------------------------------------------------------
#backend static
#    balance     roundrobin
#    server      static 127.0.0.1:4331 check

#---------------------------------------------------------------------
# round robin balancing between the various backends
#---------------------------------------------------------------------
#backend app
#    balance     roundrobin
#    server  app1 127.0.0.1:5001 check
#    server  app2 127.0.0.1:5002 check
#    server  app3 127.0.0.1:5003 check
#    server  app4 127.0.0.1:5004 check

listen my-k8s-https
    bind 0.0.0.0:16443
    mode tcp
    option redispatch
    option tcplog
    balance source
    stick match src
    stick-table type ip size 200k expire 30m
    server s1 10.18.10.1:6443 weight 1 maxconn 10000 check
    server s2 10.18.10.2:6443 weight 1 maxconn 10000 check

listen admin_stats
    bind 0.0.0.0:8099
    mode http
    option httplog
    maxconn 10
    stats refresh 30s
    stats uri /stats

```

#### 3. Start

```
systemctl start haproxy
systemctl enable haproxy
```


## Keepalived

#### 1. Download

```
yum install -y keepalived
```

#### 2. Configure

```
vi /etc/keepalived/keepalived.conf
```

You can refer to the following.

```
# MASTER

global_defs {
   notification_email {
     acassen@firewall.loc
     failover@firewall.loc
     sysadmin@firewall.loc
   }
   notification_email_from Alexandre.Cassen@firewall.loc
   smtp_server 192.168.200.1
   smtp_connect_timeout 30
   router_id ROOT_10_1
}

vrrp_script check_haproxy {
    script "/etc/keepalived/check-haproxy.sh"
    interval 3
    weight -30
}

vrrp_instance VI_1 {
    state MASTER
    interface eth0
    virtual_router_id 51
    garp_master_delay 3
    priority 100
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        10.18.10.100
    }
}

```

```
# BACKUP

global_defs {
   notification_email {
     acassen@firewall.loc
     failover@firewall.loc
     sysadmin@firewall.loc
   }
   notification_email_from Alexandre.Cassen@firewall.loc
   smtp_server 192.168.200.1
   smtp_connect_timeout 30
   router_id ROOT_10_2
}

vrrp_script check_haproxy {
    script "/etc/keepalived/check-haproxy.sh"
    interval 3
    weight -30
}

vrrp_instance VI_1 {
    state BACKUP
    interface eth0
    virtual_router_id 81
    garp_master_delay 3
    priority 50
    advert_int 1
    authentication {
        auth_type PASS
        auth_pass 1111
    }
    virtual_ipaddress {
        10.18.10.100
    }
}
```

```
#!/bin/bash

# /etc/keepalived/check-haproxy.sh

count=`netstat -apn | grep 8099 | wc -l`

if [ $count -eq 0 ]; then
    systemctl stop keepalived
fi
```






