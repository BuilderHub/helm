#!/usr/bin/env bash
# Local KinD smoke test mirroring CI chart install (operator + api).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export PATH="${ROOT}/bin:${PATH:-}"
NS="${E2E_NAMESPACE:-builderhub-ci}"
CLUSTER="${KIND_CLUSTER_NAME:-builderhub-e2e}"
HELM_WAIT="${HELM_WAIT_TIMEOUT:-5m}"

log() { echo "==> $*"; }

need() {
  command -v "$1" >/dev/null || { echo "missing: $1" >&2; exit 1; }
}

need helm
need kind
need kubectl

cd "$ROOT"
log "Bootstrap dependencies"
./scripts/bootstrap-deps.sh

if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  log "Creating KinD cluster ${CLUSTER}"
  kind create cluster --name "$CLUSTER" --wait 2m
fi
kubectl cluster-info --context "kind-${CLUSTER}"

log "Namespace + Postgres"
kubectl create namespace "$NS" 2>/dev/null || true
kubectl apply -f ci/postgres.yaml -n "$NS"
kubectl -n "$NS" rollout status deploy/postgres --timeout=5m

log "Install build-operator"
helm upgrade --install build-operator charts/build-operator \
  -n "$NS" \
  -f ci/operator-values.yaml \
  --set "build-operator.operator.image.tag=${BUILD_OPERATOR_IMAGE_TAG:-latest}" \
  --wait --timeout "$HELM_WAIT"

log "Run build-api migrations"
helm template build-api charts/build-api -n "$NS" -f ci/api-values.yaml \
  --set "build-api.image.tag=${BUILD_API_IMAGE_TAG:-latest}" \
  --show-only charts/build-api/templates/migration-configmap.yaml | kubectl apply -n "$NS" -f -
helm template build-api charts/build-api -n "$NS" -f ci/api-values.yaml \
  --set "build-api.image.tag=${BUILD_API_IMAGE_TAG:-latest}" \
  --show-only charts/build-api/templates/migration-job.yaml | kubectl apply -n "$NS" -f -
kubectl -n "$NS" wait --for=condition=complete job/build-api-migrate --timeout=5m
kubectl -n "$NS" logs job/build-api-migrate --tail=50

log "Install build-api (skip hooks; migration already done)"
helm upgrade --install build-api charts/build-api \
  -n "$NS" \
  -f ci/api-values.yaml \
  --set "build-api.image.tag=${BUILD_API_IMAGE_TAG:-latest}" \
  --no-hooks \
  --wait --timeout "$HELM_WAIT"

log "Status"
kubectl -n "$NS" get pods,jobs,events --sort-by=.lastTimestamp | tail -30
kubectl -n "$NS" wait --for=condition=available deploy/build-api --timeout=3m
log "Local install OK"
