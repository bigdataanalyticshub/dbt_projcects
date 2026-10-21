{{
  config(
    materialized='table'
  )
}}


WITH

stg_irmsods__irms_transaction as (
    select * from {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__product as (
    select * from {{ ref('stg_irmsods__product') }}
),

stg_irmsods__lob_revnu_mpng as (
    select * from {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__val_typ_bllng_calctn_mpng as (
    select * from {{ ref('stg_irmsods__val_typ_bllng_calctn_mpng') }}
),

stg_irmsods__clm_amnt as (
    select * from {{ ref('stg_irmsods__clm_amnt') }}
),

stg_irmsods__remittance as (
    select * from {{ ref('stg_irmsods__remittance') }}
),

stg_irmsods__deposit as (
    select * from {{ ref('stg_irmsods__deposit') }}
),

stg_irmsods__bank_acct_lock_box_addr as (
    select * from {{ ref('stg_irmsods__bank_acct_lock_box_addr') }}
),

stg_irmsods__lgl_ent_mpng as (
    select * from {{ ref('stg_irmsods__lgl_ent_mpng') }}
),

stg_irmsods__lgl_ent_r as (
    select * from {{ ref('stg_irmsods__lgl_ent_r') }}
),

stg_irmsods__bus_ent as (
    select * from {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__ns_dept_mpng as (
    select * from {{ ref('stg_irmsods__ns_dept_mpng') }}
),

stg_irmsods__ns_dept_r as (
    select * from {{ ref('stg_irmsods__ns_dept_r') }}
),

stg_irmsods__ns_class_r as (
    select * from {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__irms_claim as (
    select * from {{ ref('stg_irmsods__irms_claim') }}
),

stg_irmsods__clm_stgng_que as (
    select * from {{ ref('stg_irmsods__clm_stgng_que') }}
),
stg_cvtdwmcpsrptng__mcps_bill_hdr_fact as (
    select * from {{ ref('stg_cvtdwmcpsrptng__mcps_bill_hdr_fact') }}
),
-- Base transaction data for the specified accounting period
base_transactions AS (
  SELECT
    0 AS le,
    t.glbl_mpng_cd AS rcvbl_num,
    t.trns_amnt AS amnt,
    t.bill_to_bus_ent_id AS be,
    t.bk_to_bus_ent_id AS ae,
    t.acctg_dt,
    t.acctg_period_id,
    t.src_syst_cd AS src,
    m.lin_of_bus_cd AS lob,
    m.revnu_typ_cd AS revnu,
    d.rsn_typ_cd AS rsn,
    x.val_typ_cd AS vt,
    x.bllng_calctn_basis_cd AS bc,
    d.ns_gl_acct_cd AS gl_acct,
    d.ns_class_cd,
    -1 AS seq,
    t.rcvbl_id,
    t.trns_id,
    t.xref_trns_id,
    t.trns_typ_cd,
    t.ppa_flg,
    t.irms_prodt_id
  FROM
    stg_irmsods__irms_transaction t
    JOIN stg_irmsods__product d ON t.irms_prodt_id = d.irms_prodt_id
    JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    JOIN stg_irmsods__val_typ_bllng_calctn_mpng x ON d.val_typ_bllng_calctn_id = x.val_typ_bllng_calctn_id
  WHERE m.lin_of_bus_cd LIKE '%QL%'

),

-- Prepare claim amount data
clm_amnt_data AS (
  SELECT
    trns_id,
    src_clm_seq_num
  FROM stg_irmsods__clm_amnt
),

-- Update sequence numbers for MCPS credit transactions
seq_update AS (
  SELECT
    bt.*,
    CASE
      WHEN bt.src = 'MCPS' AND bt.trns_typ_cd = 'C' THEN ca.src_clm_seq_num
      WHEN bt.src != 'MCPS' THEN NULL
      WHEN bt.seq = -1 AND bt.revnu = 'PAYMNT' THEN NULL
      ELSE bt.seq
    END AS updated_seq
  FROM
    base_transactions bt
    LEFT JOIN clm_amnt_data ca ON COALESCE(bt.xref_trns_id, bt.trns_id) = ca.trns_id
),

-- Bank account based remittance lookup
bank_account_lookup AS (
  SELECT DISTINCT
    t.rcvbl_num,
    a.bank_acct_num
  FROM
    base_transactions t
    JOIN stg_irmsods__remittance r ON t.trns_id = r.trns_id
    JOIN stg_irmsods__deposit p ON r.dpst_id = p.dpst_id
    JOIN stg_irmsods__bank_acct_lock_box_addr a ON p.bank_id = a.bank_id AND p.bank_acct_num = a.bank_acct_num
),

-- Legal entity mapping for bank accounts (OAC)
le_bank_mapping AS (
  SELECT DISTINCT
    bal.rcvbl_num,
    m.lgl_ent_cd
  FROM
    bank_account_lookup bal
    JOIN stg_irmsods__lgl_ent_mpng m ON bal.bank_acct_num = m.bank_acct_num
  WHERE m.src_syst_cd = 'OAC'
),

-- Legal entity mapping for business entities (OAC)
le_be_mapping AS (
  SELECT DISTINCT
    r.oac_bus_ent_id AS be_id,
    r.lgl_ent_cd
  FROM stg_irmsods__lgl_ent_r r
),

-- Legal entity mapping for specific OAC entities by LOB
le_oac_specific_mapping AS (
  SELECT DISTINCT
    m.lin_of_bus_cd AS lob,
    m.lgl_ent_cd
  FROM stg_irmsods__lgl_ent_mpng m
  WHERE m.src_syst_cd = 'OAC'
  AND m.lgl_ent_cd IN (8, 9)
),

-- Legal entity mapping for LOB (general)
le_lob_mapping AS (
  SELECT DISTINCT
    m.lin_of_bus_cd AS lob,
    m.lgl_ent_cd
  FROM stg_irmsods__lgl_ent_mpng m
),

-- Apply all legal entity determination rules
le_determination AS (
  SELECT
    su.*,
    NULL AS base_le,  -- Start with NULL LE as in original SQL
    CASE
      WHEN su.src = 'OAC' THEN lbm.lgl_ent_cd  -- Bank account based (OAC)
      ELSE NULL
    END AS bank_le,
    CASE
      WHEN su.src = 'OAC' THEN lbem.lgl_ent_cd  -- Business entity based (OAC)
      ELSE NULL
    END AS be_le,
    CASE
      WHEN su.src = 'OAC' THEN losm.lgl_ent_cd  -- Line of business based (OAC specific)
      ELSE NULL
    END AS oac_specific_le,
    CASE
      WHEN su.src IN ('MANR', 'EST') THEN llm.lgl_ent_cd  -- Line of business based (MANR, EST)
      ELSE NULL
    END AS manr_est_le,
    CASE
      WHEN su.src = 'MCPS' THEN llm.lgl_ent_cd  -- Line of business based (MCPS)
      ELSE NULL
    END AS mcps_le
  FROM
    seq_update su
    LEFT JOIN le_bank_mapping lbm ON su.rcvbl_num = lbm.rcvbl_num AND su.src = 'OAC'
    LEFT JOIN le_be_mapping lbem ON su.be = lbem.be_id AND su.src = 'OAC'
    LEFT JOIN le_oac_specific_mapping losm ON su.lob = losm.lob AND su.src = 'OAC'
    LEFT JOIN le_lob_mapping llm ON su.lob = llm.lob
),

-- Combine all legal entity determinations with proper precedence
final_le_determination AS (
  SELECT
    ld.*,
    CASE
      WHEN ld.src = 'OAC' AND COALESCE(ld.base_le, 0) = 0 AND ld.bank_le IS NOT NULL THEN ld.bank_le
      WHEN ld.src = 'OAC' AND COALESCE(ld.base_le, 0) = 0 AND ld.be_le IS NOT NULL THEN ld.be_le
      WHEN ld.src = 'OAC' AND COALESCE(ld.base_le, 0) = 0 AND ld.oac_specific_le IS NOT NULL THEN ld.oac_specific_le
      WHEN ld.src IN ('MANR', 'EST') AND COALESCE(ld.base_le, 0) = 0 AND ld.manr_est_le IS NOT NULL THEN ld.manr_est_le
      WHEN ld.src = 'MCPS' AND COALESCE(ld.base_le, 0) = 0 AND ld.mcps_le IS NOT NULL THEN ld.mcps_le
      ELSE ld.base_le
    END AS final_le
  FROM le_determination ld
),

-- Final base table result
final_base_table AS (
  SELECT
    COALESCE(fd.final_le, 0) AS le,
    fd.rcvbl_num,
    fd.amnt,
    fd.be,
    fd.ae,
    fd.acctg_dt,
    fd.acctg_period_id,  -- Include accounting period ID
    fd.src,
    fd.lob,
    fd.revnu,
    fd.rsn,
    fd.vt,
    fd.bc,
    fd.gl_acct,
    fd.ns_class_cd,
    fd.updated_seq AS seq,
    fd.rcvbl_id,
    fd.trns_id,
    fd.xref_trns_id,
    fd.trns_typ_cd,
    fd.ppa_flg,
    fd.irms_prodt_id
  FROM final_le_determination fd
),

-- Department information
dept_info AS (
  SELECT
    dm.ns_gl_acct_cd,
    dr.ns_dept_desc
  FROM
    stg_irmsods__ns_dept_mpng dm
    JOIN stg_irmsods__ns_dept_r dr ON dm.ns_dept_cd = dr.ns_dept_cd
),

-- Class information
class_info AS (
  SELECT
    cr.ns_class_cd,
    cr.ns_class_desc
  FROM stg_irmsods__ns_class_r cr
),
pricing_hub_key_plus AS (
SELECT
          MAX(MCPS_BILL_ID) as MCPS_BILL_ID
          ,REPLACE(MCPS.EXTRNL_CLNT_BILL_ID,'-','') as EXTRNL_CLNT_BILL_ID
FROM  stg_cvtdwmcpsrptng__mcps_bill_hdr_fact MCPS
GROUP BY REPLACE(MCPS.EXTRNL_CLNT_BILL_ID,'-','')
),
-- Let's add our pricing hub key (plus some pricing hub data in clm_stgng_que)
pricing_hub_key AS (SELECT t.trns_id
         ,COALESCE(CSQ.CARE_TYP_CD,'UNKNOWN') AS CARE_TYP_CD
         ,COALESCE(CSQ.BILL_JUR_STATE_CD,'UNKNOWN') AS BILL_JUR_STATE_CD
         ,CASE WHEN t.src = 'MCPS' THEN SUBSTR(CSQ.SRC_CLM_KEY,1,16)||LPAD(NVL(CA.src_clm_seq_num,'0'),2,'0') ELSE NULL END as MCPS_BILL_ID
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 1) ELSE NULL END as SA_SITE_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 2) ELSE NULL END as SA_CLIENT_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 3) ELSE NULL END as SA_BILL_SEQ
FROM  final_base_table t
    inner join stg_irmsods__clm_amnt ca  on ca.trns_id = t.trns_id
    inner join (SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY src_clm_seq_num DESC) AS rn
           FROM stg_irmsods__irms_claim) c on c.clm_id = ca.clm_id
                                                      and c.rn = 1
    inner join stg_irmsods__clm_stgng_que csq on csq.src_clm_key = c.src_clm_key
                                                         and csq.src_clm_seq_num = c.src_clm_seq_num
                                                         and CSQ.CSQ_STATUS_CD = 'C'
WHERE t.trns_typ_cd = 'C'
and t.src in ('MCPS')
union
SELECT t.trns_id
         ,COALESCE(CSQ.CARE_TYP_CD,'UNKNOWN') AS CARE_TYP_CD
         ,COALESCE(CSQ.BILL_JUR_STATE_CD,'UNKNOWN') AS BILL_JUR_STATE_CD
         ,CASE WHEN t.src = 'MCPS' THEN SUBSTR(CSQ.SRC_CLM_KEY,1,16)||LPAD(NVL(CA.src_clm_seq_num,'0'),2,'0') ELSE NULL END as MCPS_BILL_ID
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 1) ELSE NULL END as SA_SITE_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 2) ELSE NULL END as SA_CLIENT_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 3) ELSE NULL END as SA_BILL_SEQ
FROM  final_base_table t
    inner join stg_irmsods__clm_amnt ca  on ca.trns_id = t.xref_trns_id
    inner join (SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY src_clm_seq_num DESC) AS rn
           FROM stg_irmsods__irms_claim) c on c.clm_id = ca.clm_id
                                                      and c.rn = 1
    inner join stg_irmsods__clm_stgng_que csq on csq.src_clm_key = c.src_clm_key
                                                         and csq.src_clm_seq_num = c.src_clm_seq_num
                                                         and CSQ.CSQ_STATUS_CD = 'C'
WHERE t.trns_typ_cd = 'C'
and t.src in ('MCPS')
union
SELECT t.trns_id
         ,COALESCE(CSQ.CARE_TYP_CD,'UNKNOWN') AS CARE_TYP_CD
         ,COALESCE(CSQ.BILL_JUR_STATE_CD,'UNKNOWN') AS BILL_JUR_STATE_CD
         ,CASE WHEN t.src = 'MCPS' and CSQ.SRC_CLM_KEY IS NULL THEN SUBSTR(t.rcvbl_num,1,16)||'00'
               WHEN t.src = 'MCPS' and CSQ.SRC_CLM_KEY IS NOT NULL THEN SUBSTR(CSQ.SRC_CLM_KEY,1,16)||LPAD(NVL(CA.src_clm_seq_num,'0'),2,'0')
               ELSE NULL END as MCPS_BILL_ID
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 1) ELSE NULL END as SA_SITE_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 2) ELSE NULL END as SA_CLIENT_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 3) ELSE NULL END as SA_BILL_SEQ

FROM  final_base_table t
    left outer join stg_irmsods__clm_amnt ca  on ca.trns_id = t.xref_trns_id
    left outer  join (SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY src_clm_seq_num DESC) AS rn
           FROM stg_irmsods__irms_claim) c on c.clm_id = ca.clm_id
                                                      and c.rn = 1
    left outer  join stg_irmsods__clm_stgng_que csq on csq.src_clm_key = c.src_clm_key
                                                         and csq.src_clm_seq_num = c.src_clm_seq_num
                                                         and CSQ.CSQ_STATUS_CD = 'C'
WHERE t.trns_typ_cd in ('A','S')
and t.src in ('MCPS')
)

-- Final output with additional fields
SELECT
  l.lgl_ent_desc AS legal_entity,
  z.le,
  z.rcvbl_num,
  z.amnt,
  z.be,
  b_be.bus_ent_nm AS be_name,
  z.ae,
  b_ae.bus_ent_nm AS ae_name,
  z.acctg_dt,
  z.acctg_period_id AS  acctg_period,  -- Added accounting period ID to final output
  z.src,
  z.lob,
  z.revnu,
  z.rsn,
  z.vt,
  z.bc,
  z.gl_acct,
  di.ns_dept_desc AS ns_dept,
  z.ns_class_cd,
  ci.ns_class_desc,
  z.seq,
  z.rcvbl_id,
  z.trns_id,
  z.xref_trns_id,
  z.trns_typ_cd,
  z.ppa_flg,
  z.irms_prodt_id,
  ph.care_typ_cd,
  ph.bill_jur_state_cd,
  COALESCE(ph.mcps_bill_id,php.mcps_bill_id) as mcps_bill_id
FROM
  final_base_table z
  JOIN stg_irmsods__bus_ent b_be ON z.be = b_be.bus_ent_id
  JOIN stg_irmsods__bus_ent b_ae ON z.ae = b_ae.bus_ent_id
  JOIN stg_irmsods__lgl_ent_r l ON z.le = l.lgl_ent_cd
  LEFT JOIN dept_info di ON z.gl_acct = di.ns_gl_acct_cd
  LEFT JOIN class_info ci ON z.ns_class_cd = ci.ns_class_cd
  LEFT JOIN pricing_hub_key ph ON z.trns_id = ph.trns_id AND z.src = 'MCPS' AND z.gl_acct = '4230'
  LEFT JOIN pricing_hub_key_plus php ON ph.SA_SITE_CODE||ph.SA_CLIENT_CODE||ph.SA_BILL_SEQ = php.EXTRNL_CLNT_BILL_ID