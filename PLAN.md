# Plan: Add a BigQuery E2E job alongside the existing Postgres one

Goal: keep the current Supabase integration suite (Postgres backend) exactly as
it is, and add a **second job** that runs the same suite against the **BigQuery**
backend. The only difference between the two is environment variables — supplied
from **GitHub secrets** in CI and **exported manually** for local runs. No fork
of the test specs; one parameterized harness.

---

## STATUS

**Implemented (committed code/config — no external resources needed):**
- `test/e2e/supabase/config.sh` — `LF_E2E_BACKEND` switch (default `postgres`).
- `test/e2e/supabase/bin/compose` — layers the BigQuery overlay when selected.
- `test/e2e/supabase/setup-supabase-services.sh` — bigquery-only env validation,
  `POSTGRES_BACKEND_*` stripping, and a longer (180s) readiness probe.
- `test/e2e/supabase/docker-compose.bigquery.yml` — new overlay (GOOGLE_* env +
  `gcloud.json` mount).
- `test/e2e/supabase/.gitignore` — ignores `gcloud.json` / `*.sa.json`.
- `test/e2e/supabase/features/logs.spec.ts` — backend-aware diagnostic skip +
  300s ingestion wait for BigQuery.
- `.github/workflows/_integration-supabase.yml` — new reusable workflow.
- `.github/workflows/integration-supabase.yml` — two caller jobs (postgres +
  bigquery, with fork-secret guard).

All shell scripts pass `bash -n`; all YAML parses. Postgres path is unchanged.

**Remaining — REQUIRES YOU (external, I cannot do these):**
1. **GCP setup (Phase 0):** create/choose a project (BigQuery API on), a service
   account with `roles/bigquery.dataEditor` + `roles/bigquery.jobUser`, and
   download its key JSON. Record project id + number.
2. **GitHub secrets (Phase 1):** add `GCP_SA_KEY` (the key JSON), `GCP_PROJECT_ID`,
   `GCP_PROJECT_NUMBER` to the repo.
3. **Local run:** export the env vars (recipe in Phase 7) and run the suite to
   verify the BigQuery path end-to-end — I can't, lacking credentials.
4. **Optional decisions:** dataset cleanup step (Phase 6); whether to keep the
   fork-PR guard or change the trigger policy.

Nothing else is blocking — once secrets exist, the BigQuery job runs in CI; once
you export the env vars locally, `bash ./setup-supabase-services.sh` + Playwright
runs against BigQuery.

---

## Design overview

Introduce one switch variable, `LF_E2E_BACKEND` (`postgres` | `bigquery`,
default `postgres`):

- **postgres** → current behavior, nothing changes. Upstream compose already
  sets `POSTGRES_BACKEND_URL`, so Logflare picks Postgres.
- **bigquery** → the harness (a) strips `POSTGRES_BACKEND_*` from the cloned
  upstream compose, and (b) layers a BigQuery overlay that injects
  `GOOGLE_*` env + mounts the service-account `gcloud.json`.

Why this works (`config/runtime.exs:309-318`): Logflare uses Postgres **iff**
`LOGFLARE_SINGLE_TENANT` is truthy **and** `POSTGRES_BACKEND_URL` is non-`nil`;
otherwise BigQuery + `gcloud.json` → `:goth`. The check is `not is_nil(...)`, so
the URL must be *absent*, not blank (confirmed by
`Logflare.SingleTenant.postgres_backend?/0`, `lib/logflare/single_tenant.ex:382`).

The Supabase `db` service and all `DB_*` vars stay in both modes — only the
log-storage backend changes; Logflare still uses Postgres for its own metadata.

### Env var contract

| Variable | Used for | postgres | bigquery |
|----------|----------|----------|----------|
| `LF_E2E_BACKEND` | harness switch | `postgres` (default) | `bigquery` |
| `GOOGLE_PROJECT_ID` | BQ project | — | required |
| `GOOGLE_PROJECT_NUMBER` | BQ project | — | required |
| `LOGFLARE_GCLOUD_JSON` | **abs host path** to SA key file mounted as `gcloud.json` | — | required |
| `GOOGLE_DATASET_LOCATION` | BQ dataset region | — | optional |
| `GOOGLE_DATASET_ID_APPEND` | dataset isolation per run | — | optional |

In CI the SA key arrives as secret `GCP_SA_KEY` (JSON), is written to a file, and
`LOGFLARE_GCLOUD_JSON` points at that file. Locally you export the same vars and
point `LOGFLARE_GCLOUD_JSON` at your own key file.

---

## Phase 0 — GCP prerequisites (one-time)

- [ ] Create/identify a CI GCP project with the BigQuery API enabled; record
      `GOOGLE_PROJECT_ID` and `GOOGLE_PROJECT_NUMBER`.
- [ ] Create a service account with `roles/bigquery.dataEditor` +
      `roles/bigquery.jobUser`; download its key JSON.
- [ ] Confirm cost is acceptable (real streaming inserts + queries every run);
      plan dataset cleanup (Phase 6).

## Phase 1 — GitHub secrets

- [ ] Add secrets:
  - [ ] `GCP_SA_KEY` — full SA key JSON.
  - [ ] `GCP_PROJECT_ID` → `GOOGLE_PROJECT_ID`.
  - [ ] `GCP_PROJECT_NUMBER` → `GOOGLE_PROJECT_NUMBER`.
- [ ] **Fork limitation:** secrets are not available to `pull_request` runs from
      forks. The BigQuery job must tolerate missing secrets — gate it with an
      `if:` (skip when `secrets.GCP_SA_KEY == ''`) and/or restrict to `push` /
      same-repo PRs. The Postgres job stays unconditional.

## Phase 2 — Parameterize the harness by `LF_E2E_BACKEND`

### 2a. `test/e2e/supabase/config.sh`

- [ ] Add a default: `LF_E2E_BACKEND="${LF_E2E_BACKEND:-postgres}"` (alongside the
      existing `GITHUB_ACTIONS` default).

### 2b. `test/e2e/supabase/bin/compose`

- [ ] Conditionally append the BigQuery overlay only when bigquery is selected:
  ```sh
  COMPOSE_FILES="-f docker-compose.yml -f ../../docker-compose.e2e.yml"
  if [ "$LF_E2E_BACKEND" = "bigquery" ]; then
    COMPOSE_FILES="$COMPOSE_FILES -f ../../docker-compose.bigquery.yml"
  fi
  docker compose $COMPOSE_FILES "$@"
  ```
  (postgres path is byte-for-byte unchanged.)

### 2c. `test/e2e/supabase/setup-supabase-services.sh`

- [ ] After `git checkout "$BRANCH"`, **only when** `LF_E2E_BACKEND=bigquery`,
      strip the two backend lines from the cloned
      `supabase/docker/docker-compose.yml`:
  - [ ] `sed` out `POSTGRES_BACKEND_URL:` and `POSTGRES_BACKEND_SCHEMA:` (scoped
        to the `analytics` block).
  - [ ] Assert with `grep` they're gone; fail fast if upstream renamed them.
- [ ] **Validate required env** when bigquery: fail with a clear message if
      `GOOGLE_PROJECT_ID`, `GOOGLE_PROJECT_NUMBER`, or `LOGFLARE_GCLOUD_JSON`
      (and that the file exists) are missing.
- [ ] Make the readiness-probe deadline backend-aware: keep 60s for postgres,
      bump to ~180s for bigquery (line ~137, `DEADLINE=$((SECONDS + 60))`) — BQ
      schema seeding is slower.

### 2d. New file `test/e2e/supabase/docker-compose.bigquery.yml`

- [ ] Override `services.analytics` to add BigQuery config:
  ```yaml
  services:
    analytics:
      environment:
        GOOGLE_PROJECT_ID: ${GOOGLE_PROJECT_ID}
        GOOGLE_PROJECT_NUMBER: ${GOOGLE_PROJECT_NUMBER}
        GOOGLE_DATASET_LOCATION: ${GOOGLE_DATASET_LOCATION:-}
        GOOGLE_DATASET_ID_APPEND: ${GOOGLE_DATASET_ID_APPEND:-}
      volumes:
        - ${LOGFLARE_GCLOUD_JSON:?set LOGFLARE_GCLOUD_JSON to the SA key path}:/opt/app/rel/logflare/bin/gcloud.json:ro
  ```
  - Mount target is the container `WORKDIR` (`Dockerfile.multi-step:33`), where
    `runtime.exs:321` looks for `gcloud.json`.
  - Compose interpolates `${...}` from the shell env (CI job env / local export),
    so no `.env` edits are required.

> Note on the "blank URL" alternative: instead of sed-stripping the clone you
> could make `runtime.exs` treat an empty `POSTGRES_BACKEND_URL` as `nil` and
> blank it in the overlay. That touches shipped code; the sed approach keeps the
> change test-only. Prefer sed unless we want the runtime hardening anyway.

### 2e. `test/e2e/supabase/.gitignore`

- [ ] Ignore any local creds file (e.g. `gcloud.json`, `*.sa.json`) so a local
      key is never committed.

## Phase 3 — Workflow: two jobs from one definition — `.github/workflows/integration-supabase.yml`

Recommended: extract the shared steps into a **reusable workflow** and call it
twice, so the two jobs don't duplicate ~90 lines.

- [ ] Create `.github/workflows/_integration-supabase.yml` with
      `on: workflow_call`, inputs `backend` (string) and
      `browser_*`/matrix as needed, and `secrets` for the GCP values.
- [ ] Move the existing steps there; parameterize:
  - [ ] Export `LF_E2E_BACKEND: ${{ inputs.backend }}` at job/step env level.
  - [ ] **Bigquery-only step** (guarded by `if: inputs.backend == 'bigquery'`):
        write `${{ secrets.GCP_SA_KEY }}` to
        `test/e2e/supabase/gcloud.json`, then export
        `LOGFLARE_GCLOUD_JSON=$PWD/test/e2e/supabase/gcloud.json`,
        `GOOGLE_PROJECT_ID`, `GOOGLE_PROJECT_NUMBER` into `$GITHUB_ENV`.
  - [ ] Set a unique `GOOGLE_DATASET_ID_APPEND` per matrix leg + run
        (e.g. `${{ matrix.browsers.project }}-${{ github.run_id }}`).
- [ ] In `integration-supabase.yml`, define two caller jobs:
  - [ ] `postgres` → `uses: ./.github/workflows/_integration-supabase.yml` with
        `backend: postgres` (no secrets).
  - [ ] `bigquery` → same `uses:` with `backend: bigquery`,
        `secrets: inherit`, and `if:` guard for fork/secret availability.
- [ ] Ensure the creds file is excluded from `upload-artifact` paths and logs.

> Simpler fallback if reusable workflows are undesirable: duplicate the `test`
> job as `test-bigquery` with the extra creds step + `if:` guard. More
> copy-paste, no new file.

## Phase 4 — Dataset isolation (BigQuery only)

- [ ] BQ datasets key off the default user's DB id (~1 on a fresh DB) + project;
      parallel matrix legs would collide. Set `GOOGLE_DATASET_ID_APPEND` unique
      per leg+run (Phase 3). Verify it reaches `runtime.exs:231`
      (`dataset_id_append`).

## Phase 5 — Test timing & diagnostics — `test/e2e/supabase/features/logs.spec.ts`

- [ ] Re-evaluate `waitForLogs` timeout (currently `180_000`, ~line 74) — BQ
      streaming-buffer visibility is slower/variable; may need a higher value
      when running the bigquery job. Consider reading a `LF_E2E_BACKEND` env in
      the spec to scale the timeout, or just raise it for both.
- [ ] `sampleFromPostgres()` + `SOURCE_NAME_BY_TABLE` (~lines 11-64) query the
      Postgres `_analytics` schema; under BQ there's no such table. It's a
      best-effort diagnostic (returns `[]` on error → tests still pass), so it's
      harmless but inert for BQ — optionally branch on `LF_E2E_BACKEND` to skip
      it or replace with a `bq query` sample.
- [ ] `regexp_contains` query (~line 76) is BigQuery SQL already — no change.

## Phase 6 — Cleanup (BigQuery cost hygiene)

- [ ] Add a final bigquery-job step (`if: always()`) deleting the per-run
      dataset(s) (`bq rm -r -f` via `google-github-actions/setup-gcloud`, or API).
- [ ] Optionally set a default table expiration on created datasets as a backstop.

## Phase 7 — Local testing recipe

Document in the test README / this plan.

**Postgres (current, unchanged):**
```sh
cd test/e2e/supabase
bash ./setup-supabase-services.sh      # LF_E2E_BACKEND defaults to postgres
npx playwright test --project chromium
```

**BigQuery:**
```sh
cd test/e2e/supabase
export LF_E2E_BACKEND=bigquery
export GOOGLE_PROJECT_ID=my-project
export GOOGLE_PROJECT_NUMBER=123456789
export LOGFLARE_GCLOUD_JSON=$PWD/gcloud.json   # your SA key (gitignored)
export GOOGLE_DATASET_ID_APPEND=local-$(whoami)
bash ./setup-supabase-services.sh
npx playwright test --project chromium
# teardown:
LF_E2E_BACKEND=bigquery bin/compose down -v
bq rm -r -f "${GOOGLE_PROJECT_ID}:..._local-$(whoami)"   # delete test dataset
```

- [ ] Verify analytics container is healthy, the readiness probe passes, datasets
      appear in the BQ console, and the suite goes green for both backends.

## Phase 8 — Roll out

- [ ] PR with: `config.sh`, `bin/compose`, `setup-supabase-services.sh`,
      `docker-compose.bigquery.yml`, `.gitignore`, workflow (reusable + two
      callers), and any spec timing tweaks.
- [ ] Confirm CI: Postgres job behaves identically to today; BigQuery job runs
      all browsers, skips cleanly when secrets absent, and cleans up datasets.

---

## Files touched (summary)

| File | Change |
|------|--------|
| `test/e2e/supabase/config.sh` | default `LF_E2E_BACKEND=postgres` |
| `test/e2e/supabase/bin/compose` | conditionally add bigquery overlay |
| `test/e2e/supabase/setup-supabase-services.sh` | bigquery-only: strip `POSTGRES_BACKEND_*`, validate env, longer probe deadline |
| `test/e2e/supabase/docker-compose.bigquery.yml` | **new**: `GOOGLE_*` env + `gcloud.json` mount |
| `test/e2e/supabase/.gitignore` | ignore local SA key |
| `.github/workflows/_integration-supabase.yml` | **new**: reusable parameterized workflow |
| `.github/workflows/integration-supabase.yml` | two caller jobs (postgres + bigquery) |
| `test/e2e/supabase/features/logs.spec.ts` | backend-aware timeout; optional diagnostic branch |
| `config/runtime.exs` | *(only if choosing the empty-URL alternative in 2d)* |

## Open decisions

- [ ] Reusable workflow (DRY, new file) vs. duplicated second job (copy-paste).
- [ ] sed-strip the clone (test-only) vs. harden `runtime.exs` for empty URL.
- [ ] BigQuery job trigger policy given the fork-secret limitation.
