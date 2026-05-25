#!/usr/bin/env bash
# KinD e2e: register, create org + ephemeral builder, run buildctl build.
set -euo pipefail

E2E_NAMESPACE="${E2E_NAMESPACE:-builderhub-ci}"
BUILD_API_DEPLOY="${BUILD_API_DEPLOY:-build-api}"
BUILD_API_SVC="${BUILD_API_SVC:-build-api}"
BUILD_OPERATOR_DEPLOY="${BUILD_OPERATOR_DEPLOY:-build-operator}"
API_LOCAL_PORT="${API_LOCAL_PORT:-18090}"
BUILDER_LOCAL_PORT="${BUILDER_LOCAL_PORT:-1234}"
BUILDER_NAME="${BUILDER_NAME:-e2e-builder}"
BUILDKIT_VERSION="${BUILDKIT_VERSION:-v0.20.2}"

pf_pids=()
cleanup() {
  for pid in "${pf_pids[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

log() { echo "==> $*"; }

require_cmd() {
  for c in "$@"; do
    command -v "$c" >/dev/null || { echo "missing command: $c" >&2; exit 1; }
  done
}

install_buildctl() {
  if command -v buildctl >/dev/null; then
    return
  fi
  log "Installing buildctl ${BUILDKIT_VERSION}"
  arch="$(uname -m)"
  case "$arch" in
    x86_64) arch=amd64 ;;
    aarch64) arch=arm64 ;;
  esac
  tmp="$(mktemp -d)"
  curl -fsSL "https://github.com/moby/buildkit/releases/download/${BUILDKIT_VERSION}/buildkit-${BUILDKIT_VERSION}.linux-${arch}.tar.gz" \
    | tar -xzf - -C "$tmp" --strip-components=1 bin/buildctl
  sudo install -m 0755 "$tmp/buildctl" /usr/local/bin/buildctl
  rm -rf "$tmp"
}

api_base() {
  echo "http://127.0.0.1:${API_LOCAL_PORT}"
}

wait_platform() {
  log "Waiting for operator and API deployments"
  kubectl -n "$E2E_NAMESPACE" wait --for=condition=available "deploy/${BUILD_OPERATOR_DEPLOY}" --timeout=600s
  kubectl -n "$E2E_NAMESPACE" wait --for=condition=available "deploy/${BUILD_API_DEPLOY}" --timeout=600s

  # Helm pre-install hook runs migrations; hook-delete-policy removes the job on success.
  if kubectl -n "$E2E_NAMESPACE" get job -l app.kubernetes.io/component=migrate -o name 2>/dev/null | grep -q .; then
    log "Waiting for database migration job"
    kubectl -n "$E2E_NAMESPACE" wait --for=condition=complete job \
      -l app.kubernetes.io/component=migrate --timeout=600s
  else
    log "Migration job not present (already completed during helm install)"
  fi

  log "Port-forwarding build-api"
  kubectl -n "$E2E_NAMESPACE" port-forward "svc/${BUILD_API_SVC}" \
    "${API_LOCAL_PORT}:8090" >/tmp/e2e-api-pf.log 2>&1 &
  pf_pids+=($!)

  for _ in $(seq 1 60); do
    if curl -sfS "$(api_base)/v1/health" | jq -e '.status == "ok"' >/dev/null 2>&1; then
      log "API health OK"
      return
    fi
    sleep 2
  done
  echo "API health check failed" >&2
  cat /tmp/e2e-api-pf.log >&2 || true
  exit 1
}

register_and_org() {
  local email="e2e-$(date +%s)@builderhub-ci.local"
  local password="ci-e2e-password-123"
  local slug="e2e-org-$(date +%s)"

  log "Registering user ${email}"
  local reg
  reg="$(curl -sfS -X POST "$(api_base)/v1/auth/register" \
    -H 'Content-Type: application/json' \
    -d "{\"email\":\"${email}\",\"password\":\"${password}\",\"name\":\"E2E User\"}")"
  ACCESS_TOKEN="$(echo "$reg" | jq -r '.accessToken')"
  if [[ -z "$ACCESS_TOKEN" || "$ACCESS_TOKEN" == "null" ]]; then
    echo "register failed: $reg" >&2
    exit 1
  fi

  log "Creating organization"
  local org
  org="$(curl -sfS -X POST "$(api_base)/v1/organizations" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"E2E Org\",\"slug\":\"${slug}\",\"plan\":\"starter\"}")"
  ORG_ID="$(echo "$org" | jq -r '.organization.id')"
  if [[ -z "$ORG_ID" || "$ORG_ID" == "null" ]]; then
    echo "create organization failed: $org" >&2
    exit 1
  fi
  log "Organization id=${ORG_ID}"
}

create_builder_and_wait() {
  log "Creating ephemeral builder ${BUILDER_NAME}"
  curl -sfS -X POST "$(api_base)/v1/namespaces/${ORG_ID}/builders" \
    -H "Authorization: Bearer ${ACCESS_TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "{\"name\":\"${BUILDER_NAME}\",\"spec\":{\"templateRef\":\"builder-small\",\"mode\":\"ephemeral\"}}" \
    >/dev/null

  log "Waiting for builder Ready (up to 15m)"
  local phase="" node_port=""
  for _ in $(seq 1 90); do
    local resp
    resp="$(curl -sfS "$(api_base)/v1/namespaces/${ORG_ID}/builders/${BUILDER_NAME}" \
      -H "Authorization: Bearer ${ACCESS_TOKEN}")"
    phase="$(echo "$resp" | jq -r '.builder.status.phase // empty')"
    node_port="$(echo "$resp" | jq -r '.builder.status.nodePort // 0')"
    if [[ "$phase" == "Ready" && "$node_port" != "0" && "$node_port" != "null" ]]; then
      log "Builder ready (phase=${phase}, nodePort=${node_port})"
      return
    fi
    sleep 10
  done

  echo "builder did not become Ready" >&2
  kubectl -n "$ORG_ID" get pods,svc,events --sort-by=.lastTimestamp 2>/dev/null || true
  kubectl get buildkitbuilder -n "$ORG_ID" -o yaml 2>/dev/null || true
  exit 1
}

run_build() {
  log "Port-forwarding builder client service in org namespace ${ORG_ID}"
  kubectl -n "$ORG_ID" port-forward "svc/builder-${BUILDER_NAME}-client" \
    "${BUILDER_LOCAL_PORT}:1234" >/tmp/e2e-builder-pf.log 2>&1 &
  pf_pids+=($!)

  for _ in $(seq 1 30); do
    if buildctl --addr "tcp://127.0.0.1:${BUILDER_LOCAL_PORT}" debug workers >/dev/null 2>&1; then
      break
    fi
    sleep 2
  done

  local ctx="/tmp/e2e-build-context"
  rm -rf "$ctx"
  mkdir -p "$ctx"
  printf 'FROM alpine\nRUN echo e2e-ok\n' >"$ctx/Dockerfile"

  local build_log=/tmp/e2e-buildctl.log
  log "Running buildctl build"
  # buildctl can exit 0 even when the solve fails; check output and exit code.
  set +e
  buildctl --addr "tcp://127.0.0.1:${BUILDER_LOCAL_PORT}" build \
    --frontend dockerfile.v0 \
    --local context="$ctx" \
    --local dockerfile="$ctx" \
    --opt filename=Dockerfile 2>&1 | tee "$build_log"
  local build_rc=${PIPESTATUS[0]}
  set -e

  if [[ "$build_rc" -ne 0 ]] \
    || grep -qE '(^error: failed to solve:|ERROR: encountered unknown)' "$build_log"; then
    echo "buildctl build failed (exit=${build_rc})" >&2
    cat /tmp/e2e-builder-pf.log >&2 2>/dev/null || true
    kubectl -n "$ORG_ID" get pods -o wide 2>/dev/null || true
    local bpod
    bpod="$(kubectl -n "$ORG_ID" get pods -o name 2>/dev/null | grep "builder-${BUILDER_NAME}" | head -1 || true)"
    if [[ -n "$bpod" ]]; then
      kubectl -n "$ORG_ID" logs "$bpod" -c buildkitd --tail=100 2>/dev/null || true
    fi
    return 1
  fi

  log "Build succeeded"
}

on_failure_debug() {
  echo "--- debug: platform namespace ${E2E_NAMESPACE} ---" >&2
  kubectl -n "$E2E_NAMESPACE" get pods,svc,jobs 2>/dev/null || true
  kubectl -n "$E2E_NAMESPACE" logs "deploy/${BUILD_OPERATOR_DEPLOY}" --tail=100 2>/dev/null || true
  kubectl -n "$E2E_NAMESPACE" logs "deploy/${BUILD_API_DEPLOY}" --tail=100 2>/dev/null || true
  if [[ -n "${ORG_ID:-}" ]]; then
    echo "--- debug: org namespace ${ORG_ID} ---" >&2
    kubectl -n "$ORG_ID" get pods,svc,events --sort-by=.lastTimestamp 2>/dev/null || true
    kubectl -n "$ORG_ID" get configmap -o name 2>/dev/null | grep buildkitd | while read -r cm; do
      kubectl -n "$ORG_ID" get "$cm" -o yaml 2>/dev/null || true
    done
    local bpod
    bpod="$(kubectl -n "$ORG_ID" get pods -o name 2>/dev/null | grep "builder-${BUILDER_NAME}" | head -1 || true)"
    if [[ -n "$bpod" ]]; then
      kubectl -n "$ORG_ID" logs "$bpod" -c buildkitd --tail=100 2>/dev/null || true
    fi
  fi
  if [[ -f /tmp/e2e-buildctl.log ]]; then
    echo "--- debug: buildctl output ---" >&2
    tail -80 /tmp/e2e-buildctl.log >&2 || true
  fi
}

main() {
  require_cmd kubectl curl jq
  install_buildctl

  if ! wait_platform; then
    on_failure_debug
    exit 1
  fi

  register_and_org
  create_builder_and_wait || { on_failure_debug; exit 1; }
  run_build || { on_failure_debug; exit 1; }

  log "E2E passed"
}

main "$@"
