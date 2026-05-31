.PHONY: deps lint template verify

deps:
	@echo "Chart sources live in charts/; no dependency fetch required."

lint:
	helm lint .
	helm lint charts/build-operator -f ci/operator-values.yaml
	helm lint charts/build-api -f ci/api-values.yaml
	helm lint charts/build-console

template:
	helm template builderhub . --namespace builderhub

verify:
	./scripts/verify-api-migration-hooks.sh
