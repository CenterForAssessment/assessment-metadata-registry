#!/usr/bin/env bash
# PostToolUse hook: validate the registry the instant a Tier A sidecar or a schema
# is edited — the tightest authoring feedback loop (see wiki/patterns/development-harness.md,
# ADR-004). Degrades to a no-op (never blocks editing) when the R toolchain is absent.
#
# Contract: Claude Code passes the tool invocation as JSON on stdin. On a clean
# registry the hook is silent and exits 0. On validation failure it writes the errors
# to stderr and exits 2, which surfaces them back to the agent to fix.
set -euo pipefail

payload="$(cat)"
file_path="$(printf '%s' "$payload" \
  | python3 -c 'import sys, json; print(json.load(sys.stdin).get("tool_input", {}).get("file_path", ""))' \
  2>/dev/null || true)"

# Only react to the live Tier A layer: sidecars under metadata/ or the JSON Schemas
# under schemas/. Ignore the amrr package fixture (r-pkg/**), which is not the registry.
case "$file_path" in
  *r-pkg/*) exit 0 ;;
esac
case "$file_path" in
  *metadata/*|*schemas/*) ;;
  *) exit 0 ;;
esac

cd "${CLAUDE_PROJECT_DIR:-.}"

Rscript -e '
  if (!requireNamespace("jsonvalidate", quietly = TRUE)) {
    message("[validate-metadata] jsonvalidate not installed (run `make setup`); skipping.")
    quit(status = 0)
  }
  if (!requireNamespace("amrr", quietly = TRUE)) {
    if (requireNamespace("pkgload", quietly = TRUE)) {
      suppressMessages(pkgload::load_all("r-pkg/amrr", quiet = TRUE))
    } else {
      message("[validate-metadata] amrr not installed and pkgload unavailable; skipping.")
      quit(status = 0)
    }
  }
  r <- tryCatch(
    amrr::validate_registry(".", quiet = TRUE, error = FALSE),
    error = function(e) {
      message("[validate-metadata] validation crashed: ", conditionMessage(e))
      quit(status = 2)
    }
  )
  if (r$n_errors > 0L) {
    message(sprintf("[validate-metadata] %d validation error(s) in %d file(s):",
                    r$n_errors, length(r$results)))
    for (f in names(r$results)) {
      message("  ", f)
      for (msg in r$results[[f]]) message("    - ", msg)
    }
    quit(status = 2)
  }
' 1>&2
