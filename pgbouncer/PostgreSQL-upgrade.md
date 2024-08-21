## Upgrade procedure

The following procedure will allow us to upgrade PostgreSQL major version and enable page checksums.

We will first enable the checksums on the standby, and then promote it to upgrade the PostgreSQL version on that node. This would give us a new primary with checksums enabled and the new PostgreSQL version installed, while the old primary would still be there in case something goes wrong during the upgrade. Once the upgrade process is finished and successful, we'll take a new backup using pgBackRest and use that backup to reconstruct the old primary onto a new standby server.

* As we would enable the checksums on the standby server first, on the PgBouncer node, redirect the traffic (SQL queries) from the standby to the primary:

```bash
sudo sed -i 's/postgres1/postgres0/g' /etc/pgbouncer/pgbouncer-standby-10101.ini
sudo -iu postgres psql -U pgbouncer -p 10101 -c "RELOAD;"
PGPASSWORD=Secret psql -U test -d testdb -p 10101 -c "SELECT pg_is_in_recovery();"
sudo sed -i 's/postgres1/postgres0/g' /etc/pgbouncer/pgbouncer-standby-10102.ini
sudo -iu postgres psql -U pgbouncer -p 10102 -c "RELOAD;"
PGPASSWORD=Secret psql -U test -d testdb -p 10102 -c "SELECT pg_is_in_recovery();"
```

* Stop the standby service:

```bash
sudo systemctl stop postgresql@15-main.service
```

* Make sure it was stopped properly:

```bash
$ sudo -iu postgres /usr/lib/postgresql/15/bin/pg_controldata \
    -D /var/lib/postgresql/15/main |\
    grep -E '(Database cluster state)|(REDO location)|(page checksum)'
Database cluster state:               shut down in recovery
Latest checkpoint's REDO location:    0/80000D8
Data page checksum version:           0
```

* Enable the checksums using `pg_checksums`:

```bash
$ sudo -iu postgres /usr/lib/postgresql/15/bin/pg_checksums \
    -D /var/lib/postgresql/15/main --enable --progress
29/29 MB (100%) computed
Checksum operation completed
Files scanned:   1242
Blocks scanned:  3739
Files written:  1024
Blocks written: 3739
pg_checksums: syncing data directory
pg_checksums: updating control file
Checksums enabled in cluster
```

* Start the standby server:

```bash
sudo systemctl start postgresql@15-main.service
```

* Make sure it catches up with the primary replication state, and check that the page checksums have been enabled:

```bash
$ sudo -iu postgres psql -xtc "SELECT status,sender_host FROM pg_stat_wal_receiver;"
status                | streaming
sender_host           | postgres0

$ sudo -iu postgres psql -Axc 'show data_checksums'
data_checksums|on
```

The standby server should be able to replay the WAL entries from the primary or, if the primary already removed it, replay from the WAL archives (using pgBackRest).

* Resume traffic to the standby:

```bash
sudo sed -i 's/postgres0/postgres1/g' /etc/pgbouncer/pgbouncer-standby-10101.ini
sudo -iu postgres psql -U pgbouncer -p 10101 -c "RELOAD;"
PGPASSWORD=Secret psql -U test -d testdb -p 10101 -c "SELECT pg_is_in_recovery();"
sudo sed -i 's/postgres0/postgres1/g' /etc/pgbouncer/pgbouncer-standby-10102.ini
sudo -iu postgres psql -U pgbouncer -p 10102 -c "RELOAD;"
PGPASSWORD=Secret psql -U test -d testdb -p 10102 -c "SELECT pg_is_in_recovery();"
```

* It's now time to prepare the PostgreSQL version update. On the PostgreSQL nodes, install and verify all necessary packages.

To make sure to enable checksums on the new cluster, configure `initdb_options`:

```bash
sudo mkdir /etc/postgresql-common/createcluster.d
sudo sh -c "echo \"initdb_options = '--data-checksums'\" >> /etc/postgresql-common/createcluster.d/initdb.conf"
```

Install the target release and stop the service:

```bash
sudo apt-get install -y postgresql-16
sudo systemctl disable --now postgresql@16-main.service
```

The initdb log should tell you:

> Data page checksums are enabled.

<!--
    Ongoing discussion on the -hackers mailing list to [enable data checksums by default](https://www.postgresql.org/message-id/flat/CAKAnmmKwiMHik5AHmBEdf5vqzbOBbcwEPHo4-PioWeAbzwcTOQ%40mail.gmail.com).
-->

* Prepare the PostgreSQL configuration files for the new version installed. We will here only copy configurations and hba settings that were added in the provisioning scripts when initiating the VMs.

```bash
cat<<EOF | sudo tee "/var/lib/postgresql/16/main/postgresql.auto.conf"
listen_addresses = '*'
archive_mode = on
archive_command = 'pgbackrest --stanza=mycluster archive-push %p'
EOF
```

```bash
sudo -iu postgres sh -c 'echo "host replication replicator postgres0 scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf'
sudo -iu postgres sh -c 'echo "host replication replicator postgres1 scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf'
sudo -iu postgres sh -c 'echo "host all all bouncer scram-sha-256" >> /etc/postgresql/16/main/pg_hba.conf'
sudo sed -i 's/5433/5432/g' /etc/postgresql/16/main/postgresql.conf
```

* Pause traffic to the primary and standby:

```bash
sudo -iu postgres psql -U pgbouncer -p 10001 -c "PAUSE;"
sudo -iu postgres psql -U pgbouncer -p 10002 -c "PAUSE;"
sudo -iu postgres psql -U pgbouncer -p 10101 -c "PAUSE;"
sudo -iu postgres psql -U pgbouncer -p 10102 -c "PAUSE;"
```

* Stop the primary:

```bash
sudo systemctl stop postgresql@15-main.service
sudo systemctl disable postgresql@15-main.service
```

* Make sure it was stopped properly:

```bash
$ sudo -iu postgres /usr/lib/postgresql/15/bin/pg_controldata \
    -D /var/lib/postgresql/15/main |\
    grep -E '(Database cluster state)|(REDO location)|(page checksum)'
Database cluster state:               shut down
Latest checkpoint's REDO location:    0/9000028
Data page checksum version:           0
```

* Check that the standby node received all activity from the primary and then promote:

```bash
$ sudo -iu postgres psql -c "CHECKPOINT;"
$ sudo -iu postgres /usr/lib/postgresql/15/bin/pg_controldata \
    -D /var/lib/postgresql/15/main |\
    grep -E '(Database cluster state)|(REDO location)|(page checksum)'
Database cluster state:               in archive recovery
Latest checkpoint's REDO location:    0/9000028
Data page checksum version:           1
```
```bash
$ sudo -iu postgres psql -c "SELECT pg_promote();"
 pg_promote
------------
 t
(1 row)
$ sudo -iu postgres psql -c "CHECKPOINT;"
```

* Check that the upgrade is possible using `pg_upgrade --check`:

```bash
sudo -iu postgres /usr/lib/postgresql/16/bin/pg_upgrade \
--old-bindir /usr/lib/postgresql/15/bin/ --new-bindir /usr/lib/postgresql/16/bin/ \
--old-datadir /var/lib/postgresql/15/main/ --new-datadir /var/lib/postgresql/16/main/ \
--old-options " -c config_file=/etc/postgresql/15/main/postgresql.conf" \
--new-options " -c config_file=/etc/postgresql/16/main/postgresql.conf" \
--new-options " -c archive_mode=off" \
--retain --jobs 4 --link --check
```

* Stop the running services:

```bash
sudo systemctl stop postgresql@15-main.service
sudo systemctl disable postgresql@15-main.service
```

* Perform the upgrade using the command above, without the `--check` option. The output should end with the following message:

```
Upgrade Complete
----------------
Optimizer statistics are not transferred by pg_upgrade.
Once you start the new server, consider running:
    /usr/lib/postgresql/16/bin/vacuumdb --all --analyze-in-stages
Running this script will delete the old cluster's data files:
    ./delete_old_cluster.sh
```

* Upgrade pgBackRest configuration to let it know that the cluster was upgraded with the `stanza-upgrade` command:

```bash
sudo sed -i 's/\/var\/lib\/postgresql\/15\/main/\/var\/lib\/postgresql\/16\/main/g' /etc/pgbackrest.conf
sudo -iu postgres pgbackrest --stanza=mycluster --no-online stanza-upgrade
```

* Start the new upgraded cluster:

```bash
sudo systemctl start postgresql@16-main.service
sudo systemctl enable postgresql@16-main.service
```

* Run `vacuumdb` as suggested in the `pg_upgrade` output.

```bash
sudo -iu postgres /usr/lib/postgresql/16/bin/vacuumdb --all --analyze-in-stages
```

* Resume traffic to new primary and check team that everything is fine:

```bash
sudo -iu postgres psql -U pgbouncer -p 10101 -c "RESUME;"
sudo -iu postgres psql -U pgbouncer -p 10102 -c "RESUME;"
PGPASSWORD=Secret psql -U test -d testdb -p 10101 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10102 -c "SELECT pg_is_in_recovery();"

sudo sed -i 's/postgres0/postgres1/g' /etc/pgbouncer/pgbouncer-primary-10001.ini
sudo sed -i 's/postgres0/postgres1/g' /etc/pgbouncer/pgbouncer-primary-10002.ini
sudo -iu postgres psql -U pgbouncer -p 10001 -c "RELOAD;"
sudo -iu postgres psql -U pgbouncer -p 10001 -c "RESUME;"
sudo -iu postgres psql -U pgbouncer -p 10002 -c "RELOAD;"
sudo -iu postgres psql -U pgbouncer -p 10002 -c "RESUME;"
PGPASSWORD=Secret psql -U test -d testdb -p 10001 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10002 -c "SELECT pg_is_in_recovery();"
```

* Make a fresh backup:

```bash
sudo -iu postgres pgbackrest --stanza=mycluster --type=full backup
sudo -iu postgres pgbackrest --stanza=mycluster info
```

* Once you're sure that everything is fine with the new cluster, clean-up the old cluster directory and packages:

```bash
sudo -iu postgres rm -rf '/var/lib/postgresql/15/main'
sudo apt-get remove -y postgresql-15
```

Apply the same commands on the old primary node to clean up some space to create the new standby by restoring the latest backup taken on the new primary node.

* Re-sync the old primary as new standby:

```bash
sudo sed -i 's/\/var\/lib\/postgresql\/15\/main/\/var\/lib\/postgresql\/16\/main/g' /etc/pgbackrest.conf
sudo -iu postgres pgbackrest --stanza=mycluster --delta --type=standby restore
sudo -iu postgres cat /var/lib/postgresql/16/main/postgresql.auto.conf
sudo systemctl start postgresql@16-main.service
sudo systemctl enable postgresql@16-main.service
```

* Make sure it catches up with the primary replication state, and check that the page checksums have been enabled:

```bash
$ sudo -iu postgres psql -xtc "SELECT status,sender_host FROM pg_stat_wal_receiver;"
status                | streaming
sender_host           | postgres1

$ sudo -iu postgres psql -Axc 'show data_checksums'
data_checksums|on
```

* Resume traffic back to the new standby:

```bash
sudo sed -i 's/postgres1/postgres0/g' /etc/pgbouncer/pgbouncer-standby-10101.ini
sudo sed -i 's/postgres1/postgres0/g' /etc/pgbouncer/pgbouncer-standby-10102.ini
sudo -iu postgres psql -U pgbouncer -p 10101 -c "RELOAD;"
sudo -iu postgres psql -U pgbouncer -p 10102 -c "RELOAD;"
PGPASSWORD=Secret psql -U test -d testdb -p 10101 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10102 -c "SELECT pg_is_in_recovery();"
```

---

### [Optional] Switch-over primary/standby roles to get back to initial state

* Pause traffic to the primary:

```bash
sudo -iu postgres psql -U pgbouncer -p 10001 -c "PAUSE;"
sudo -iu postgres psql -U pgbouncer -p 10002 -c "PAUSE;"
```

* Stop the primary:

```bash
sudo systemctl stop postgresql@16-main.service
```

* Make sure it was stopped properly:

```bash
$ sudo -iu postgres /usr/lib/postgresql/16/bin/pg_controldata \
    -D /var/lib/postgresql/16/main |\
    grep -E '(Database cluster state)|(REDO location)'
Database cluster state:               shut down
Latest checkpoint's REDO location:    0/C000028
```

* Check that the standby node received all activity from the primary and then promote:

```bash
$ sudo -iu postgres psql -c "CHECKPOINT;"
$ sudo -iu postgres /usr/lib/postgresql/16/bin/pg_controldata \
    -D /var/lib/postgresql/16/main |\
    grep -E '(Database cluster state)|(REDO location)'
Database cluster state:               in archive recovery
Latest checkpoint's REDO location:    0/C000028
```
```bash
$ sudo -iu postgres psql -c "SELECT pg_promote();"
 pg_promote
------------
 t
(1 row)
$ sudo -iu postgres psql -c "CHECKPOINT;"
```

* Resume traffic to the new primary:

```bash
sudo sed -i 's/postgres1/postgres0/g' /etc/pgbouncer/pgbouncer-primary-10001.ini
sudo -iu postgres psql -U pgbouncer -p 10001 -c "RELOAD;"
sudo -iu postgres psql -U pgbouncer -p 10001 -c "RESUME;"
PGPASSWORD=Secret psql -U test -d testdb -p 10001 -c "SELECT pg_is_in_recovery();"
sudo sed -i 's/postgres1/postgres0/g' /etc/pgbouncer/pgbouncer-primary-10002.ini
sudo -iu postgres psql -U pgbouncer -p 10002 -c "RELOAD;"
sudo -iu postgres psql -U pgbouncer -p 10002 -c "RESUME;"
PGPASSWORD=Secret psql -U test -d testdb -p 10002 -c "SELECT pg_is_in_recovery();"
```

* Prepare the configuration for the replication and start the standby service:

```bash
sudo -iu postgres sh -c 'echo "primary_conninfo = '\''host=postgres0 port=5432 user=replicator'\''" >> /var/lib/postgresql/16/main/postgresql.auto.conf'
sudo -iu postgres touch /var/lib/postgresql/16/main/standby.signal
sudo systemctl start postgresql@16-main.service
```

* Make sure it catches up with the primary replication state:

```bash
$ sudo -iu postgres psql -xtc "SELECT status,sender_host FROM pg_stat_wal_receiver;"
status                | streaming
sender_host           | postgres0
```

* Redirect traffic to the new standby:

```bash
sudo sed -i 's/postgres0/postgres1/g' /etc/pgbouncer/pgbouncer-standby-10101.ini
sudo -iu postgres psql -U pgbouncer -p 10101 -c "RELOAD;"
PGPASSWORD=Secret psql -U test -d testdb -p 10101 -c "SELECT pg_is_in_recovery();"
sudo sed -i 's/postgres0/postgres1/g' /etc/pgbouncer/pgbouncer-standby-10102.ini
sudo -iu postgres psql -U pgbouncer -p 10102 -c "RELOAD;"
PGPASSWORD=Secret psql -U test -d testdb -p 10102 -c "SELECT pg_is_in_recovery();"
```
