.PHONY: bootstrap-deps deps lint template

WRAPPERS := build-operator build-api build-console

bootstrap-deps:
	@./scripts/bootstrap-deps.sh

deps:
	@for chart in $(WRAPPERS); do \
		echo "Updating dependencies for $$chart..."; \
		helm dependency update "charts/$$chart"; \
	done

lint: bootstrap-deps
	helm lint .

template: bootstrap-deps
	helm template builderhub . --namespace builderhub
