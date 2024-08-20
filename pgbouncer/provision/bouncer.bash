# Setup bouncer node
export DEBIAN_FRONTEND=noninteractive
sudo -E apt-get update
sudo -E apt-get -y install postgresql-client net-tools
sudo -E apt-get -y install curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
sudo -E apt-get update
sudo -E apt-get -y install pgbouncer
pgbouncer -V
sudo systemctl disable --now pgbouncer

cat<<EOF | sudo tee "/etc/pgbouncer/pgbouncer-primary-10001.ini"
[databases]
testdb = host=postgres0 port=5432 dbname=testdb

[peers]
1 = host=/run/postgresql port=10001
2 = host=/run/postgresql port=10002

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer-primary-10001.log
pool_mode = transaction
listen_addr = 0.0.0.0
listen_port = 7432
auth_type = hba
auth_file = /etc/pgbouncer/userlist.txt
auth_hba_file = /etc/pgbouncer/pgbouncer_hba.conf
admin_users = admin, pgbouncer
peer_id = 1
EOF

cat<<EOF | sudo tee "/etc/pgbouncer/pgbouncer-primary-10002.ini"
[databases]
testdb = host=postgres0 port=5432 dbname=testdb

[peers]
1 = host=/run/postgresql port=10001
2 = host=/run/postgresql port=10002

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer-primary-10002.log
pool_mode = transaction
listen_addr = 0.0.0.0
listen_port = 7432
auth_type = hba
auth_file = /etc/pgbouncer/userlist.txt
auth_hba_file = /etc/pgbouncer/pgbouncer_hba.conf
admin_users = admin, pgbouncer
peer_id = 2
EOF

cat<<EOF | sudo tee "/etc/systemd/system/pgbouncer_primary@.service"
[Unit]
Description=connection pooler for PostgreSQL (%i)
After=network.target
Requires=pgbouncer_primary@%i.socket

[Service]
Type=notify
User=postgres
ExecStart=/usr/sbin/pgbouncer /etc/pgbouncer/pgbouncer-primary-%i.ini
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

cat<<EOF | sudo tee "/etc/systemd/system/pgbouncer_primary@.socket"
[Unit]
Description=sockets (%i) for PgBouncer

[Socket]
ListenStream=0.0.0.0:7432
ListenStream=0.0.0.0:%i
ListenStream=/run/postgresql/.s.PGSQL.%i
ReusePort=true

[Install]
WantedBy=sockets.target
EOF

cat<<EOF | sudo tee "/etc/pgbouncer/pgbouncer-standby-10101.ini"
[databases]
testdb = host=postgres1 port=5432 dbname=testdb

[peers]
1 = host=/run/postgresql port=10101
2 = host=/run/postgresql port=10102

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer-standby-10101.log
pool_mode = transaction
listen_addr = 0.0.0.0
listen_port = 7433
auth_type = hba
auth_file = /etc/pgbouncer/userlist.txt
auth_hba_file = /etc/pgbouncer/pgbouncer_hba.conf
admin_users = admin, pgbouncer
peer_id = 1
EOF

cat<<EOF | sudo tee "/etc/pgbouncer/pgbouncer-standby-10102.ini"
[databases]
testdb = host=postgres1 port=5432 dbname=testdb

[peers]
1 = host=/run/postgresql port=10101
2 = host=/run/postgresql port=10102

[pgbouncer]
logfile = /var/log/postgresql/pgbouncer-standby-10102.log
pool_mode = transaction
listen_addr = 0.0.0.0
listen_port = 7433
auth_type = hba
auth_file = /etc/pgbouncer/userlist.txt
auth_hba_file = /etc/pgbouncer/pgbouncer_hba.conf
admin_users = admin, pgbouncer
peer_id = 2
EOF

cat<<EOF | sudo tee "/etc/systemd/system/pgbouncer_standby@.service"
[Unit]
Description=connection pooler for PostgreSQL (%i)
After=network.target
Requires=pgbouncer_standby@%i.socket

[Service]
Type=notify
User=postgres
ExecStart=/usr/sbin/pgbouncer /etc/pgbouncer/pgbouncer-standby-%i.ini
ExecReload=/bin/kill -HUP $MAINPID
KillSignal=SIGINT

[Install]
WantedBy=multi-user.target
EOF

cat<<EOF | sudo tee "/etc/systemd/system/pgbouncer_standby@.socket"
[Unit]
Description=sockets (%i) for PgBouncer

[Socket]
ListenStream=0.0.0.0:7433
ListenStream=0.0.0.0:%i
ListenStream=/run/postgresql/.s.PGSQL.%i
ReusePort=true

[Install]
WantedBy=sockets.target
EOF

sudo -iu postgres sh -c 'echo "*:*:*:admin:SuperSecret" > /var/lib/postgresql/.pgpass'
sudo -iu postgres chmod 600 /var/lib/postgresql/.pgpass
sudo -iu postgres psql -Atq -h postgres0 -U admin -d postgres -c "SELECT concat('\"', usename, '\" \"', passwd, '\"') FROM pg_shadow WHERE usename IN ('admin', 'test');" -o /etc/pgbouncer/userlist.txt

cat<<EOF | sudo tee "/etc/pgbouncer/pgbouncer_hba.conf"
local all all scram-sha-256
host all all 0.0.0.0/0 scram-sha-256
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now pgbouncer_primary@10001.socket
sudo systemctl enable --now pgbouncer_primary@10002.socket
sudo systemctl enable --now pgbouncer_standby@10101.socket
sudo systemctl enable --now pgbouncer_standby@10102.socket

sudo netstat -tulnp | grep -E '7432'
sudo systemctl list-sockets | grep pgbouncer_primary
sudo systemctl status pgbouncer_primary@*.socket
sudo -iu postgres psql -U pgbouncer -p 10001 -c "SHOW VERSION;"
sudo -iu postgres psql -U pgbouncer -p 10002 -c "SHOW VERSION;"
sudo -iu postgres psql -U admin -p 10001 -d pgbouncer -c "SHOW VERSION;"
sudo -iu postgres psql -U admin -p 10002 -d pgbouncer -c "SHOW VERSION;"
PGPASSWORD=Secret psql -U test -d testdb -h 127.0.0.1 -p 7432 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10001 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10002 -c "SELECT pg_is_in_recovery();"

sudo netstat -tulnp | grep -E '7433'
sudo systemctl list-sockets | grep pgbouncer_standby
sudo systemctl status pgbouncer_standby@*.socket
sudo -iu postgres psql -U pgbouncer -p 10101 -c "SHOW VERSION;"
sudo -iu postgres psql -U pgbouncer -p 10102 -c "SHOW VERSION;"
sudo -iu postgres psql -U admin -p 10101 -d pgbouncer -c "SHOW VERSION;"
sudo -iu postgres psql -U admin -p 10102 -d pgbouncer -c "SHOW VERSION;"
PGPASSWORD=Secret psql -U test -d testdb -h 127.0.0.1 -p 7433 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10101 -c "SELECT pg_is_in_recovery();"
PGPASSWORD=Secret psql -U test -d testdb -p 10102 -c "SELECT pg_is_in_recovery();"
