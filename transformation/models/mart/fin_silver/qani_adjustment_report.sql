{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Source CTEs
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__irms_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
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

stg_irmsods__irms_trns_adjmt AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_trns_adjmt') }}
),

stg_irmsods__adjmt_rsn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__adjmt_rsn_r') }}
),

stg_irmsods__trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__process AS (
    SELECT * FROM {{ ref('stg_irmsods__process') }}
),

stg_irmsods__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__ns_class_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__ns_cc_lctn_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_cc_lctn_mpng') }}
),

stg_irmsods__ns_lctn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_lctn_r') }}
),

stg_irmsods__clm_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__clm_stgng_que') }}
),

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__lgl_ent_r AS (
    SELECT * FROM {{ ref('stg_irmsods__lgl_ent_r') }}
),

-- QLX Base Transactions
qlx_base_transactions AS (
    SELECT
        t.trns_id,
        t.xref_trns_id,
        t.bill_to_bus_ent_id AS be_id,
        t.run_id,
        t.bk_to_bus_ent_id AS ae_id,
        t.acctg_period_id AS acctg_period,
        t.glbl_mpng_cd,
        t.src_syst_cd,
        t.trns_amnt,
        t.acctg_dt,
        r.rcvbl_id,
        r.lin_of_bus_cd AS lob,
        d.rsn_typ_cd AS reason_typ,
        d.ns_gl_acct_cd AS gl_accnt,
        d.ns_class_cd,
        d.cost_cntr,
        m.revnu_typ_cd AS revenue_typ,
        v.val_typ_cd AS value_typ,
        9 AS le
    FROM stg_irmsods__irms_transaction t
    JOIN stg_irmsods__irms_receivable r ON t.rcvbl_id = r.rcvbl_id
    JOIN stg_irmsods__product d ON d.irms_prodt_id = t.irms_prodt_id
    JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    JOIN stg_irmsods__val_typ_bllng_calctn_mpng v ON d.val_typ_bllng_calctn_id = v.val_typ_bllng_calctn_id
    WHERE --t.acctg_period_id BETWEEN {{ var('start_period', 202504) }} AND {{ var('end_period', 202504) }}
      r.lin_of_bus_cd IN ('PPOQLX','TPAQLX')
      AND d.rsn_typ_cd IN ('ADJPP','ADJCP')
),

-- QLX earliest accounting dates
qlx_earliest_acctg_dates AS (
    SELECT
        glbl_mpng_cd,
        MIN(acctg_dt) AS earliest_acctg_dt
    FROM stg_irmsods__irms_transaction
    GROUP BY glbl_mpng_cd
),

-- QLX with billed date
qlx_with_billed_date AS (
    SELECT
        b.*,
        e.earliest_acctg_dt AS billed_dt
    FROM qlx_base_transactions b
    LEFT JOIN qlx_earliest_acctg_dates e ON b.glbl_mpng_cd = e.glbl_mpng_cd
),

-- QLX with adjustment reason and comments
qlx_with_adj_reason AS (
    SELECT
        t.*,
        ita.adjmt_rsn_cd AS adj_rsn_cd,
        aar.adjmt_rsn_desc AS adj_rsn_desc,
        LTRIM(RTRIM(a.applctn_comnt_desc)) AS adj_comment
    FROM qlx_with_billed_date t
    LEFT JOIN stg_irmsods__irms_trns_adjmt ita ON ita.trns_id = t.trns_id
    LEFT JOIN stg_irmsods__adjmt_rsn_r aar ON aar.adjmt_rsn_cd = ita.adjmt_rsn_cd
    LEFT JOIN stg_irmsods__trns_comnt tc ON tc.trns_id = t.trns_id AND tc.intrnl_extrnl_flg = 'I'
    LEFT JOIN stg_irmsods__applctn_comnt a ON a.applctn_comnt_id = tc.applctn_comnt_id
),

-- QLX with process and user details
qlx_with_user_info AS (
    SELECT
        t.*,
        p.prcs_desc,
        s.sec_usr_nm AS irms_user
    FROM qlx_with_adj_reason t
    LEFT JOIN stg_irmsods__run_log r ON r.run_id = t.run_id
    LEFT JOIN stg_irmsods__process p ON p.prcs_id = r.prcs_id
    LEFT JOIN stg_irmsods__sec_usr s ON s.sec_usr_id = r.sec_usr_id
),

-- QLX with class and location descriptions
qlx_final AS (
    SELECT
        t.*,
        cr.ns_class_desc,
        lr.ns_lctn_desc
    FROM qlx_with_user_info t
    LEFT JOIN stg_irmsods__ns_class_r cr ON cr.ns_class_cd = t.ns_class_cd
    LEFT JOIN stg_irmsods__ns_cc_lctn_mpng lm ON lm.cost_cntr = t.cost_cntr
    LEFT JOIN stg_irmsods__ns_lctn_r lr ON lr.ns_lctn_cd = lm.ns_lctn_cd
),

-- QLC Base Transactions
qlc_base_transactions AS (
    SELECT
        t.trns_id,
        t.xref_trns_id,
        t.bill_to_bus_ent_id AS be_id,
        t.run_id,
        t.bk_to_bus_ent_id AS ae_id,
        t.acctg_period_id AS acctg_period,
        t.glbl_mpng_cd,
        t.src_syst_cd,
        t.trns_amnt,
        t.acctg_dt,
        r.rcvbl_id,
        r.lin_of_bus_cd AS lob,
        d.rsn_typ_cd AS reason_typ,
        d.ns_gl_acct_cd AS gl_accnt,
        d.ns_class_cd,
        d.cost_cntr,
        m.revnu_typ_cd AS revenue_typ,
        v.val_typ_cd AS value_typ,
        8 AS le
    FROM stg_irmsods__irms_transaction t
    JOIN stg_irmsods__irms_receivable r ON t.rcvbl_id = r.rcvbl_id
    JOIN stg_irmsods__product d ON d.irms_prodt_id = t.irms_prodt_id
    JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    JOIN stg_irmsods__val_typ_bllng_calctn_mpng v ON d.val_typ_bllng_calctn_id = v.val_typ_bllng_calctn_id
    WHERE --t.acctg_period_id BETWEEN {{ var('start_period', 202504) }} AND {{ var('end_period', 202504) }}
      r.lin_of_bus_cd IN ('PPOQLC','CLNQLC','HLTQLC')
      AND d.rsn_typ_cd IN ('ADJPP','ADJCP')
),

-- QLC earliest accounting dates
qlc_earliest_acctg_dates AS (
    SELECT
        glbl_mpng_cd,
        MIN(acctg_dt) AS earliest_acctg_dt
    FROM stg_irmsods__irms_transaction
    GROUP BY glbl_mpng_cd
),

-- QLC sequence numbers
qlc_sequence_numbers AS (
    SELECT
        src_clm_key,
        MAX(src_clm_seq_num) AS max_seq_num,
        MIN(src_clm_seq_num) AS min_seq_num
    FROM stg_irmsods__clm_stgng_que
    WHERE csq_status_cd = 'C'
    GROUP BY src_clm_key
),

-- QLC with dates and sequence numbers
qlc_with_dates_seq AS (
    SELECT
        b.*,
        e.earliest_acctg_dt AS acctg_trns,
        s.max_seq_num,
        s.min_seq_num
    FROM qlc_base_transactions b
    LEFT JOIN qlc_earliest_acctg_dates e ON b.glbl_mpng_cd = e.glbl_mpng_cd
    LEFT JOIN qlc_sequence_numbers s ON b.glbl_mpng_cd = s.src_clm_key
),

-- QLC with staging queue details
qlc_with_staging_data AS (
    SELECT
        t.*,
        cs.clnt_clm_key AS claim_num,
        cs.first_nm || ' ' || cs.last_nm AS patient_name,
        cs.bill_jur_state_cd AS soj,
        csq.admsn_dt AS dos_from,
        cs.dschg_dt AS dos_to,
        cs.inj_dt AS injury_dt,
        csq.acctg_dt AS acctg_stg
    FROM qlc_with_dates_seq t
    LEFT JOIN stg_irmsods__clm_stgng_que cs
        ON cs.src_clm_key = t.glbl_mpng_cd
        AND cs.src_clm_seq_num = t.max_seq_num
        AND cs.csq_status_cd = 'C'
    LEFT JOIN stg_irmsods__clm_stgng_que csq
        ON csq.src_clm_key = t.glbl_mpng_cd
        AND csq.src_clm_seq_num = t.min_seq_num
        AND csq.csq_status_cd = 'C'
),

-- QLC with adjustment reason and comments
qlc_with_adj_reason AS (
    SELECT
        t.*,
        ita.adjmt_rsn_cd AS adj_rsn_cd,
        aar.adjmt_rsn_desc AS adj_rsn_desc,
        LTRIM(RTRIM(a.applctn_comnt_desc)) AS adj_comment
    FROM qlc_with_staging_data t
    LEFT JOIN stg_irmsods__irms_trns_adjmt ita ON ita.trns_id = t.trns_id
    LEFT JOIN stg_irmsods__adjmt_rsn_r aar ON aar.adjmt_rsn_cd = ita.adjmt_rsn_cd
    LEFT JOIN stg_irmsods__trns_comnt tc ON tc.trns_id = t.trns_id AND tc.intrnl_extrnl_flg = 'I'
    LEFT JOIN stg_irmsods__applctn_comnt a ON a.applctn_comnt_id = tc.applctn_comnt_id
),

-- QLC with process and user details
qlc_with_user_info AS (
    SELECT
        t.*,
        p.prcs_desc,
        s.sec_usr_nm AS irms_user
    FROM qlc_with_adj_reason t
    LEFT JOIN stg_irmsods__run_log r ON r.run_id = t.run_id
    LEFT JOIN stg_irmsods__process p ON p.prcs_id = r.prcs_id
    LEFT JOIN stg_irmsods__sec_usr s ON s.sec_usr_id = r.sec_usr_id
),

-- QLC with class and location descriptions
qlc_final AS (
    SELECT
        t.*,
        cr.ns_class_desc,
        lr.ns_lctn_desc
    FROM qlc_with_user_info t
    LEFT JOIN stg_irmsods__ns_class_r cr ON cr.ns_class_cd = t.ns_class_cd
    LEFT JOIN stg_irmsods__ns_cc_lctn_mpng lm ON lm.cost_cntr = t.cost_cntr
    LEFT JOIN stg_irmsods__ns_lctn_r lr ON lr.ns_lctn_cd = lm.ns_lctn_cd
),

-- QLX final output with business entity names
qlx_output AS (
    SELECT
        l.lgl_ent_desc AS legal_entity,
        t.be_id,
        be.bus_ent_nm AS be_name,
        t.ae_id,
        ae.bus_ent_nm AS ae_name,
        CAST(NULL AS VARCHAR) AS claim_num,
        CAST(NULL AS VARCHAR) AS patient_name,
        CAST(NULL AS VARCHAR) AS soj,
        CAST(NULL AS DATE) AS dos_from,
        CAST(NULL AS DATE) AS dos_to,
        CAST(NULL AS DATE) AS injury_dt,
        t.src_syst_cd,
        t.lob,
        t.revenue_typ,
        t.reason_typ,
        t.adj_rsn_cd,
        t.adj_rsn_desc,
        t.glbl_mpng_cd AS irms_rcvbl_num,
        t.acctg_period,
        t.billed_dt AS billed_dt,
        t.acctg_dt AS accntng_dt,
        t.trns_amnt,
        t.prcs_desc,
        t.adj_comment,
        t.irms_user,
        t.gl_accnt,
        t.ns_class_cd,
        t.ns_class_desc,
        t.ns_lctn_desc
    FROM qlx_final t
    LEFT JOIN stg_irmsods__lgl_ent_r l ON t.le = l.lgl_ent_cd
    LEFT JOIN stg_irmsods__bus_ent be ON t.be_id = be.bus_ent_id
    LEFT JOIN stg_irmsods__bus_ent ae ON t.ae_id = ae.bus_ent_id
),

-- QLC final output with business entity names
qlc_output AS (
    SELECT
        l.lgl_ent_desc AS legal_entity,
        t.be_id,
        be.bus_ent_nm AS be_name,
        t.ae_id,
        ae.bus_ent_nm AS ae_name,
        t.claim_num,
        t.patient_name,
        t.soj,
        t.dos_from,
        t.dos_to,
        t.injury_dt,
        t.src_syst_cd,
        t.lob,
        t.revenue_typ,
        t.reason_typ,
        t.adj_rsn_cd,
        t.adj_rsn_desc,
        t.glbl_mpng_cd AS irms_rcvbl_num,
        t.acctg_period,
        NVL(t.acctg_stg, t.acctg_trns) AS billed_dt,
        t.acctg_dt AS accntng_dt,
        t.trns_amnt,
        t.prcs_desc,
        t.adj_comment,
        t.irms_user,
        t.gl_accnt,
        t.ns_class_cd,
        t.ns_class_desc,
        t.ns_lctn_desc
    FROM qlc_final t
    LEFT JOIN stg_irmsods__lgl_ent_r l ON t.le = l.lgl_ent_cd
    LEFT JOIN stg_irmsods__bus_ent be ON t.be_id = be.bus_ent_id
    LEFT JOIN stg_irmsods__bus_ent ae ON t.ae_id = ae.bus_ent_id
)

-- Final combined output
SELECT
    legal_entity,
    be_id,
    be_name,
    ae_id,
    ae_name,
    claim_num,
    patient_name,
    soj,
    dos_from,
    dos_to,
    injury_dt,
    src_syst_cd,
    lob,
    revenue_typ,
    reason_typ,
    adj_rsn_cd,
    adj_rsn_desc,
    irms_rcvbl_num,
    acctg_period,
    billed_dt,
    accntng_dt,
    SUM(trns_amnt) AS trns_amnt,
    prcs_desc,
    adj_comment,
    irms_user,
    gl_accnt,
    ns_class_cd,
    ns_class_desc,
    ns_lctn_desc
FROM (
    SELECT * FROM qlx_output
    UNION ALL
    SELECT * FROM qlc_output
)
GROUP BY
    legal_entity,
    be_id,
    be_name,
    ae_id,
    ae_name,
    claim_num,
    patient_name,
    soj,
    dos_from,
    dos_to,
    injury_dt,
    src_syst_cd,
    lob,
    revenue_typ,
    reason_typ,
    adj_rsn_cd,
    adj_rsn_desc,
    irms_rcvbl_num,
    acctg_period,
    billed_dt,
    accntng_dt,
    prcs_desc,
    adj_comment,
    irms_user,
    gl_accnt,
    ns_class_cd,
    ns_class_desc,
    ns_lctn_desc
ORDER BY irms_rcvbl_num

