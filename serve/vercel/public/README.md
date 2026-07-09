This directory is intentionally empty.

It exists so Vercel's zero-config picks `public/` as the static output directory.
Without it the project root is published as static assets — which would expose
lib/*.ts source and, worse, make the bundled read-only registry.sqlite downloadable
at /data/registry.sqlite. The DB must reach the FUNCTIONS (via vercel.json
functions.includeFiles), never the static surface.
