DOCKER_BUILD_ARGS=$(NO_CACHE) --quiet --force-rm --rm

all:
	@echo "TARGET         DESCRIPTION"
	@echo "env            clone the source to oftee and aaa into workspace"
	@echo "host.image     build the Docker image for example client host"
	@echo "oftee.image    build the Docker image for the oftee"
	@echo "aaa.image      build the Docker image for the aaa SDN app"
	@echo "pull.images    pull all standard images from dockhub.com"
	@echo "images         build or pull all required Docker imagges"
	@echo "bridge         create the ovs bridge"
	@echo "del-bridge     delete the ovs bridge"
	@echo "add-iface      add an interface to the ovs bridge for the host container"
	@echo "deploy         start the Docker Swarm stack (all the containers)"
	@echo "undeploy       delete the Docker Swarm stack (all the containers)"
	@echo "flows          push the EAP flow to packet in to the controller"
	@echo "flow-wait      same as flows, but waits for success"
	@echo "up             bring up everything"
	@echo "down           tear down everything"
	@echo "host.shell     start a shell in the host container"
	@echo "radius.shell   start a shell in the radius container"
	@echo "aaa.shell      start a shell in the aaa container"
	@echo "relay.shell    start a shell in the DHCP relay container"
	@echo "dhcpd.shell    start a shell in the DHCP server container"
	@echo "wpa            start a wpa_supplicant in the host container"
	@echo "dhcp           start a dhcp request in the host container"
	@echo "oftee.logs     tail -f the oftee logs"
	@echo "aaa.logs       tail -f the aaa SDN app logs"
	@echo "onos.logs      tail -f the onos logs"
	@echo "radius.logs    tail -f the radius logs"
	@echo "relay.logs     tail -f the DHCP relay logs"
	@echo "dhcp.logs      tail -f the DHCP server logs"

env:
	mkdir -p oftee/src/github.com/ciena aaa/src/github.com/ciena
	git clone http://github.com/ciena/oftee oftee/src/github.com/ciena/oftee
	git clone http://github.com/dbainbri-ciena/oftee-sdn-aaa-app aaa/src/github.com/ciena/aaa
	git clone http://github.com/dbainbri-ciena/oftee-sdn-dhcp-l3-relay-app dhcp-relay

host.image:
	docker build $(DOCKER_BUILD_ARGS) -t host:local -f example/docker/Dockerfile.host example/docker

oftee.image:
	docker build $(DOCKER_BUILD_ARGS) -t oftee:local -f oftee/src/github.com/ciena/oftee/Dockerfile oftee/src/github.com/ciena/oftee

aaa.image:
	docker build $(DOCKER_BUILD_ARGS) -t aaa:local -f aaa/src/github.com/ciena/aaa/Dockerfile aaa/src/github.com/ciena/aaa

relay.image:
	docker build $(DOCKER_BUILD_ARGS) -t dhcp-relay:local -f dhcp-relay/Dockerfile dhcp-relay

pull.images:
	docker pull freeradius/freeradius-server:latest
	docker pull onosproject/onos:1.13.1
	docker pull networkboot/dhcpd:latest

images: host.image oftee.image aaa.image relay.image pull.images

bridge:
	sudo sudo ovs-vsctl list-br | grep -q br0 || sudo ovs-vsctl add-br br0
	sudo ovs-vsctl set-controller br0 tcp:127.0.0.1:6654

del-bridge:
	sudo ovs-vsctl del-br br0

add-iface:
	sudo ovs-docker add-port br0 eth2 $(shell ./utils/cid oftee_host)

deploy:
	docker stack deploy -c example/oftee-stack.yml oftee

flows:
	curl -sSL -H 'Content-type: application/json' http://karaf:karaf@127.0.0.1:8181/onos/v1/flows/of:$(shell sudo ovs-ofctl show br0 | grep dpid | awk -F: '{print $$NF}')  -d@example/aaa_in.json
	curl -sSL -H 'Content-type: application/json' http://karaf:karaf@127.0.0.1:8181/onos/v1/flows/of:$(shell sudo ovs-ofctl show br0 | grep dpid | awk -F: '{print $$NF}')  -d@example/dhcp_in.json

flow-aaa-wait:
	@bash -c \
		curl --fail -sSL -H 'Content-type: application/json' http://karaf:karaf@127.0.0.1:8181/onos/v1/flows/of:$(shell sudo ovs-ofctl show br0 2>/dev/null | grep dpid | awk -F: '{print $$NF}')  -d@example/aaa_in.json 2>/dev/null 1>/dev/null; \
		while [ $$? -ne 0 ]; do \
		  echo "waiting for ONOS to accept flow requests ..."; \
		  sleep 3; \
		  curl --fail -sSL -H 'Content-type: application/json' http://karaf:karaf@127.0.0.1:8181/onos/v1/flows/of:$(shell sudo ovs-ofctl show br0 2>/dev/null | grep dpid | awk -F: '{print $$NF}')  -d@example/aaa_in.json 2>/dev/null 1>/dev/null; \
		done;

flow-dhcp-wait:
	@bash -c \
                curl --fail -sSL -H 'Content-type: application/json' http://karaf:karaf@127.0.0.1:8181/onos/v1/flows/of:$(shell sudo ovs-ofctl show br0 2>/dev/null | grep dpid | awk -F: '{print $$NF}')  -d@example/dhcp_in.json 2>/dev/null 1>/dev/null; \
                while [ $$? -ne 0 ]; do \
                  echo "waiting for ONOS to accept flow requests ..."; \
                  sleep 3; \
                  curl --fail -sSL -H 'Content-type: application/json' http://karaf:karaf@127.0.0.1:8181/onos/v1/flows/of:$(shell sudo ovs-ofctl show br0 2>/dev/null | grep dpid | awk -F: '{print $$NF}')  -d@example/dhcp_in.json 2>/dev/null 1>/dev/null; \
                done;

flow-wait: flow-aaa-wait flow-dhcp-wait

undeploy:
	docker stack rm oftee

up: bridge deploy add-iface flow-wait

down: undeploy del-bridge

wpa:
	docker exec -ti $(shell ./utils/cid oftee_host) wpa_supplicant -i eth2 -D wired -c /etc/wpa_supplicant/wpa_supplicant.conf -ddd

dhcp:
	docker exec -ti $(shell ./utils/cid oftee_host) dhclient -4 -v -d -1 eth2

host.shell:
	docker exec -ti $(shell ./utils/cid oftee_host) bash

radius.shell:
	docker exec -ti $(shell ./utils/cid oftee_radius) bash

aaa.shell:
	docker exec -ti $(shell ./utils/cid oftee_aaa) bash

relay.shell:
	docker exec -ti $(shell ./utils/cid oftee_relay) ash

dhcpd.shell:
	docker exec -ti $(shell ./utils/cid oftee_dhcpd) bash

oftee.logs:
	docker service logs --raw -f oftee_oftee

aaa.logs:
	docker service logs --raw -f oftee_aaa

radius.logs:
	docker service logs --raw -f oftee_radius

onos.logs:
	docker service logs -f oftee_onos

relay.logs:
	docker service logs -f oftee_relay

dhcp.logs:
	docker service logs -f oftee_dhcpd

clean:
	docker service rm oftee_relay oftee_oftee || true

try: clean relay.image deploy
