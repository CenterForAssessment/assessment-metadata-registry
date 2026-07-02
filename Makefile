# Assessment Metadata Registry — local dogfooding runner.
#
# One entry point for humans and agents. Tier A sidecars are canonical; Tier B/C
# are derived and disposable. See AGENTS.md. The whole toolchain is R (ADR-004):
# validate + build are Rscript, and the amrr consumer package is R.

RPKG := r-pkg/amrr
R    := Rscript

.DEFAULT_GOAL := help
.PHONY: help setup validate build check test all clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'

setup: ## Install the R packages the tooling + dev loop need
	$(R) -e 'install.packages(c("jsonlite","jsonvalidate","DBI","RSQLite","digest","devtools","roxygen2","testthat"), repos="https://cloud.r-project.org")'

validate: ## Tier A gate: validate every sidecar (schema + registry invariants)
	$(R) -e 'pkgload::load_all("$(RPKG)", quiet=TRUE); amrr::validate_registry(".")'

build: validate ## Regenerate the derived layer (Tier B) into build/ (validates first)
	$(R) -e 'pkgload::load_all("$(RPKG)", quiet=TRUE); amrr::build_registry(".", out="build")'

test: ## amrr testthat suite (Tier C)
	cd $(RPKG) && $(R) -e 'devtools::test()'

check: ## amrr R CMD check (Tier C) — pure-R package, mirrors CI
	cd $(RPKG) && $(R) -e 'roxygen2::roxygenise()'
	cd r-pkg && R CMD build amrr && R CMD check --no-manual --no-vignettes amrr_*.tar.gz && rm -rf amrr.Rcheck amrr_*.tar.gz

all: build test ## Full fast loop: validate -> build -> R tests

clean: ## Remove derived artifacts (never canonical)
	rm -rf build
