# Setup postgres1 node
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update
sudo -E apt-get -y install curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo -E apt-get update
sudo -E apt-get -y install postgresql-15
sudo systemctl stop postgresql@15-main.service

BACKUP_DIR=/shared/backups
sudo -E apt-get -y install pgbackrest
cat<<EOF | sudo tee "/etc/pgbackrest.conf"
[global]
repo1-path=$BACKUP_DIR
repo1-retention-full=4
repo1-bundle=y
repo1-block=y
start-fast=y
log-level-console=info
log-level-file=detail
delta=y
process-max=2
compress-type=zst

[mycluster]
pg1-path=/var/lib/postgresql/15/main
recovery-option=primary_conninfo=host=postgres0 port=5432 user=replicator
EOF

sudo -iu postgres sh -c 'echo "host replication replicator postgres0 scram-sha-256" >> /etc/postgresql/15/main/pg_hba.conf'
sudo -iu postgres sh -c 'echo "host replication replicator postgres1 scram-sha-256" >> /etc/postgresql/15/main/pg_hba.conf'
sudo -iu postgres sh -c 'echo "host all all bouncer scram-sha-256" >> /etc/postgresql/15/main/pg_hba.conf'
sudo -iu postgres sh -c 'echo "postgres0:*:replication:replicator:sEcReTpAsSwOrD" >> /var/lib/postgresql/.pgpass'
sudo -iu postgres chmod 600 /var/lib/postgresql/.pgpass
sudo -iu postgres pgbackrest --stanza=mycluster --delta --type=standby restore
sudo -iu postgres cat /var/lib/postgresql/15/main/postgresql.auto.conf
sudo systemctl start postgresql@15-main.service
sudo -iu postgres ps -o pid,cmd fx
