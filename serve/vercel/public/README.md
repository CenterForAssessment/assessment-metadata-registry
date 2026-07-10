This directory is the **entire** public static surface. Add nothing you would not
publish.

It exists so Vercel's zero-config picks `public/` as the static output directory.
Without it the project root is published as static assets — which would expose
lib/*.ts source and, worse, make the bundled read-only registry.sqlite downloadable
at /data/registry.sqlite. The DB must reach the FUNCTIONS (via vercel.json
functions.includeFiles), never the static surface.

`deploy-vercel.yml` asserts a 404 on the store path on every deploy, which is the
check that keeps that true.

It holds exactly one file: `index.html`, the landing page at `/`. That page carries no
endpoint list of its own — it fetches `/api` at load and renders whatever the catalog
says, so it cannot drift from the routes. `lib/endpoints.ts` remains the single source
of truth. Keep this directory to that one self-contained file: every asset added here
is added to the public surface.
