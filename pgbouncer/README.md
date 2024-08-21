# How to bootstrap this cluster using vagrant

## Introduction

This `Vagrantfile` is bootstrapping a fresh `Ubuntu 22.04` cluster with:

* PgBouncer: 1 node (`bouncer`)
* PostgreSQL 15: 2 nodes (`postgres0` and `postgres1`)
* pgBackRest setup with nfs `shared` directory

---

## Create the cluster

To create the cluster, run:

```bash
make all
```

Then, you can connect to the servers using:

```bash
vagrant ssh postgres0
vagrant ssh postgres1
vagrant ssh bouncer
```

To destroy the cluster, run:

```bash
make clean
```

---

## Cluster details

### PostgreSQL

* Users: `admin` and `test` (owning the `testdb` database)

### PgBouncer

* Instances: `pgbouncer-primary` (port 7432) and
  * `pgbouncer-primary` (port 7432), using sockets 10001 and 10002, is aiming at the primary
  * `pgbouncer-standby` (port 7433), using sockets 10101 and 10102, is aiming at the standby

From the `bouncer` node, to reach the PgBouncer administration console, use the `pgbouncer` or `admin` users:

```bash
psql -U pgbouncer -p 10001 -c "SHOW VERSION;"
psql -U pgbouncer -p 10002 -c "SHOW VERSION;"
psql -U admin -p 10001 -d pgbouncer -c "SHOW VERSION;"
psql -U admin -p 10002 -d pgbouncer -c "SHOW VERSION;"
psql -U pgbouncer -p 10101 -c "SHOW VERSION;"
psql -U pgbouncer -p 10102 -c "SHOW VERSION;"
psql -U admin -p 10101 -d pgbouncer -c "SHOW VERSION;"
psql -U admin -p 10102 -d pgbouncer -c "SHOW VERSION;"
```

To reach the `testdb` PgBouncer pool, use the `test` user. Connect to port 7432 to reach the primary, 7433 to reach the standby:

```bash
PGPASSWORD=Secret psql -U test -d testdb -h 127.0.0.1 -p 7432 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -h 127.0.0.1 -p 7433 -c "SELECT pg_is_in_recovery();"
```

The `bouncer` VM should receive the `10.0.0.11` IP, with the 7432 and 7433 port forwarded to the host, so you can use `-h 10.0.0.11` to reach those ports:

```bash
PGPASSWORD=Secret psql -U test -d testdb -h 10.0.0.11 -p 7432 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -h 10.0.0.11 -p 7433 -c "SELECT pg_is_in_recovery();"
```

On the `bouncer` guest VM, it is also possible to connect directly to a specific socket number to make sure it works:

```bash
PGPASSWORD=Secret psql -U test -d testdb -p 10001 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10002 -c "SELECT pg_is_in_recovery();"
```
