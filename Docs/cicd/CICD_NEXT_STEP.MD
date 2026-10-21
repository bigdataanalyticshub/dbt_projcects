# dbt CI/CD on Snowflake — Current State vs Future State

**Audience:** Engineering leadership, platform team, data engineering  
**Project:** Snowflake DBT PROJECT deployment for the `transformation` dbt repo  
**Date:** September 2026

---

## The problem we are solving

We are moving dbt deployments onto **Snowflake DBT PROJECT** objects with GitHub Actions. Early runs exposed three risks:

1. **Long model runtimes (6+ hours)** conflict with GitHub Actions job limits and EC2 runner availability.
2. **No enforced promotion path** — code could reach production without a validated PREPROD run.
3. **Limited auditability** — no central record of what was deployed, by whom, or whether it succeeded.

---

## At a glance

| Dimension | **Current state (today)** | **Future state (target)** |
|-----------|---------------------------|---------------------------|
| **Branch model** | Moving to **`feature/* → stage → main`**; code merged in repo | Fully enforced via branch protection + promotion registry |
| **PREPROD deploy** | Auto on **`stage`** push: deploy + dbt build on EC2 | Deploy from GitHub (~15 min); **execute in Snowflake** (no timeout) |
| **PROD deploy** | Manual workflow; SHA gate started | Automated only for **PREPROD-validated SHAs** + approver gate |
| **Build execution** | `dbt build` on **EC2 self-hosted runner** | **`snow dbt execute`** / Snowflake Tasks (elastic warehouse) |
| **State deployments** | GitHub Artifact manifest; first run builds all models | **Snowflake Stage** manifest per env; `state:modified+` slim runs |
| **Audit & compliance** | Workflow logs only | **`DBT_CICD`** schema: deployments, model runs, promotion registry |
| **Merge to main** | Promote-gate workflow (needs GitHub config) | Blocked unless **`preprod-cd`** status = success on that SHA |

---

## Current state — what exists now

```
feature/*  ──PR──►  stage  ──auto──►  CI (dev) + PREPROD CD (deploy + build on EC2)
                      │
                      └──PR──►  main   (promote gate checks preprod-cd — when branch rules enabled)
```

**Delivered in repo:**

- GitHub workflows: CI, CD (PREPROD on `stage`), manual mart build, promote gate, PROD gate (partial)
- Snowflake DDL for **`{DATABASE}.DBT_CICD`** — audit tables, manifest stage, promotion procedures
- Fixes: `run_build` checkbox, `CTS_OPS` role, runner label issues

**Still requires one-time setup:** run Snowflake DDL, create `stage` branch, configure GitHub branch protection.

**Known limitation:** First PREPROD CD without a manifest baseline may run **all models** on EC2 and hit timeout on very long jobs.

---

## Future state — where we are heading

```
feature/* → stage → [PREPROD deploy + Snowflake execute] → validated SHA
                              ↓
                    PROMOTION_REGISTRY (Snowflake)
                              ↓
              main (PR gate) → [PROD deploy + Snowflake execute] → prod
```

**Target capabilities:**

1. **GitHub = control plane** — deploy, trigger, audit, approve (jobs finish in minutes).
2. **Snowflake = execution plane** — long-running builds use warehouse scale, not EC2.
3. **Manifest on Snowflake Stage** — reliable `state:modified+` per environment.
4. **SHA-based promotion** — PROD only runs code that passed PREPROD; full audit trail in `DBT_CICD`.
5. **Phased bootstrap** — mart-by-mart first deploy instead of full project run.

---

## Business value

| Benefit | Impact |
|---------|--------|
| **Safer releases** | No PROD deploy without PREPROD validation |
| **Operational resilience** | No GitHub 6-hour timeout blocking deployments |
| **Cost & scale** | Right-size Snowflake warehouses; reduce EC2 dependency |
| **Audit readiness** | Deployment and model-level history in Snowflake |
| **Developer velocity** | Automated PREPROD on `stage`; clear promotion path |

---

## Implementation phases

| Phase | Focus | Status |
|-------|--------|--------|
| **1 — Foundation** | Workflows, `stage` branch model, DBT_CICD DDL, promote gate | **Code complete** |
| **2 — Enablement** | Snowflake DDL deploy, branch protection, bootstrap PREPROD | **In progress (ops)** |
| **3 — Scale** | Snowflake-native execute, Stage manifests, full PROD CD | **Planned** |
| **4 — Operate** | Dashboards, alerts, model-run audit ingestion | **Planned** |

---

## Ask / decisions needed

1. **Approve `stage` as integration branch** and branch protection rules on `main`.
2. **Confirm database** for `DBT_CICD` schema (recommended: `DATAWAREHOUSE_CTS`).
3. **Prioritize Phase 3** — Snowflake-native execution to resolve long-running model timeouts.
4. **First-deploy strategy** — phased mart rollout vs full backfill (recommend phased).

---

**Detail docs:** [DBT_CICD_SETUP.md](DBT_CICD_SETUP.md) · [README.md](../../README.md)
