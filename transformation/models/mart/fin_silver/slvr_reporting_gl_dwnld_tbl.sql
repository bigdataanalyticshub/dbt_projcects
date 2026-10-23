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
        ipc.trns_id,
        ipc.invoice_no AS rcvbl_num,
        ipc.amount AS amnt,
        ipc.bill_to_bus_ent_id AS be,
        be.bus_ent_nm AS be_name,
        icd.acct_location AS c_code,
        ipc.ae,
        ae.bus_ent_nm AS ae_name,
        icd.customer_subclient_number AS e_code,
        ipc.acctg_dt,
        ipc.src_syst_cd AS src,
        ipc.lob,
        ipc.revnu,
        ipc.rsn_typ_cd AS rsn,
        ipc.val_typ AS vt,
        ipc.bcb AS bc,
        icd.src_prodt_cd AS prodt,
        p.ns_gl_acct_cd AS gl_acct,
        ipc.ns_dept_cd AS ns_dept,
        p.ns_class_cd,
        ipc.ns_class_desc,
        SUBSTR(icd.customer_client_loc_number, -4) AS cc,
        ipc.ns_lctn_desc AS ns_lctn,
        icd.inv_num,
        ipc.dpst_id,
        be.sector_cd AS sector,
        ipc.original_accounting_id AS acctg_period_id,
        cte.bank_acct_num,
        ipc.mos
    FROM
        slvr_reporting_ipc_view ipc
        LEFT JOIN cte ON cte.invoice_no = ipc.invoice_no AND cte.src_syst_cd = ipc.src_syst_cd
        LEFT JOIN clnc_clm_stg_que_trns_id ON ipc.invoice_no = clnc_clm_stg_que_trns_id.invoice_no
        LEFT JOIN irms_clinical_details icd ON clnc_clm_stg_que_trns_id.trns_id = icd.transaction_id
        LEFT JOIN products p ON ipc.original_product_id = p.original_product_id
        LEFT JOIN bill_to_accounts be ON ipc.bill_to_bus_ent_id = be.bus_ent_id
        LEFT JOIN bill_to_accounts ae ON ipc.ae = ae.bus_ent_id
    WHERE
        ipc.src_syst_cd != 'MANR'
        AND ipc.lob IN ('OACGNX','WCGNX','CLNGNX')

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
        ipc.invoice_no AS rcvbl_num,
        ipc.amount AS amnt,
        ipc.bill_to_bus_ent_id AS be,
        be.bus_ent_nm AS be_name,
        NULL AS c_code,
        ipc.ae,
        ae.bus_ent_nm AS ae_name,
        NULL AS e_code,
        ipc.acctg_dt,
        ipc.src_syst_cd AS src,
        ipc.lob,
        ipc.revnu,
        ipc.rsn_typ_cd AS rsn,
        ipc.val_typ AS vt,
        ipc.bcb AS bc,
        p.ns_class_cd AS prodt,
        po.ns_gl_acct_cd AS gl_acct,
        ipc.ns_dept_cd AS ns_dept,
        p.ns_class_cd,
        ipc.ns_class_desc,
        p.cost_cntr AS cc,
        ipc.ns_lctn_desc AS ns_lctn,
        NULL AS inv_num,
        ipc.dpst_id,
        be.sector_cd AS sector,
        ipc.original_accounting_id AS acctg_period_id,
        NULL AS bank_acct_num,
        ipc.mos
    FROM
        slvr_reporting_ipc_view ipc
        LEFT JOIN manr_cte ON manr_cte.invoice_no = ipc.invoice_no
        LEFT JOIN products p ON manr_cte.original_product_id = p.original_product_id
        LEFT JOIN products po ON ipc.original_product_id = po.original_product_id
        LEFT JOIN bill_to_accounts be ON ipc.bill_to_bus_ent_id = be.bus_ent_id
        LEFT JOIN bill_to_accounts ae ON ipc.ae = ae.bus_ent_id
    WHERE
        ipc.src_syst_cd = 'MANR'
        AND ipc.lob IN ('OACGNX','WCGNX','CLNGNX')
),

final AS (
    SELECT
        le_code,
        trns_id,
        rcvbl_num,
        amnt,
        be,
        be_name,
        c_code,
        ae,
        ae_name,
        e_code,
        acctg_dt,
        src,
        lob,
        revnu,
        rsn,
        vt,
        bc,
        prodt,
        gl_acct,
        ns_dept,
        ns_class_cd,
        ns_class_desc,
        cc,
        ns_lctn,
        inv_num,
        dpst_id,
        sector,
        acctg_period_id,
        bank_acct_num,
        mos
    FROM main_query
    WHERE amnt != 0
)

SELECT * FROM final
