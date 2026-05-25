#!/usr/bin/env bash
# Vendor application charts from GitHub for local lint/template until OCI publish exists.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${CHART_VERSION:-0.1.0}"
REPOS=(build-operator build-api build-console)

for repo in "${REPOS[@]}"; do
  echo "==> ${repo}"
  tmp="$(mktemp -d)"
  dest="${ROOT}/charts/${repo}/charts"
  rm -rf "${dest}"
  mkdir -p "${dest}"

  git clone --depth 1 "https://github.com/BuilderHub/${repo}.git" "${tmp}/repo"
  chart_src="${tmp}/repo/helm/${repo}"
  rm -f "${chart_src}/.helmignore"

  if [[ "${repo}" == "build-operator" ]]; then
    deploy="${chart_src}/templates/deployment.yaml"
    # | quote renders --leader-elect="true"; the manager flag parser rejects quoted booleans.
    sed -i 's/--leader-elect={{ .Values.operator.leaderElection | quote }}/--leader-elect={{ .Values.operator.leaderElection }}/' \
      "$deploy"
    # GHCR image uses named user "nonroot"; KinD/kubelet requires numeric runAsUser with runAsNonRoot.
    if grep -q 'runAsNonRoot: true' "$deploy" && ! grep -q 'runAsUser:' "$deploy"; then
      sed -i '/runAsNonRoot: true/a\            runAsUser: 65532' "$deploy"
    fi
    # Upstream helm chart ships no RBAC; operator needs manager + leader-election roles.
    cp "${ROOT}/ci/operator-rbac.yaml.tpl" "${chart_src}/templates/rbac.yaml"
    mkdir -p "${chart_src}/crds"
    cp "${tmp}/repo/config/crd/bases/"*.yaml "${chart_src}/crds/"
  fi

  if [[ "${repo}" == "build-api" ]]; then
    deploy="${chart_src}/templates/deployment.yaml"
    # Upstream chart embeds a second Service in deployment.yaml; service.yaml already defines it.
    awk '/^---$/{exit} {print}' "$deploy" > "${deploy}.tmp" && mv "${deploy}.tmp" "$deploy"
    # Helm chart omits 000001; copy from app migrations so migrate can create schema.
    if [[ ! -f "${chart_src}/migrations/000001_init.up.sql" ]]; then
      cp "${tmp}/repo/migrations/000001_init.up.sql" "${chart_src}/migrations/"
      cp "${tmp}/repo/migrations/000001_init.down.sql" "${chart_src}/migrations/" 2>/dev/null || true
    fi
    # Migration Job is a pre-install hook; ConfigMap must be a hook too or the job never starts.
    cp "${ROOT}/ci/api-migration-configmap.yaml.tpl" "${chart_src}/templates/migration-configmap.yaml"
    # Upstream RBAC omits namespaces; CreateOrganization calls EnsureOrgNamespace.
    cp "${ROOT}/ci/api-rbac.yaml.tpl" "${chart_src}/templates/rbac.yaml"
    helpers="${chart_src}/templates/_helpers.tpl"
    cat >> "${helpers}" <<'EOF'

{{- define "build-api.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else }}
{{- include "build-api.fullname" . }}
{{- end }}
{{- end }}
EOF
  fi

  tgz="${dest}/${repo}-${VERSION}.tgz"
  helm package "${chart_src}" --version "${VERSION}" --app-version "${VERSION}" -d "${dest}"

  digest="sha256:$(openssl dgst -sha256 -binary "${tgz}" | openssl base64 -A)"
  lock="${ROOT}/charts/${repo}/Chart.lock"
  cat > "${lock}" <<EOF
dependencies:
- name: ${repo}
  repository: oci://ghcr.io/builderhub
  version: ${VERSION}
  condition: enabled
  digest: ${digest}
generated: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
EOF

  tar -xzf "${tgz}" -C "${dest}"
  rm -f "${tgz}"
done

echo "Bootstrap complete."
