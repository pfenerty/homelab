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

TALOS_VERSION      := v1.14.0
KUBERNETES_VERSION := v1.37.0
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
	upgrade-all upgrade-x86-01 upgrade-k8s upgrade-k8s-dry-run k8s-versions \
	cnpg-maintenance-on cnpg-maintenance-off bootstrap kubeconfig health

generate: $(OUTPUT)/rpi-01.yaml $(OUTPUT)/rpi-02.yaml $(OUTPUT)/rpi-03.yaml $(OUTPUT)/x86-01.yaml
	@echo "✓ All configs generated in $(OUTPUT)/"

# Makefile is a prerequisite so a TALOS_VERSION/KUBERNETES_VERSION bump forces a
# regenerate — otherwise the configs on disk keep the versions they were pinned
# to and `repatch-%` silently applies a stale one.
$(OUTPUT)/controlplane.yaml: $(SECRETS) $(wildcard $(PATCHES)/*.yaml) Makefile
	@mkdir -p $(OUTPUT)
	sops exec-file $(SECRETS) 'talosctl gen config $(CLUSTER_NAME) $(ENDPOINT) --with-secrets {} --talos-version $(TALOS_VERSION) --kubernetes-version $(KUBERNETES_VERSION:v%=%) --output $(OUTPUT)/ --config-patch @$(PATCHES)/all-nodes.yaml --config-patch-control-plane @$(PATCHES)/controlplane.yaml --force'
	@# `gen config` writes talosconfig with `endpoints: []`, so every talosctl
	@# call that does not pass --endpoints fails with "failed to determine
	@# endpoints". Point it at the control-plane nodes once, here.
	talosctl --talosconfig $(TALOSCONFIG) config endpoint $(NODE_IPS)

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
	talosctl kubeconfig --talosconfig $(TALOSCONFIG) --endpoints $(VIP) --nodes $(VIP) -f ~/.kube/config

health:
	talosctl health --talosconfig $(TALOSCONFIG) --endpoints $(VIP) --nodes $(VIP) --wait-timeout 15m

# ── Upgrades ───────────────────────────────────────────────────

# Every Talos upgrade cordons and drains the node before rebooting it, so a run
# that dies partway leaves the node cordoned with nothing upgraded. Each target
# below uncordons on the way out — success, failure or Ctrl-C.

DRAIN         ?= true
# CNPG gives the Postgres pod terminationGracePeriodSeconds=1800; talosctl's 5m
# default leaves no margin on Pi-class hardware.
DRAIN_TIMEOUT ?= 10m

# Talos node names are generated (talos-jlf-6ro), so resolve them from the IP.
node_name = kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null | awk '$$2=="$(1)"{print $$1}'

# Usage: make upgrade-103  (upgrades node at 192.168.1.103)
upgrade-%:
	@if [ "$*" = "104" ]; then \
		echo "✗ 192.168.1.104 is the amd64 worker — use 'make upgrade-x86-01' (different schematic)"; \
		exit 1; \
	fi
	@set -e; \
	node=$$($(call node_name,192.168.1.$*)); rc=0; \
	trap 'kubectl uncordon "$$node" >/dev/null 2>&1 || true; exit 130' INT TERM; \
	talosctl upgrade --talosconfig $(TALOSCONFIG) --endpoints 192.168.1.$* --nodes 192.168.1.$* \
		--image $(IMAGE_URL) --drain=$(DRAIN) --drain-timeout=$(DRAIN_TIMEOUT) || rc=$$?; \
	kubectl uncordon "$$node" >/dev/null 2>&1 || true; \
	exit $$rc

# Upgrade every node: control plane last-to-first (103 → 102 → 101), then the
# worker, then prove the cluster actually came back.
upgrade-all: upgrade-103 upgrade-102 upgrade-101 upgrade-x86-01
	@echo "✓ All nodes upgraded to $(TALOS_VERSION)"
	@$(MAKE) --no-print-directory health

# Upgrade the amd64 worker (its own schematic — binfmt-misc, not the RPi overlay).
#
# The worker runs ocidex's CloudNativePG instance on local-path storage: the PVC
# is pinned to this node and the PDB allows zero disruptions, so a plain drain
# can never evict it. Opening CNPG's node-maintenance window drops that PDB —
# but the Cluster CR is Flux-managed, and a reconcile puts the PDB straight back
# mid-drain, so the window only holds while its kustomization is suspended.
# This target runs that whole sequence and always unwinds it, failure included.
#
#   make upgrade-x86-01                    # maintenance window + drain
#   make upgrade-x86-01 MAINTENANCE=false  # leave CNPG and Flux alone
#   make upgrade-x86-01 DRAIN=false        # no cordon/drain; reboot stops pods
MAINTENANCE ?= true

upgrade-x86-01:
	@set -e; \
	node=$$($(call node_name,$(NODE_IP_x86-01))); rc=0; \
	unwind() { \
		if [ "$(MAINTENANCE)" = "true" ]; then $(MAKE) --no-print-directory cnpg-maintenance-off; fi; \
		kubectl uncordon "$$node" >/dev/null 2>&1 || true; \
	}; \
	trap 'unwind; exit 130' INT TERM; \
	if [ "$(MAINTENANCE)" = "true" ]; then $(MAKE) --no-print-directory cnpg-maintenance-on; fi; \
	talosctl upgrade --talosconfig $(TALOSCONFIG) --endpoints $(VIP) --nodes $(NODE_IP_x86-01) \
		--image $(WORKER_IMAGE_URL) --drain=$(DRAIN) --drain-timeout=$(DRAIN_TIMEOUT) || rc=$$?; \
	unwind; \
	exit $$rc

# ── CloudNativePG node-maintenance window ──────────────────────

CNPG_CLUSTER := ocidex-pg
CNPG_NS      := ocidex-dev
CNPG_FLUX_KS := ocidex-dev-infra

# Suspend Flux, open the window, and confirm the PDB is actually gone — that is
# the precondition a drain depends on, and it is worth failing early rather than
# discovering it five minutes into an eviction retry loop. If the window cannot
# be opened, unwind (resume Flux) rather than leaving reconciliation suspended.
cnpg-maintenance-on:
	@set -e; \
	flux suspend kustomization $(CNPG_FLUX_KS); \
	for i in 1 2 3 4 5 6; do \
		if kubectl patch cluster $(CNPG_CLUSTER) -n $(CNPG_NS) --type=merge \
			-p '{"spec":{"nodeMaintenanceWindow":{"inProgress":true,"reusePVC":true}}}' >/dev/null 2>&1; then \
			break; \
		fi; \
		echo "  CNPG webhook not answering yet ($$i/6) — its operator pod may still be rescheduling"; \
		sleep 10; \
	done; \
	for i in 1 2 3 4 5 6; do \
		if [ -z "$$(kubectl get pdb -n $(CNPG_NS) -l cnpg.io/cluster=$(CNPG_CLUSTER) -o name 2>/dev/null)" ]; then \
			echo "✓ maintenance window open ($(CNPG_FLUX_KS) suspended, PDB dropped)"; \
			exit 0; \
		fi; \
		sleep 5; \
	done; \
	echo "✗ $(CNPG_CLUSTER) PDB is still present — a drain would block. Unwinding."; \
	$(MAKE) --no-print-directory cnpg-maintenance-off; \
	exit 1

# The patch can fail right after the worker reboots: CNPG's webhook is served by
# an operator pod that runs on that very node. Retry it, but resume Flux either
# way — a resumed reconcile clears the window on its own, since git never
# declared it.
cnpg-maintenance-off:
	@for i in 1 2 3 4 5 6; do \
		if kubectl patch cluster $(CNPG_CLUSTER) -n $(CNPG_NS) --type=merge \
			-p '{"spec":{"nodeMaintenanceWindow":{"inProgress":false}}}' >/dev/null 2>&1; then \
			break; \
		fi; \
		echo "  CNPG webhook not answering yet ($$i/6) — its operator runs on the node that just rebooted"; \
		sleep 10; \
	done
	@flux resume kustomization $(CNPG_FLUX_KS)
	@echo "✓ maintenance window closed ($(CNPG_FLUX_KS) resumed)"

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
