#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PATRONI_NODES_NB="$1"

yum install --nogpgcheck --quiet -y -e 0 haproxy
cp /etc/haproxy/haproxy.cfg /etc/haproxy/haproxy.cfg.old

for (( i=1; i<=$PATRONI_NODES_NB; i++ ))
do
   TARGET_IP=$(dig +short pg-patroni$i)
   TARGET_ARRAY[$i]="    server pg-patroni$i $TARGET_IP:5432 check port 8008"
done
PATRONI_MEMBERS=$(printf "%s\n" "${TARGET_ARRAY[@]}")

cat > /etc/haproxy/haproxy.cfg <<EOF
global
    log /dev/log local0
    chroot /var/lib/haproxy
    maxconn 100
    user haproxy
    group haproxy
    daemon
    stats socket /var/lib/haproxy/stats
    stats timeout 30s
   
defaults
    log global
    mode tcp
    retries 6
    timeout client 30m
    timeout connect 3s
    timeout server 30m
    timeout check 5s
    timeout tunnel 30m
    timeout client-fin 10s

listen stats
    mode http
    bind 0.0.0.0:7000
    stats enable
    stats hide-version
    stats realm Haproxy\ Statistics
    stats uri /

listen read-write
    bind 0.0.0.0:5000
    option httpchk GET /read-write
    http-check expect status 200
    default-server fall 5 inter 1000 rise 5 downinter 1000 on-marked-down shutdown-sessions weight 10
$PATRONI_MEMBERS

listen read
    bind 0.0.0.0:5001
    option httpchk GET /read-only
    http-check expect status 200
    default-server fall 5 inter 1000 rise 5 downinter 1000 on-marked-down shutdown-sessions weight 10
$PATRONI_MEMBERS
EOF

setsebool -P haproxy_connect_any=1
systemctl enable haproxy
systemctl stop haproxy
systemctl start haproxy
firewall-cmd --quiet --zone=public --add-port=7000/tcp --permanent
firewall-cmd --quiet --zone=public --add-port=5000/tcp --permanent
firewall-cmd --quiet --zone=public --add-port=5001/tcp --permanent
firewall-cmd --quiet --reload