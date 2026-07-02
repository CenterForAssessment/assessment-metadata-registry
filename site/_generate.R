# Pre-render step: emit one flat `record-<slug>.qmd` per sidecar from the derived
# dist bundles. Flat (site-root) pages keep every relative asset path resolving at
# a single URL depth. Runs from the site/ project root before Quarto renders.

source("_common.R")

# Remove previously generated pages so deleted records don't linger.
old <- list.files(".", pattern = "^record-.*\\.qmd$")
if (length(old)) invisible(file.remove(old))

recs <- amr_all_records()

for (rec in recs) {
  slug <- amr_slug(rec)
  page <- sprintf(
'---
title: "%s"
subtitle: "%s sidecar · schema `%s`"
toc: true
---

```{r}
#| output: asis
source("_common.R")
amr_render_record(amr_record_by_slug("%s"))
```
',
    gsub('"', "'", amr_title(rec)), amr_type(rec), rec$schema_version, slug)
  writeLines(page, sprintf("record-%s.qmd", slug))
}

cat(sprintf("[_generate] wrote %d record page(s)\n", length(recs)))
