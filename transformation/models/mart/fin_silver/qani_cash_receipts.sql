{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Import CTEs for tables actually used in the model
stg_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
),

stg_product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_remittance AS (
    SELECT * FROM {{ ref('stg_irmsods__remittance') }}
),

stg_deposit AS (
    SELECT * FROM {{ ref('stg_irmsods__deposit') }}
),

stg_trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
),

stg_run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_process AS (
    SELECT * FROM {{ ref('stg_irmsods__process') }}
),

stg_sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_lgl_ent_r AS (
    SELECT * FROM {{ ref('stg_irmsods__lgl_ent_r') }}
),

stg_bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

cash_transactions_qlc AS (
  SELECT
    t.trns_id,
    t.xref_trns_id,
    t.run_id,
    t.bill_to_bus_ent_id AS be_id,
    t.bk_to_bus_ent_id AS ae_id,
    t.acctg_period_id AS acctg_period,
    t.glbl_mpng_cd,
    t.src_syst_cd,
    t.trns_amnt,
    t.acctg_dt,
    r.rcvbl_id,
    r.lin_of_bus_cd AS lob,
    d.ns_gl_acct_cd AS gl_accnt,
    d.ns_class_cd,
    m.revnu_typ_cd AS revenue_typ,
    8 AS le
  FROM stg_transaction t
  JOIN stg_receivable r ON t.rcvbl_id = r.rcvbl_id
  JOIN stg_product d ON d.irms_prodt_id = t.irms_prodt_id
  JOIN stg_lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
  WHERE
    --t.acctg_period_id BETWEEN start_period AND end_period
    r.lin_of_bus_cd IN ('PPOQLC', 'CLNQLC', 'HLTQLC')
    AND m.revnu_typ_cd = 'PAYMNT'
),

cash_transactions_qlx AS (
  SELECT
    t.trns_id,
    t.xref_trns_id,
    t.run_id,
    t.bill_to_bus_ent_id AS be_id,
    t.bk_to_bus_ent_id AS ae_id,
    t.acctg_period_id AS acctg_period,
    t.glbl_mpng_cd,
    t.src_syst_cd,
    t.trns_amnt,
    t.acctg_dt,
    r.rcvbl_id,
    r.lin_of_bus_cd AS lob,
    d.ns_gl_acct_cd AS gl_accnt,
    d.ns_class_cd,
    m.revnu_typ_cd AS revenue_typ,
    9 AS le
  FROM stg_transaction t
  JOIN stg_receivable r ON t.rcvbl_id = r.rcvbl_id
  JOIN stg_product d ON d.irms_prodt_id = t.irms_prodt_id
  JOIN stg_lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
  WHERE
    --t.acctg_period_id BETWEEN start_period AND end_period
    r.lin_of_bus_cd IN ('PPOQLX', 'TPAQLX')
    AND m.revnu_typ_cd = 'PAYMNT'
),

remittance_details_qlc AS (
  SELECT
    t.*,
    r.check_num,
    r.check_dt,
    r.dpst_id,
    d.dpst_dt
  FROM cash_transactions_qlc t
  LEFT JOIN stg_remittance r ON r.trns_id = t.trns_id
  LEFT JOIN stg_deposit d ON d.dpst_id = r.dpst_id
),

remittance_details_qlx AS (
  SELECT
    t.*,
    r.check_num,
    r.check_dt,
    r.dpst_id,
    d.dpst_dt
  FROM cash_transactions_qlx t
  LEFT JOIN stg_remittance r ON r.trns_id = t.trns_id
  LEFT JOIN stg_deposit d ON d.dpst_id = r.dpst_id
),

comment_details_qlc AS (
  SELECT
    t.*,
    LTRIM(RTRIM(a.applctn_comnt_desc)) AS inv_comment
  FROM remittance_details_qlc t
  LEFT JOIN stg_trns_comnt tc
    ON tc.trns_id = t.trns_id AND tc.intrnl_extrnl_flg = 'I'
  LEFT JOIN stg_applctn_comnt a
    ON a.applctn_comnt_id = tc.applctn_comnt_id
),

comment_details_qlx AS (
  SELECT
    t.*,
    LTRIM(RTRIM(a.applctn_comnt_desc)) AS inv_comment
  FROM remittance_details_qlx t
  LEFT JOIN stg_trns_comnt tc
    ON tc.trns_id = t.trns_id AND tc.intrnl_extrnl_flg = 'I'
  LEFT JOIN stg_applctn_comnt a
    ON a.applctn_comnt_id = tc.applctn_comnt_id
),

process_details_qlc AS (
  SELECT
    t.*,
    p.prcs_desc,
    s.sec_usr_nm AS irms_user
  FROM comment_details_qlc t
  LEFT JOIN stg_run_log r ON r.run_id = t.run_id
  LEFT JOIN stg_process p ON p.prcs_id = r.prcs_id
  LEFT JOIN stg_sec_usr s ON s.sec_usr_id = r.sec_usr_id
),

process_details_qlx AS (
  SELECT
    t.*,
    p.prcs_desc,
    s.sec_usr_nm AS irms_user
  FROM comment_details_qlx t
  LEFT JOIN stg_run_log r ON r.run_id = t.run_id
  LEFT JOIN stg_process p ON p.prcs_id = r.prcs_id
  LEFT JOIN stg_sec_usr s ON s.sec_usr_id = r.sec_usr_id
),

qlx_results AS (
  SELECT
    l.lgl_ent_desc AS legal_entity,
    t.be_id,
    be.bus_ent_nm AS be_name,
    t.ae_id,
    ae.bus_ent_nm AS ae_name,
    t.src_syst_cd,
    t.lob,
    t.revenue_typ,
    t.glbl_mpng_cd AS irms_rcvbl_num,
    t.acctg_period,
    t.acctg_dt AS accntng_dt,
    t.inv_comment,
    SUM(t.trns_amnt) AS applied_amnt,
    t.check_num,
    t.check_dt AS check_dt,
    t.dpst_id,
    t.dpst_dt AS dpst_dt,
    t.trns_id,
    t.prcs_desc,
    t.irms_user
  FROM process_details_qlx t
  LEFT JOIN stg_lgl_ent_r l ON t.le = l.lgl_ent_cd
  LEFT JOIN stg_bus_ent be ON t.be_id = be.bus_ent_id
  LEFT JOIN stg_bus_ent ae ON t.ae_id = ae.bus_ent_id
  GROUP BY
    l.lgl_ent_desc,
    t.be_id,
    be.bus_ent_nm,
    t.ae_id,
    ae.bus_ent_nm,
    t.src_syst_cd,
    t.lob,
    t.revenue_typ,
    t.glbl_mpng_cd,
    t.acctg_period,
    t.acctg_dt,
    t.inv_comment,
    t.check_num,
    t.check_dt,
    t.dpst_id,
    t.dpst_dt,
    t.trns_id,
    t.prcs_desc,
    t.irms_user
),

qlc_results AS (
  SELECT
    l.lgl_ent_desc AS legal_entity,
    t.be_id,
    be.bus_ent_nm AS be_name,
    t.ae_id,
    ae.bus_ent_nm AS ae_name,
    t.src_syst_cd,
    t.lob,
    t.revenue_typ,
    t.glbl_mpng_cd AS irms_rcvbl_num,
    t.acctg_period,
    t.acctg_dt AS accntng_dt,
    t.inv_comment,
    SUM(t.trns_amnt) AS applied_amnt,
    t.check_num,
    t.check_dt AS check_dt,
    t.dpst_id,
    t.dpst_dt AS dpst_dt,
    t.trns_id,
    t.prcs_desc,
    t.irms_user
  FROM process_details_qlc t
  LEFT JOIN stg_lgl_ent_r l ON t.le = l.lgl_ent_cd
  LEFT JOIN stg_bus_ent be ON t.be_id = be.bus_ent_id
  LEFT JOIN stg_bus_ent ae ON t.ae_id = ae.bus_ent_id
  GROUP BY
    l.lgl_ent_desc,
    t.be_id,
    be.bus_ent_nm,
    t.ae_id,
    ae.bus_ent_nm,
    t.src_syst_cd,
    t.lob,
    t.revenue_typ,
    t.glbl_mpng_cd,
    t.acctg_period,
    t.acctg_dt,
    t.inv_comment,
    t.check_num,
    t.check_dt,
    t.dpst_id,
    t.dpst_dt,
    t.trns_id,
    t.prcs_desc,
    t.irms_user
)

SELECT * FROM qlx_results
UNION ALL
SELECT * FROM qlc_results
ORDER BY irms_rcvbl_num
