#!/usr/bin/env bash
# Verify build-api migration hook manifests after bootstrap.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

./scripts/bootstrap-deps.sh >/dev/null

cm="$(helm template build-api charts/build-api -f ci/api-values.yaml \
  --show-only charts/build-api/templates/migration-configmap.yaml)"
job="$(helm template build-api charts/build-api -f ci/api-values.yaml \
  --show-only charts/build-api/templates/migration-job.yaml)"

echo "$cm" | grep -q 'helm.sh/hook' || { echo "ConfigMap missing hook annotation" >&2; exit 1; }
echo "$cm" | grep -q 'hook-weight": "-10"' || { echo "ConfigMap missing hook-weight -10" >&2; exit 1; }
echo "$job" | grep -q 'helm.sh/hook' || { echo "Job missing hook annotation" >&2; exit 1; }
echo "$job" | grep -q 'hook-weight": "-5"' || { echo "Job missing hook-weight -5" >&2; exit 1; }

test -f charts/build-api/charts/build-api/migrations/000001_init.up.sql \
  || { echo "missing 000001_init.up.sql in chart" >&2; exit 1; }

svc_count="$(helm template build-api charts/build-api -f ci/api-values.yaml 2>/dev/null | rg -c '^kind: Service$' || true)"
if [[ "${svc_count}" != "1" ]]; then
  echo "expected exactly one Service manifest, got ${svc_count}" >&2
  exit 1
fi

echo "OK: migration hooks, 000001 migration, single Service manifest"
