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
        t.be,
        t.be_name,
        t.ae,
        t.ae_name,
        t.src,
        t.rcvbl_num,
        t.patnt_nm,
        t.amnt as adjmt_amnt,
        t.lob,
        t.revnu,
        t.rsn,
        t.acctg_period_id,
        t.acctg_dt,
        t.mos,
        t.adjmt_rsn,
        t.gl_acct,
        t.sec_usr_nm,
        t.finalized_run_id,
        t.prcs_desc,
        t.pymt_comnt AS adjmt_comnt
    FROM mrt_ppo_invoicing__coventry_gl_transactions t
    WHERE t.le = 1
    AND t.amnt != 0
    AND (t.trns_typ_cd = 'A' OR (t.trns_typ_cd != 'R' AND t.rsn != 'ORIG'))
),

-- Final
final AS (
    SELECT
        t.be,
        t.be_name,
        t.ae,
        t.ae_name,
        t.src,
        t.rcvbl_num,
        t.patnt_nm,
        t.adjmt_amnt,
        t.lob,
        t.revnu,
        t.rsn,
        t.acctg_period_id,
        t.acctg_dt,
        t.mos,
        t.adjmt_rsn,
        t.gl_acct,
        t.sec_usr_nm,
        t.finalized_run_id,
        t.prcs_desc,
        t.adjmt_comnt
    FROM apply_criteria t
)
SELECT * FROM final