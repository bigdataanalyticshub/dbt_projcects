{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Import CTEs
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

stg_irmsods__glbl_rcvbl_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__glbl_rcvbl_mpng') }}
),

stg_irmsods__retro_dme_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__retro_dme_stgng_que') }}
),

stg_irmsods__retro_dme_stgng_que_dtl AS (
    SELECT * FROM {{ ref('stg_irmsods__retro_dme_stgng_que_dtl') }}
),

stg_irmsods__ns_class_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__dme_rcvbl_po_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__dme_rcvbl_po_mpng') }}
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

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

-- Base transaction data
trns_adjmt_dme_t AS (
    SELECT t.trns_id, t.xref_trns_id, t.bill_to_bus_ent_id as be_id, t.run_id, t.bk_to_bus_ent_id as ae_id,
           t.acctg_period_id as acctg_period, t.glbl_mpng_cd, t.src_syst_cd, t.trns_amnt, t.acctg_dt,
           r.lin_of_bus_cd as lob, d.rsn_typ_cd as reason_typ, d.ns_gl_acct_cd as gl_acct, d.ns_class_cd,
           m.revnu_typ_cd as revenue_typ, v.val_typ_cd as value_typ, v.bllng_calctn_basis_cd as bcb,
           (CASE WHEN d.ns_gl_acct_cd = '4230' THEN t.trns_id ELSE t.xref_trns_id END) as grp_trns_id,
           0 as seq, t.create_dt
    FROM stg_irmsods__irms_transaction t
    JOIN stg_irmsods__irms_receivable r ON t.rcvbl_id = r.rcvbl_id
    JOIN stg_irmsods__product d ON d.irms_prodt_id = t.irms_prodt_id
    JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    JOIN stg_irmsods__val_typ_bllng_calctn_mpng v ON d.val_typ_bllng_calctn_id = v.val_typ_bllng_calctn_id
    WHERE r.lin_of_bus_cd = 'DMERD'
    AND d.rsn_typ_cd IN ('ADJPP','ADJCP')
),

-- Get curr_clm_key using join instead of subquery
curr_clm_key_data AS (
    SELECT DISTINCT m.glbl_mpng_cd, x.glbl_mpng_cd AS curr_clm_key
    FROM stg_irmsods__glbl_rcvbl_mpng m
    JOIN stg_irmsods__glbl_rcvbl_mpng x ON m.rcvbl_id = x.rcvbl_id
    JOIN stg_irmsods__irms_receivable r ON x.rcvbl_id = r.rcvbl_id
    WHERE m.glbl_mpng_typ_cd = 'B'
    AND x.extrnl_inv_src_cd = 'UKN'
    AND x.glbl_mpng_typ_cd = 'H'
    AND r.lin_of_bus_cd = 'DMERD'
),

-- Get class descriptions
class_desc_data AS (
    SELECT DISTINCT ns_class_cd, ns_class_desc
    FROM stg_irmsods__ns_class_r
),

-- Get accounting dates
acctg_dte_data AS (
    SELECT glbl_mpng_cd, src_syst_cd, MIN(acctg_dt) AS acctg_dte
    FROM stg_irmsods__irms_transaction
    GROUP BY glbl_mpng_cd, src_syst_cd
),

-- Get PO IDs
po_id_data AS (
    SELECT DISTINCT rcvbl_num, po_id
    FROM stg_irmsods__dme_rcvbl_po_mpng
),

-- Get sequence numbers
seq_data AS (
    SELECT src_clm_key, MAX(src_clm_seq_num) AS max_seq
    FROM stg_irmsods__retro_dme_stgng_que
    WHERE csq_status_cd = 'C'
    GROUP BY src_clm_key
),

-- Get invoice billed dates
inv_blld_dt_data AS (
    SELECT src_clm_key, MIN(inv_blld_dt) AS inv_blld_dt
    FROM stg_irmsods__retro_dme_stgng_que
    WHERE csq_status_cd = 'C'
    GROUP BY src_clm_key
),

-- Get comment IDs
comnt_id_data AS (
    SELECT trns_id, MAX(applctn_comnt_id) AS applctn_comnt_id
    FROM stg_irmsods__trns_comnt
    WHERE intrnl_extrnl_flg = 'I'
    GROUP BY trns_id
),

-- Combine base data with lookups
trns_adjmt_dme_enriched AS (
    SELECT
        t.*,
        CASE WHEN t.src_syst_cd = 'MANR' THEN ck.curr_clm_key ELSE NULL END AS curr_clm_key,
        cd.ns_class_desc,
        ad.acctg_dte,
        pd.po_id AS rcvbl_po_id,
        CASE
            WHEN t.src_syst_cd != 'OAC' THEN sd.max_seq
            ELSE t.seq
        END AS updated_seq,
        ci.applctn_comnt_id
    FROM trns_adjmt_dme_t t
    LEFT JOIN curr_clm_key_data ck ON ck.glbl_mpng_cd = t.glbl_mpng_cd
    LEFT JOIN class_desc_data cd ON cd.ns_class_cd = t.ns_class_cd
    LEFT JOIN acctg_dte_data ad ON ad.glbl_mpng_cd = t.glbl_mpng_cd AND ad.src_syst_cd = t.src_syst_cd
    LEFT JOIN po_id_data pd ON pd.rcvbl_num = t.glbl_mpng_cd
    LEFT JOIN seq_data sd ON sd.src_clm_key = t.glbl_mpng_cd
    LEFT JOIN comnt_id_data ci ON ci.trns_id = t.trns_id
),

-- Get invoice billed dates with COALESCE logic
trns_adjmt_with_inv_dt AS (
    SELECT
        t.*,
        COALESCE(ib1.inv_blld_dt, ib2.inv_blld_dt) AS inv_blld_dt
    FROM trns_adjmt_dme_enriched t
    LEFT JOIN inv_blld_dt_data ib1 ON ib1.src_clm_key = t.curr_clm_key
    LEFT JOIN inv_blld_dt_data ib2 ON ib2.src_clm_key = t.glbl_mpng_cd
),

-- Add stgng_que details
trns_adjmt_dme_stg_t AS (
    SELECT
        t.*,
        COALESCE(h.po_svc_typ, m.po_svc_typ) AS po_svc_typ,
        COALESCE(h.po_id, m.po_id) AS po_id,
        COALESCE(h.orig_clnt_bill_id, m.orig_clnt_bill_id) AS mic_bill_id
    FROM trns_adjmt_with_inv_dt t
    LEFT JOIN stg_irmsods__retro_dme_stgng_que h
        ON h.src_clm_key = t.curr_clm_key AND h.src_clm_seq_num = t.updated_seq AND h.csq_status_cd = 'C'
    LEFT JOIN stg_irmsods__retro_dme_stgng_que m
        ON m.src_clm_key = t.glbl_mpng_cd AND m.src_clm_seq_num = t.updated_seq AND m.csq_status_cd = 'C'
),

-- Add stgng_que_dtl details
trns_adjmt_dme_dtl_t AS (
    SELECT
        t.*,
        COALESCE(h.svc_typ, m.svc_typ) AS line_svc_typ
    FROM trns_adjmt_dme_stg_t t
    LEFT JOIN stg_irmsods__retro_dme_stgng_que_dtl h
        ON h.trns_id = t.grp_trns_id AND h.src_clm_key = t.curr_clm_key
    LEFT JOIN stg_irmsods__retro_dme_stgng_que_dtl m
        ON m.trns_id = t.grp_trns_id AND m.src_clm_key = t.glbl_mpng_cd
),

-- Get line_svc_typ for gl_acct = '4230'
line_svc_typ_data AS (
    SELECT DISTINCT ds.trns_id, ds.src_clm_key, ds.svc_typ
    FROM stg_irmsods__retro_dme_stgng_que_dtl ds
),

-- Update line_svc_typ for gl_acct = '4230'
trns_adjmt_dme_dtl_updated AS (
    SELECT
        t.*,
        CASE
            WHEN t.gl_acct = '4230' AND t.line_svc_typ IS NULL THEN
                lst.svc_typ
            ELSE t.line_svc_typ
        END AS updated_line_svc_typ
    FROM trns_adjmt_dme_dtl_t t
    LEFT JOIN line_svc_typ_data lst
        ON lst.trns_id = t.xref_trns_id
        AND lst.src_clm_key = COALESCE(t.curr_clm_key, t.glbl_mpng_cd)
),

-- Add adjustment reason and comment details
trns_adjmt_dme_rsn_t AS (
    SELECT
        t.*,
        ita.adjmt_rsn_cd AS adj_rsn_cd,
        aar.adjmt_rsn_desc AS adj_rsn_desc,
        REGEXP_REPLACE(TRIM(a.applctn_comnt_desc), '[\r\n]', ' ') AS adj_comment
    FROM trns_adjmt_dme_dtl_updated t
    LEFT JOIN stg_irmsods__irms_trns_adjmt ita ON ita.trns_id = t.trns_id
    LEFT JOIN stg_irmsods__adjmt_rsn_r aar ON aar.adjmt_rsn_cd = ita.adjmt_rsn_cd
    LEFT JOIN stg_irmsods__applctn_comnt a ON a.applctn_comnt_id = t.applctn_comnt_id
),

-- Add process and user details
trns_adjmt_dme_rpt_t AS (
    SELECT
        t.*,
        p.prcs_desc,
        s.sec_usr_nm AS irms_user
    FROM trns_adjmt_dme_rsn_t t
    LEFT JOIN stg_irmsods__run_log r ON r.run_id = t.run_id
    LEFT JOIN stg_irmsods__process p ON p.prcs_id = r.prcs_id
    LEFT JOIN stg_irmsods__sec_usr s ON s.sec_usr_id = r.sec_usr_id
),

-- Final output

final AS (
    SELECT
        t.be_id,
        be.bus_ent_nm AS be_name,
        t.ae_id,
        ae.bus_ent_nm AS ae_name,
        t.po_svc_typ,
        COALESCE(t.updated_line_svc_typ, t.line_svc_typ) AS line_svc_typ,
        t.src_syst_cd,
        t.lob,
        t.revenue_typ,
        t.reason_typ,
        t.adj_rsn_cd,
        t.adj_rsn_desc,
        t.value_typ,
        t.bcb,
        t.mic_bill_id,
        t.curr_clm_key AS extrnl_inv_id,
        t.glbl_mpng_cd AS irms_rcvbl_num,
        t.acctg_period,
        COALESCE(TO_VARCHAR(t.inv_blld_dt, 'MM/DD/YYYY'), TO_VARCHAR(t.acctg_dte, 'MM/DD/YYYY')) AS billed_dt,
        t.acctg_dt AS accntng_dt,  -- Changed from TO_VARCHAR conversion to keep as DATE
        SUM(t.trns_amnt) AS trns_amnt,
        COALESCE(t.rcvbl_po_id, t.po_id) AS po_id,
        t.run_id,
        t.prcs_desc,
        t.adj_comment,
        t.irms_user,
        t.gl_acct,
        t.ns_class_desc,
        TO_VARCHAR(t.create_dt, 'MM/DD/YYYY') AS create_dt
    FROM trns_adjmt_dme_rpt_t t
    LEFT JOIN stg_irmsods__bus_ent be ON t.be_id = be.bus_ent_id
    LEFT JOIN stg_irmsods__bus_ent ae ON t.ae_id = ae.bus_ent_id
    GROUP BY
        t.be_id,
        be.bus_ent_nm,
        t.ae_id,
        ae.bus_ent_nm,
        t.po_svc_typ,
        COALESCE(t.updated_line_svc_typ, t.line_svc_typ),
        t.src_syst_cd,
        t.lob,
        t.revenue_typ,
        t.reason_typ,
        t.adj_rsn_cd,
        t.adj_rsn_desc,
        t.value_typ,
        t.bcb,
        t.mic_bill_id,
        t.curr_clm_key,
        t.glbl_mpng_cd,
        t.acctg_period,
        COALESCE(TO_VARCHAR(t.inv_blld_dt, 'MM/DD/YYYY'), TO_VARCHAR(t.acctg_dte, 'MM/DD/YYYY')),
        t.acctg_dt,  -- Changed from TO_VARCHAR conversion in GROUP BY as well
        COALESCE(t.rcvbl_po_id, t.po_id),
        t.run_id,
        t.prcs_desc,
        t.adj_comment,
        t.irms_user,
        t.gl_acct,
        t.ns_class_desc,
        TO_VARCHAR(t.create_dt, 'MM/DD/YYYY')
    ORDER BY t.glbl_mpng_cd
)
SELECT * FROM final