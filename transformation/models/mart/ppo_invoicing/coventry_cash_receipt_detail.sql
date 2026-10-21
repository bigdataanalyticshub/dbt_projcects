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
        t.dpst_dt,
        t.dpst_fnlzd_dt,
        t.rcvbl_num,
        t.patnt_nm,
        t.mos,
        t.amnt as applied_amnt,
        t.check_num,
        t.check_dt,
        t.dpst_id,
        t.rsn,
        t.acctg_period_id,
        t.acctg_dt,
        t.src,
        t.lob,
        t.gl_acct,
        t.sec_usr_nm,
        t.pymt_comnt
    FROM mrt_ppo_invoicing__coventry_gl_transactions t
    WHERE t.le = 1
    AND t.amnt != 0
    AND t.revnu = 'PAYMNT'
),

-- Final
final AS (
    SELECT
        t.be,
        t.be_name,
        t.ae,
        t.ae_name,
        t.dpst_dt,
        t.dpst_fnlzd_dt,
        t.rcvbl_num,
        t.patnt_nm,
        t.mos,
        t.applied_amnt,
        t.check_num,
        t.check_dt,
        t.dpst_id,
        t.rsn,
        t.acctg_period_id,
        t.acctg_dt,
        t.src,
        t.lob,
        t.gl_acct,
        t.sec_usr_nm,
        t.pymt_comnt
    FROM apply_criteria t
)
SELECT * FROM final