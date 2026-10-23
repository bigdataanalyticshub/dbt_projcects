{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

-- Import CTEs
WITH stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__clm_amnt AS (
    SELECT * FROM {{ ref('stg_irmsods__clm_amnt') }}
),

stg_irmsods__irms_claim AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_claim') }}
),

stg_irmsods__patient AS (
    SELECT * FROM {{ ref('stg_irmsods__patient') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__process AS (
    SELECT * FROM {{ ref('stg_irmsods__process') }}
),

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__irms_trns_adjmt AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_trns_adjmt') }}
),

stg_irmsods__adjmt_rsn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__adjmt_rsn_r') }}
),

stg_irmsods__usr_prcs_rqst AS (
    SELECT * FROM {{ ref('stg_irmsods__usr_prcs_rqst') }}
),

stg_irmsods__trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
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

-- Base transactions filtered for the accounting period
gl_cvt_trns AS (
    SELECT
        1 AS le,
        t.bill_to_bus_ent_id AS be,
        t.bk_to_bus_ent_id AS ae,
        t.glbl_mpng_cd AS rcvbl_num,
        t.trns_amnt AS amnt,
        t.acctg_dt,
        t.src_syst_cd AS src,
        m.lin_of_bus_cd AS lob,
        m.revnu_typ_cd AS revnu,
        d.rsn_typ_cd AS rsn,
        d.ns_gl_acct_cd AS gl_acct,
        t.rcvbl_id,
        t.trns_id,
        t.xref_trns_id,
        t.trns_typ_cd,
        t.run_id,
        t.mnth_of_svc,
        t.irms_prodt_id
    FROM
        stg_irmsods__irms_transaction t
        JOIN stg_irmsods__product d ON t.irms_prodt_id = d.irms_prodt_id
        JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
        JOIN stg_irmsods__val_typ_bllng_calctn_mpng x ON d.val_typ_bllng_calctn_id = x.val_typ_bllng_calctn_id
    WHERE m.lin_of_bus_cd IN ('PPOGRP', 'WRKCMP', 'CLNCAL')
),

-- Filtered for adjustments only
adjustment_details AS (
    SELECT
        z.be,
        z.ae,
        z.src,
        z.rcvbl_num,
        z.amnt AS adjmt_amnt,
        z.lob,
        z.revnu,
        z.rsn,
        TO_CHAR(z.acctg_dt, 'YYYYMM') AS acctg_period_id,
        z.acctg_dt,
        z.mnth_of_svc AS mos,
        z.gl_acct,
        z.rcvbl_id,
        z.trns_id,
        z.run_id
    FROM
        gl_cvt_trns z
    WHERE
        z.le = 1
        AND z.amnt != 0
        AND (z.trns_typ_cd = 'A' OR (z.trns_typ_cd != 'R' AND z.rsn != 'ORIG'))
),

-- Patient names lookup
patient_names AS (
    SELECT
        t.rcvbl_id,
        TRIM(n.first_nm || ' ' || n.last_nm) AS patnt_nm
    FROM
        stg_irmsods__irms_transaction t
        JOIN stg_irmsods__clm_amnt a ON t.trns_id = a.trns_id
        JOIN stg_irmsods__irms_claim c ON a.clm_id = c.clm_id
        JOIN stg_irmsods__patient n ON c.patient_id = n.patient_id
    WHERE
        t.trns_typ_cd = 'C'
        AND t.glbl_mpng_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.rcvbl_id ORDER BY t.trns_id) = 1
),

-- Adjustment reasons
adjustment_reasons AS (
    SELECT
        a.trns_id,
        a.adjmt_rsn_cd || ': ' || r.adjmt_rsn_desc AS adjmt_rsn
    FROM
        stg_irmsods__irms_trns_adjmt a
        JOIN stg_irmsods__adjmt_rsn_r r ON a.adjmt_rsn_cd = r.adjmt_rsn_cd
    WHERE r.adjmt_src_syst = 'IRMS'
),

-- Finalized runs
finalized_runs AS (
    SELECT
        l.run_id,
        u.run_id AS finalized_run_id
    FROM
        stg_irmsods__run_log l
        JOIN stg_irmsods__usr_prcs_rqst u ON l.run_id = u.rqst_val_num
    WHERE
        l.prcs_id = 620
        AND u.run_id > l.run_id
        AND u.rqst_typ_cd = 'FNLZ'
        AND u.cmpltd_dt IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY l.run_id ORDER BY u.run_id) = 1
),

-- Adjustment comments
adjustment_comments AS (
    SELECT
        c.trns_id,
        TRIM(REGEXP_REPLACE(REPLACE(REPLACE(a.applctn_comnt_desc, CHR(13)), CHR(10), '; '), '[[:space:]]+', ' ')) AS adjmt_comnt
    FROM
        stg_irmsods__trns_comnt c
        JOIN stg_irmsods__applctn_comnt a ON a.applctn_comnt_id = c.applctn_comnt_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY c.trns_id ORDER BY a.applctn_comnt_id) = 1
),

-- Run log information
run_log_info AS (
    SELECT
        l.run_id,
        s.sec_usr_nm,
        p.prcs_desc
    FROM
        stg_irmsods__run_log l
        JOIN stg_irmsods__sec_usr s ON l.sec_usr_id = s.sec_usr_id
        JOIN stg_irmsods__process p ON l.prcs_id = p.prcs_id
)

-- Final output with all information joined together
SELECT
    ad.be,
    be_data.bus_ent_nm AS be_name,
    ad.ae,
    ae_data.bus_ent_nm AS ae_name,
    ad.src,
    ad.rcvbl_num,
    pn.patnt_nm,
    ad.adjmt_amnt,
    ad.lob,
    ad.revnu,
    ad.rsn,
    ad.acctg_period_id,
    ad.acctg_dt,
    ad.mos,
    ar.adjmt_rsn,
    ad.gl_acct,
    rl.sec_usr_nm,
    fr.finalized_run_id,
    rl.prcs_desc,
    ac.adjmt_comnt
FROM
    adjustment_details ad
    LEFT JOIN stg_irmsods__bus_ent be_data ON ad.be = be_data.bus_ent_id
    LEFT JOIN stg_irmsods__bus_ent ae_data ON ad.ae = ae_data.bus_ent_id
    LEFT JOIN patient_names pn ON ad.rcvbl_id = pn.rcvbl_id
    LEFT JOIN adjustment_reasons ar ON ad.trns_id = ar.trns_id
    LEFT JOIN run_log_info rl ON ad.run_id = rl.run_id
    LEFT JOIN finalized_runs fr ON ad.run_id = fr.run_id
    LEFT JOIN adjustment_comments ac ON ad.trns_id = ac.trns_id
