{{
  config(
    materialized='table'
  )
}}

WITH
-- Import
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

stg_irmsods__clm_stgng_que as (
    select * from {{ ref('stg_irmsods__clm_stgng_que') }}
),

stg_irmsods__clnc_clm_stgng_que as (
    select * from {{ ref('stg_irmsods__clnc_clm_stgng_que') }}
),

stg_irmsods__lgl_ent_r as (
    select * from {{ ref('stg_irmsods__lgl_ent_r') }}
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

stg_irmsods__bus_ent as (
    select * from {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__process as (
    select * from {{ ref('stg_irmsods__process') }}
),

stg_irmsods__run_log as (
    select * from {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__deposit as (
    select * from {{ ref('stg_irmsods__deposit') }}
),


stg_irmsods__remittance as (
    select * from {{ ref('stg_irmsods__remittance') }}
),

stg_irmsods__sec_usr as (
    select * from {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__trns_comnt as (
    select * from {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__applctn_comnt as (
    select * from {{ ref('stg_irmsods__applctn_comnt') }}
),

stg_irmsods__irms_trns_adjmt as (
    select * from {{ ref('stg_irmsods__irms_trns_adjmt') }}
),

stg_irmsods__adjmt_rsn_r as (
    select * from {{ ref('stg_irmsods__adjmt_rsn_r') }}
),

stg_irmsods__usr_prcs_rqst as (
    select * from {{ ref('stg_irmsods__usr_prcs_rqst') }}
),

stg_irmsods__patient as (
    select * from {{ ref('stg_irmsods__patient') }}
),

stg_irmsods__irms_claim as (
    select * from {{ ref('stg_irmsods__irms_claim') }}
),
stg_cvtdwmcpsrptng__mcps_bill_hdr_fact as (
    select * from {{ ref('stg_cvtdwmcpsrptng__mcps_bill_hdr_fact') }}
),
-- COVENTRY_DW.MCPSRPTNG.MCPS_BILL_HDR_FACT MCPS
-- Logical
-- base transactions
base_model as (
    SELECT CAST(0 AS NUMBER) as le,
        t.glbl_mpng_cd as rcvbl_num,
        t.trns_amnt as amnt,
        t.bill_to_bus_ent_id as be,
        t.bk_to_bus_ent_id as ae,
        t.acctg_dt,
        t.src_syst_cd as src,
        m.lin_of_bus_cd as lob,
        m.revnu_typ_cd as revnu,
        d.rsn_typ_cd as rsn,
        x.val_typ_cd as vt,
        x.bllng_calctn_basis_cd as bc,
        '-----' as prodt,
        d.ns_gl_acct_cd as gl_acct,
        d.ns_class_cd,
        t.glbl_mpng_cd as curr_clm_key,
        CAST(-1 AS NUMBER) as seq,
        '-' as rec_typ,
        t.rcvbl_id,
        t.trns_id,
        t.xref_trns_id,
        t.trns_typ_cd,
        t.ppa_flg,
        t.irms_prodt_id,
        t.acctg_period_id,
        t.run_id,
        t.mnth_of_svc
    FROM stg_irmsods__irms_transaction t
    INNER JOIN stg_irmsods__product d ON t.irms_prodt_id = d.irms_prodt_id
    INNER JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    INNER JOIN stg_irmsods__val_typ_bllng_calctn_mpng x ON d.val_typ_bllng_calctn_id = x.val_typ_bllng_calctn_id
    WHERE m.lin_of_bus_cd IN ('PPOGRP','WRKCMP','CLNCAL')

),

seq AS (
    SELECT t1.trns_id, a1.src_clm_seq_num
    FROM base_model t1
    LEFT JOIN stg_irmsods__clm_amnt a1 ON a1.trns_id = nvl(t1.xref_trns_id,t1.trns_id)
    WHERE t1.src != 'OAC'
    and t1.src != 'MANR'
    and t1.trns_typ_cd = 'C'
),

base_model_w_seq AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        CASE WHEN s.trns_id IS NOT NULL THEN s.src_clm_seq_num
             ELSE b.seq
        END AS seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
FROM base_model b
LEFT JOIN seq s ON b.TRNS_ID = s.TRNS_ID
),

rec_type_strata AS (
    SELECT t1.trns_id, q1.rec_typ
    from base_model_w_seq t1
    LEFT JOIN stg_irmsods__clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src != 'OAC'
    and t1.src = 'STRATA'
    and t1.trns_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

rec_type_cognos AS (
    SELECT t1.trns_id, q1.record_type AS rec_typ
    FROM base_model_w_seq t1
    LEFT JOIN stg_irmsods__clnc_clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src = 'COGNOS'
    and t1.trns_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

rec_type_union_all AS (
    SELECT * FROM rec_type_strata
    UNION ALL
    SELECT * FROM rec_type_cognos
),

base_model_w_rec_type AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.rec_typ ELSE b.rec_typ END AS rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_seq b
    LEFT JOIN rec_type_union_all r ON b.TRNS_ID = r.TRNS_ID
),

base_model_w_curr_clm_key_rec_type_seq AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        NULL AS curr_clm_key,
        CASE
            WHEN b.src NOT IN ('MCPS','STRATA','COGNOS','NT24') THEN NULL
            WHEN b.seq = -1 AND b.revnu = 'PAYMNT' THEN NULL
            ELSE b.seq
        END AS seq,
        CASE
            WHEN b.src = 'NT24' AND b.trns_typ_cd = 'C' THEN 'I'
            WHEN b.src NOT IN ('MCPS','STRATA','COGNOS','NT24') THEN NULL
            WHEN b.src != 'OAC' AND b.trns_typ_cd != 'C' THEN NULL
            WHEN b.seq = -1 AND b.revnu = 'PAYMNT' THEN NULL
            ELSE b.rec_typ
        END AS rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_rec_type b
),

prodt_mcps AS (
    SELECT x1.trns_id, q1.src_prodt_cd
    FROM base_model_w_curr_clm_key_rec_type_seq x1
    LEFT JOIN stg_irmsods__clm_stgng_que q1
    ON q1.src_clm_key = x1.rcvbl_num
    and q1.src_clm_seq_num = x1.seq
    and q1.csq_status_cd = 'C'
    WHERE x1.src = 'MCPS'
    and x1.seq is not null
    and x1.trns_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY x1.trns_id ORDER BY q1.run_id DESC) = 1
),

prodt_strata AS (
    SELECT x1.trns_id, q1.src_prodt_cd
    from base_model_w_curr_clm_key_rec_type_seq x1
    LEFT JOIN stg_irmsods__clm_stgng_que q1
    ON q1.src_clm_key = x1.rcvbl_num
    and q1.src_clm_seq_num = x1.seq
    and q1.csq_status_cd = 'C'
    WHERE x1.src = 'STRATA'
    and x1.seq is not null
    and x1.trns_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY x1.trns_id ORDER BY q1.run_id DESC) = 1
),

prodt_cognos AS (
    SELECT x1.trns_id, q1.src_prodt_cd
    FROM base_model_w_curr_clm_key_rec_type_seq x1
    LEFT JOIN stg_irmsods__clnc_clm_stgng_que q1
    ON q1.src_clm_key = x1.rcvbl_num
    and q1.src_clm_seq_num = x1.seq
    and q1.csq_status_cd = 'C'
    WHERE x1.src = 'COGNOS'
    and x1.seq is not null
    and x1.trns_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY x1.trns_id ORDER BY q1.run_id DESC) = 1
),

prodt_union_all AS (
    SELECT * FROM prodt_mcps
    UNION ALL
    SELECT * FROM prodt_strata
    UNION ALL
    SELECT * FROM prodt_cognos
),

base_model_w_prodt AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        CASE WHEN p.TRNS_ID IS NOT NULL THEN p.src_prodt_cd ELSE b.prodt END AS prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_curr_clm_key_rec_type_seq b
    LEFT JOIN prodt_union_all p ON b.TRNS_ID = p.TRNS_ID
),

base_model_w_le_prodt_ns_class_cd AS (
    SELECT CASE WHEN COALESCE(b.le, 0) = 0 THEN 1 ELSE b.le END AS le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        CASE
            WHEN b.src NOT IN ('MCPS','STRATA','COGNOS','NT24') OR b.revnu = 'PAYMNT' THEN NULL
            WHEN b.src = 'NT24' AND b.seq IS NOT NULL AND b.trns_typ_cd = 'C' THEN 'NT'
            WHEN b.prodt = '-----' THEN NULL
            ELSE b.prodt
        END AS prodt,
        b.gl_acct,
        CASE WHEN b.ns_class_cd IN ('XXX','NA') THEN NULL ELSE b.ns_class_cd END AS ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_prodt b
),

-- Add fields to support downstream reports
ns_dept_desc_lookup AS (
    SELECT dm.ns_gl_acct_cd, dr.ns_dept_desc
    FROM stg_irmsods__ns_dept_mpng dm
    INNER JOIN stg_irmsods__ns_dept_r dr ON dm.ns_dept_cd = dr.ns_dept_cd
),

process_run_log AS (
    SELECT l.run_id, c.prcs_desc
    FROM stg_irmsods__run_log l
    INNER JOIN stg_irmsods__process c ON l.prcs_id = c.prcs_id
),

sec_usr_run_log AS (
    SELECT l.run_id, s.sec_usr_nm
    FROM stg_irmsods__run_log l
    INNER JOIN stg_irmsods__sec_usr s ON l.sec_usr_id = s.sec_usr_id
),

patient_name AS (
    SELECT t.rcvbl_id, TRIM(COALESCE(n.first_nm,'') || ' ' || COALESCE(n.last_nm,'')) AS patnt_nm
    FROM stg_irmsods__irms_transaction t
    INNER JOIN stg_irmsods__clm_amnt a ON t.trns_id = a.trns_id
    INNER JOIN stg_irmsods__irms_claim c ON a.clm_id = c.clm_id
    INNER JOIN stg_irmsods__patient n ON c.patient_id = n.patient_id
    WHERE t.trns_typ_cd = 'C'
    AND t.glbl_mpng_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.rcvbl_id ORDER BY n.patient_id DESC) = 1
),

remittance_deposit AS (
    SELECT i.trns_id, p.dpst_dt, r.strt_dt AS dpst_fnlzd_dt, i.check_num, i.check_dt, i.dpst_id
    FROM stg_irmsods__deposit p
    INNER JOIN stg_irmsods__remittance i ON i.dpst_id = p.dpst_id
    LEFT JOIN stg_irmsods__run_log r ON p.run_id = r.run_id AND p.dpst_finlzd_flg = 'Y'
),

trns_applctn_comnt AS (
    SELECT c.trns_id, trim(regexp_replace(replace(replace(a.applctn_comnt_desc,chr(13)),chr(10),'; '),'[[:space:]]+',' ')) AS pymt_comnt
    FROM stg_irmsods__trns_comnt c
    INNER JOIN stg_irmsods__applctn_comnt a ON a.applctn_comnt_id = c.applctn_comnt_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY c.trns_id ORDER BY a.applctn_comnt_id DESC) = 1
),

trns_adjmt_rsn AS (
    SELECT a.trns_id, a.adjmt_rsn_cd || ': ' || r.adjmt_rsn_desc as adjmt_rsn
    FROM stg_irmsods__irms_trns_adjmt a
    INNER JOIN stg_irmsods__adjmt_rsn_r r ON a.adjmt_rsn_cd = r.adjmt_rsn_cd
    WHERE r.adjmt_src_syst = 'IRMS'
),

last_run AS (
    SELECT l.run_id, u.run_id AS finalized_run_id
    FROM stg_irmsods__usr_prcs_rqst u
    INNER JOIN stg_irmsods__run_log l ON l.run_id = u.rqst_val_num
    WHERE l.prcs_id = 620
    AND u.run_id > l.run_id
    AND u.rqst_typ_cd = 'FNLZ'
    AND u.cmpltd_dt IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY l.run_id ORDER BY u.run_id DESC) = 1
),

-- Let's add our pricing hub key (plus some pricing hub data in clm_stgng_que)
pricing_hub_key_plus AS (
SELECT
          MAX(MCPS_BILL_ID) as MCPS_BILL_ID
          ,REPLACE(MCPS.EXTRNL_CLNT_BILL_ID,'-','') as EXTRNL_CLNT_BILL_ID
FROM  stg_cvtdwmcpsrptng__mcps_bill_hdr_fact MCPS
GROUP BY REPLACE(MCPS.EXTRNL_CLNT_BILL_ID,'-','')
),

pricing_hub_key AS (
SELECT t.trns_id
         ,COALESCE(CSQ.CARE_TYP_CD,'UNKNOWN') AS CARE_TYP_CD
         ,COALESCE(CSQ.BILL_JUR_STATE_CD,'UNKNOWN') AS BILL_JUR_STATE_CD
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN 'SA' ELSE t.src END as BILL_SRC_CD
         ,CASE WHEN t.src = 'MCPS' THEN SUBSTR(CSQ.SRC_CLM_KEY,1,16)||LPAD(NVL(CA.src_clm_seq_num,'0'),2,'0')
          WHEN  t.src = 'STRATA' THEN CSQ.MCPS_CLM_NUM||LPAD(NVL(CSQ.MCPS_CLM_SEQ_NUM,'0'),2,'0') ELSE NULL END as MCPS_BILL_ID
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NOT NULL THEN CSQ.SRC_CLM_KEY ELSE NULL END as STRATA_BILL_REVW_CNTRL_NUM
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 1) ELSE NULL END as SA_SITE_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 2) ELSE NULL END as SA_CLIENT_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 3) ELSE NULL END as SA_BILL_SEQ
FROM  base_model_w_le_prodt_ns_class_cd t
    inner join stg_irmsods__clm_amnt ca  on ca.trns_id = t.trns_id
    inner join (SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY src_clm_seq_num DESC) AS rn
           FROM stg_irmsods__irms_claim) c on c.clm_id = ca.clm_id
                                                      and c.rn = 1
    inner join stg_irmsods__clm_stgng_que csq on csq.src_clm_key = c.src_clm_key
                                                         and csq.src_clm_seq_num = c.src_clm_seq_num
                                                         and CSQ.CSQ_STATUS_CD = 'C'
WHERE t.trns_typ_cd = 'C'
and t.src in ('MCPS','STRATA')
union
SELECT t.trns_id
         ,COALESCE(CSQ.CARE_TYP_CD,'UNKNOWN') AS CARE_TYP_CD
         ,COALESCE(CSQ.BILL_JUR_STATE_CD,'UNKNOWN') AS BILL_JUR_STATE_CD
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN 'SA' ELSE t.src END as BILL_SRC_CD
         ,CASE WHEN t.src = 'MCPS' THEN SUBSTR(CSQ.SRC_CLM_KEY,1,16)||LPAD(NVL(CA.src_clm_seq_num,'0'),2,'0')
          WHEN  t.src = 'STRATA' THEN CSQ.MCPS_CLM_NUM||LPAD(NVL(CSQ.MCPS_CLM_SEQ_NUM,'0'),2,'0') ELSE NULL END as MCPS_BILL_ID
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NOT NULL THEN CSQ.SRC_CLM_KEY ELSE NULL END as STRATA_BILL_REVW_CNTRL_NUM
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 1) ELSE NULL END as SA_SITE_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 2) ELSE NULL END as SA_CLIENT_CODE
         ,CASE WHEN t.src = 'STRATA' and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 3) ELSE NULL END as SA_BILL_SEQ
FROM  base_model_w_le_prodt_ns_class_cd t
    inner join stg_irmsods__clm_amnt ca  on ca.trns_id = t.xref_trns_id
    inner join (SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY src_clm_seq_num DESC) AS rn
           FROM stg_irmsods__irms_claim) c on c.clm_id = ca.clm_id
                                                      and c.rn = 1
    inner join stg_irmsods__clm_stgng_que csq on csq.src_clm_key = c.src_clm_key
                                                         and csq.src_clm_seq_num = c.src_clm_seq_num
                                                         and CSQ.CSQ_STATUS_CD = 'C'
WHERE t.trns_typ_cd = 'C'
and t.src in ('MCPS','STRATA')
union
SELECT t.trns_id
         ,COALESCE(CSQ.CARE_TYP_CD,'UNKNOWN') AS CARE_TYP_CD
         ,COALESCE(CSQ.BILL_JUR_STATE_CD,'UNKNOWN') AS BILL_JUR_STATE_CD
         ,CASE WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NULL AND TRY_TO_NUMBER(t.rcvbl_num) IS NULL THEN 'SA'
               WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NOT NULL AND TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN 'SA'
               ELSE t.src END as BILL_SRC_CD
         ,CASE WHEN t.src = 'MCPS' and CSQ.SRC_CLM_KEY IS NULL THEN SUBSTR(t.rcvbl_num,1,16)||'00'
               WHEN t.src = 'MCPS' and CSQ.SRC_CLM_KEY IS NOT NULL THEN SUBSTR(CSQ.SRC_CLM_KEY,1,16)||LPAD(NVL(CA.src_clm_seq_num,'0'),2,'0')
               WHEN  t.src = 'STRATA' THEN CSQ.MCPS_CLM_NUM||LPAD(NVL(CSQ.MCPS_CLM_SEQ_NUM,'0'),2,'0')
               ELSE NULL END as MCPS_BILL_ID
         ,CASE WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NULL and TRY_TO_NUMBER(t.rcvbl_num) IS NOT NULL THEN t.rcvbl_num
               WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NOT NULL and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NOT NULL THEN CSQ.SRC_CLM_KEY
               ELSE NULL END as STRATA_BILL_REVW_CNTRL_NUM
         ,CASE WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NULL and TRY_TO_NUMBER(t.rcvbl_num) IS NULL THEN SPLIT_PART(t.rcvbl_num, '-', 1)
               WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NOT NULL and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 1)
               ELSE NULL END as SA_SITE_CODE
         ,CASE WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NULL and TRY_TO_NUMBER(t.rcvbl_num) IS NULL THEN SPLIT_PART(t.rcvbl_num, '-', 2)
               WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NOT NULL and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 2)
               ELSE NULL END as SA_SITE_CODE
         ,CASE WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NULL and TRY_TO_NUMBER(t.rcvbl_num) IS NULL THEN SPLIT_PART(t.rcvbl_num, '-', 3)
               WHEN t.src = 'STRATA' and CSQ.SRC_CLM_KEY IS NOT NULL and TRY_TO_NUMBER(CSQ.SRC_CLM_KEY) IS NULL THEN SPLIT_PART(CSQ.SRC_CLM_KEY, '-', 3)
               ELSE NULL END as SA_SITE_CODE
FROM  base_model_w_le_prodt_ns_class_cd t
    left outer join stg_irmsods__clm_amnt ca  on ca.trns_id = t.xref_trns_id
    left outer  join (SELECT *, ROW_NUMBER() OVER (PARTITION BY clm_id ORDER BY src_clm_seq_num DESC) AS rn
           FROM stg_irmsods__irms_claim) c on c.clm_id = ca.clm_id
                                                      and c.rn = 1
    left outer  join stg_irmsods__clm_stgng_que csq on csq.src_clm_key = c.src_clm_key
                                                         and csq.src_clm_seq_num = c.src_clm_seq_num
                                                         and CSQ.CSQ_STATUS_CD = 'C'
WHERE t.trns_typ_cd in ('A','S')
and t.src in ('MCPS','STRATA')
),

base_model_w_fields_added_for_various_downstream_reports AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,  -- Same as the acctg_period_id in transaction table? Also, why is this TO_CHAR in original? Let's find out.
        b.run_id,
        l.lgl_ent_desc as legal_entity,
        d.ns_dept_desc as ns_dept,
        cr.ns_class_desc,
        be.bus_ent_nm AS be_name,
        ae.bus_ent_nm AS ae_name,
        p.prcs_desc,
        rd.dpst_dt,
        rd.dpst_fnlzd_dt,
        CASE WHEN TRIM(pn.patnt_nm) = '' THEN NULL ELSE  pn.patnt_nm END AS  patnt_nm,
        b.mnth_of_svc AS mos,
        regexp_replace(rd.check_num,'[[:space:]]*$','') as check_num,
        rd.check_dt,
        rd.dpst_id,
        s.sec_usr_nm,
        CASE WHEN TRIM(ac.pymt_comnt) = '' THEN NULL ELSE ac.pymt_comnt END AS pymt_comnt,
        ar.adjmt_rsn,
        lr.finalized_run_id,
        ph.care_typ_cd,
        ph.bill_jur_state_cd,
        ph.bill_src_cd,
        COALESCE(ph.mcps_bill_id,php.mcps_bill_id) as mcps_bill_id,
        ph.strata_bill_revw_cntrl_num,
        ph.sa_site_code,
        ph.sa_client_code,
        ph.sa_bill_seq
    FROM base_model_w_le_prodt_ns_class_cd b
    LEFT JOIN stg_irmsods__lgl_ent_r l ON b.le = l.lgl_ent_cd
    LEFT JOIN ns_dept_desc_lookup d ON b.gl_acct = d.ns_gl_acct_cd
    LEFT JOIN stg_irmsods__ns_class_r cr ON b.ns_class_cd = cr.ns_class_cd
    LEFT JOIN stg_irmsods__bus_ent be ON b.be = be.bus_ent_id
    LEFT JOIN stg_irmsods__bus_ent ae ON b.ae = ae.bus_ent_id
    LEFT JOIN process_run_log p ON b.run_id = p.run_id
    LEFT JOIN sec_usr_run_log s ON b.run_id = s.run_id
    LEFT JOIN remittance_deposit rd ON b.trns_id = rd.trns_id
    LEFT JOIN trns_applctn_comnt ac ON b.trns_id = ac.trns_id
    LEFT JOIN patient_name pn ON b.rcvbl_id = pn.rcvbl_id
    LEFT JOIN trns_adjmt_rsn ar ON b.trns_id = ar.trns_id
    LEFT JOIN last_run lr ON b.run_id = lr.run_id
    LEFT JOIN pricing_hub_key ph ON b.trns_id = ph.trns_id
    LEFT JOIN pricing_hub_key_plus php ON ph.SA_SITE_CODE||ph.SA_CLIENT_CODE||ph.SA_BILL_SEQ = php.EXTRNL_CLNT_BILL_ID
),


final AS (
    SELECT
        b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.legal_entity,
        b.ns_dept,
        b.ns_class_desc,
        b.be_name,
        b.ae_name,
        b.prcs_desc,
        b.dpst_dt,
        b.dpst_fnlzd_dt,
        b.patnt_nm,
        b.mos,
        b.check_num,
        b.check_dt,
        b.dpst_id,
        b.sec_usr_nm,
        b.pymt_comnt,
        b.adjmt_rsn,
        b.finalized_run_id,
        b.care_typ_cd,
        b.bill_jur_state_cd,
        b.bill_src_cd,
        b.mcps_bill_id,
        b.strata_bill_revw_cntrl_num,
        b.sa_site_code,
        b.sa_client_code,
        b.sa_bill_seq
    FROM base_model_w_fields_added_for_various_downstream_reports b
)

-- Final
SELECT * FROM final