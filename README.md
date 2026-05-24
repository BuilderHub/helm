# BuilderHub Helm chart

Install the BuilderHub platform—operator, API, and web console—in one pass. Application charts are maintained in their own repositories; this repo wires them together with shared defaults and install toggles.

## Components

| Subchart | Source chart |
|----------|----------------|
| [build-operator](https://github.com/BuilderHub/build-operator/tree/main/helm/build-operator) | Kubernetes operator for BuildKit builders |
| [build-api](https://github.com/BuilderHub/build-api/tree/main/helm/build-api) | Public gRPC/HTTP API |
| [build-console](https://github.com/BuilderHub/build-console/tree/main/helm/build-console) | Web console |

Each subchart under [`charts/`](charts/) is a thin wrapper: it pins an upstream chart version from OCI and supplies platform-oriented defaults. Templates stay in the application repos.

## Prerequisites

- Kubernetes 1.25+
- Helm 3
- PostgreSQL reachable by the API if `build-api` is enabled (see upstream chart migrations)
- Application charts published to `oci://ghcr.io/builderhub/<chart-name>` (required for `helm dependency update`; use the bootstrap script below until those are available)

## Install from Git

```bash
./scripts/bootstrap-deps.sh   # vendor upstream charts for local use
helm install builderhub . -n builderhub --create-namespace
```

`bootstrap-deps.sh` clones the application repos, applies a small workaround for a missing helper in the `build-api` chart, writes `Chart.lock` files, and unpacks dependencies under each wrapper.

## Install from OCI (after a release)

```bash
helm install builderhub oci://ghcr.io/builderhub/helm/charts/builderhub \
  --version <release-version> \
  -n builderhub \
  --create-namespace
```

Replace `<release-version>` with a published release tag (without the `v` prefix), for example `0.1.0`.

## Configuration

Top-level toggles in [`values.yaml`](values.yaml):

```yaml
build-operator:
  enabled: true
build-api:
  enabled: true
build-console:
  enabled: true
```

Override settings for a component under the same key. Because each wrapper pulls in an upstream chart with the same name, nested values use a second level with that name—for example:

```yaml
build-api:
  enabled: true
  build-api:
    database:
      url: "postgres://user:pass@postgres:5432/builderhub?sslmode=disable"
    jwt:
      secret: "replace-me"
```

Production installs should replace dev defaults (database URL, JWT secret, CORS origins, ingress hosts, image tags).

## Makefile targets

```bash
make bootstrap-deps   # vendor upstream charts (same as the script)
make template         # render manifests locally
```

`make deps` runs `helm dependency update` against OCI and needs registry access plus published application charts.

## Releases

Publishing runs on GitHub release via [`.github/workflows/release.yaml`](.github/workflows/release.yaml): bootstrap dependencies, smoke-test with `helm template`, package the umbrella chart, and push to `oci://ghcr.io/builderhub/helm/charts`.

Release tags should be semver with an optional `v` prefix (`v0.1.0` → chart version `0.1.0`).

## Upstream chart publishing

Wrapper `helm dependency update` and clean `enabled: false` handling expect application charts at:

- `oci://ghcr.io/builderhub/build-operator`
- `oci://ghcr.io/builderhub/build-api`
- `oci://ghcr.io/builderhub/build-console`

Add chart publish workflows to those repositories so CI and end users can resolve dependencies without the bootstrap script.
