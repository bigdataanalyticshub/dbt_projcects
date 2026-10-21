{{
  config(
    materialized='view'
  )
}}

WITH
-- Import
mrt_ppo_invoicing__coventry_gl_transactions as (
    select * from {{ ref('coventry_gl_transactions') }}
),

-- Logical
apply_criteria AS (
      SELECT
        t.legal_entity,
        t.le,
        t.rcvbl_num,
        t.amnt,
        t.be,
        t.ae,
        t.acctg_dt,
        t.src,
        t.lob,
        t.revnu,
        t.rsn,
        t.vt,
        t.bc,
        t.prodt,
        t.gl_acct,
        t.ns_dept,
        t.ns_class_cd,
        t.ns_class_desc,
        t.acctg_period_id,
        t.be_name,
        t.ae_name,
        t.prcs_desc
    FROM mrt_ppo_invoicing__coventry_gl_transactions t
    WHERE t.amnt != 0
),

-- Final
final AS (
    SELECT
      t.legal_entity,
      t.le,
      t.rcvbl_num,
      t.amnt,
      t.be,
      t.ae,
      t.acctg_dt,
      t.src,
      t.lob,
      t.revnu,
      t.rsn,
      t.vt,
      t.bc,
      t.prodt,
      t.gl_acct,
      t.ns_dept,
      t.ns_class_cd,
      t.ns_class_desc,
      t.acctg_period_id,
      t.be_name,
      t.ae_name,
      t.prcs_desc
    FROM apply_criteria t
)
SELECT * FROM final