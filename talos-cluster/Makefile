# Makefile

export SOPS_AGE_KEY_FILE := $(CURDIR)/../age.key

CLUSTER_NAME   := rpi-cluster
ENDPOINT       := https://192.168.1.100:6443
SECRETS        := talos/secrets.yaml
OUTPUT         := talos/clusterconfig
TALOSCONFIG    := $(CURDIR)/$(OUTPUT)/talosconfig
PATCHES        := talos/patches

NODES          := rpi-01 rpi-02 rpi-03
NODE_IPS       := 192.168.1.101 192.168.1.102 192.168.1.103

NODE_IP_rpi-01 := 192.168.1.101
NODE_IP_rpi-02 := 192.168.1.102
NODE_IP_rpi-03 := 192.168.1.103
VIP            := 192.168.1.100

WORKER_NODES       := x86-01
NODE_IP_x86-01     := 192.168.1.104

TALOS_VERSION      := v1.13.9
KUBERNETES_VERSION := v1.36.4
# RPi (arm64) control-plane nodes: unchanged (sbc-raspberrypi overlay, no extensions).
# Multi-arch container builds are pinned to the amd64 worker, so binfmt lives only there.
SCHEMATIC          := ee21ef4a5ef808a9b7484cc0dda0f25075021691c8c09a276591eedb638ea1f9
IMAGE_URL          := factory.talos.dev/installer/$(SCHEMATIC):$(TALOS_VERSION)
# amd64 worker schematic: siderolabs/binfmt-misc extension (ships binfmt_misc.ko,
# which the stock image strips) so the worker can emulate arm64 for melange builds.
# Source: customization.systemExtensions.officialExtensions: [siderolabs/binfmt-misc]
WORKER_SCHEMATIC   := 14e9b0100f05654bedf19b92313cdc224cbff52879193d24f3741f1da4a3cbb1
WORKER_IMAGE_URL   := factory.talos.dev/installer/$(WORKER_SCHEMATIC):$(TALOS_VERSION)

# ── Config generation ──────────────────────────────────────────

.PHONY: generate validate clean repatch-all repatch-x86-01 \
	upgrade-k8s upgrade-k8s-dry-run k8s-versions

generate: $(OUTPUT)/rpi-01.yaml $(OUTPUT)/rpi-02.yaml $(OUTPUT)/rpi-03.yaml $(OUTPUT)/x86-01.yaml
	@echo "✓ All configs generated in $(OUTPUT)/"

$(OUTPUT)/controlplane.yaml: $(SECRETS) $(wildcard $(PATCHES)/*.yaml)
	@mkdir -p $(OUTPUT)
	sops exec-file $(SECRETS) 'talosctl gen config $(CLUSTER_NAME) $(ENDPOINT) --with-secrets {} --talos-version $(TALOS_VERSION) --kubernetes-version $(KUBERNETES_VERSION:v%=%) --output $(OUTPUT)/ --config-patch @$(PATCHES)/all-nodes.yaml --config-patch-control-plane @$(PATCHES)/controlplane.yaml --force'

$(OUTPUT)/rpi-%.yaml: $(OUTPUT)/controlplane.yaml $(PATCHES)/rpi-%-network.yaml
	talosctl machineconfig patch $(OUTPUT)/controlplane.yaml \
		--patch @$(PATCHES)/rpi-$*-network.yaml \
		--output $@

$(OUTPUT)/x86-01.yaml: $(OUTPUT)/controlplane.yaml $(PATCHES)/x86-01-network.yaml
	talosctl machineconfig patch $(OUTPUT)/worker.yaml \
		--patch @$(PATCHES)/x86-01-network.yaml \
		--output $@

validate: generate
	@for f in $(NODES) $(WORKER_NODES); do \
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
	talosctl apply-config --talosconfig $(TALOSCONFIG) --nodes 192.168.1.101 --endpoints $(VIP) --file $(OUTPUT)/rpi-01.yaml
	talosctl apply-config --talosconfig $(TALOSCONFIG) --nodes 192.168.1.102 --endpoints $(VIP) --file $(OUTPUT)/rpi-02.yaml
	talosctl apply-config --talosconfig $(TALOSCONFIG) --nodes 192.168.1.103 --endpoints $(VIP) --file $(OUTPUT)/rpi-03.yaml

# Re-apply patches to a node by regenerating its config from patches + existing
# secrets (via the same $(OUTPUT)/%.yaml rules `generate` uses) and applying it.
# `talosctl gen config --with-secrets` reuses the existing CA/tokens, so this is
# idempotent and safe to re-run.
# NOTE: previously this re-patched an *already-patched* $(OUTPUT)/%.yaml with
# all-nodes.yaml/controlplane.yaml a second time. Since Talos merges list fields
# (like `files:`) additively rather than replacing them, that duplicated any list
# entries on every repatch — which surfaced as a `files.talos.dev already exists`
# boot failure once all-nodes.yaml gained a `files:` block. Building from the
# generate targets avoids double-applying any patch.
# Usage: make repatch-rpi-01  or  make repatch-all
repatch-%: $(OUTPUT)/%.yaml
	talosctl apply-config --talosconfig $(TALOSCONFIG) --endpoints $(NODE_IP_$*) --nodes $(NODE_IP_$*) --file $(OUTPUT)/$*.yaml

repatch-x86-01: $(OUTPUT)/x86-01.yaml
	talosctl apply-config --talosconfig $(TALOSCONFIG) --endpoints $(NODE_IP_x86-01) --nodes $(NODE_IP_x86-01) --file $(OUTPUT)/x86-01.yaml

repatch-all: repatch-rpi-01 repatch-rpi-02 repatch-rpi-03 repatch-x86-01
	@echo "✓ Patches re-applied to all nodes"

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
	talosctl upgrade --talosconfig $(TALOSCONFIG) --endpoints 192.168.1.$* --nodes 192.168.1.$* --image $(IMAGE_URL)

# Upgrade all nodes: last-to-first order (103 → 102 → 101)
upgrade-all: upgrade-103 upgrade-102 upgrade-101
	@echo "✓ All nodes upgraded to $(TALOS_VERSION)"

# Upgrade x86 worker (uses standard installer, not RPi factory schematic)
upgrade-x86-01:
	talosctl upgrade --nodes $(NODE_IP_x86-01) --image $(WORKER_IMAGE_URL) --talosconfig $(TALOSCONFIG)

# ── Kubernetes upgrades ────────────────────────────────────────

# `talosctl upgrade-k8s` upgrades the whole cluster in a single run: it rewrites
# the control-plane static-pod manifests on every control-plane node, rolls the
# kubelet on every node (workers included), and re-applies the bundled manifests.
# It is driven through one control-plane node — the VIP is fine.
#
# KUBERNETES_VERSION at the top of this file is the source of truth (Renovate
# bumps it, and `make generate` bakes it into the machine configs). Override
# ad hoc with: make upgrade-k8s K8S_TO=1.36.5
K8S_TO ?= $(KUBERNETES_VERSION:v%=%)

# --with-docs/--with-examples default to true, which injects commented field
# documentation into the machine config talosctl writes back to each node.
# Configs here are generated from patches, so keep the node-side copies lean.
K8S_UPGRADE_FLAGS := --talosconfig $(TALOSCONFIG) --endpoints $(VIP) --nodes $(VIP) \
	--with-docs=false --with-examples=false

# Show the upgrade plan without touching the cluster.
upgrade-k8s-dry-run:
	talosctl upgrade-k8s $(K8S_UPGRADE_FLAGS) --to $(K8S_TO) --dry-run

# Usage: make upgrade-k8s  (upgrades to $(KUBERNETES_VERSION))
upgrade-k8s:
	talosctl upgrade-k8s $(K8S_UPGRADE_FLAGS) --to $(K8S_TO)
	@echo "✓ Kubernetes upgraded to v$(K8S_TO)"

# Kubelet + control-plane versions per node. Skew here (e.g. after a `repatch-%`
# that carried a newer KUBERNETES_VERSION into one node's config) means the
# cluster needs `make upgrade-k8s` to converge.
k8s-versions:
	@echo "Target: v$(K8S_TO)"
	@kubectl get nodes -o custom-columns=NODE:.metadata.name,IP:.status.addresses[0].address,KUBELET:.status.nodeInfo.kubeletVersion,OS-IMAGE:.status.nodeInfo.osImage
	@kubectl get pods -n kube-system -l k8s-app=kube-apiserver \
		-o custom-columns=APISERVER:.spec.nodeName,IMAGE:.spec.containers[0].image
