# Snowflake dbt CI/CD Platform

Enterprise deployment platform for the **transformation** dbt project using **Snowflake DBT PROJECT** objects, GitHub Actions, and manifest-based state deployments.

**Related docs:**
- [Current vs future — 1-page summary (presentation)](./docs/explaining.md)
- [JIRA stories draft](./docs/JIRA_STORIES.md)
- [DBT_CICD schema setup & stage → main promotion](./docs/DBT_CICD_SETUP.md)
- [Snowflake RBAC & SCIM alignment](./snowflake_rbac_readme.md)

---

## Table of contents

1. [Overview](#overview)
2. [Current architecture](#current-architecture)
3. [Known issues & fixes](#known-issues--fixes)
4. [Target-state architecture](#target-state-architecture)
5. [GitHub Actions workflow design](#1-github-actions-workflow-design)
6. [Snowflake-native execution strategy](#2-snowflake-native-execution-strategy)
7. [Audit & observability framework](#3-audit--observability-framework)
8. [Promotion control framework](#4-promotion-control-framework)
9. [Manifest management](#5-manifest-management)
10. [Failure handling](#6-failure-handling)
11. [First deployment strategy](#7-first-deployment-strategy)
12. [Scalability considerations](#8-scalability-considerations)
13. [Repository layout](#repository-layout)
14. [Workflow reference](#workflow-reference)
15. [Implementation roadmap](#implementation-roadmap)
16. [Best practices](#best-practices)

---

## Overview

### Goals

| Goal | Approach |
|------|----------|
| Avoid GitHub Actions timeout issues | GitHub orchestrates; Snowflake executes long-running builds |
| Keep manifest-based state deployments | `state:modified+` with env-specific manifests on Snowflake Stage |
| Ensure PREPROD passes before PROD | Promotion registry enforced by Git SHA |
| Minimize EC2 runner dependency | EC2 used only for deploy CLI; execution moves to Snowflake |
| Auditable, scalable platform | Deployment + model-level audit tables in Snowflake |

### Design principles

- **Deploy ≠ Execute** — deployment uploads the DBT PROJECT definition; execution is a separate, async step.
- **Git SHA is the release artifact** — PROD may only run SHAs that validated in PREPROD.
- **Manifests are env-specific** — never compare a dev manifest against a preprod/prod execution.
- **GitHub Actions is the control plane, not the compute plane** — jobs should complete in minutes, not hours.

---

## Current architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              GITHUB (Control Plane)                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  feature/* ──►  [CI Workflow]  ──► parse, lint, slim build (dev), tests         │
│                      │                    │                                      │
│                      │                    └── uses manifest artifact (read-only) │
│                      ▼                                                           │
│                   PR required ──► main                                           │
│                                                                                  │
│  main push ──►  [CD: Deploy PREPROD]  (~5-15 min, EC2 runner)                    │
│                      │                                                           │
│                      ├── snow dbt deploy (DBT PROJECT object)                    │
│                      ├── upload manifest → GitHub Artifact                       │
│                      └── optional: dbt build on EC2 (being phased out)           │
│                                                                                  │
│  manual ──►  [Manual Build]  ──► mart-scoped dbt build (CTS_OPS)               │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              SNOWFLAKE (Data Plane)                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│  DBT PROJECT: DATAWAREHOUSE                                                      │
│  Databases: DATAWAREHOUSE_CTS (dev/prod), DATAWAREHOUSE_CTS__PREPROD (preprod)  │
│  Role: CTS_OPS (deploy + build)                                                  │
│  Warehouses: WH_TAG_M (dev/preprod), WH_TAG_L (prod — recommended for builds)   │
└─────────────────────────────────────────────────────────────────────────────────┘
```

### Assumptions challenged

| Assumption | Verdict |
|------------|---------|
| GitHub Actions should run `dbt build` for CD | **Reject for production** — GHA is an orchestrator, not a compute plane for 6+ hour jobs |
| EC2 self-hosted runner is the long-term execution engine | **Reject** — single point of failure, timeout coupling, ops burden |
| Deploy + build in one job is fine | **Reject** — split deploy (minutes) from execute (hours) |
| First deploy should run all models | **Reject** — bootstrap via phased mart rollout |
| Manifest in GitHub Artifacts only is enough | **Partially reject** — Artifacts for CI; **Snowflake Stage** as system of record per env |
| PREPROD auto-deploy on `main` without promotion registry | **Reject** — need SHA-level promotion ledger in Snowflake |

---

## Known issues & fixes

### `run_build` checkbox ignored (fixed)

**Symptom:** Unchecking **Execute dbt build after deploy** still triggered `dbt build`.

**Root cause:** GitHub Actions expressions treat boolean `false` as falsy:

```yaml
# BAD — false || 'true' evaluates to 'true'
inputs.run_build || 'true'
```

**Fix in `run-dbt-cd.yaml`:**

```yaml
RUN_BUILD_INPUT: ${{ github.event_name == 'push' && 'true' || format('{0}', inputs.run_build) }}

# Build step
if: ${{ github.event_name == 'push' || inputs.run_build }}
```

> **Note:** `dbt compile` still runs after deploy (metadata only — does not execute models).

### GitHub Actions 6-hour timeout

**Symptom:** First CD run executes all models (no manifest baseline); some models run 6+ hours; job times out on EC2.

**Root cause:** Synchronous `dbt build` on EC2 inside a GitHub Actions job.

**Target fix:** Move execution to Snowflake (`snow dbt execute` or Task-based); GitHub triggers and exits. See [Target-state architecture](#target-state-architecture).

### `env` context in `runs-on` (fixed in CI)

**Symptom:** `Unrecognized named-value: 'env'` in `run-dbt-ci.yaml`.

**Fix:** Use literal runner labels or `inputs.*` in `runs-on` — workflow-level `env` is not valid there.

---

## Target-state architecture

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              GITHUB (Control Plane)                              │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  feature/* ──►  [CI Workflow]  ──► parse, lint, slim build (dev), tests         │
│                      │                    │                                      │
│                      │                    └── uses manifest artifact (read-only) │
│                      ▼                                                           │
│                   PR required ──► main                                           │
│                                                                                  │
│  main push ──►  [CD: Deploy PREPROD]  (~5-15 min, EC2 or small runner)          │
│                      │                                                           │
│                      ├── snow dbt deploy (DBT PROJECT object)                    │
│                      ├── upload manifest → Snowflake Stage + artifact            │
│                      ├── write DEPLOYMENT_AUDIT (QUEUED)                        │
│                      └── trigger Snowflake EXECUTE job (async) ───────────────┐  │
│                                                                                 │  │
│  manual / scheduled ──► [CD: Promote PROD]                                      │  │
│                      │   requires: PREPROD SHA validated + approval           │  │
│                      └── deploy PROD DBT PROJECT @ same SHA                     │  │
│                          trigger PROD execute                                   │  │
│                                                                                 │  │
└─────────────────────────────────────────────────────────────────────────────────┘  │
                                                                                     │
                                      REST callback / polling (optional)           │
                                                                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                         SNOWFLAKE (Execution + State Plane)                      │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  @DBT_CICD (database)                                                            │
│    ├── DEPLOYMENTS           ← deployment audit (SHA, env, status, GH run id)   │
│    ├── MODEL_RUNS            ← model-level execution audit                       │
│    ├── PROMOTION_REGISTRY    ← SHA allowed for PROD                              │
│    └── STAGES/manifests/{env}/{sha}/manifest.json                               │
│                                                                                  │
│  DBT PROJECT: DATAWAREHOUSE  (per env database/schema)                           │
│                                                                                  │
│  EXECUTION (recommended primary):                                                │
│    snow dbt execute  (Snowflake-managed dbt runtime)                             │
│                                                                                  │
│  ALTERNATIVES:                                                                   │
│    Snowflake Task → stored proc → execute wrapper                                │
│    Snowflake Job (orchestration shell)                                           │
│                                                                                  │
│  Warehouses: WH_DBT_BUILD_{ENV} (XL+ for long models, auto-suspend)             │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘
```

---

## 1. GitHub Actions workflow design

### Separation of CI and CD

```
┌──────────────┐     ┌──────────────────┐     ┌─────────────────────┐
│   CI (dev)   │     │  CD Deploy       │     │  CD Execute         │
│              │     │  (short-lived)   │     │  (Snowflake-native) │
├──────────────┤     ├──────────────────┤     ├─────────────────────┤
│ dbt parse    │     │ snow dbt deploy  │     │ snow dbt execute    │
│ dbt compile  │     │ manifest upload  │     │   OR Task trigger   │
│ slim build   │     │ audit: DEPLOYED  │     │ audit: RUNNING/DONE │
│ unit tests   │     │ trigger execute  │     │ poll status (opt.)  │
│ < 30 min     │     │ < 20 min         │     │ hours, no GHA wait  │
└──────────────┘     └──────────────────┘     └─────────────────────┘
```

### Recommended workflows

| Workflow | File | Trigger | Runner | Duration cap |
|----------|------|---------|--------|--------------|
| dbt CI | `run-dbt-ci.yaml` | PR / feature push | dev EC2 (`dev` label) | 30 min |
| dbt CD Deploy | `run-dbt-cd.yaml` | push `main` → PREPROD | prod EC2 (`prod` label) | 20 min (deploy only) |
| dbt CD Promote PROD | `run-dbt-cd-promote-prod.yaml` *(planned)* | manual, gated | prod EC2 | 20 min |
| dbt Build (Manual) | `run-dbt-build.yaml` | manual mart builds | env runner | trigger-only (< 5 min) |
| dbt Status Poll | `run-dbt-status.yaml` *(planned)* | schedule / manual | `ubuntu-latest` | 5 min |

### Deployment stages & promotion

```
  DEV          PREPROD              PROD
   │              │                   │
   │  CI slim     │  full execute     │  promote same SHA only
   │  build       │  + validation     │  + approval
   ▼              ▼                   ▼
 state:mod+    state:mod+         state:mod+ (against PROD manifest)
 (dev mf)      (preprod mf)       (prod mf)
```

### Approval gates

| Gate | Mechanism |
|------|-----------|
| PREPROD deploy | Auto on `main` merge (optional: required reviewer on `preprod` GitHub Environment) |
| PREPROD execute | Auto-trigger after deploy; optional data QA workflow |
| PROD deploy | **Manual** workflow + GitHub Environment `prod` required reviewers |
| PROD execute | Only if `PROMOTION_REGISTRY` has SHA with `status = VALIDATED` |

### Rollback strategy

Rollback is **not** re-running an old branch blindly:

1. **Deploy** prior DBT PROJECT version (redeploy at prior Git SHA).
2. **Execute** with prior manifest from Stage: `@DBT_CICD/manifests/preprod/{previous_sha}/`.
3. Write `DEPLOYMENTS` row: `action = ROLLBACK`, `from_sha`, `to_sha`.
4. For model-level rollback: re-run specific models via dbt selector, not full project.

Treat **Git SHA as an immutable release artifact**.

---

## 2. Snowflake-native execution strategy

### Options comparison

| Option | Pros | Cons | Verdict |
|--------|------|------|---------|
| **EC2 `dbt build`** (current) | Familiar, full dbt CLI | 6 hr GHA limit, runner dependency, no elastic WH | **Retire for CD** |
| **`snow dbt execute`** | Native runtime, scales with WH, no runner timeout | Newer, less CLI flexibility | **Primary for CD** |
| **Snowflake Task + SP** | In-account scheduling, retry, audit | Custom wrapper code | **Good for schedules/retries** |
| **Snowflake Jobs** | Orchestration, monitoring | Another layer to maintain | **Optional shell** |
| **Stored proc calling external** | Flexible | Defeats native execution purpose | **Avoid** |

### Recommended pattern

```bash
# Deploy (GitHub Actions, ~10 min)
snow dbt deploy DATAWAREHOUSE \
  --source transformation \
  --profiles-dir "$DBT_PROFILES_DIR" \
  --default-target preprod \
  --dbt-version 1.10.15 \
  --force

# Execute (Snowflake, async — no GitHub wait)
snow dbt execute DATAWAREHOUSE \
  --select "state:modified+" \
  --state @DBT_CICD/manifests/preprod/{prev_sha}/ \
  --vars '{"deployment_id": "..."}'
```

**Why this fixes timeout:** GitHub exits after triggering execute. Snowflake runs for hours on a dedicated build warehouse.

### Warehouse sizing for long-running models

- Dedicated **`WH_DBT_BUILD_PREPROD`** / **`WH_DBT_BUILD_PROD`**
- Size **L–XL+** for known 6 hr+ models (or isolate to **`WH_DBT_HEAVY`**)
- Set `statement_timeout_in_seconds` per session where appropriate
- Tag queries: **`QUERY_TAG = dbt:deployment_id:model_name`**

---

## 3. Audit & observability framework

### Snowflake database layout

```sql
CREATE DATABASE DBT_CICD;
CREATE SCHEMA DBT_CICD.OPS;
CREATE SCHEMA DBT_CICD.MANIFESTS;  -- stages + file formats
```

### Deployment audit table

```sql
CREATE TABLE DBT_CICD.OPS.DEPLOYMENTS (
    deployment_id           VARCHAR PRIMARY KEY,      -- UUID
    environment             VARCHAR NOT NULL,         -- dev | preprod | prod
    git_sha                 VARCHAR NOT NULL,
    git_ref                 VARCHAR,                  -- main, tag, etc.
    github_run_id           NUMBER,
    github_run_url          VARCHAR,
    github_actor            VARCHAR,
    dbt_project_name        VARCHAR DEFAULT 'DATAWAREHOUSE',
    dbt_project_version     VARCHAR,
    deploy_status           VARCHAR NOT NULL,         -- QUEUED|DEPLOYING|DEPLOYED|FAILED
    execute_status          VARCHAR,                  -- QUEUED|RUNNING|SUCCEEDED|FAILED|PARTIAL
    execute_mode            VARCHAR,                  -- full|state_modified|mart|manual
    selector                VARCHAR,
    manifest_path           VARCHAR,                  -- @stage/path
    prior_manifest_path     VARCHAR,
    models_requested        NUMBER,
    models_succeeded        NUMBER,
    models_failed           NUMBER,
    started_at              TIMESTAMP_NTZ,
    deploy_finished_at      TIMESTAMP_NTZ,
    execute_started_at      TIMESTAMP_NTZ,
    execute_finished_at     TIMESTAMP_NTZ,
    error_message           VARCHAR,
    is_rollback             BOOLEAN DEFAULT FALSE,
    rollback_from_sha       VARCHAR,
    promoted_to_prod        BOOLEAN DEFAULT FALSE,
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### Model-level execution audit

```sql
CREATE TABLE DBT_CICD.OPS.MODEL_RUNS (
    model_run_id            VARCHAR PRIMARY KEY,
    deployment_id           VARCHAR NOT NULL,
    environment             VARCHAR NOT NULL,
    git_sha                 VARCHAR NOT NULL,
    model_unique_id         VARCHAR NOT NULL,         -- model.transformation.marts.analytics.foo
    resource_type           VARCHAR,                  -- model | test | snapshot
    status                  VARCHAR NOT NULL,         -- started|success|error|skipped
    snowflake_query_id      VARCHAR,
    warehouse               VARCHAR,
    execution_time_ms       NUMBER,
    rows_affected           NUMBER,
    error_message           VARCHAR,
    started_at              TIMESTAMP_NTZ,
    finished_at             TIMESTAMP_NTZ,
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### Promotion registry

```sql
CREATE TABLE DBT_CICD.OPS.PROMOTION_REGISTRY (
    git_sha                 VARCHAR PRIMARY KEY,
    preprod_deployment_id   VARCHAR NOT NULL,
    preprod_validated_at    TIMESTAMP_NTZ,
    preprod_validated_by    VARCHAR,
    prod_deployment_id      VARCHAR,
    prod_deployed_at        TIMESTAMP_NTZ,
    prod_deployed_by        VARCHAR,
    status                  VARCHAR NOT NULL,         -- VALIDATED|PROMOTED|REVOKED
    validation_notes        VARCHAR,
    created_at              TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### GitHub run tracking

Write to `DEPLOYMENTS` at workflow start with `github_run_id` and run URL. Optional: Slack/Teams webhook on status transitions.

### Metrics to dashboard

- Deploy frequency / lead time (deploy → execute complete)
- Model failure rate by mart
- P95 model duration (from `MODEL_RUNS` + `QUERY_HISTORY`)
- % runs using `state:modified+` vs full
- Promotion lag (PREPROD validated → PROD deployed)

---

## 4. Promotion control framework

### Deployment lifecycle state machine

```
                    ┌─────────────┐
                    │  CI PASSED  │
                    └──────┬──────┘
                           │ merge to main
                           ▼
                    ┌─────────────┐
               ┌───►│ PREPROD     │
               │    │ DEPLOYED    │
               │    └──────┬──────┘
               │           │ execute
               │           ▼
               │    ┌─────────────┐
               │    │ PREPROD     │
               │    │ EXECUTING   │
               │    └──────┬──────┘
               │      success│      failure
               │           ▼           ▼
               │    ┌─────────────┐  BLOCKED
               │    │ VALIDATED   │
               │    └──────┬──────┘
               │           │ manual approve + promote workflow
               │           ▼
               │    ┌─────────────┐
               └─── │ PROD        │  (only if git_sha in PROMOTION_REGISTRY
                    │ DEPLOYED    │   with status = VALIDATED)
                    └──────┬──────┘
                           ▼
                    ┌─────────────┐
                    │ PROD        │
                    │ EXECUTING   │
                    └─────────────┘
```

### Enforce promotion by Git SHA

PROD workflow guard (first step):

```yaml
- name: Verify PREPROD validation for this SHA
  run: |
    # Query PROMOTION_REGISTRY — fail if SHA not VALIDATED
    snow sql -q "
      SELECT status FROM DBT_CICD.OPS.PROMOTION_REGISTRY
      WHERE git_sha = '${{ github.sha }}' AND status = 'VALIDATED'
    "
```

**Do not allow PROD workflow to accept arbitrary SHA input** — deploy only SHAs from the validated registry or the release tag.

### Stored procedure: execute deployment

```sql
CREATE OR REPLACE PROCEDURE DBT_CICD.OPS.EXECUTE_DEPLOYMENT(
    DEPLOYMENT_ID VARCHAR,
    SELECTOR VARCHAR DEFAULT 'state:modified+'
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS
$$
BEGIN
    UPDATE DBT_CICD.OPS.DEPLOYMENTS
    SET execute_status = 'RUNNING', execute_started_at = CURRENT_TIMESTAMP()
    WHERE deployment_id = :DEPLOYMENT_ID;

    -- Invoke snow dbt execute or native Snowflake dbt execution API
    -- Parse results → MODEL_RUNS
    -- On success: update manifest pointer, execute_status = SUCCEEDED
    -- On failure: execute_status = FAILED
END;
$$;
```

---

## 5. Manifest management

### Storage strategy

| Store | Purpose |
|-------|---------|
| **Snowflake Stage** `@DBT_CICD/manifests/{env}/{sha}/manifest.json` | System of record for `state:modified+` in CD execute |
| **GitHub Artifact** `dbt-manifest-{env}-{sha}` | CI slim builds, debugging |
| **S3** *(optional)* | Org-wide backup / DR — mirror from Stage |

### Versioning layout

```
@DBT_CICD/manifests/
  preprod/
    abc123/manifest.json     ← baseline for preprod state:modified+
    def456/manifest.json
  prod/
    abc123/manifest.json
  latest_preprod.json        ← pointer updated post-success
  latest_prod.json
```

After successful execute:

1. Copy `target/manifest.json` → `@DBT_CICD/manifests/{env}/{sha}/`
2. Update `latest_{env}.json` pointer
3. Upload GitHub Artifact for CI consumption

### `state:modified+` implementation

```bash
# Download prior manifest from Stage (not artifact — artifact may be stale/missing)
snow stage copy @DBT_CICD/manifests/latest_preprod.json /tmp/prior/

snow dbt execute DATAWAREHOUSE \
  --select "state:modified+" \
  --state /tmp/prior/
```

**CI vs CD manifests must be env-specific.** Do not compare a dev manifest against a preprod execution.

---

## 6. Failure handling

| Failure | Recovery |
|---------|----------|
| **GHA timeout during deploy** | Idempotent redeploy; check `DEPLOYMENTS.deploy_status` |
| **GHA timeout during build** | Should not occur once build moves to Snowflake |
| **Runner failure mid-deploy** | Re-run deploy job; `snow dbt deploy --force` is idempotent |
| **Snowflake warehouse failure** | Task retry with backoff; resume via `dbt retry` or re-execute failed selector |
| **Partial model failure** | Record in `MODEL_RUNS`; trigger `execute --select result:error+` |
| **Orphaned execute (GHA died after trigger)** | Status poller workflow queries `DEPLOYMENTS` + Snowflake query history |

### Workflow retries

- Deploy steps: retry up to 2× on transient Snowflake/network errors
- Execute: retry at Snowflake layer (Task / SP), not in GitHub

---

## 7. First deployment strategy

**Do not run all models on the first PREPROD CD run.**

### Phased bootstrap

| Phase | Action |
|-------|--------|
| **Phase 0** | Deploy only (`snow dbt deploy --force`); upload manifest from `dbt parse`/`compile` (no run) |
| **Phase 1** | Mart-by-mart manual builds via `run-dbt-build.yaml`: analytics → auditpro → hex → ppo_invoicing → strategy_planning |
| **Phase 2** | Enable `state:modified+` CD once baseline manifest exists in Stage |
| **Phase 3** | Enable auto PREPROD execute on `main` (small deltas only) |

### Tag-based tiers (alternative)

```yaml
# dbt_project.yml
models:
  transformation:
    marts:
      analytics:
        +tags: [tier1, nightly]
      heavy_model:
        +tags: [tier3, weekly]
```

Bootstrap: `--select tag:tier1`, then tier2, etc.

### Backfill recommendation

Run long-running historical models **outside CD** as one-time Snowflake tasks with a dedicated warehouse, then register the manifest baseline.

---

## 8. Scalability considerations

| Concern | Approach |
|---------|----------|
| Thousands of models | Never full build in CD; strict `state:modified+`; mart boundaries |
| 6+ hour models | Snowflake execute + XL warehouse; isolate via `heavy` tag |
| Concurrency | `threads: 4–8` in profile; separate WH for heavy vs light |
| DAG depth | Split into Snowflake Tasks by mart with dependencies |
| Cost | Auto-suspend WH; separate WH per env; query tags for chargeback |

---

## Repository layout

```
.
├── .github/workflows/
│   ├── run-dbt-ci.yaml          # CI: parse, slim build, tests (dev)
│   ├── run-dbt-cd.yaml          # CD: deploy DBT PROJECT to PREPROD/PROD
│   ├── run-dbt-build.yaml       # Manual mart-scoped build (CTS_OPS)
│   ├── run-dbt-ci-manual.sh     # EC2 replay script for CI
│   ├── run-dbt-cd-manual.sh     # EC2 replay script for CD
│   └── run-snow-cli-manual.sh   # Snow CLI connection test
├── transformation/              # dbt project root
│   ├── dbt_project.yml
│   ├── profiles.yml             # Local dev only — not used in CI/CD
│   └── models/
│       ├── staging/
│       └── marts/
│           ├── analytics/
│           ├── auditpro/
│           ├── hex/
│           ├── ppo_invoicing/
│           └── strategy_planning/
├── database/schema-model/       # Flyway SQL (RBAC, stored procedures)
└── snowflake_rbac_readme.md     # RBAC / SCIM role alignment
```

---

## Workflow reference

### dbt CI (`run-dbt-ci.yaml`)

| Setting | Value |
|---------|-------|
| Trigger | PR to `main`, push to `feature*`, manual |
| Environment | `dev` |
| Runner | Self-hosted, label `dev` |
| Snowflake role | `DBT_DEVELOPER` |
| Build | `state:modified+` if manifest artifact exists; fallback single model |

### dbt CD (`run-dbt-cd.yaml`)

| Setting | Value |
|---------|-------|
| Trigger | Push to `main` (PREPROD), manual dispatch |
| Snowflake role | `CTS_OPS` |
| Deploy | `snow dbt deploy DATAWAREHOUSE` |
| Build | Optional (`run_build` input); skipped when unchecked |
| Manifest | Uploaded as `dbt-manifest-main` artifact (90 days) |

**Environments:**

| Env | Database | Account secret | Key secret |
|-----|----------|----------------|------------|
| dev | `DATAWAREHOUSE_CTS` | `DBT_SNOWFLAKE_ACCOUNT_DEV` | `SNOWFLAKE_PRIVATE_KEY_DEV` |
| preprod | `DATAWAREHOUSE_CTS__PREPROD` | `DBT_SNOWFLAKE_ACCOUNT_PROD` | `SNOWFLAKE_PRIVATE_KEY_PROD` |
| prod | `DATAWAREHOUSE_CTS` | `DBT_SNOWFLAKE_ACCOUNT_PROD` | `SNOWFLAKE_PRIVATE_KEY_PROD` |

### dbt Build Manual (`run-dbt-build.yaml`)

| Setting | Value |
|---------|-------|
| Trigger | Manual only (must exist on `main` to appear in Actions UI) |
| Snowflake role | `CTS_OPS` |
| Model selection | Dropdown mart or custom dbt selector |
| Confirmation | Must select **Yes — run dbt build** |

**Available marts:** `analytics`, `auditpro`, `hex`, `ppo_invoicing`, `strategy_planning`

### Required GitHub secrets

| Secret | Used by |
|--------|---------|
| `DBT_SNOWFLAKE_USER` | All workflows |
| `DBT_SNOWFLAKE_ACCOUNT_DEV` | CI, dev CD/build |
| `DBT_SNOWFLAKE_ACCOUNT_PROD` | preprod, prod CD/build |
| `SNOWFLAKE_PRIVATE_KEY_DEV` | CI, dev |
| `SNOWFLAKE_PRIVATE_KEY_PROD` | preprod, prod |

Configure **GitHub Environments** (`dev`, `preprod`, `prod`) for secrets scoping and required reviewers.

---

## Implementation roadmap

### Phase 1 — Immediate (this week)

- [x] Fix `run_build` boolean bug in `run-dbt-cd.yaml`
- [x] Fix `env` context in `runs-on` for CI
- [ ] Split CD: deploy job ends after `snow dbt deploy` + manifest upload
- [ ] Add option for deploy-only on `main` push (no build until manifest baseline exists)
- [ ] Remove synchronous long-running `dbt build` from CD

### Phase 2 — Short term (2–4 weeks)

- [ ] Create `DBT_CICD` database, audit tables, manifest Stage
- [ ] Implement `snow dbt execute` trigger from GitHub (async)
- [ ] Store manifest on Snowflake Stage per env/SHA
- [ ] Add `PROMOTION_REGISTRY` + PROD gate workflow

### Phase 3 — Medium term (1–2 months)

- [ ] Status polling workflow + Slack/Teams alerts
- [ ] Model-level audit ingestion from dbt artifacts / query history
- [ ] Retire EC2 for execution (thin runner for deploy CLI only)
- [ ] Dashboard for deployment metrics

---

## Best practices

### Snowflake DBT PROJECT

1. **Deploy ≠ Execute** — always separate.
2. **One DBT PROJECT per logical env** with strict target/database separation.
3. **Pin `dbt-version`** in deploy (`DBT_VERSION: 1.10.15`).
4. **Strip `analyses/`** before deploy (Snowflake DBT PROJECT cannot bundle analysis SQL).
5. **Never commit secrets** — generate `profiles.yml` per run from GitHub secrets.
6. **Use `CTS_OPS`** for production deploy and execute.
7. **Manifest per env** — never share PREPROD/PROD state files.
8. **Idempotent deploys** — `--force` with version tracking in audit table.

### GitHub Actions

1. **`workflow_dispatch` workflows** must be on `main` to appear in the Actions UI.
2. **Boolean inputs:** never use `input || 'true'` — use `format('{0}', inputs.flag)` or explicit `if` conditions.
3. **`runs-on`:** use literal labels or `inputs.*`; not `env.*`.
4. **Concurrency groups** per environment to prevent overlapping deploys.
5. **Self-hosted runners** must carry env labels (`dev`, `prod`) matching workflow `runs-on`.

### dbt

1. Use **`state:modified+`** for CI/CD after bootstrap.
2. Scope manual builds by **mart** (`path:models/marts/{mart}`).
3. Exclude analyses in CI/CD: `--exclude path:analyses`.
4. Tag long-running models (`heavy`, `tier3`) for isolated execution.

---

## Document history

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | 2026-09-04 | Initial platform architecture and workflow reference |
