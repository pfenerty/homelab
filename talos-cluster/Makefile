# Makefile

CLUSTER_NAME   := rpi-cluster
ENDPOINT       := https://192.168.1.100:6443
SECRETS        := talos/secrets.yaml
OUTPUT         := talos/clusterconfig
PATCHES        := talos/patches

NODES          := rpi-01 rpi-02 rpi-03
NODE_IPS       := 192.168.1.101 192.168.1.102 192.168.1.103
VIP            := 192.168.1.100

TALOS_VERSION  := v1.12.5
SCHEMATIC      := ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9
IMAGE_URL      := factory.talos.dev/installer/$(SCHEMATIC):$(TALOS_VERSION)

# ── Config generation ──────────────────────────────────────────

.PHONY: generate validate clean

generate: $(OUTPUT)/rpi-01.yaml $(OUTPUT)/rpi-02.yaml $(OUTPUT)/rpi-03.yaml
	@echo "✓ All configs generated in $(OUTPUT)/"

$(OUTPUT)/controlplane.yaml: $(SECRETS) $(wildcard $(PATCHES)/*.yaml)
	@mkdir -p $(OUTPUT)
	talosctl gen config $(CLUSTER_NAME) $(ENDPOINT) \
		--with-secrets $(SECRETS) \
		--output $(OUTPUT)/ \
		--config-patch @$(PATCHES)/all-nodes.yaml \
		--config-patch-control-plane @$(PATCHES)/controlplane.yaml \
		--force

$(OUTPUT)/rpi-%.yaml: $(OUTPUT)/controlplane.yaml $(PATCHES)/rpi-%-network.yaml
	talosctl machineconfig patch $(OUTPUT)/controlplane.yaml \
		--patch @$(PATCHES)/rpi-$*-network.yaml \
		--output $@

validate: generate
	@for f in $(NODES); do \
		echo "Validating $$f..."; \
		talosctl validate --config $(OUTPUT)/$$f.yaml --mode metal; \
	done
	@echo "✓ All configs valid"

clean:
	rm -rf $(OUTPUT)

# ── Applying configs ───────────────────────────────────────────

# First-time apply via temporary DHCP IP:
#   make apply-rpi-01 NODE_DHCP_IP=192.168.1.121
apply-%: $(OUTPUT)/%.yaml
	talosctl apply-config --insecure \
		--nodes $(NODE_DHCP_IP) \
		--file $(OUTPUT)/$*.yaml

# Re-apply to already-configured nodes (using their static IPs)
apply-all:
	talosctl apply-config --nodes 192.168.1.101 --file $(OUTPUT)/rpi-01.yaml
	talosctl apply-config --nodes 192.168.1.102 --file $(OUTPUT)/rpi-02.yaml
	talosctl apply-config --nodes 192.168.1.103 --file $(OUTPUT)/rpi-03.yaml

# ── Bootstrap ──────────────────────────────────────────────────

bootstrap:
	talosctl config merge $(OUTPUT)/talosconfig
	talosctl config endpoint 192.168.1.101
	talosctl config node 192.168.1.101
	talosctl bootstrap --nodes 192.168.1.101

kubeconfig:
	talosctl kubeconfig --nodes $(VIP) -f ~/.kube/config

health:
	talosctl health --nodes $(VIP) --wait-timeout 15m

# ── Upgrades ───────────────────────────────────────────────────

# Usage: make upgrade-103  (upgrades node at 192.168.1.103)
upgrade-%:
	talosctl upgrade --nodes 192.168.1.$* --image $(IMAGE_URL)

# Upgrade all nodes: last-to-first order (103 → 102 → 101)
upgrade-all: upgrade-103 upgrade-102 upgrade-101
	@echo "✓ All nodes upgraded to $(TALOS_VERSION)"
