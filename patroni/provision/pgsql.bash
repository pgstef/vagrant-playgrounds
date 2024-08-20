#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

PGVER="$1"
PGDATA="$2"

yum install --nogpgcheck --quiet -y -e 0 "https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm"

PACKAGES=(
    "postgresql${PGVER}"
    "postgresql${PGVER}-server"
    "postgresql${PGVER}-contrib"
)

yum install --nogpgcheck --quiet -y -e 0 "${PACKAGES[@]}"
firewall-cmd --quiet --permanent --add-service=postgresql
firewall-cmd --quiet --reload

# pgBackRest
yum install --nogpgcheck --quiet -y -e 0 pgbackrest

cat<<EOC > "/etc/pgbackrest.conf"
[global]
repo1-host=pgbackrest
repo1-host-user=postgres
process-max=2
log-level-console=warn
log-level-file=info
delta=y

[my_stanza]
pg1-path=${PGDATA}
EOC

# force proper permissions on .ssh files
chmod -R 0600 /root/.ssh
chmod 0700 /root/.ssh
cp -rf /root/.ssh /var/lib/pgsql/.ssh
chown -R postgres: /var/lib/pgsql/.ssh
restorecon -R /root/.ssh
restorecon -R /var/lib/pgsql/.ssh