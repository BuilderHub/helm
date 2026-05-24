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

  if [[ "${repo}" == "build-api" ]]; then
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
