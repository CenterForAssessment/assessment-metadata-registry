# Assessment Metadata Registry — local dogfooding runner.
#
# One entry point for humans and agents. Tier A sidecars are canonical; Tier B/C
# are derived and disposable. See AGENTS.md. The venv exists because tools/ needs
# jsonschema and modern macOS/Linux Python is externally managed (PEP 668).

VENV := .venv
PY   := $(VENV)/bin/python
PIP  := $(VENV)/bin/pip
RPKG := r-pkg/amrr

.DEFAULT_GOAL := help
.PHONY: help setup validate build check test all clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-9s\033[0m %s\n", $$1, $$2}'

$(PY): tools/requirements.txt ## (internal) bootstrap the Python venv
	python3 -m venv $(VENV)
	$(PIP) install -q -r tools/requirements.txt

setup: $(PY) ## Create the venv and install Python deps

validate: $(PY) ## Tier A gate: validate every sidecar (schema + registry invariants)
	$(PY) tools/validate.py

build: validate ## Regenerate the derived layer (Tier B) into build/ (validates first)
	$(PY) tools/build.py --out build

test: ## amrr testthat suite (Tier C) — no compiler needed
	cd $(RPKG) && Rscript -e 'devtools::test()'

check: ## amrr R CMD check (Tier C) — pure-R package, mirrors CI
	cd $(RPKG) && Rscript -e 'roxygen2::roxygenise()'
	cd r-pkg && R CMD build amrr && R CMD check --no-manual --no-vignettes amrr_*.tar.gz && rm -rf amrr.Rcheck amrr_*.tar.gz

all: build test ## Full fast loop: validate -> build -> R tests

clean: ## Remove derived artifacts (never canonical)
	rm -rf build
