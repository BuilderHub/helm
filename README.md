# BuilderHub Helm chart

Install the BuilderHub platform—operator, API, and web console—in one pass.

**Chart source lives in this repository** under [`charts/`](charts/). The application repos (`build-operator`, `build-api`, `build-console`) ship container images only; their legacy `helm/` directories are not the deployment source of truth.

## Components

| Subchart | Path | Description |
|----------|------|-------------|
| build-operator | [`charts/build-operator`](charts/build-operator) | Kubernetes operator for BuildKit builders |
| build-api | [`charts/build-api`](charts/build-api) | Public gRPC/HTTP API |
| build-console | [`charts/build-console`](charts/build-console) | Web console |

## Prerequisites

- Kubernetes 1.25+
- Helm 3
- PostgreSQL reachable by the API if `build-api` is enabled (see [`charts/build-api/migrations/`](charts/build-api/migrations/))

## Install from Git

```bash
helm install builderhub . -n builderhub --create-namespace
```

## Install from OCI (after a release)

```bash
helm install builderhub oci://ghcr.io/builderhub/helm/charts/builderhub \
  --version <release-version> \
  -n builderhub \
  --create-namespace
```

Replace `<release-version>` with a published release tag (without the `v` prefix), for example `0.1.0`.

## Configuration

Component settings in [`values.yaml`](values.yaml):

```yaml
build-operator:
  operator:
    image:
      tag: latest
build-api:
  database:
    url: "postgres://user:pass@postgres:5432/builderhub?sslmode=disable"
  jwt:
    secret: "replace-me"
build-console:
  ingress:
    enabled: true
```

Production installs should replace dev defaults (database URL, JWT secret, CORS origins, ingress hosts, image tags). The console image must be built with `NEXT_PUBLIC_API_URL` at image build time (see [`charts/build-console/README.md`](charts/build-console/README.md)).

## Makefile targets

```bash
make lint      # lint umbrella and component charts
make template  # render all manifests locally
make verify    # check build-api migration hooks and RBAC
```

## Releases

Publishing runs on GitHub release via [`.github/workflows/release.yaml`](.github/workflows/release.yaml): lint, smoke-test with `helm template`, package the umbrella chart, and push to `oci://ghcr.io/builderhub/helm/charts`.

Release tags should be semver with an optional `v` prefix (`v0.1.0` → chart version `0.1.0`).

## PR checks

Pull requests that touch chart or CI paths run [`.github/workflows/on-pr.yaml`](.github/workflows/on-pr.yaml):

1. Lint/template committed charts under `charts/`
2. Create a KinD cluster, deploy Postgres and builder templates from [`ci/`](ci/)
3. `helm upgrade --install` operator and API charts directly (console skipped in e2e)
4. [`scripts/e2e-test.sh`](scripts/e2e-test.sh) registers a user, creates an organization and ephemeral builder, then runs a minimal `buildctl` build

CI manifests live under [`ci/`](ci/) so Helm does not treat them as a subchart.

## Editing charts

Change templates, values, or migrations under `charts/<component>/` in this repo. There is no sync step from upstream application repositories.
