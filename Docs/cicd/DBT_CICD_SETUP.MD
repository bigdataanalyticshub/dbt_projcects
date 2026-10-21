# DBT_CICD Schema Setup & Stage → Main Promotion

Setup guide for the **DBT_CICD** schema in your **existing Snowflake database**, plus GitHub branch/workflow configuration for the **stage → main** promotion model.

---

## Branch flow

```
feature/*  ──PR──►  stage  ──(auto CI + PREPROD CD)──►  preprod-cd ✓
                      │
                      └──PR (gate)──►  main  ──(manual PROD CD)──►  prod
```

| Branch | Trigger | What runs |
|--------|---------|-----------|
| `feature/*` | Push / PR → `stage` | **CI** (dev): parse, slim build |
| `stage` | Push (merge) | **CI** + **CD PREPROD** (deploy + **automatic dbt build**) |
| `stage` → `main` | Pull request | **Promote gate** — blocks merge if `preprod-cd` ≠ success |
| `main` | Manual | **PROD CD** (after gate verified SHA) |

---

## Part 1 — Snowflake: DBT_CICD schema setup

### Choose your database

Use an **existing database** (recommended: **`DATAWAREHOUSE_CTS`**). Do **not** create a new database.

All objects live under:

```
{YOUR_DATABASE}.DBT_CICD
```

Update `{{DATABASE}}` in the SQL scripts (or set once in your Flyway/session config).

### Run scripts in order

| Order | File | Creates |
|-------|------|---------|
| 1 | `database/schema-model/DBT_CICD/001_create_schema.sql` | Schema + grants |
| 2 | `database/schema-model/DBT_CICD/002_file_format_and_stage.sql` | `MANIFEST_JSON_FORMAT`, stage `MANIFESTS` |
| 3 | `database/schema-model/DBT_CICD/003_tables.sql` | `DEPLOYMENTS`, `MODEL_RUNS`, `PROMOTION_REGISTRY`, `BRANCH_EVENTS` |
| 4 | `database/schema-model/DBT_CICD/004_views.sql` | Monitoring views |
| 5 | `database/schema-model/DBT_CICD/005_stored_procedures.sql` | Audit + promotion SPs |

**Example (replace database name):**

```bash
# Run each file in Snowflake worksheet or via Flyway after substituting {{DATABASE}}
sed 's/{{DATABASE}}/DATAWAREHOUSE_CTS/g' database/schema-model/DBT_CICD/001_create_schema.sql
```

### Objects checklist

#### Schema

- [ ] `DATAWAREHOUSE_CTS.DBT_CICD` (or your chosen database)

#### Stage & file format

- [ ] `MANIFEST_JSON_FORMAT` — JSON for `manifest.json`
- [ ] `MANIFESTS` — internal stage for per-env manifests  
  Path convention: `preprod/{git_sha}/manifest.json`

#### Tables

| Table | Purpose |
|-------|---------|
| **DEPLOYMENTS** | One row per GitHub CD run (deploy + execute lifecycle) |
| **MODEL_RUNS** | Per-model execution audit (populate from dbt artifacts / query history) |
| **PROMOTION_REGISTRY** | SHAs **VALIDATED** in PREPROD — allowed to merge to `main` |
| **BRANCH_EVENTS** | Optional audit of blocked/allowed promotion attempts |

#### Views

| View | Purpose |
|------|---------|
| **V_LATEST_PREPROD_SUCCESS** | Latest successful PREPROD deployment |
| **V_SHA_PROMOTABLE_TO_MAIN** | SHAs with `status = VALIDATED` |
| **V_DEPLOYMENT_STATUS** | Dashboard of recent deployments |

#### Stored procedures

| Procedure | Called when |
|-----------|-------------|
| **SP_DEPLOYMENT_START** | CD starts on `stage` push |
| **SP_DEPLOYMENT_DEPLOYED** | After `snow dbt deploy` succeeds |
| **SP_DEPLOYMENT_EXECUTE_FINISH** | After dbt build completes |
| **SP_REGISTER_PREPROD_VALIDATION** | PREPROD success → enables `stage → main` |
| **SP_REVOKE_PROMOTION** | Manually block a SHA |
| **SP_IS_SHA_PROMOTABLE** | Returns TRUE if SHA is VALIDATED |

#### Grants

Grant **`CTS_OPS`** (GitHub Actions service user role):

```sql
GRANT USAGE ON DATABASE DATAWAREHOUSE_CTS TO ROLE CTS_OPS;
GRANT USAGE ON SCHEMA DATAWAREHOUSE_CTS.DBT_CICD TO ROLE CTS_OPS;
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA DATAWAREHOUSE_CTS.DBT_CICD TO ROLE CTS_OPS;
GRANT USAGE ON ALL PROCEDURES IN SCHEMA DATAWAREHOUSE_CTS.DBT_CICD TO ROLE CTS_OPS;
GRANT READ, WRITE ON STAGE DATAWAREHOUSE_CTS.DBT_CICD.MANIFESTS TO ROLE CTS_OPS;
```

### GitHub repo variable (optional)

Set repository variable `DBT_CICD_DATABASE` if not using `DATAWAREHOUSE_CTS` (workflow env defaults to `DATAWAREHOUSE_CTS`).

---

## Part 2 — GitHub branch setup

### Create the `stage` branch

```bash
git checkout main
git pull
git checkout -b stage
git push -u origin stage
```

Set **`stage`** as the default integration branch for feature work (optional but recommended).

### Branch protection: `stage`

| Rule | Setting |
|------|---------|
| Require pull request | ✅ |
| Required checks | `dbt CI` / `dbt-ci` (job name from workflow) |
| Allow direct push | ❌ (except admins if needed) |

Feature branches merge **only into `stage`** via PR.

### Branch protection: `main`

| Rule | Setting |
|------|---------|
| Require pull request | ✅ |
| **Restrict source branches** | **Only `stage`** |
| Required status checks | **`preprod-cd`** (commit status from CD workflow) |
| Required checks | **`Promote gate (stage → main)`** / `verify-preprod-promotion` |
| Require branch up to date | ✅ |

This **rejects merge to `main`** when:

1. Latest commit on the PR does not have **`preprod-cd` = success**, or  
2. PR is not from **`stage`**, or  
3. **Promote gate** workflow failed.

### How `preprod-cd` status is set

On every **push to `stage`**, `run-dbt-cd.yaml`:

1. Deploys DBT PROJECT to **PREPROD**
2. Runs **`dbt build` automatically** (no manual trigger)
3. On success → sets commit status **`preprod-cd`** = `success` on that SHA
4. On failure → sets **`preprod-cd`** = `failure` (blocks future PR to `main`)
5. Registers SHA in **`PROMOTION_REGISTRY`** via `SP_REGISTER_PREPROD_VALIDATION`

---

## Part 3 — Workflow map

| Workflow | Trigger | Purpose |
|----------|---------|---------|
| `run-dbt-ci.yaml` | PR/push → `stage`, push → `feature/*` | Dev validation |
| `run-dbt-cd.yaml` | **Push → `stage`** | PREPROD deploy + auto build |
| `run-dbt-promote-gate.yaml` | PR → `main` | Block merge without `preprod-cd` |
| `run-dbt-cd-prod.yaml` | Manual | PROD deploy (after SHA validated) |
| `run-dbt-build.yaml` | Manual | Mart-scoped builds |

---

## Part 4 — Day-to-day developer flow

1. Create `feature/my-change` from `stage`
2. Open PR → **`stage`** → CI runs automatically
3. Merge PR to **`stage`**
4. CD runs automatically on `stage` push → PREPROD deploy + build
5. Wait for green **`preprod-cd`** on the merge commit
6. Open PR **`stage` → `main`**
7. **Promote gate** + branch protection verify `preprod-cd`
8. Merge to **`main`**
9. Run **dbt Project CD (PROD)** manually (or extend `run-dbt-cd-prod.yaml`)

---

## Part 5 — Verify promotion state

```sql
-- SHAs allowed to merge to main
SELECT * FROM DATAWAREHOUSE_CTS.DBT_CICD.V_SHA_PROMOTABLE_TO_MAIN;

-- Latest PREPROD success
SELECT * FROM DATAWAREHOUSE_CTS.DBT_CICD.V_LATEST_PREPROD_SUCCESS;

-- Check specific SHA
CALL DATAWAREHOUSE_CTS.DBT_CICD.SP_IS_SHA_PROMOTABLE('abc123...');
```

---

## Part 6 — Troubleshooting

| Problem | Fix |
|---------|-----|
| PR to `main` blocked, no `preprod-cd` | Merge to `stage` first; wait for CD workflow |
| `preprod-cd` failed on `stage` | Fix models; push fix to `stage`; new SHA needs new green CD |
| CD runs but Snowflake audit empty | Run DBT_CICD DDL; verify `CTS_OPS` grants; check CD logs for `snow sql` errors |
| Merge to `main` allowed without PREPROD | Enable branch protection required check **`preprod-cd`** |
| Build runs when checkbox unchecked | Fixed — only applies to manual CD dispatch; **stage push always builds** |

---

## Part 7 — Optional hardening

1. **Rulesets** (GitHub Enterprise): enforce `stage`-only → `main` at org level  
2. **Environment reviewers** on `prod` GitHub Environment  
3. **Revoke promotion** after bad deploy: `CALL SP_REVOKE_PROMOTION('sha', 'reason')`  
4. **Upload manifest to stage** after successful build (extend CD upload step)

---

See also: [README.md](../../README.md) for full platform architecture.
