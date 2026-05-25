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

echo "OK: migration hooks and 000001 migration present"
