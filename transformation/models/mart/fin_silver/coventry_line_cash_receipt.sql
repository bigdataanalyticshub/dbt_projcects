{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Source staging tables
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
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

stg_irmsods__clm_amnt AS (
    SELECT * FROM {{ ref('stg_irmsods__clm_amnt') }}
),

stg_irmsods__clm_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__clm_stgng_que') }}
),

stg_irmsods__clnc_clm_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__clnc_clm_stgng_que') }}
),

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__remittance AS (
    SELECT * FROM {{ ref('stg_irmsods__remittance') }}
),

stg_irmsods__deposit AS (
    SELECT * FROM {{ ref('stg_irmsods__deposit') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__irms_claim AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_claim') }}
),

stg_irmsods__patient AS (
    SELECT * FROM {{ source('irmsods','patient') }}
),

stg_irmsods__trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
),

-- Base transaction data with GL attributes
base_transactions AS (
    SELECT
        0 AS le,
        t.glbl_mpng_cd AS rcvbl_num,
        t.trns_amnt AS amnt,
        t.bill_to_bus_ent_id AS be,
        t.bk_to_bus_ent_id AS ae,
        t.acctg_dt,
        t.src_syst_cd AS src,
        m.lin_of_bus_cd AS lob,
        m.revnu_typ_cd AS revnu,
        p.rsn_typ_cd AS rsn,
        v.val_typ_cd AS vt,
        v.bllng_calctn_basis_cd AS bc,
        '-----' AS prodt,
        p.ns_gl_acct_cd AS gl_acct,
        p.ns_class_cd,
        t.glbl_mpng_cd AS curr_clm_key,
        -1 AS seq,
        '-' AS rec_typ,
        t.rcvbl_id,
        t.trns_id,
        t.xref_trns_id,
        t.trns_typ_cd,
        t.ppa_flg,
        t.irms_prodt_id,
        t.run_id,
        t.mnth_of_svc
    FROM
        stg_irmsods__irms_transaction t
        JOIN stg_irmsods__product p ON t.irms_prodt_id = p.irms_prodt_id
        JOIN stg_irmsods__lob_revnu_mpng m ON p.lob_revnu_id = m.lob_revnu_id
        JOIN stg_irmsods__val_typ_bllng_calctn_mpng v ON p.val_typ_bllng_calctn_id = v.val_typ_bllng_calctn_id
    WHERE
        m.lin_of_bus_cd IN ('PPOGRP', 'WRKCMP', 'CLNCAL')
),

-- Pre-join claim amounts for sequence updates
claim_amounts AS (
    SELECT
        a.trns_id,
        a.src_clm_seq_num,
        a.clm_id
    FROM
        stg_irmsods__clm_amnt a
),

-- Update sequence numbers from claim amounts
seq_updated AS (
    SELECT
        b.*,
        CASE
            WHEN b.src != 'OAC' AND b.src != 'MANR' AND b.trns_typ_cd = 'C' THEN
                COALESCE(ca.src_clm_seq_num, b.seq)
            ELSE b.seq
        END AS updated_seq,
        ca.clm_id
    FROM
        base_transactions b
        LEFT JOIN claim_amounts ca ON COALESCE(b.xref_trns_id, b.trns_id) = ca.trns_id
),

-- Pre-join claim staging data for record type updates
strata_staging AS (
    SELECT
        q.src_clm_key,
        q.src_clm_seq_num,
        q.rec_typ,
        q.src_prodt_cd
    FROM
        stg_irmsods__clm_stgng_que q
    WHERE
        q.csq_status_cd = 'C'
),

cognos_staging AS (
    SELECT
        q.src_clm_key,
        q.src_clm_seq_num,
        q.record_type,
        q.src_prodt_cd
    FROM
        stg_irmsods__clnc_clm_stgng_que q
    WHERE
        q.csq_status_cd = 'C'
),

-- Update record types and product codes
record_and_product_updates AS (
    SELECT
        s.*,
        -- Record type updates
        CASE
            WHEN s.src = 'STRATA' AND s.trns_typ_cd = 'C' THEN
                COALESCE(ss.rec_typ, s.rec_typ)
            WHEN s.src = 'COGNOS' AND s.trns_typ_cd = 'C' THEN
                COALESCE(cs.record_type, s.rec_typ)
            WHEN s.src = 'NT24' AND s.trns_typ_cd = 'C' THEN
                'I'
            ELSE s.rec_typ
        END AS updated_rec_typ,

        -- Product code updates
        CASE
            WHEN s.src = 'MCPS' AND s.trns_typ_cd = 'C' THEN
                COALESCE(ss.src_prodt_cd, s.prodt)
            WHEN s.src = 'STRATA' AND s.trns_typ_cd = 'C' THEN
                COALESCE(ss.src_prodt_cd, s.prodt)
            WHEN s.src = 'COGNOS' AND s.trns_typ_cd = 'C' THEN
                COALESCE(cs.src_prodt_cd, s.prodt)
            WHEN s.src = 'NT24' AND s.trns_typ_cd = 'C' THEN
                'NT'
            ELSE s.prodt
        END AS updated_prodt
    FROM
        seq_updated s
        LEFT JOIN strata_staging ss ON s.rcvbl_num = ss.src_clm_key AND s.updated_seq = ss.src_clm_seq_num
        LEFT JOIN cognos_staging cs ON s.rcvbl_num = cs.src_clm_key AND s.updated_seq = cs.src_clm_seq_num
),

-- Clean up record types and product codes
clean_data AS (
    SELECT
        r.*,
        CASE
            WHEN r.src NOT IN ('MCPS', 'STRATA', 'COGNOS', 'NT24') THEN NULL
            WHEN r.trns_typ_cd != 'C' THEN NULL
            WHEN r.updated_seq = -1 AND r.revnu = 'PAYMNT' THEN NULL
            ELSE r.updated_rec_typ
        END AS final_rec_typ,

        CASE
            WHEN r.src NOT IN ('MCPS', 'STRATA', 'COGNOS', 'NT24') THEN NULL
            WHEN r.trns_typ_cd != 'C' THEN NULL
            WHEN r.updated_seq = -1 AND r.revnu = 'PAYMNT' THEN NULL
            ELSE r.updated_seq
        END AS final_seq,

        CASE
            WHEN r.updated_prodt = '-----' THEN NULL
            WHEN r.src NOT IN ('MCPS', 'STRATA', 'COGNOS', 'NT24') THEN NULL
            WHEN r.revnu = 'PAYMNT' THEN NULL
            ELSE r.updated_prodt
        END AS final_prodt,

        CASE
            WHEN r.ns_class_cd IN ('XXX', 'NA') THEN NULL
            ELSE r.ns_class_cd
        END AS final_ns_class_cd
    FROM
        record_and_product_updates r
),

-- Set legal entity
final_gl_data AS (
    SELECT
        1 AS le, -- Set to 1 as per the original script
        c.rcvbl_num,
        c.amnt,
        c.be,
        c.ae,
        c.acctg_dt,
        c.src,
        c.lob,
        c.revnu,
        c.rsn,
        c.vt,
        c.bc,
        c.final_prodt AS prodt,
        c.gl_acct,
        c.final_ns_class_cd AS ns_class_cd,
        c.curr_clm_key,
        c.final_seq AS seq,
        c.final_rec_typ AS rec_typ,
        c.rcvbl_id,
        c.trns_id,
        c.run_id,
        c.mnth_of_svc
    FROM
        clean_data c
    WHERE
        c.amnt != 0
),

-- Get remittance information
remittance_info AS (
    SELECT
        r.trns_id,
        REGEXP_REPLACE(r.check_num, '[[:space:]]*$', '') AS check_num,
        r.check_dt,
        r.dpst_id
    FROM
        stg_irmsods__remittance r
),

-- Get deposit information
deposit_info AS (
    SELECT
        d.dpst_id,
        d.dpst_dt,
        d.dpst_finlzd_flg,
        d.run_id
    FROM
        stg_irmsods__deposit d
),

-- Get deposit finalized date
deposit_finalized_dates AS (
    SELECT
        r.run_id,
        r.strt_dt AS dpst_fnlzd_dt
    FROM
        stg_irmsods__run_log r
),

-- Get user information
user_info AS (
    SELECT
        l.run_id,
        s.sec_usr_nm
    FROM
        stg_irmsods__run_log l
        JOIN stg_irmsods__sec_usr s ON l.sec_usr_id = s.sec_usr_id
),

-- Get patient information
patient_info AS (
    SELECT
        t.rcvbl_id,
        t.glbl_mpng_cd,
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

-- Get payment comments
payment_comments AS (
    SELECT
        c.trns_id,
        TRIM(REGEXP_REPLACE(REPLACE(REPLACE(a.applctn_comnt_desc, CHR(13)), CHR(10), '; '), '[[:space:]]+', ' ')) AS pymt_comnt
    FROM
        stg_irmsods__trns_comnt c
        JOIN stg_irmsods__applctn_comnt a ON c.applctn_comnt_id = a.applctn_comnt_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY c.trns_id ORDER BY c.applctn_comnt_id) = 1
),

-- Business entity information
bus_ent_info AS (
    SELECT
        be.bus_ent_id,
        be.bus_ent_nm
    FROM
        stg_irmsods__bus_ent be
)

-- Final cash receipts report
SELECT
    g.be,
    be_info.bus_ent_nm AS be_name,
    g.ae,
    ae_info.bus_ent_nm AS ae_name,
    d.dpst_dt,
    df.dpst_fnlzd_dt,
    g.rcvbl_num,
    p.patnt_nm,
    g.mnth_of_svc AS mos,
    g.amnt AS applied_amnt,
    r.check_num,
    r.check_dt,
    r.dpst_id,
    g.rsn,
    TO_CHAR(g.acctg_dt, 'YYYYMM') AS acctg_period_id,
    g.acctg_dt,
    g.src,
    g.lob,
    g.gl_acct,
    u.sec_usr_nm,
    pc.pymt_comnt
FROM
    final_gl_data g
    JOIN remittance_info r ON g.trns_id = r.trns_id
    JOIN deposit_info d ON r.dpst_id = d.dpst_id
    LEFT JOIN deposit_finalized_dates df ON d.run_id = df.run_id
    LEFT JOIN user_info u ON g.run_id = u.run_id
    LEFT JOIN patient_info p ON g.rcvbl_id = p.rcvbl_id
    LEFT JOIN payment_comments pc ON g.trns_id = pc.trns_id
    LEFT JOIN bus_ent_info be_info ON g.be = be_info.bus_ent_id
    LEFT JOIN bus_ent_info ae_info ON g.ae = ae_info.bus_ent_id
WHERE
    g.le = 1
    AND g.amnt != 0
    AND g.revnu = 'PAYMNT'
ORDER BY
    be_name,
    ae_name,
    d.dpst_dt,
    g.rcvbl_num