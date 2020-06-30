#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
PGDATA="$2"
ETCD_NODES_NB="$3"
VIP="$4"
CLUSTER_NAME="$5"

PACKAGES=(
    "gcc"
    "python3-devel"
    "python3-psycopg2"
    "PyYAML"
    "python3-pip"
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"

echo "export PATH=/usr/local/bin/:\$PATH" >> /etc/profile
export PATH=/usr/local/bin/:$PATH
python3 -m pip install --upgrade pip
python3 -m pip install --upgrade setuptools
python3 -m pip install patroni[etcd]

MY_NAME=$(hostname --short)
MY_IP=$(hostname -I | awk ' {print $1}')
for (( i=1; i<=$ETCD_NODES_NB; i++ ))
do
   TARGET_ARRAY[$i]="etcd$i:2379"
done
ETCD_HOSTS=$(printf ",%s" "${TARGET_ARRAY[@]}")
ETCD_HOSTS=${ETCD_HOSTS:1}
PATRONI_PASSWORD="mySupeSecretPassword"

cat > /etc/patroni-$CLUSTER_NAME.yml <<EOF
scope: $CLUSTER_NAME
namespace: /db/
name: $MY_NAME
restapi:
  listen: "0.0.0.0:8008"
  connect_address: "$MY_IP:8008"
  authentication:
    username: patroni
    password: $PATRONI_PASSWORD
etcd:
    hosts: $ETCD_HOSTS
bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      use_pg_rewind: true
      use_slots: true
      parameters:
        archive_mode: "on"
        archive_command: /bin/true
  initdb:
  - encoding: UTF8
  - data-checksums
  pg_hba:
  - host replication replicator 0.0.0.0/0 md5
  - host all all 0.0.0.0/0 md5
  users:
    admin:
      password: admin
      options:
          - superuser
postgresql:
  listen: "0.0.0.0:5432"
  connect_address: "$MY_IP:5432"
  data_dir: $PGDATA
  bin_dir: /usr/pgsql-${PGVER}/bin
  pgpass: /tmp/pgpass0
  authentication:
    replication:
      username: replicator
      password: confidential
    superuser:
      username: postgres
      password: my-super-password
  parameters:
    unix_socket_directories: '/var/run/postgresql,/tmp'
watchdog:
  mode: required
  device: /dev/watchdog
  safety_margin: 5
tags:
  nofailover: false
  noloadbalance: false
  clonefrom: false
  nosync: false
EOF

ln -s /etc/patroni-$CLUSTER_NAME.yml /etc/patroni.yml

cat > /lib/systemd/system/patroni.service <<EOF
[Unit]
Description=Runners to orchestrate a high-availability PostgreSQL
After=syslog.target network.target

[Service]
Type=simple

User=postgres
Group=postgres

# Read in configuration file if it exists, otherwise proceed
EnvironmentFile=-/etc/patroni_env.conf

WorkingDirectory=~

# Where to send early-startup messages from the server
# This is normally controlled by the global default set by systemd
#StandardOutput=syslog

# Pre-commands to start watchdog device
# Uncomment if watchdog is part of your patroni setup
#ExecStartPre=-/usr/bin/sudo /sbin/modprobe softdog
#ExecStartPre=-/usr/bin/sudo /bin/chown postgres /dev/watchdog

# Disable OOM kill on the postmaster
OOMScoreAdjust=-1000

# Start the patroni process
ExecStart=/usr/local/bin/patroni /etc/patroni.yml

# Send HUP to reload from patroni.yml
ExecReload=/bin/kill -s HUP \$MAINPID

# only kill the patroni process, not it's children, so it will gracefully stop postgres
KillSignal=SIGINT
KillMode=process

# Give a reasonable amount of time for the server to start up/shut down
TimeoutSec=30
TimeoutStopSec=120s

# Do not restart the service if it crashes, we want to manually inspect database on failure
Restart=no

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF' > /etc/udev/rules.d/99-watchdog.rules
SUBSYSTEM=="misc", KERNEL=="watchdog", ACTION=="add", RUN+="/bin/setfacl -m u:postgres:rw- /dev/watchdog"
EOF
modprobe softdog

systemctl daemon-reload
systemctl enable patroni
systemctl start patroni
systemctl status patroni

firewall-cmd --quiet --zone=public --add-port=8008/tcp --permanent
firewall-cmd --quiet --reload