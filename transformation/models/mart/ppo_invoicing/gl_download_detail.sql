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
mrt_ppo_invoicing__qani_gl_transactions as (
    select * from {{ ref('qani_gl_transactions') }}
),
mrt_ppo_invoicing__gnx_gl_transactions as (
    select * from {{ ref('gnx_gl_transactions') }}
),

-- Logical
combined_set AS (
    SELECT
        'COVENTRY' AS business_unit,
        be_name,
        ae,
        legal_entity,
        rcvbl_num,
        vt,
        acctg_dt,
        rsn,
        ns_class_desc,
        gl_acct,
        src,
        bc,
        ns_class_cd,
        ns_dept,
        be,
        le,
        revnu,
        amnt,
        ae_name,
        lob,
        acctg_period_id AS acctg_period
    FROM
        mrt_ppo_invoicing__coventry_gl_transactions
    UNION ALL
    SELECT
        'QANI' AS business_unit,
        be_name,
        ae,
        legal_entity,
        rcvbl_num,
        vt,
        acctg_dt,
        rsn,
        ns_class_desc,
        gl_acct,
        src,
        bc,
        ns_class_cd,
        ns_dept,
        be,
        le,
        revnu,
        amnt,
        ae_name,
        lob,
        acctg_period
    FROM
        mrt_ppo_invoicing__qani_gl_transactions
    UNION ALL
    SELECT
        'GENEX' AS business_unit,
        be_name,
        ae,
        legal_entity,
        rcvbl_num,
        vt,
        acctg_dt,
        rsn,
        ns_class_desc,
        gl_acct,
        src,
        bc,
        ns_class_cd,
        ns_dept,
        be,
        le,
        revnu,
        amnt,
        ae_name,
        lob,
        acctg_period
    FROM
        mrt_ppo_invoicing__gnx_gl_transactions
),

-- Final
final AS (
    SELECT
        business_unit,
        be_name,
        ae,
        legal_entity,
        rcvbl_num,
        vt,
        acctg_dt,
        rsn,
        ns_class_desc,
        gl_acct,
        src,
        bc,
        ns_class_cd,
        ns_dept,
        be,
        le,
        revnu,
        amnt,
        ae_name,
        lob,
        acctg_period
    FROM
        combined_set
)

select * from final