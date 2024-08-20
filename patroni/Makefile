all: clean create_vm etcd pgsql patroni pgbackrest

create_vm:
	vagrant up

etcd:
	vagrant up --provision-with=etcd

pgsql:
	vagrant up --provision-with=pgsql

patroni:
	vagrant up --provision-with=patroni
	vagrant up --provision-with=haproxy
	vagrant up --provision-with=keepalived

pgbackrest:
	vagrant up --provision-with=pgbackrest_remote

clean:
	vagrant destroy -f