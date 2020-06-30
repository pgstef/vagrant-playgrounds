all: clean create_vm etcd patroni

create_vm:
	vagrant up

etcd:
	vagrant up --provision-with=etcd

patroni:
	vagrant up --provision-with=pgsql
	vagrant up --provision-with=patroni
	vagrant up --provision-with=haproxy
	vagrant up --provision-with=keepalived

clean:
	vagrant destroy -f