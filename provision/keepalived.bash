#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

VIP="$1"
MY_IP=$(hostname -I | awk ' {print $1}')
DEVICE=$(ip -br address | grep $MY_IP | awk '{print $1}')

yum install --nogpgcheck --quiet -y -e 0 keepalived
cp /etc/keepalived/keepalived.conf /etc/keepalived/keepalived.conf.bck

cat >/etc/keepalived/keepalived.conf <<EOF
global_defs {
  vrrp_garp_master_delay 3
  vrrp_garp_master_repeat 4
  vrrp_garp_master_refresh 60
  vrrp_garp_master_refresh_repeat 4
}

vrrp_instance patroni {
  state BACKUP
  interface $DEVICE
  virtual_router_id 100
  priority 100
  advert_int 1

  virtual_ipaddress {
    $VIP
  }

  authentication {
    auth_type PASS
    auth_pass secret
  }
}
EOF

firewall-cmd --add-rich-rule='rule protocol value="vrrp" accept' --permanent
firewall-cmd --reload
systemctl enable keepalived.service
systemctl start keepalived.service