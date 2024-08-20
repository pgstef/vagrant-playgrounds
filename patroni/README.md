# How to bootstrap a patroni cluster using vagrant

## Introduction

This `Vagrantfile` is bootstrapping a fresh cluster with:

* etcd: 3 nodes
* PostgreSQL 12 + patroni: 2 nodes
* HAProxy: on each PostgreSQL / patroni node
* Keepalived: vip management
* watchdog enabled

Nodes names: `etcd*`, `pg-patroni*`.

PostgreSQL version, number of etcd / patroni nodes, virtual ip and patroni
scope name can be configured in the `Vagrantfile`.

### To be improved

* etcd with HTTPS and specific user
* HAProxy with HTTPS

### To add / other possibilities

* to add
  * pgBackRest
  * monitoring

* other possibilities
  * vip: https://github.com/cybertec-postgresql/vip-manager

---

## Create the cluster

To create the cluster, run:

```bash
make all
```

After some minutes and tons of log messages, you can connect to your servers
using eg.:

```bash
vagrant ssh etcd1
vagrant ssh pg-patroni1
```

To destroy your cluster, run:

```bash
make clean
```

---

## Get URLs with private IPs

To get a list of some usual URLs reachable through the private network, run:

```bash
vagrant up --provision-with=get_urls <nodename>
```

`<nodename>` may be any node.

Using `etcd1` will print something like:

```bash
etcd1: --------ETCD--------
etcd1: etcd1 health:  http://192.168.122.139:2379/health
etcd1: etcd1 metrics: http://192.168.122.139:2379/metrics
etcd1: etcd2 health:  http://192.168.122.143:2379/health
etcd1: etcd2 metrics: http://192.168.122.143:2379/metrics
etcd1: etcd3 health:  http://192.168.122.208:2379/health
etcd1: etcd3 metrics: http://192.168.122.208:2379/metrics
etcd1: --------PATRONI--------
etcd1: patroni cluster state: http://192.168.122.251:8008/cluster
etcd1: pg-patroni1 endpoint:  http://192.168.122.130:8008/patroni
etcd1: pg-patroni2 endpoint:  http://192.168.122.225:8008/patroni
etcd1: scope: demo
etcd1: config file: /etc/patroni-demo.yml
etcd1: --------HAProxy--------
etcd1: Haproxy Statistics: http://192.168.122.251:7000
etcd1: --------VIP--------
etcd1: read-write: 192.168.122.251:5000
etcd1: read-only : 192.168.122.251:5001
```

---

## PostgreSQL access

You can use the `read-write` or `read-only` URLs to access the PostgreSQL cluster,
using the provided IP and PORT.

A PostgreSQL superuser has been bootstrapped: *admin* / __admin__.

Example:

```bash
$ psql -U admin -d postgres -h 192.168.122.251 -p 5000 -c "SELECT * FROM pg_is_in_recovery();"
 pg_is_in_recovery 
-------------------
 f
(1 row)

$ psql -U admin -d postgres -h 192.168.122.251 -p 5001 -c "SELECT * FROM pg_is_in_recovery();"
 pg_is_in_recovery 
-------------------
 t
(1 row)
```

---

## patronictl

The `patronictl` can be used on the `pg-patroni*` nodes. The configuration file
can be showed in the `get_urls` above script. For conveniency, a `/etc/patroni.yml`
symlink is created.

### List

Use:

```bash
vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml list"
```

```bash
+ Cluster: demo (6844088724443827679) ---+---------+----+-----------+
|    Member   |       Host      |  Role  |  State  | TL | Lag in MB |
+-------------+-----------------+--------+---------+----+-----------+
| pg-patroni1 | 192.168.122.130 | Leader | running |  1 |           |
| pg-patroni2 | 192.168.122.225 |        | running |  1 |         0 |
+-------------+-----------------+--------+---------+----+-----------+
```

### Maintenance mode

To pause / resume cluster management, use:

```bash
vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml pause"
vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml resume"
```

### Switchover

Use:

```bash
vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml switchover"
```

Get status again after switchover:

```bash
vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml list"
+ Cluster: demo (6844088724443827679) ---+---------+----+-----------+
|    Member   |       Host      |  Role  |  State  | TL | Lag in MB |
+-------------+-----------------+--------+---------+----+-----------+
| pg-patroni1 | 192.168.122.130 |        | running |  2 |         0 |
| pg-patroni2 | 192.168.122.225 | Leader | running |  2 |           |
+-------------+-----------------+--------+---------+----+-----------+
```

### Get history

Use:

```bash
vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml history"
```

```bash
+----+----------+------------------------------+---------------------------+
| TL |      LSN |            Reason            |         Timestamp         |
+----+----------+------------------------------+---------------------------+
|  1 | 67109024 | no recovery target specified | 2020-06-30T14:03:22+02:00 |
+----+----------+------------------------------+---------------------------+
```

### Reinitialize a cluster member

To reinitialize `pg-patroni1` member of the `demo` cluster, use:

```bash
vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml reinit demo pg-patroni1 --wait"
```

```bash
+ Cluster: demo (6844088724443827679) ---+---------+----+-----------+
|    Member   |       Host      |  Role  |  State  | TL | Lag in MB |
+-------------+-----------------+--------+---------+----+-----------+
| pg-patroni1 | 192.168.122.130 |        | running |  2 |         0 |
| pg-patroni2 | 192.168.122.225 | Leader | running |  2 |           |
+-------------+-----------------+--------+---------+----+-----------+
Are you sure you want to reinitialize members pg-patroni1? [y/N]: y
Success: reinitialize for member pg-patroni1
Waiting for reinitialize to complete on: pg-patroni1
Reinitialize is completed on: pg-patroni1
```

---

## Testing

* `pkill postgres`
* `kill -9` patroni pid
* `echo c > /proc/sysrq-trigger`
* `rm -rf /var/lib/pgsql/12/data`
* `systemctl stop etcd` on 2 nodes

### `pkill postgres`

#### Standby

```bash
$ ps -o pid,cmd fx
  PID CMD
14343 -bash
14661  \_ ps -o pid,cmd fx
14145 /usr/pgsql-12/bin/postgres ...
14147  \_ postgres: demo: logger   
14148  \_ postgres: demo: startup   recovering 000000020000000000000006
14149  \_ postgres: demo: checkpointer   
14150  \_ postgres: demo: background writer   
14151  \_ postgres: demo: stats collector   
14152  \_ postgres: demo: walreceiver   
14154  \_ postgres: demo: postgres postgres 127.0.0.1(42710) idle
 3531 /bin/python3 /usr/local/bin/patroni /etc/patroni.yml

$ pkill postgres
$ ps -o pid,cmd fx
  PID CMD
14343 -bash
14767  \_ ps -o pid,cmd fx
 3531 /bin/python3 /usr/local/bin/patroni /etc/patroni.yml

$ cat postgresql-Tue.log
...
LOG:  received smart shutdown request
FATAL:  terminating walreceiver process due to administrator command
FATAL:  terminating connection due to administrator command
LOG:  shutting down
LOG:  database system is shut down
LOG:  database system was shut down in recovery at 2020-06-30 14:09:57 CEST
LOG:  entering standby mode
LOG:  redo starts at 0/5000028
LOG:  consistent recovery state reached at 0/6000060
LOG:  invalid record length at 0/6000060: wanted 24, got 0
LOG:  database system is ready to accept read only connections
LOG:  started streaming WAL from primary at 0/6000000 on timeline 2
```

The standby PostgreSQL server is restarted within a few seconds.

#### Leader

```bash
$ ps -o pid,cmd fx
  PID CMD
15177 -bash
15234  \_ ps -o pid,cmd fx
 3797 /usr/pgsql-12/bin/postgres ...
 3803  \_ postgres: demo: logger   
 3827  \_ postgres: demo: checkpointer   
 3828  \_ postgres: demo: background writer   
 3831  \_ postgres: demo: postgres postgres 127.0.0.1(57948) idle
12527  \_ postgres: demo: walwriter   
12528  \_ postgres: demo: archiver   last was 000000020000000000000005.00000028.backup
12529  \_ postgres: demo: logical replication launcher   
14140  \_ postgres: demo: walsender replicator 192.168.122.130(56766) streaming 0/6000148
 3527 /bin/python3 /usr/local/bin/patroni /etc/patroni.yml

$ pkill postgres

$ cat postgresql-Tue.log 
...
LOG:  received smart shutdown request
FATAL:  terminating connection due to administrator command
FATAL:  terminating connection due to administrator command
LOG:  background worker "logical replication launcher" (PID 12529) exited with exit code 1
LOG:  database system is shut down
LOG:  database system was shut down at 2020-06-30 14:14:31 CEST
LOG:  entering standby mode
LOG:  consistent recovery state reached at 0/70000A0
LOG:  invalid record length at 0/70000A0: wanted 24, got 0
LOG:  database system is ready to accept read only connections
LOG:  received promote request
LOG:  redo is not required
LOG:  selected new timeline ID: 3
LOG:  archive recovery complete
LOG:  database system is ready to accept connections
```

Using `patronictl`:

```bash
$ vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml list"
+ Cluster: demo (6844088724443827679) ---+---------+----+-----------+
|    Member   |       Host      |  Role  |  State  | TL | Lag in MB |
+-------------+-----------------+--------+---------+----+-----------+
| pg-patroni1 | 192.168.122.130 |        | running |  3 |         0 |
| pg-patroni2 | 192.168.122.225 | Leader | running |  3 |           |
+-------------+-----------------+--------+---------+----+-----------+

$ vagrant ssh pg-patroni1 -c "patronictl -c /etc/patroni.yml history"
+----+-----------+------------------------------+---------------------------+
| TL |       LSN |            Reason            |         Timestamp         |
+----+-----------+------------------------------+---------------------------+
|  1 |  67109024 | no recovery target specified | 2020-06-30T14:03:22+02:00 |
|  2 | 117440672 | no recovery target specified | 2020-06-30T14:14:35+02:00 |
+----+-----------+------------------------------+---------------------------+
```

PostgreSQL was restarted quickly and since it started as standby before being
promoted by patroni, a new timeline was selected.
