#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ETCD_NODES_NB="$1"

yum install --nogpgcheck --quiet -y -e 0 etcd
cp /etc/etcd/etcd.conf /etc/etcd/etcd.conf.bck

MY_NAME=$(hostname --short)
MY_IP=$(hostname -I | awk ' {print $1}')
for (( i=1; i<=$ETCD_NODES_NB; i++ ))
do
   TARGET_IP=$(dig +short etcd$i)
   TARGET_ARRAY[$i]="etcd$i=http://$TARGET_IP:2380"
done
ETCD_CLUSTER_URL=$(printf ",%s" "${TARGET_ARRAY[@]}")
ETCD_CLUSTER_URL=${ETCD_CLUSTER_URL:1}
TOKEN="O2Z24eykG0n8lhuHLET8Ww=="

cat > /etc/etcd/etcd.conf <<EOF
#[Member]
ETCD_DATA_DIR="/var/lib/etcd/default.etcd"
ETCD_LISTEN_PEER_URLS="http://$MY_IP:2380"
ETCD_LISTEN_CLIENT_URLS="http://$MY_IP:2379"
ETCD_NAME="$MY_NAME"
#[Clustering]
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://$MY_IP:2380"
ETCD_ADVERTISE_CLIENT_URLS="http://$MY_IP:2379"
ETCD_INITIAL_CLUSTER="$ETCD_CLUSTER_URL"
ETCD_INITIAL_CLUSTER_TOKEN="$TOKEN"
ETCD_INITIAL_CLUSTER_STATE="new"
EOF

firewall-cmd --quiet --zone=public --add-port=2379/tcp --permanent
firewall-cmd --quiet --zone=public --add-port=2380/tcp --permanent
firewall-cmd --quiet --reload
systemctl enable etcd
systemctl start etcd
