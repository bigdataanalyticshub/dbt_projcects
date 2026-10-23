{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Base tables as CTEs
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__irms_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
    WHERE LIN_OF_BUS_CD = 'DMESLF'
),

stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_irmsods__lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__val_typ_bllng_calctn_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__val_typ_bllng_calctn_mpng') }}
),

stg_irmsods__dme_clm_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__dme_clm_stgng_que') }}
),

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__glbl_rcvbl_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__glbl_rcvbl_mpng') }}
),

-- Base transactions data
base_transactions AS (
  SELECT
    2 AS le,
    t.glbl_mpng_cd AS rcvbl_num,
    t.trns_amnt AS amnt,
    t.bill_to_bus_ent_id AS be,
    t.bk_to_bus_ent_id AS ae,
    t.acctg_dt,
    t.src_syst_cd AS src,
    t.acctg_period_id,
    m.lin_of_bus_cd AS lob,
    m.revnu_typ_cd AS revnu,
    d.rsn_typ_cd AS rsn,
    x.val_typ_cd AS vt,
    x.bllng_calctn_basis_cd AS bc,
    d.ns_gl_acct_cd AS gl_acct,
    d.ns_class_cd,
    d.cost_cntr AS cc,
    t.mnth_of_svc AS mos,
    CASE WHEN t.src_syst_cd IN ('OAC', 'MANR') THEN NULL ELSE t.glbl_mpng_cd END AS bill_id,
    t.glbl_mpng_cd AS svc_item_id,
    t.rcvbl_id,
    t.trns_id,
    t.xref_trns_id,
    t.trns_typ_cd,
    t.ppa_flg,
    t.irms_prodt_id,
    t.run_id,
    NULL AS med_cd,
    NULL AS svc_typ,
    NULL AS paid_qty,
    NULL AS clm_num,
    NULL AS patnt_first_nm,
    NULL AS patnt_last_nm,
    NULL AS jur_st,
    NULL AS patnt_zip
  FROM
    stg_irmsods__irms_transaction t
    JOIN stg_irmsods__product d ON t.irms_prodt_id = d.irms_prodt_id
    JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    JOIN stg_irmsods__val_typ_bllng_calctn_mpng x ON d.val_typ_bllng_calctn_id = x.val_typ_bllng_calctn_id
  WHERE
    m.lin_of_bus_cd = 'DMESLF'
),

-- Global mapping for MANR transactions
global_mapping AS (
  SELECT
    t.rcvbl_num,
    t.rcvbl_id,
    t.trns_typ_cd,
    t.src,
    t.acctg_dt,
    replace(replace(x.glbl_mpng_cd, chr(13)), chr(10)) AS glbl_mpng_cd
  FROM
    base_transactions t
    JOIN stg_irmsods__glbl_rcvbl_mpng m ON m.glbl_mpng_cd = t.rcvbl_num
    JOIN stg_irmsods__glbl_rcvbl_mpng x ON m.rcvbl_id = x.rcvbl_id
  WHERE
    trim(x.extrnl_inv_src_cd) = 'UKN'
    AND trim(x.glbl_mpng_typ_cd) = 'H'
),

-- Direct global mapping for MANR transactions
direct_mapping AS (
  SELECT
    t.rcvbl_id,
    t.trns_typ_cd,
    t.src,
    t.acctg_dt,
    replace(replace(m.glbl_mpng_cd, chr(13)), chr(10)) AS glbl_mpng_cd
  FROM
    base_transactions t
    JOIN stg_irmsods__glbl_rcvbl_mpng m ON m.rcvbl_id = t.rcvbl_id
  WHERE
    trim(m.extrnl_inv_src_cd) = 'UKN'
    AND trim(m.glbl_mpng_typ_cd) = 'H'
),

-- Enhanced transactions with claim data
enhanced_transactions AS (
  -- MANR M transactions
  SELECT
    t.*,
    d.bill_id AS dme_bill_id,
    d.svc_item_id AS dme_svc_item_id,
    d.svc_item_cd AS dme_med_cd,
    d.dme_type AS dme_svc_typ,
    d.clm_num AS dme_clm_num,
    d.patnt_first_nm AS dme_patnt_first_nm,
    d.patnt_last_nm AS dme_patnt_last_nm,
    d.jursdctn_state_cd AS dme_jur_st,
    d.patnt_zip AS dme_patnt_zip,
    d.paid_qty AS dme_paid_qty,
    d.emplyr_nm,
    d.create_date,
    d.svc_from_dt,
    d.svc_to_dt,
    1 AS priority
  FROM
    base_transactions t
    JOIN global_mapping g ON g.rcvbl_num = t.rcvbl_num
    JOIN stg_irmsods__dme_clm_stgng_que d ON g.glbl_mpng_cd = d.src_clm_key
  WHERE
    t.trns_typ_cd = 'M'
    AND t.src = 'MANR'

  UNION ALL

  -- Non-M MANR transactions with M transactions
  SELECT
    t.*,
    d.bill_id AS dme_bill_id,
    d.svc_item_id AS dme_svc_item_id,
    d.svc_item_cd AS dme_med_cd,
    d.dme_type AS dme_svc_typ,
    d.clm_num AS dme_clm_num,
    d.patnt_first_nm AS dme_patnt_first_nm,
    d.patnt_last_nm AS dme_patnt_last_nm,
    d.jursdctn_state_cd AS dme_jur_st,
    d.patnt_zip AS dme_patnt_zip,
    d.paid_qty AS dme_paid_qty,
    d.emplyr_nm,
    d.create_date,
    d.svc_from_dt,
    d.svc_to_dt,
    2 AS priority
  FROM
    base_transactions t
    JOIN direct_mapping g ON g.rcvbl_id = t.rcvbl_id
    JOIN stg_irmsods__dme_clm_stgng_que d ON g.glbl_mpng_cd = d.src_clm_key
  WHERE
    t.trns_typ_cd != 'M'
    AND t.src = 'MANR'
    AND EXISTS (
      SELECT 1
      FROM stg_irmsods__irms_transaction x
      WHERE x.rcvbl_id = t.rcvbl_id
      AND x.trns_typ_cd = 'M'
    )

  UNION ALL

  -- Non-M SLSF transactions with M transactions
  SELECT
    t.*,
    d.bill_id AS dme_bill_id,
    d.svc_item_id AS dme_svc_item_id,
    d.svc_item_cd AS dme_med_cd,
    d.dme_type AS dme_svc_typ,
    d.clm_num AS dme_clm_num,
    d.patnt_first_nm AS dme_patnt_first_nm,
    d.patnt_last_nm AS dme_patnt_last_nm,
    d.jursdctn_state_cd AS dme_jur_st,
    d.patnt_zip AS dme_patnt_zip,
    d.paid_qty AS dme_paid_qty,
    d.emplyr_nm,
    d.create_date,
    d.svc_from_dt,
    d.svc_to_dt,
    3 AS priority
  FROM
    base_transactions t
    JOIN direct_mapping g ON g.rcvbl_id = t.rcvbl_id
    JOIN stg_irmsods__dme_clm_stgng_que d ON g.glbl_mpng_cd = d.src_clm_key
  WHERE
    t.trns_typ_cd != 'M'
    AND t.src = 'SLSF'
    AND EXISTS (
      SELECT 1
      FROM stg_irmsods__irms_transaction x
      WHERE x.rcvbl_id = t.rcvbl_id
      AND x.trns_typ_cd = 'M'
    )

  UNION ALL

  -- SLSF C transactions
  SELECT
    t.*,
    d.bill_id AS dme_bill_id,
    d.svc_item_id AS dme_svc_item_id,
    d.svc_item_cd AS dme_med_cd,
    d.dme_type AS dme_svc_typ,
    d.clm_num AS dme_clm_num,
    d.patnt_first_nm AS dme_patnt_first_nm,
    d.patnt_last_nm AS dme_patnt_last_nm,
    d.jursdctn_state_cd AS dme_jur_st,
    d.patnt_zip AS dme_patnt_zip,
    d.paid_qty AS dme_paid_qty,
    d.emplyr_nm,
    d.create_date,
    d.svc_from_dt,
    d.svc_to_dt,
    4 AS priority
  FROM
    base_transactions t
    JOIN stg_irmsods__dme_clm_stgng_que d ON t.rcvbl_num = d.src_clm_key
  WHERE
    t.trns_typ_cd = 'C'
    AND t.src = 'SLSF'

  UNION ALL

  -- Non-C SLSF transactions
  SELECT
    t.*,
    d.bill_id AS dme_bill_id,
    d.svc_item_id AS dme_svc_item_id,
    d.svc_item_cd AS dme_med_cd,
    d.dme_type AS dme_svc_typ,
    d.clm_num AS dme_clm_num,
    d.patnt_first_nm AS dme_patnt_first_nm,
    d.patnt_last_nm AS dme_patnt_last_nm,
    d.jursdctn_state_cd AS dme_jur_st,
    d.patnt_zip AS dme_patnt_zip,
    d.paid_qty AS dme_paid_qty,
    d.emplyr_nm,
    d.create_date,
    d.svc_from_dt,
    d.svc_to_dt,
    5 AS priority
  FROM
    base_transactions t
    JOIN stg_irmsods__dme_clm_stgng_que d ON t.rcvbl_num = d.src_clm_key
  WHERE
    t.trns_typ_cd != 'C'
    AND t.src = 'SLSF'

  UNION ALL

  -- All other transactions
  SELECT
    t.*,
    NULL AS dme_bill_id,
    NULL AS dme_svc_item_id,
    NULL AS dme_med_cd,
    NULL AS dme_svc_typ,
    NULL AS dme_clm_num,
    NULL AS dme_patnt_first_nm,
    NULL AS dme_patnt_last_nm,
    NULL AS dme_jur_st,
    NULL AS dme_patnt_zip,
    NULL AS dme_paid_qty,
    NULL AS emplyr_nm,
    NULL AS create_date,
    NULL AS svc_from_dt,
    NULL AS svc_to_dt,
    99 AS priority
  FROM
    base_transactions t
  WHERE
    NOT (
      (t.trns_typ_cd = 'M' AND t.src = 'MANR') OR
      (t.trns_typ_cd != 'M' AND t.src = 'MANR' AND EXISTS (
        SELECT 1 FROM stg_irmsods__irms_transaction x
        WHERE x.rcvbl_id = t.rcvbl_id AND x.trns_typ_cd = 'M'
      )) OR
      (t.trns_typ_cd != 'M' AND t.src = 'SLSF' AND EXISTS (
        SELECT 1 FROM stg_irmsods__irms_transaction x
        WHERE x.rcvbl_id = t.rcvbl_id AND x.trns_typ_cd = 'M'
      )) OR
      (t.trns_typ_cd = 'C' AND t.src = 'SLSF') OR
      (t.trns_typ_cd != 'C' AND t.src = 'SLSF')
    )
),

-- Get the highest priority record for each transaction
final_data AS (
  SELECT DISTINCT
    le,
    rcvbl_num,
    amnt,
    be,
    ae,
    acctg_dt,
    src,
    lob,
    revnu,
    rsn,
    vt,
    bc,
    gl_acct,
    ns_class_cd,
    cc,
    mos,
    COALESCE(dme_bill_id, bill_id) AS bill_id,
    acctg_period_id,
    COALESCE(dme_svc_item_id, svc_item_id) AS svc_item_id,
    rcvbl_id,
    trns_id,
    xref_trns_id,
    trns_typ_cd,
    ppa_flg,
    irms_prodt_id,
    run_id,
    COALESCE(dme_med_cd, med_cd) AS med_cd,
    COALESCE(dme_svc_typ, svc_typ) AS svc_typ,
    COALESCE(dme_paid_qty, paid_qty) AS paid_qty,
    COALESCE(dme_clm_num, clm_num) AS clm_num,
    COALESCE(dme_patnt_first_nm, patnt_first_nm) AS patnt_first_nm,
    COALESCE(dme_patnt_last_nm, patnt_last_nm) AS patnt_last_nm,
    COALESCE(dme_jur_st, jur_st) AS jur_st,
    COALESCE(dme_patnt_zip, patnt_zip) AS patnt_zip,
    emplyr_nm,
    create_date,
    svc_from_dt,
    svc_to_dt
  FROM (
    SELECT
      *,
      ROW_NUMBER() OVER (PARTITION BY trns_id ORDER BY priority) AS rn
    FROM
      enhanced_transactions
  ) ranked
  WHERE
    rn = 1
)

-- Final output for revenue/cost data
SELECT
  f.be,
  b.bus_ent_nm AS be_name,
  f.ae,
  a.bus_ent_nm AS ae_name,
  f.rcvbl_num,
  f.bill_id,
  f.acctg_period_id,
  f.svc_item_id,
  f.med_cd AS rx_code,
  f.svc_typ,
  f.clm_num,
  f.jur_st,
  f.emplyr_nm,
  f.create_date AS billed_dt,
  f.svc_from_dt AS dos_from,
  f.svc_to_dt AS dos_to,
  f.patnt_first_nm,
  f.patnt_last_nm,
  to_char(f.acctg_dt, 'YYYYMM') AS ap,
  f.acctg_dt,
  f.src,
  f.lob,
  f.revnu,
  f.gl_acct,
  f.amnt,
  f.rsn
FROM
  final_data f
  LEFT JOIN stg_irmsods__bus_ent b ON b.bus_ent_id = f.be
  LEFT JOIN stg_irmsods__bus_ent a ON a.bus_ent_id = f.ae
WHERE
  f.gl_acct IN ('4230', '5130')
  AND f.amnt != 0

