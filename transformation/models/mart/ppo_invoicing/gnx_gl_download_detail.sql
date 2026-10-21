{{
  config(
    materialized='view'
  )
}}

WITH
-- Import
mrt_ppo_invoicing__gnx_gl_transactions as (
    select * from {{ ref('gnx_gl_transactions') }}
),
-- Logical
apply_criteria AS (
    select
        t.legal_entity,
        t.le,
        t.rcvbl_num,
        t.amnt,
        t.be,
        t.be_name,
        t.ae,
        t.ae_name,
        t.acctg_dt,
        t.acctg_period,
        t.src,
        t.lob,
        t.revnu,
        t.rsn,
        t.vt,
        t.bc,
        t.gl_acct,
        t.ns_dept,
        t.ns_class_cd,
        t.ns_class_desc,
        t.c_code,
        t.cc,
        t.dpst_id,
        t.e_code,
        t.curr_clm_key,
        t.ns_lctn_desc,
        t.prodt,
        t.mos
    from mrt_ppo_invoicing__gnx_gl_transactions t
    where t.amnt != 0
),
-- Final
final as (
    select
        t.legal_entity,
        t.le,
        t.rcvbl_num,
        t.amnt,
        t.be,
        t.be_name,
        t.ae,
        t.ae_name,
        t.acctg_dt,
        t.acctg_period,
        t.src,
        t.lob,
        t.revnu,
        t.rsn,
        t.vt,
        t.bc,
        t.gl_acct,
        t.ns_dept,
        t.ns_class_cd,
        t.ns_class_desc,
        t.c_code,
        t.cc,
        t.dpst_id,
        t.e_code,
        t.curr_clm_key,
        t.ns_lctn_desc,
        t.prodt,
        t.mos
    from apply_criteria t
)
select * from final