SHARED_DIR = shared
.PHONY: all clean create_vm pgsql

all: create_vm pgsql

create_vm:
	@if [ ! -d "$(SHARED_DIR)" ]; then \
		mkdir $(SHARED_DIR); \
	fi
	vagrant up

pgsql:
	vagrant up --provision-with=postgres0
	vagrant up --provision-with=postgres1
	vagrant up --provision-with=bouncer

clean:
	vagrant destroy -f
	@if [ -d "$(SHARED_DIR)" ]; then \
		rm -r $(SHARED_DIR); \
	fi
