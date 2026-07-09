# Assessment Metadata Registry — local dogfooding runner.
#
# One entry point for humans and agents. Tier A sidecars are canonical; Tier B/C
# are derived and disposable. See AGENTS.md. The whole toolchain is R (ADR-004):
# validate + build are Rscript, and the amrr consumer package is R.

RPKG := r-pkg/amrr
R    := Rscript

.DEFAULT_GOAL := help
.PHONY: help setup validate build check test all clean site site-preview \
        api-render serve-native api-image serve-local serve-down mcp-local

# Track B: read-only query API + MCP backend (Tier C, ADR-012). Serves the derived
# build/registry.sqlite; never a write path, never canonical.
SERVE    := serve
API_DB   := build/registry.sqlite
API_META := build/metadata.rendered.yaml

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-13s\033[0m %s\n", $$1, $$2}'

setup: ## Install the R packages the tooling + dev loop need
	$(R) -e 'install.packages(c("jsonlite","jsonvalidate","DBI","RSQLite","digest","devtools","roxygen2","testthat","reactable","htmltools","knitr","rmarkdown"), repos="https://cloud.r-project.org")'

validate: ## Tier A gate: validate every sidecar (schema + registry invariants)
	$(R) -e 'pkgload::load_all("$(RPKG)", quiet=TRUE); amrr::validate_registry(".")'

build: validate ## Regenerate the derived layer (Tier B) into build/ (validates first)
	$(R) -e 'pkgload::load_all("$(RPKG)", quiet=TRUE); amrr::build_registry(".", out="build")'

test: ## amrr testthat suite (Tier C)
	cd $(RPKG) && $(R) -e 'devtools::test()'

check: ## amrr R CMD check (Tier C) — pure-R package, mirrors CI
	cd $(RPKG) && $(R) -e 'roxygen2::roxygenise()'
	cd r-pkg && R CMD build amrr && R CMD check --no-manual --no-vignettes amrr_*.tar.gz && rm -rf amrr.Rcheck amrr_*.tar.gz

site: build ## Render the Quarto catalog into site/_site (+ copy JSON bundles in)
	quarto render site
	cp -R build/. site/_site/
	touch site/_site/.nojekyll
	@echo "Catalog: site/_site/index.html"

site-preview: build ## Live-preview the catalog (Quarto preview server)
	quarto preview site

all: build test ## Full fast loop: validate -> build -> R tests

clean: ## Remove derived artifacts (never canonical)
	rm -rf build

api-render: build ## Stamp git_sha/built_at from the DB into build/metadata.rendered.yaml
	bash $(SERVE)/datasette/render_metadata.sh $(API_DB) $(SERVE)/datasette/metadata.yaml $(API_META)

serve-native: api-render ## Run Datasette locally WITHOUT Docker (needs `pipx install datasette`); :8001
	datasette -i $(API_DB) -m $(API_META) --cors --setting max_returned_rows 2000 -p 8001

api-image: ## Build the API container images (Datasette pulled, MCP built) — needs Docker
	cd $(SERVE) && docker compose build

serve-local: api-render ## Run the full API stack via Docker compose (Datasette + MCP + Caddy) — needs Docker
	AMR_DATA_DIR=$(abspath build) docker compose -f $(SERVE)/docker-compose.yml up

serve-down: ## Stop the local Docker API stack
	docker compose -f $(SERVE)/docker-compose.yml down

mcp-local: build ## Run the MCP server over stdio against the freshly-built DB (for Claude Code)
	AMRR_REGISTRY_DB=$(API_DB) python3 $(SERVE)/mcp/server.py
