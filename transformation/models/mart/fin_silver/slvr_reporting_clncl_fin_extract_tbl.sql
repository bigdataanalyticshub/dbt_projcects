{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH slvr_reporting_ipc_view AS (
    SELECT * FROM {{ ref('slvr_reporting_ipc_view') }}
),

irms_clinical_details AS (
    SELECT * FROM {{ ref('irms_clinical_details') }}
),

products AS (
    SELECT * FROM {{ ref('products') }}
),

bill_to_accounts AS (
    SELECT * FROM {{ ref('bill_to_accounts') }}
),

cte AS (
    SELECT
        invoice_no,
        bank_acct_num,
        src_syst_cd
    FROM
        slvr_reporting_ipc_view
    WHERE
        src_syst_cd = 'OAC'
        AND revnu = 'PAYMNT'
),

clnc_clm_stg_que_trns_id AS (
    SELECT
        invoice_no,
        MIN(trns_id) AS trns_id
    FROM
        slvr_reporting_ipc_view
    GROUP BY
        invoice_no
),

manr_cte AS (
    SELECT
        invoice_no,
        MIN(original_product_id) AS original_product_id
    FROM
        slvr_reporting_ipc_view
    WHERE
        src_syst_cd = 'MANR'
        AND rsn_typ_cd = 'ORIG'
        AND lob = 'CLNGNX'
    GROUP BY
        invoice_no
),

main_query AS (
    SELECT
        CASE
            WHEN ipc.src_syst_cd = 'CMS' AND
                ccsq.src_prodt_cd IN ('FCM','IME','TCM') AND
                SUBSTR(ccsq.customer_client_loc_number, -4) IN ('0254','0797','0828') AND
                ipc.lob = 'CLNGNX'
            THEN '4'
            WHEN ipc.src_syst_cd = 'OAC' AND
                cte.bank_acct_num = '711448148209'
            THEN '4'
            WHEN
                ipc.src_syst_cd IN ('MANR') AND
                (SUBSTR(ccsq.customer_client_loc_number, -4) NOT IN ('4001') OR ccsq.customer_client_loc_number IS NULL) AND
                (ccsq.src_prodt_cd NOT IN ('OCI') OR ccsq.src_prodt_cd IS NULL) AND
                ipc.lob IN ('CLNGNX','WCGNX')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'CMS' AND
                (ccsq.src_prodt_cd IN ('FCM','IME','MSA','TCM','UR') OR ccsq.src_prodt_cd IS NULL) AND
                (SUBSTR(ccsq.customer_client_loc_number, -4) NOT IN ('0254','0797','0828','0831') OR ccsq.customer_client_loc_number IS NULL)
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'NT24' AND
                ccsq.src_prodt_cd = 'NT24'
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'SAGNX'
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'SSAM' AND
                ccsq.src_prodt_cd IN ('SS')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'RITE' AND
                ccsq.src_prodt_cd IN ('UR')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'UNITY' AND
                ccsq.src_prodt_cd IN ('IME')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'W5' AND
                ccsq.src_prodt_cd IN ('IME')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'OAC' AND
                ((cte.bank_acct_num NOT IN ('518021576','708354014','708354592','NDS','4125067124','711448148209')) OR (cte.bank_acct_num IS NULL))
            THEN '5'
            WHEN ipc.src_syst_cd = 'CMS' AND
                ccsq.src_prodt_cd IN ('TCM') AND
                SUBSTR(ccsq.customer_client_loc_number, -4) IN ('831') AND
                ipc.lob = 'CLNGNX'
            THEN '6'
            WHEN ipc.src_syst_cd = 'MANR' AND
                ccsq.src_prodt_cd IN ('OCI') AND
                SUBSTR(ccsq.customer_client_loc_number, -4) IN ('4001') AND
                ipc.lob = 'CLNGNX'
            THEN '7'
            WHEN ipc.src_syst_cd = 'OAC' AND
                cte.bank_acct_num = '518021576'
            THEN '7'
            ELSE '0'
        END AS le_code,
        ipc.trns_id,
        ccsq.inv_num,
        ccsq.orig_inv_num AS prior_bill_iteration,
        ipc.bill_to_bus_ent_id AS be_number,
        be.bus_ent_nm AS be_name,
        ipc.ae AS ae_number,
        ae.bus_ent_nm AS ae_name,
        ccsq.acct_location AS genex_c_code,
        ccsq.customer_subclient_number AS genex_e_code,
        ccsq.adjstr_nm,
        NULL AS ae_address1,
        NULL AS ae_address2,
        NULL AS private_label,
        ccsq.record_type AS invoice_type,
        NULL AS ae_city,
        NULL AS ae_zip,
        NULL AS ae_state,
        NULL AS referral_number,
        ccsq.claimant_name,
        ccsq.claim_number,
        ccsq.employer,
        ccsq.gl_product AS product,
        SUBSTR(ccsq.customer_client_loc_number, -4) AS cost_center,
        ccsq.injury_date,
        ccsq.referral_date,
        ipc.original_accounting_id AS accounting_period,
        ipc.amount AS irms_booked_revenue,
        ccsq.acctg_dt AS invoice_date,
        ccsq.provider_service_date_from AS billing_date_from,
        ccsq.provider_service_date_to AS billing_date_to,
        ipc.prcs_desc,
        NULL AS claimant_ssn,
        ipc.invoice_no AS irms_rcvbl_num,
        ccsq.irms_rcvbl_seq_num,
        ipc.revnu,
        p.rsn_typ_cd,
        ccsq.src_prodt_cd AS rev_code,
        ccsq.referral_type,
        ccsq.line_of_insurance,
        ccsq.case_type,
        ccsq.claimant_benefit_state,
        ccsq.customer_client_number,
        ccsq.customer_subclient_number,
        ipc.src_syst_cd AS source_system_name,
        ccsq.invoice_line_count,
        p.ns_gl_acct_cd AS gl_acct_num,
        COALESCE(ccsq.ns_dept_desc, 'NA') AS dept_desc,
        COALESCE(ccsq.ns_class_desc, 'NA') AS class_desc,
        COALESCE(ccsq.ns_lctn_desc, 'NA') AS lctn_desc,
        ipc.comment_int AS comments,
        p.ns_class_cd,
        ipc.lob,
        cte.bank_acct_num,
        ipc.mos
    FROM
        slvr_reporting_ipc_view ipc
        LEFT JOIN cte ON cte.invoice_no = ipc.invoice_no AND cte.src_syst_cd = ipc.src_syst_cd
        LEFT JOIN clnc_clm_stg_que_trns_id ON ipc.invoice_no = clnc_clm_stg_que_trns_id.invoice_no
        LEFT JOIN irms_clinical_details ccsq ON clnc_clm_stg_que_trns_id.trns_id = ccsq.transaction_id
        LEFT JOIN products p ON p.original_product_id = ipc.original_product_id
        LEFT JOIN bill_to_accounts be ON be.bus_ent_id = ipc.bill_to_bus_ent_id
        LEFT JOIN bill_to_accounts ae ON ae.bus_ent_id = ipc.ae
    WHERE
        ipc.lob IN ('CLNGNX') AND
        ipc.src_syst_cd NOT IN ('SAGNX','MCPS','MANR') AND
        ipc.trns_typ_cd in ('C', 'A', 'M') AND
        ipc.revnu != 'PAYMNT'

    UNION ALL

    SELECT
        CASE
            WHEN ipc.src_syst_cd = 'MANR' AND
                p.ns_class_cd IN ('OCI') AND
                p.cost_cntr IN ('4001') AND
                ipc.lob = 'CLNGNX'
            THEN '7'
            WHEN ipc.src_syst_cd IN ('MANR') AND
                (p.cost_cntr NOT IN ('4001') OR p.cost_cntr IS NULL) AND
                (p.ns_class_cd NOT IN ('OCI') OR p.ns_class_cd IS NULL) AND
                ipc.lob IN ('CLNGNX','WCGNX')
            THEN '5'
            ELSE '0'
        END AS le_code,
        ipc.trns_id,
        NULL AS inv_num,
        NULL AS prior_bill_iteration,
        ipc.bill_to_bus_ent_id AS be_number,
        be.bus_ent_nm AS be_name,
        ipc.ae AS ae_number,
        ae.bus_ent_nm AS ae_name,
        NULL AS genex_c_code,
        NULL AS genex_e_code,
        NULL AS adjstr_nm,
        NULL AS ae_address1,
        NULL AS ae_address2,
        NULL AS private_label,
        NULL AS invoice_type,
        NULL AS ae_city,
        NULL AS ae_zip,
        NULL AS ae_state,
        NULL AS referral_number,
        NULL AS claimant_name,
        NULL AS claim_number,
        NULL AS employer,
        NULL AS product,
        p.cost_cntr AS cost_center,
        NULL AS injury_date,
        NULL AS referral_date,
        ipc.original_accounting_id AS accounting_period,
        ipc.amount AS irms_booked_revenue,
        ipc.acctg_dt AS invoice_date,
        NULL AS billing_date_from,
        NULL AS billing_date_to,
        ipc.prcs_desc,
        NULL AS claimant_ssn,
        ipc.invoice_no AS irms_rcvbl_num,
        NULL AS irms_rcvbl_seq_num,
        ipc.revnu,
        po.rsn_typ_cd,
        p.ns_class_cd AS rev_code,
        NULL AS referral_type,
        NULL AS line_of_insurance,
        NULL AS case_type,
        NULL AS claimant_benefit_state,
        NULL AS customer_client_number,
        NULL AS customer_subclient_number,
        ipc.src_syst_cd AS source_system_name,
        NULL AS invoice_line_count,
        po.ns_gl_acct_cd AS gl_acct_num,
        NULL AS dept_desc,
        NULL AS class_desc,
        NULL AS lctn_desc,
        ipc.comment_int AS comments,
        p.ns_class_cd,
        ipc.lob,
        NULL AS bank_acct_num,
        ipc.mos
    FROM
        slvr_reporting_ipc_view ipc
        LEFT JOIN manr_cte ON manr_cte.invoice_no = ipc.invoice_no
        LEFT JOIN products p ON manr_cte.original_product_id = p.original_product_id
        LEFT JOIN products po ON ipc.original_product_id = po.original_product_id
        LEFT JOIN bill_to_accounts be ON be.bus_ent_id = ipc.bill_to_bus_ent_id
        LEFT JOIN bill_to_accounts ae ON ae.bus_ent_id = ipc.ae
    WHERE
        ipc.lob IN ('CLNGNX') AND
        ipc.src_syst_cd = 'MANR' AND
        ipc.trns_typ_cd in ('C', 'A', 'M') AND
        ipc.revnu != 'PAYMNT'
),

final AS (
    SELECT
        le_code,
        trns_id,
        inv_num,
        prior_bill_iteration,
        be_number,
        be_name,
        ae_number,
        ae_name,
        genex_c_code,
        genex_e_code,
        adjstr_nm,
        ae_address1,
        ae_address2,
        private_label,
        invoice_type,
        ae_city,
        ae_zip,
        ae_state,
        referral_number,
        claimant_name,
        claim_number,
        employer,
        product,
        cost_center,
        injury_date,
        referral_date,
        accounting_period,
        irms_booked_revenue,
        invoice_date,
        billing_date_from,
        billing_date_to,
        prcs_desc,
        claimant_ssn,
        irms_rcvbl_num,
        irms_rcvbl_seq_num,
        revnu AS revnu_typ_cd,
        rsn_typ_cd,
        rev_code,
        referral_type,
        line_of_insurance,
        case_type,
        claimant_benefit_state,
        customer_client_number,
        customer_subclient_number,
        source_system_name,
        invoice_line_count,
        gl_acct_num,
        dept_desc,
        class_desc,
        lctn_desc,
        comments,
        ns_class_cd,
        lob,
        bank_acct_num,
        mos
    FROM main_query
)

SELECT * FROM final
