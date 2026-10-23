{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

-- Import CTEs
WITH slvr_reporting_ipc_view AS (
    SELECT * FROM {{ ref('slvr_reporting_ipc_view') }}
),

transactions AS (
    SELECT * FROM {{ ref('transactions') }}
),

transaction_lines AS (
    SELECT * FROM {{ ref('transaction_lines') }}
),

credits AS (
    SELECT * FROM {{ ref('credits') }}
),

products AS (
    SELECT * FROM {{ ref('products') }}
),

bill_to_accounts AS (
    SELECT * FROM {{ ref('bill_to_accounts') }}
),

irms_clinical_details AS (
    SELECT * FROM {{ ref('irms_clinical_details') }}
),

-- Logical CTEs
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

net_fee_calc AS (
    SELECT
        invoice_no,
        SUM(amount) AS net_fee
    FROM (
        SELECT
            t.invoice_no,
            tl.unit_price AS amount
        FROM
            transactions t
            LEFT JOIN transaction_lines tl ON t.id = tl.transaction_id
        UNION ALL
        SELECT
            c.invoice_no,
            c.amount
        FROM
            credits c
    ) a
    GROUP BY invoice_no
),

clnc_clm_stg_que AS (
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
                icd.src_prodt_cd IN ('FCM','IME','TCM') AND
                SUBSTR(icd.customer_client_loc_number, -4) IN ('0254','0797','0828') AND
                ipc.lob = 'CLNGNX'
            THEN '4'
            WHEN ipc.src_syst_cd = 'OAC' AND
                cte.bank_acct_num = '711448148209'
            THEN '4'
            WHEN
                ipc.src_syst_cd IN ('MANR') AND
                (SUBSTR(icd.customer_client_loc_number, -4) NOT IN ('4001') OR icd.customer_client_loc_number IS NULL) AND
                (icd.src_prodt_cd NOT IN ('OCI') OR icd.src_prodt_cd IS NULL) AND
                ipc.lob IN ('CLNGNX','WCGNX')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'CMS' AND
                (icd.src_prodt_cd IN ('FCM','IME','MSA','TCM','UR') OR icd.src_prodt_cd IS NULL) AND
                (SUBSTR(icd.customer_client_loc_number, -4) NOT IN ('0254','0797','0828','0831') OR icd.customer_client_loc_number IS NULL)
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'NT24' AND
                icd.src_prodt_cd = 'NT24'
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'SAGNX'
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'SSAM' AND
                icd.src_prodt_cd IN ('SS')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'RITE' AND
                icd.src_prodt_cd IN ('UR')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'UNITY' AND
                icd.src_prodt_cd IN ('IME')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'W5' AND
                icd.src_prodt_cd IN ('IME')
            THEN '5'
            WHEN
                ipc.src_syst_cd = 'OAC' AND
                ((cte.bank_acct_num NOT IN ('518021576','708354014','708354592','NDS','4125067124','711448148209')) OR (cte.bank_acct_num IS NULL))
            THEN '5'
            WHEN ipc.src_syst_cd = 'CMS' AND
                icd.src_prodt_cd IN ('TCM') AND
                SUBSTR(icd.customer_client_loc_number, -4) IN ('831') AND
                ipc.lob = 'CLNGNX'
            THEN '6'
            WHEN ipc.src_syst_cd = 'MANR' AND
                icd.src_prodt_cd IN ('OCI') AND
                SUBSTR(icd.customer_client_loc_number, -4) IN ('4001') AND
                ipc.lob = 'CLNGNX'
            THEN '7'
            WHEN ipc.src_syst_cd = 'OAC' AND
                cte.bank_acct_num = '518021576'
            THEN '7'
            ELSE '0'
        END AS le_code,
        bta.bus_ent_nm,
        ipc.bill_to_bus_ent_id,
        icd.acct_location AS genex_c_code,
        icd.customer_subclient_number AS genex_e_code,
        bta.admin_typ_cd,
        ipc.dpst_dt AS dpst_dt,
        ipc.invoice_no AS receivable_cd,
        NULL AS patient_nm, -- TABLE MISSING
        ipc.mos,
        nfc.net_fee,
        ipc.lob || ' ' || ipc.revnu AS prodt_desc,
        ipc.amount AS applied_amount,
        ipc.bal AS rcvbl_bal,
        ipc.check_num,
        ipc.check_dt,
        ipc.dpst_id,
        ipc.strt_dt AS dpst_fnlz_dt,
        ipc.src_syst_cd AS source,
        ipc.pymt_status_cd AS pc,
        ipc.bkng_status_cd AS ts,
        ipc.trns_id,
        ipc.prcs_desc,
        ipc.actv_dt AS prcs_dt,
        ipc.user_code AS irms_user,
        ipc.comments AS comnt,
        ipc.lob,
        ipc.original_accounting_id AS acctg_period,
        ipc.ae,
        SUBSTR(icd.customer_client_loc_number, -4) AS cost_cntr,
        ipc.pymt_status_cd,
        ipc.acctg_dt,
        cte.bank_acct_num,
        icd.src_prodt_cd
    FROM
        slvr_reporting_ipc_view ipc
        LEFT JOIN cte ON cte.invoice_no = ipc.invoice_no AND cte.src_syst_cd = ipc.src_syst_cd
        LEFT JOIN net_fee_calc nfc ON ipc.invoice_no = nfc.invoice_no
        LEFT JOIN products p ON ipc.original_product_id = p.original_product_id
        LEFT JOIN bill_to_accounts bta ON ipc.bill_to_bus_ent_id = bta.bus_ent_id
        LEFT JOIN clnc_clm_stg_que ON ipc.invoice_no = clnc_clm_stg_que.invoice_no
        LEFT JOIN irms_clinical_details icd ON clnc_clm_stg_que.trns_id = icd.transaction_id
    WHERE
        ipc.revnu = 'PAYMNT'
        AND ipc.lob IN ('OACGNX','WCGNX','CLNGNX')
        AND ipc.src_syst_cd != 'MANR'

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
        bta.bus_ent_nm,
        ipc.bill_to_bus_ent_id,
        NULL AS genex_c_code,
        NULL AS genex_e_code,
        bta.admin_typ_cd,
        ipc.dpst_dt AS dpst_dt,
        ipc.invoice_no AS receivable_cd,
        NULL AS patient_nm, -- TABLE MISSING
        ipc.mos,
        nfc.net_fee,
        ipc.lob || ' ' || ipc.revnu AS prodt_desc,
        ipc.amount AS applied_amount,
        ipc.bal AS rcvbl_bal,
        ipc.check_num,
        ipc.check_dt,
        ipc.dpst_id,
        ipc.strt_dt AS dpst_fnlz_dt,
        ipc.src_syst_cd AS source,
        ipc.pymt_status_cd AS pc,
        ipc.bkng_status_cd AS ts,
        ipc.trns_id,
        ipc.prcs_desc,
        ipc.actv_dt AS prcs_dt,
        ipc.user_code AS irms_user,
        ipc.comments AS comnt,
        ipc.lob,
        ipc.original_accounting_id AS acctg_period,
        ipc.ae,
        p.cost_cntr,
        ipc.pymt_status_cd,
        ipc.acctg_dt,
        NULL AS bank_acct_num,
        p.ns_class_cd AS src_prodt_cd
    FROM
        slvr_reporting_ipc_view ipc
        LEFT JOIN manr_cte ON manr_cte.invoice_no = ipc.invoice_no
        LEFT JOIN net_fee_calc nfc ON ipc.invoice_no = nfc.invoice_no
        LEFT JOIN products p ON manr_cte.original_product_id = p.original_product_id
        LEFT JOIN bill_to_accounts bta ON ipc.bill_to_bus_ent_id = bta.bus_ent_id
    WHERE
        ipc.revnu = 'PAYMNT'
        AND ipc.lob IN ('OACGNX','WCGNX','CLNGNX')
        AND ipc.src_syst_cd = 'MANR'
),

final AS (
    SELECT
        le_code,
        bus_ent_nm,
        bill_to_bus_ent_id,
        genex_c_code,
        genex_e_code,
        admin_typ_cd,
        dpst_dt,
        receivable_cd,
        patient_nm,
        mos,
        net_fee,
        prodt_desc,
        applied_amount,
        rcvbl_bal,
        check_num,
        check_dt,
        dpst_id,
        dpst_fnlz_dt,
        source,
        pc,
        ts,
        trns_id,
        prcs_desc,
        prcs_dt,
        irms_user,
        comnt,
        lob,
        acctg_period,
        ae,
        cost_cntr,
        pymt_status_cd,
        acctg_dt,
        bank_acct_num,
        src_prodt_cd
    FROM main_query
)

SELECT * FROM final
