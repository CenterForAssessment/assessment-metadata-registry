/**
 * Run the shared SELECT-only corpus against this repo's `assertSelectOnly`.
 *
 * `lib/__fixtures__/select-only-cases.json` is a byte-identical vendored copy of
 * the corpus in dataimago-ai (`packages/shared-utils/src/store/__fixtures__/`).
 * Two independent implementations of the guard exist — the one here, and the
 * Level-1 port in `@dataimago/shared-utils/store` — and they must agree on every
 * case. That is what makes the L1 extraction safe to consume from here later.
 *
 * The corpus is the specification; this file is one of its two conformance runs.
 * To change guard behaviour, change the corpus and both implementations together,
 * and bump `_corpus_version`.
 *
 * Nothing checks byte-identity across repositories automatically (they are in
 * different orgs). `_corpus_version` is the tripwire: if the two copies disagree
 * on it, someone edited one and not the other.
 *
 *   npm run test:guard
 */
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { RegistryError, assertSelectOnly } from "../lib/registry-db.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const CORPUS = path.join(here, "..", "lib", "__fixtures__", "select-only-cases.json");

interface Case {
  name: string;
  sql: string;
  expect: { ok: true; normalized: string } | { ok: false; code: string };
}

const { _corpus_version, cases } = JSON.parse(readFileSync(CORPUS, "utf8")) as {
  _corpus_version: number;
  cases: Case[];
};

const failures: string[] = [];

for (const c of cases) {
  let actual: Case["expect"];
  try {
    actual = { ok: true, normalized: assertSelectOnly(c.sql) };
  } catch (e) {
    if (!(e instanceof RegistryError)) throw e;
    actual = { ok: false, code: e.code };
  }

  if (JSON.stringify(actual) !== JSON.stringify(c.expect)) {
    failures.push(
      `  ✗ ${c.name}\n      sql      : ${JSON.stringify(c.sql)}\n` +
        `      expected : ${JSON.stringify(c.expect)}\n      actual   : ${JSON.stringify(actual)}`,
    );
  }
}

if (failures.length > 0) {
  console.error(`\nSELECT-only guard diverged from the shared corpus:\n\n${failures.join("\n\n")}\n`);
  process.exit(1);
}

console.log(`SELECT-only guard: ${cases.length}/${cases.length} corpus cases pass (v${_corpus_version})`);
