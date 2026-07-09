/**
 * Build a FIXTURE registry.sqlite for local validation of the Tier 1 functions.
 *
 * Uses the REAL DDL (schemas/sql/amr-registry.v1.sql) so the schema cannot drift, and a
 * handful of hand-written rows with realistic values. This is NOT a substitute for
 * `make build` — the deployed DB must be `amrr::build_registry()`'s output. registry_meta
 * is stamped `fixture=true` so a fixture can never masquerade as a real build.
 */
import { execSync } from "node:child_process";
import { copyFileSync, existsSync, mkdirSync, readFileSync, truncateSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";

const here = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(here, "..", "..", "..");
const ddlPath = path.join(repoRoot, "schemas", "sql", "amr-registry.v1.sql");
const outDir = path.resolve(here, "..", "data");
const outPath = path.join(outDir, "registry.sqlite");

let gitSha = "fixture-unknown";
try {
  gitSha = execSync("git rev-parse HEAD", { cwd: repoRoot }).toString().trim();
} catch {
  /* not a git checkout — keep the placeholder */
}

mkdirSync(outDir, { recursive: true });
// Build in a temp dir, then copy over the destination: overwrite-by-copy needs no
// unlink permission, and a fresh temp file guarantees a clean schema.
const tmpPath = path.join(os.tmpdir(), `amr-fixture-${process.pid}.sqlite`);

const db = new DatabaseSync(tmpPath);
db.exec(readFileSync(ddlPath, "utf8"));

const insert = (table, rows) => {
  if (rows.length === 0) return;
  const cols = Object.keys(rows[0]);
  const stmt = db.prepare(
    `insert into ${table} (${cols.join(", ")}) values (${cols.map((c) => `:${c}`).join(", ")})`,
  );
  for (const r of rows) stmt.run(r);
};

insert("registry_meta", [
  { key: "git_sha", value: gitSha },
  { key: "built_at", value: new Date().toISOString() },
  { key: "schema_version", value: "amr.registry.v1" },
  { key: "fixture", value: "true" },
]);

insert("jurisdiction", [
  { jurisdiction_id: "IN", name: "Indiana", type: "state", nces_id: null, fips: "18" },
  { jurisdiction_id: "SC", name: "South Carolina", type: "state", nces_id: null, fips: "45" },
]);

insert("assessment_system", [
  {
    assessment_system_id: "ilearn",
    name: "Indiana Learning Evaluation Assessment Readiness Network",
    family: "ILEARN",
    assessment_type: "summative",
  },
  {
    assessment_system_id: "wida-access",
    name: "WIDA ACCESS for ELLs",
    family: "WIDA",
    assessment_type: "elp",
  },
  {
    assessment_system_id: "sc-summative",
    name: "SC READY",
    family: "SC_READY",
    assessment_type: "summative",
  },
]);

const admin = (jur, sys, year, vendor) => ({
  jurisdiction_id: jur,
  assessment_system_id: sys,
  year,
  administration_id: `${sys}-${jur.toLowerCase()}-${year}`,
  vendor,
  window: "annual",
  csem_ref: null,
  status: "draft",
  source_confidence: "low",
  source_citation: null,
});
insert("administration", [
  admin("IN", "ilearn", "2023", "Indiana Department of Education"),
  admin("IN", "ilearn", "2024", "Indiana Department of Education"),
  admin("IN", "wida-access", "2024", "WIDA Consortium"),
  admin("SC", "sc-summative", "2024", "Cambium Assessment"),
]);

insert("assessment_program", [
  {
    jurisdiction_id: "IN",
    assessment_system_id: "ilearn",
    year: "2024",
    assessment_name: "Indiana Learning Evaluation Assessment Readiness Network",
    abbreviation: "ILEARN",
    organization_name: "Indiana Department of Education",
    organization_abbreviation: "IDOE",
    organization_url: "https://www.in.gov/doe/",
  },
]);

const vscale = (jur, sys, ca, year, vs, name) => ({
  jurisdiction_id: jur,
  assessment_system_id: sys,
  content_area: ca,
  year,
  vertical_scale: vs,
  scale_name: name,
  label: null,
});
insert("vertical_scale", [
  vscale("IN", "ilearn", "ELA", "2024", 0, "ILEARN scale"),
  vscale("IN", "ilearn", "MATHEMATICS", "2024", 0, "ILEARN scale"),
  vscale("IN", "wida-access", "ELP_COMPOSITE", "2024", 1, "WIDA scale"),
  vscale("SC", "sc-summative", "ELA", "2024", 0, "SC READY scale"),
]);

const levels = (jur, sys, ca, year, labels, proficientFrom) =>
  labels.map((label, i) => ({
    jurisdiction_id: jur,
    assessment_system_id: sys,
    content_area: ca,
    year,
    level_index: i + 1,
    label,
    proficient: i + 1 >= proficientFrom ? 1 : 0,
  }));
insert("achievement_level", [
  ...levels("IN", "ilearn", "ELA", "2024",
    ["Below Proficiency", "Approaching Proficiency", "At Proficiency", "Above Proficiency"], 3),
  ...levels("IN", "ilearn", "MATHEMATICS", "2024",
    ["Below Proficiency", "Approaching Proficiency", "At Proficiency", "Above Proficiency"], 3),
  ...levels("SC", "sc-summative", "ELA", "2024",
    ["Does Not Meet Expectations", "Approaches Expectations", "Meets Expectations", "Exceeds Expectations"], 3),
]);

const cuts = (jur, sys, ca, year, grade, bounds) =>
  bounds.map((lower_bound, i) => ({
    jurisdiction_id: jur,
    assessment_system_id: sys,
    content_area: ca,
    year,
    grade,
    level_index: i + 1,
    lower_bound,
  }));
insert("cutscore", [
  ...cuts("IN", "ilearn", "ELA", "2024", "3", [6425, 6500, 6572]),
  ...cuts("IN", "ilearn", "ELA", "2024", "4", [6450, 6525, 6600]),
  ...cuts("SC", "sc-summative", "ELA", "2024", "3", [401, 452, 501]),
]);

insert("comparability", [
  {
    jurisdiction_id: "IN",
    assessment_system_id: "ilearn",
    year: "2019",
    administered: 1,
    scale_transition: 1,
    comparable_to_prior_year: 0,
    prior_scale_name: "ISTEP+",
    notes: "ILEARN replaced ISTEP+ (new scale)",
  },
  {
    jurisdiction_id: "IN",
    assessment_system_id: "ilearn",
    year: "2024",
    administered: 1,
    scale_transition: 0,
    comparable_to_prior_year: 1,
    prior_scale_name: null,
    notes: null,
  },
  {
    jurisdiction_id: "SC",
    assessment_system_id: "sc-summative",
    year: "2024",
    administered: 1,
    scale_transition: 0,
    comparable_to_prior_year: 1,
    prior_scale_name: null,
    notes: null,
  },
]);

db.close();
copyFileSync(tmpPath, outPath); // truncates + overwrites; no unlink needed
// A leftover hot journal from an interrupted run could roll back the fresh copy —
// truncating it to 0 bytes makes it cold/ignored.
const journal = `${outPath}-journal`;
if (existsSync(journal)) truncateSync(journal, 0);
console.log(`fixture registry.sqlite written to ${outPath} (git_sha=${gitSha}, fixture=true)`);
