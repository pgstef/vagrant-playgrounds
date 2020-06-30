#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

ETCD_NODES_NB="$1"
PATRONI_NODES_NB="$2"
VIP="$3"
CLUSTER_NAME="$4"

echo "--------ETCD--------"
for (( i=1; i<=$ETCD_NODES_NB; i++ ))
do
   TARGET_IP=$(dig +short etcd$i)
   ETCD_TARGET_IP[$i]=$TARGET_IP
   echo "etcd$i health:  http://$TARGET_IP:2379/health"
   echo "etcd$i metrics: http://$TARGET_IP:2379/metrics"
done

echo "--------PATRONI--------"
echo "patroni cluster state: http://$VIP:8008/cluster"
for (( i=1; i<=$PATRONI_NODES_NB; i++ ))
do
   TARGET_IP=$(dig +short pg-patroni$i)
   PATRONI_TARGET_IP[$i]=$TARGET_IP
   echo "pg-patroni$i endpoint:  http://$TARGET_IP:8008/patroni"
done
echo "scope: $CLUSTER_NAME"
echo "config file: /etc/patroni-$CLUSTER_NAME.yml"

echo "--------HAProxy--------"
echo "Haproxy Statistics: http://$VIP:7000"
echo "--------VIP--------"
echo "read-write: $VIP:5000"
echo "read-only : $VIP:5001"
