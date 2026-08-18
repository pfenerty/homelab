# ocidex

The OCIDex deployment on this cluster. Everything lives under `dev/`, reconciled by one
root `ocidex-dev-*.kustomization.yaml` per directory (see `../../kustomization.yaml`).

| Directory | Flux Kustomization | What |
|-----------|--------------------|------|
| `dev/infra/` | `ocidex-dev-infra` | CNPG Postgres cluster + app secret |
| `dev/main/` | `ocidex-dev-main` | The `ocidex` chart — API, workers, web, HTTPRoute for https://ocidex.app |
| `dev/operator/` | `ocidex-dev-operator` | `ocidex-operator` chart, watching `ocidex-dev` for CRDs |
| `dev/registries/` | `ocidex-dev-registries` | `OCIRegistry` CRs the operator reconciles |
| `dev/k8s-agent/` | `ocidex-dev-k8s-agent` | `ocidex-k8s-agent` chart — cluster inventory (ADR-044). **Scaffold, not yet enabled** |

Charts come from `oci://ghcr.io/pfenerty/charts` via the `ocidex` HelmRepository in
`dev/main/helmrepository.yaml`. Dev releases pin no `image.tag`, so each one renders the
chart's `appVersion` (`sha-<sha>`), which advances on every push build.

## Enabling the k8s inventory agent

`dev/k8s-agent/` is committed complete except for the two things that cannot be guessed,
and its root kustomization is commented out of `../../kustomization.yaml` until both exist
— an empty `cluster.id` would make the agent's full-snapshot pushes replace the wrong
cluster's inventory, and there is no `secrets.enc.yaml` for the kustomize build to find.

1. Register the cluster in OCIDex (UI, or `POST /api/v1/clusters`) and paste the returned
   UUID into `dev/k8s-agent/helmrelease.yaml` under `values.cluster.id`.
2. Create an API key with the `read-write` scope, owned by the user who owns the namespace
   the cluster is registered under, then:
   ```bash
   cp dev/k8s-agent/secrets.template.yaml dev/k8s-agent/secrets.enc.yaml
   # replace <api_key>, then encrypt in place
   sops -e -i dev/k8s-agent/secrets.enc.yaml
   ```
3. Uncomment `- ocidex-dev-k8s-agent.kustomization.yaml` in `../../kustomization.yaml`.

The agent reaches the API in-cluster
(`http://ocidex-dev-api.ocidex-dev.svc.cluster.local`) rather than through the public
hostname: this is the unusual case where the reported cluster is also the one hosting
OCIDex, so the push never has to leave the cluster network.

## Connecting an agent (MCP)

`ocidex-mcp` is a local stdio server, not a workload — ADR-045 deliberately ships no image,
so nothing about it is deployed here. Install it on the workstation and point it at this
cluster's instance:

```bash
go install github.com/pfenerty/ocidex/cmd/ocidex-mcp@latest
ocidex-cli login --server-url https://ocidex.app   # writes ~/.config/ocidex/config.yaml, mode 0600
claude mcp add ocidex --env OCIDEX_URL=https://ocidex.app -- ocidex-mcp
```

The `--env` is belt-and-braces: `login --server-url` already records the URL in the
shared config, and the MCP server reads the same file. Set it when the workstation talks to
more than one OCIDex.

`go install ... @latest` only resolves once the `ocidex-x59x` epic branch lands on
`main`; until then build it from a checkout (`make build` produces `bin/ocidex-mcp`).

Full tool list, troubleshooting and the credential rules are in `ocidex/docs/MCP.md`.
