{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Import CTEs for tables actually used in the model
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__irms_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
),

stg_irmsods__applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
),

stg_irmsods__trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__glbl_rcvbl_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__glbl_rcvbl_mpng') }}
),

stg_irmsods__retro_dme_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__retro_dme_stgng_que') }}
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

stg_irmsods__ns_class_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__retro_dme_stgng_que_dtl AS (
    SELECT * FROM {{ ref('stg_irmsods__retro_dme_stgng_que_dtl') }}
),

stg_irmsods__edi_835s AS (
    SELECT * FROM {{ ref('stg_irmsods__edi_835s') }}
),

stg_irmsods__edi_835b AS (
    SELECT * FROM {{ ref('stg_irmsods__edi_835b') }}
),

stg_irmsods__process AS (
    SELECT * FROM {{ ref('stg_irmsods__process') }}
),

-- Base CTE: Initial extraction of cash transactions for DME
base_transactions AS (
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
        r.lin_of_bus_cd AS lob,
        r.pymt_status_cd AS inv_pay_cd,
        r.bal AS rcvbl_bal,
        d.ns_gl_acct_cd AS gl_accnt,
        d.ns_class_cd,
        CASE WHEN d.ns_gl_acct_cd = '4230' THEN t.trns_id ELSE t.xref_trns_id END AS grp_trns_id,
        0 AS seq,
        t.create_dt
    FROM stg_irmsods__irms_transaction t
    JOIN stg_irmsods__irms_receivable r ON t.rcvbl_id = r.rcvbl_id
    JOIN stg_irmsods__product d ON d.irms_prodt_id = t.irms_prodt_id
    JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    WHERE r.lin_of_bus_cd = 'DMERD'
      AND m.revnu_typ_cd = 'PAYMNT'
      --AND t.acctg_period_id = {{ var('acctg_period_id', 202504) }}
),

-- Prepare external invoice mapping
external_invoice_mapping AS (
    SELECT
        m.glbl_mpng_cd,
        x.glbl_mpng_cd AS external_invoice_id
    FROM stg_irmsods__glbl_rcvbl_mpng m
    JOIN stg_irmsods__glbl_rcvbl_mpng x ON m.rcvbl_id = x.rcvbl_id
    JOIN stg_irmsods__irms_receivable r ON x.rcvbl_id = r.rcvbl_id
    WHERE m.glbl_mpng_typ_cd = 'B'
      AND x.extrnl_inv_src_cd = 'UKN'
      AND x.glbl_mpng_typ_cd = 'H'
      AND r.lin_of_bus_cd = 'DMERD'
),

-- Add external invoice reference
with_external_invoice AS (
    SELECT
        bt.*,
        CASE
            WHEN bt.src_syst_cd = 'MANR' THEN eim.external_invoice_id
            ELSE NULL
        END AS curr_clm_key
    FROM base_transactions bt
    LEFT JOIN external_invoice_mapping eim ON bt.glbl_mpng_cd = eim.glbl_mpng_cd AND bt.src_syst_cd = 'MANR'
),

-- Add remittance details
with_remittance AS (
    SELECT
        wei.*,
        REPLACE(REPLACE(LTRIM(RTRIM(r.check_num)), CHR(13), ''), CHR(10), '') AS check_num,
        r.check_dt,
        r.dpst_id
    FROM with_external_invoice wei
    LEFT JOIN stg_irmsods__remittance r ON wei.trns_id = r.trns_id
),

-- Add deposit details
with_deposit AS (
    SELECT
        wr.*,
        d.dpst_dt,
        REPLACE(REPLACE(LTRIM(RTRIM(d.dpst_desc)), CHR(13), ''), CHR(10), '') AS dpst_desc
    FROM with_remittance wr
    LEFT JOIN stg_irmsods__deposit d ON wr.dpst_id = d.dpst_id
),

-- Add class description
with_class_desc AS (
    SELECT
        wd.*,
        c.ns_class_desc
    FROM with_deposit wd
    LEFT JOIN stg_irmsods__ns_class_r c ON wd.ns_class_cd = c.ns_class_cd
),

-- Prepare earliest accounting dates
earliest_acctg_dates AS (
    SELECT
        glbl_mpng_cd,
        src_syst_cd,
        MIN(acctg_dt) AS earliest_acctg_dt
    FROM stg_irmsods__irms_transaction
    GROUP BY glbl_mpng_cd, src_syst_cd
),

-- Add accounting dates
with_accounting_dates AS (
    SELECT
        wc.*,
        ead.earliest_acctg_dt AS acctg_dte
    FROM with_class_desc wc
    LEFT JOIN earliest_acctg_dates ead
        ON wc.glbl_mpng_cd = ead.glbl_mpng_cd
        AND wc.src_syst_cd = ead.src_syst_cd
),

-- Prepare max sequence numbers
max_sequence_numbers AS (
    SELECT
        src_clm_key,
        MAX(src_clm_seq_num) AS max_seq_num
    FROM stg_irmsods__retro_dme_stgng_que
    WHERE csq_status_cd = 'C'
    GROUP BY src_clm_key
),

-- Update sequence numbers
with_sequence AS (
    SELECT
        wa.*,
        CASE
            WHEN wa.src_syst_cd NOT IN ('OAC') THEN msn.max_seq_num
            ELSE wa.seq
        END AS seq_updated
    FROM with_accounting_dates wa
    LEFT JOIN max_sequence_numbers msn ON wa.glbl_mpng_cd = msn.src_clm_key AND wa.src_syst_cd NOT IN ('OAC')
),

-- Prepare earliest invoice billed dates for all claim keys
earliest_inv_dates AS (
    SELECT
        src_clm_key,
        MIN(inv_blld_dt) AS earliest_inv_blld_dt
    FROM stg_irmsods__retro_dme_stgng_que
    WHERE csq_status_cd = 'C'
    GROUP BY src_clm_key
),

-- Add invoice billed dates - using joins instead of subqueries
with_invoice_dates AS (
    SELECT
        ws.*,
        CASE
            WHEN ws.src_syst_cd NOT IN ('OAC') THEN
                COALESCE(eid_curr.earliest_inv_blld_dt, eid_glbl.earliest_inv_blld_dt)
            ELSE NULL
        END AS inv_blld_dt
    FROM with_sequence ws
    LEFT JOIN earliest_inv_dates eid_curr
        ON ws.curr_clm_key = eid_curr.src_clm_key
        AND ws.curr_clm_key IS NOT NULL
        AND ws.src_syst_cd NOT IN ('OAC')
    LEFT JOIN earliest_inv_dates eid_glbl
        ON ws.glbl_mpng_cd = eid_glbl.src_clm_key
        AND ws.src_syst_cd NOT IN ('OAC')
),

-- Add staging queue data
with_staging_data AS (
    SELECT
        wi.*,
        COALESCE(h.emplyr_nm, m.emplyr_nm) AS employer,
        COALESCE(h.clm_num, m.clm_num) AS claim_num,
        COALESCE(TRIM(h.patnt_first_nm), TRIM(m.patnt_first_nm)) AS patnt_first_nm,
        COALESCE(TRIM(h.patnt_last_nm), TRIM(m.patnt_last_nm)) AS patnt_last_nm,
        COALESCE(h.po_svc_typ, m.po_svc_typ) AS po_svc_typ,
        COALESCE(h.orig_clnt_bill_id, m.orig_clnt_bill_id) AS mic_bill_id,
        COALESCE(h.wc_clm_id, m.wc_clm_id) AS wc_claim_id
    FROM with_invoice_dates wi
    LEFT JOIN stg_irmsods__retro_dme_stgng_que h
        ON h.src_clm_key = wi.curr_clm_key
        AND h.src_clm_seq_num = wi.seq_updated
        AND h.csq_status_cd = 'C'
    LEFT JOIN stg_irmsods__retro_dme_stgng_que m
        ON m.src_clm_key = wi.glbl_mpng_cd
        AND m.src_clm_seq_num = wi.seq_updated
        AND m.csq_status_cd = 'C'
),

-- Add staging queue detail data
with_detail_data AS (
    SELECT
        wsd.*,
        COALESCE(h.svc_typ, m.svc_typ) AS line_svc_typ,
        COALESCE(h.med_cd, m.med_cd) AS med_cd,
        COALESCE(h.rev_cd, m.rev_cd) AS rev_cd
    FROM with_staging_data wsd
    LEFT JOIN stg_irmsods__retro_dme_stgng_que_dtl h
        ON h.trns_id = wsd.grp_trns_id
        AND h.src_clm_key = wsd.curr_clm_key
    LEFT JOIN stg_irmsods__retro_dme_stgng_que_dtl m
        ON m.trns_id = wsd.grp_trns_id
        AND m.src_clm_key = wsd.glbl_mpng_cd
),

-- Prepare internal comments
internal_comments AS (
    SELECT
        tc.trns_id,
        ac.applctn_comnt_desc AS internal_comment
    FROM stg_irmsods__trns_comnt tc
    JOIN stg_irmsods__applctn_comnt ac ON tc.applctn_comnt_id = ac.applctn_comnt_id
    WHERE tc.intrnl_extrnl_flg = 'I'
),

-- Prepare external comments
external_comments AS (
    SELECT
        tc.trns_id,
        ac.applctn_comnt_desc AS external_comment
    FROM stg_irmsods__trns_comnt tc
    JOIN stg_irmsods__applctn_comnt ac ON tc.applctn_comnt_id = ac.applctn_comnt_id
    WHERE tc.intrnl_extrnl_flg = 'E'
),

-- Add comments
with_comments AS (
    SELECT
        wdd.*,
        REPLACE(REPLACE(
            LTRIM(RTRIM(
                CASE
                    WHEN ic.internal_comment IS NULL AND ec.external_comment IS NULL THEN NULL
                    WHEN ic.internal_comment IS NOT NULL AND ec.external_comment IS NULL THEN ic.internal_comment
                    WHEN ic.internal_comment IS NULL AND ec.external_comment IS NOT NULL THEN ec.external_comment
                    ELSE SUBSTR((ic.internal_comment || ' // ' || ec.external_comment), 1, 2000)
                END
            )),
        CHR(13), ' '), CHR(10), ' ') AS adj_comment
    FROM with_detail_data wdd
    LEFT JOIN internal_comments ic ON ic.trns_id = wdd.trns_id
    LEFT JOIN external_comments ec ON ec.trns_id = wdd.trns_id
),

-- Add process and user details
with_process_info AS (
    SELECT
        wc.*,
        p.prcs_desc,
        s.sec_usr_nm AS irms_user,
        eb.payr_nm AS payer_name,
        es.patnt_cntrl_nbr AS oac_claim_id,
        eb.patnt_frst_nm AS oac_patnt_frst_nm,
        eb.patnt_lst_nm AS oac_patnt_lst_nm,
        es.adjt_prc_cd AS oac_med_cd,
        es.svc_from_dt AS dos_from,
        es.svc_to_dt AS dos_to
    FROM with_comments wc
    LEFT JOIN stg_irmsods__run_log r ON r.run_id = wc.run_id
    LEFT JOIN stg_irmsods__process p ON p.prcs_id = r.prcs_id
    LEFT JOIN stg_irmsods__sec_usr s ON s.sec_usr_id = r.sec_usr_id
    LEFT JOIN stg_irmsods__edi_835s es ON es.trns_id = wc.trns_id
    LEFT JOIN stg_irmsods__edi_835b eb
        ON eb.run_id = es.run_id
        AND eb.bll_seq_num = es.bll_seq_num
),

-- Add business entity names
with_entity_names AS (
    SELECT
        wpi.*,
        be.bus_ent_nm AS be_name,
        ae.bus_ent_nm AS ae_name
    FROM with_process_info wpi
    LEFT JOIN stg_irmsods__bus_ent be ON wpi.be_id = be.bus_ent_id
    LEFT JOIN stg_irmsods__bus_ent ae ON wpi.ae_id = ae.bus_ent_id
)

-- Final output
SELECT
    wen.be_id,
    wen.be_name,
    wen.ae_id,
    wen.ae_name,
    wen.payer_name,
    wen.employer,
    wen.claim_num,
    CASE WHEN wen.src_syst_cd = 'OAC' THEN wen.oac_claim_id ELSE wen.wc_claim_id END AS wc_claim_id,
    CASE
        WHEN wen.src_syst_cd = 'OAC' THEN wen.oac_patnt_frst_nm
        ELSE wen.patnt_first_nm
    END AS patient_first_name,
    CASE
        WHEN wen.src_syst_cd = 'OAC' THEN wen.oac_patnt_lst_nm
        ELSE wen.patnt_last_nm
    END AS patient_last_name,
    CONCAT(
        CASE WHEN wen.src_syst_cd = 'OAC' THEN wen.oac_patnt_frst_nm ELSE wen.patnt_first_nm END,
        ' ',
        CASE WHEN wen.src_syst_cd = 'OAC' THEN wen.oac_patnt_lst_nm ELSE wen.patnt_last_nm END
    ) AS patient_name,
    wen.po_svc_typ,
    wen.line_svc_typ,
    COALESCE(wen.med_cd, wen.rev_cd) AS proc_cd,
    wen.oac_med_cd,
    wen.dos_from,
    wen.dos_to,
    wen.src_syst_cd,
    wen.lob,
    wen.mic_bill_id,
    wen.curr_clm_key AS extrnl_inv_id,
    wen.glbl_mpng_cd AS irms_rcvbl_num,
    wen.acctg_period,
    COALESCE(wen.inv_blld_dt,wen.acctg_dte) AS billed_dt,
    wen.acctg_dt AS accntng_dt,
    wen.inv_pay_cd,
    SUM(wen.trns_amnt) AS applied_amnt,
    wen.rcvbl_bal,
    wen.check_num,
    wen.check_dt AS check_dt,
    wen.dpst_id,
    wen.dpst_desc,
    wen.dpst_dt AS dpst_dt,
    wen.trns_id,
    wen.prcs_desc,
    wen.adj_comment,
    wen.irms_user,
    wen.gl_accnt,
    wen.ns_class_desc,
    wen.create_dt AS create_dt
FROM with_entity_names wen
GROUP BY
    wen.be_id, wen.be_name, wen.ae_id, wen.ae_name,
    wen.payer_name, wen.employer, wen.claim_num, wen.wc_claim_id, wen.oac_claim_id,
    wen.patnt_first_nm, wen.patnt_last_nm, wen.oac_patnt_frst_nm, wen.oac_patnt_lst_nm,
    wen.po_svc_typ, wen.line_svc_typ, COALESCE(wen.med_cd, wen.rev_cd),
    wen.oac_med_cd, wen.dos_from, wen.dos_to,
    wen.src_syst_cd, wen.lob, wen.mic_bill_id, wen.curr_clm_key, wen.glbl_mpng_cd,
    wen.acctg_period,
    COALESCE(wen.inv_blld_dt, wen.acctg_dte),
    wen.acctg_dt, wen.inv_pay_cd, wen.rcvbl_bal,
    wen.check_num, wen.check_dt, wen.dpst_id, wen.dpst_desc,
    wen.dpst_dt, wen.trns_id, wen.prcs_desc, wen.adj_comment,
    wen.irms_user, wen.gl_accnt, wen.ns_class_desc,wen.create_dt
ORDER BY wen.glbl_mpng_cd