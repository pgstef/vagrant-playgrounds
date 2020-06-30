vm_prefix = 'patroni_c7'
pgver = '12' # pg version to use
etcd_nodes = 3 # nb of etcd nodes to create
patroni_nodes = 2 # nb of pg/patroni nodes to create
vip = '192.168.122.251' # vip to use
cluster_name = 'demo' # patroni scope

Vagrant.configure(2) do |config|

    pgdata = "/var/lib/pgsql/#{pgver}/data"

    config.vm.box = 'centos/7'

    # hardware and host settings
    config.vm.provider 'libvirt' do |lv|
        lv.cpus = 1
        lv.memory = 1024
        lv.default_prefix = vm_prefix
	end

    # don't mind about insecure ssh key
    config.ssh.insert_key = false

    # common install on all nodes
    config.vm.provision 'common', type: 'shell',
    path: 'provision/common.bash',
    args: [ etcd_nodes, patroni_nodes, vip, cluster_name ]

    # cluster etcd
    (1..etcd_nodes).each do |i|
        config.vm.define "etcd#{i}" do |etcd|
            etcd.vm.hostname = "etcd#{i}"

            # install etcd. Use "vagrant up --provision-with=etcd"
            etcd.vm.provision 'etcd', type: 'shell',
                path: 'provision/etcd.bash',
                args: [ etcd_nodes ], run: 'never'
        end  
    end

    # cluster patroni
    (1..patroni_nodes).each do |i|
        config.vm.define "pg-patroni#{i}" do |patroni|
            patroni.vm.hostname = "pg-patroni#{i}"

            # install PostgreSQL. Use "vagrant up --provision-with=pgsql"
            patroni.vm.provision 'pgsql', type: 'shell', 
                path: 'provision/pgsql.bash', 
                args: [ pgver ], run: 'never'
            
            # install patroni. Use "vagrant up --provision-with=patroni"
            patroni.vm.provision 'patroni', type: 'shell', 
                path: 'provision/patroni.bash',
                args: [ pgver, pgdata, etcd_nodes, vip, cluster_name ], run: 'never'

            # install haproxy. Use "vagrant up --provision-with=haproxy"
            patroni.vm.provision 'haproxy', type: 'shell', 
                path: 'provision/haproxy.bash',
                args: [ patroni_nodes ], run: 'never'

            # install keepalived. Use "vagrant up --provision-with=keepalived"
            patroni.vm.provision 'keepalived', type: 'shell',
                path: 'provision/keepalived.bash',
                args: [ vip ], run: 'never'
        end
    end

    # get urls. Use "vagrant up --provision-with=get_urls"
    config.vm.provision 'get_urls', type: 'shell',
        path: 'provision/get_urls.bash',
        args: [ etcd_nodes, patroni_nodes, vip, cluster_name ], run: 'never'
end