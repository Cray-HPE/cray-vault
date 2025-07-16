# Copyright 2021-2025 Hewlett Packard Enterprise Development LP

CHART_METADATA_IMAGE ?= artifactory.algol60.net/csm-docker/stable/chart-metadata
YQ_IMAGE ?= artifactory.algol60.net/docker.io/mikefarah/yq:4
HELM_IMAGE ?= artifactory.algol60.net/docker.io/alpine/helm:3.7.1
HELM_UNITTEST_IMAGE ?= artifactory.algol60.net/docker.io/quintush/helm-unittest
HELM_DOCS_IMAGE ?= artifactory.algol60.net/docker.io/jnorwood/helm-docs:v1.5.0

all: lint dep-up test package

helm:
	docker run --rm \
		--user $(shell id -u):$(shell id -g) \
		--mount type=bind,src="$(shell pwd)",dst=/src \
		-w /src \
		-e HELM_CACHE_HOME=/src/.helm/cache \
		-e HELM_CONFIG_HOME=/src/.helm/config \
		-e HELM_DATA_HOME=/src/.helm/data \
		-e HELM_EXPERIMENTAL_OCI=1 \
		$(HELM_IMAGE) \
		$(CMD)

lint:
	CMD="lint charts/cray-vault-operator" $(MAKE) helm
	CMD="lint charts/cray-vault"          $(MAKE) helm

dep-up:
	CMD="dep up charts/cray-vault-operator" $(MAKE) helm
	CMD="dep up charts/cray-vault"          $(MAKE) helm
	$(MAKE) copy-crds

copy-crds:
	@echo "Copying CRDs from dependency chart to crds directory..."
	@mkdir -p charts/cray-vault-operator/crds
	@cd charts/cray-vault-operator/charts && \
	if [ -f vault-operator-*.tgz ]; then \
		echo "Extracting dependency chart CRDs..."; \
		if tar -xzf vault-operator-*.tgz -C ../crds --strip-components 2 vault-operator/crds/crd.yaml; then \
			echo "CRDs copied successfully"; \
		else \
			echo "Warning: Failed to extract CRDs from dependency chart"; \
		fi; \
	else \
		echo "Warning: Dependency chart vault-operator-*.tgz file not found"; \
	fi

test:
	docker run --rm \
		-v ${PWD}/charts:/apps \
		${HELM_UNITTEST_IMAGE} \
		cray-vault-operator \
		cray-vault

package:
ifdef CHART_VERSIONS
	CMD="package charts/cray-vault-operator   --version $(word 1, $(CHART_VERSIONS)) -d packages" $(MAKE) helm
	CMD="package charts/cray-vault   --version $(word 2, $(CHART_VERSIONS)) -d packages" $(MAKE) helm
else
	CMD="package charts/* -d packages" $(MAKE) helm
endif

extracted-images:
	CMD="template release $(CHART) --dry-run --replace --dependency-update" $(MAKE) -s helm \
	| docker run --rm -i $(YQ_IMAGE) e -N '.. | .image? | select(.)' -

annotated-images:
	CMD="show chart $(CHART)" $(MAKE) -s helm \
	| docker run --rm -i $(YQ_IMAGE) e -N '.annotations."artifacthub.io/images"' - \
	| docker run --rm -i $(YQ_IMAGE) e -N '.. | .image? | select(.)' -

images:
	{ CHART=charts/cray-vault-operator $(MAKE) -s extracted-images annotated-images; \
	  CHART=charts/cray-vault          $(MAKE) -s extracted-images annotated-images; \
	} | sort -u

snyk:
	$(MAKE) -s images | xargs --verbose -n 1 snyk container test

gen-docs:
	docker run --rm \
		--user $(shell id -u):$(shell id -g) \
		--mount type=bind,src="$(shell pwd)",dst=/src \
		-w /src \
		$(HELM_DOCS_IMAGE) \
		helm-docs --chart-search-root=charts

clean:
	$(RM) -r .helm packages charts/cray-vault-operator/charts
