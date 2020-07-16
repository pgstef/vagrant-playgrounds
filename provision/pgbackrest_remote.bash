#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
PGDATA="$2"
PATRONI_NODES_NB="$3"

yum install --nogpgcheck --quiet -y -e 0 "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

PACKAGES=(
    "postgresql${PGVER}"
    "postgresql${PGVER}-server"
    "postgresql${PGVER}-contrib"
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"
yum install --nogpgcheck --quiet -y -e 0 pgbackrest

TARGET_ARRAY=()
for (( i=1; i<=$PATRONI_NODES_NB; i++ ))
do
   TARGET_ARRAY+=("pg$i-host=pg-patroni$i")
   TARGET_ARRAY+=("pg$i-path=${PGDATA}")
done
PG_MEMBERS=$(printf "%s\n" "${TARGET_ARRAY[@]}")

# pgbackrest.conf setup
cat<<EOC > "/etc/pgbackrest.conf"
[global]
repo1-path=/var/lib/pgbackrest
repo1-retention-full=1
process-max=2
log-level-console=warn
log-level-file=info
start-fast=y
delta=y
repo1-cipher-type=aes-256-cbc
repo1-cipher-pass=acbd

[my_stanza]
$PG_MEMBERS
EOC

# force proper permissions on repo1-path
chmod 755 /var/lib/pgbackrest

# force proper permissions on .ssh files
chmod -R 0600 /root/.ssh
chmod 0700 /root/.ssh
cp -rf /root/.ssh /var/lib/pgsql/.ssh
chown -R postgres: /var/lib/pgsql/.ssh
restorecon -R /root/.ssh
restorecon -R /var/lib/pgsql/.ssh

# pgBackRest init
sudo -iu postgres pgbackrest --stanza=my_stanza stanza-create
sudo -iu postgres pgbackrest --stanza=my_stanza check
sudo -iu postgres pgbackrest --stanza=my_stanza backup --type=full --repo1-retention-full=1
sudo -iu postgres pgbackrest --stanza=my_stanza info