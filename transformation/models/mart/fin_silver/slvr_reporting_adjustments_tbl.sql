{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Import CTEs
slvr_reporting_ipc_view AS (
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

-- Logical CTEs
cte AS (
    SELECT
        invoice_no,
        bank_acct_num,
        src_syst_cd
    FROM
       slvr_reporting_ipc_view
    WHERE src_syst_cd = 'OAC'
        AND revnu = 'PAYMNT'
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
    WHERE src_syst_cd = 'MANR'
        AND rsn_typ_cd = 'ORIG'
        AND lob = 'CLNGNX'
    GROUP BY
        invoice_no
),

main_query AS (
    SELECT
        IPC.trns_id,
        IPC.ae AS bus_ent_id,
        BTAE.bus_ent_nm,
        ICD.customer_subclient_number AS genex_e_code,
        IPC.bill_to_bus_ent_id AS be,
        BTA.bus_ent_nm AS be_name,
        ICD.acct_location AS genex_c_code,
        BTA.admin_typ_cd AS sector_cd,
        IPC.src_syst_cd,
        IPC.prcs_desc AS prcs_desc,
        IPC.invoice_no AS receivable_cd,
        IPC.agng_dt AS agng_dt,
        IPC.acctg_dt AS actv_dt,
        IPC.original_accounting_id AS acctg_period,
        IPC.mos AS mos,
        IPC.lob AS lob,
        IPC.revnu AS revnu,
        P.rsn_typ_cd AS reason,
        IPC.val_typ AS val_typ,
        IPC.bcb AS bcb,
        P.gl_ora_major_cd || '-' || P.gl_ora_minor_cd AS gl_acct_num,
        P.ns_gl_acct_cd,
        P.gl_ora_prodt_cd AS gl_prodt,
        P.ns_class_cd AS class_cd,
        SUBSTR(ICD.customer_client_loc_number, -4) AS cost_cntr,
        ICD.ns_lctn_desc AS location,
        P.gl_ora_segment AS gl_segment,
        IPC.amount,
        IPC.user_code AS user_code,
        IPC.adjmt_rsn_cd AS adjmt_rsn_cd,
        IPC.adjmt_rsn_desc AS adjmt_rsn_desc,
        IPC.finalize_run_id AS finalize_run_id,
        IPC.comment_int AS comments,
        P.gl_ora_major_cd,
        P.gl_ora_minor_cd,
        IPC.ae,
        OAC.bank_acct_num,
        ICD.src_prodt_cd
    FROM
        slvr_reporting_ipc_view IPC
        LEFT JOIN cte OAC ON OAC.invoice_no = IPC.invoice_no AND OAC.src_syst_cd = IPC.src_syst_cd
        LEFT JOIN clnc_clm_stg_que TR ON IPC.invoice_no = TR.invoice_no
        LEFT JOIN irms_clinical_details ICD ON TR.trns_id = ICD.transaction_id
        LEFT JOIN products P ON IPC.original_product_id = P.original_product_id
        LEFT JOIN bill_to_accounts BTA ON BTA.bus_ent_id = IPC.bill_to_bus_ent_id
        LEFT JOIN bill_to_accounts BTAE ON BTAE.bus_ent_id = IPC.ae
    WHERE
        IPC.ppa_flag IN ('C', 'P')
        AND IPC.src_syst_cd != 'MANR'
        AND IPC.lob IN ('OACGNX', 'WCGNX', 'CLNGNX')
        AND IPC.amount != 0.0

    UNION ALL

    SELECT
        IPC.trns_id,
        IPC.ae AS bus_ent_id,
        BTAE.bus_ent_nm,
        NULL AS genex_e_code,
        IPC.bill_to_bus_ent_id AS be,
        BTA.bus_ent_nm AS be_name,
        NULL AS genex_c_code,
        BTA.admin_typ_cd AS sector_cd,
        IPC.src_syst_cd,
        IPC.prcs_desc AS prcs_desc,
        IPC.invoice_no AS receivable_cd,
        IPC.agng_dt AS agng_dt,
        IPC.acctg_dt AS actv_dt,
        IPC.original_accounting_id AS acctg_period,
        IPC.mos AS mos,
        IPC.lob AS lob,
        IPC.revnu AS revnu,
        P.rsn_typ_cd AS reason,
        IPC.val_typ AS val_typ,
        IPC.bcb AS bcb,
        PO.gl_ora_major_cd || '-' || PO.gl_ora_minor_cd AS gl_acct_num,
        P.ns_gl_acct_cd,
        P.gl_ora_prodt_cd AS gl_prodt,
        P.ns_class_cd AS class_cd,
        P.cost_cntr AS cost_cntr,
        NULL AS location,
        P.gl_ora_segment AS gl_segment,
        IPC.amount,
        IPC.user_code AS user_code,
        IPC.adjmt_rsn_cd AS adjmt_rsn_cd,
        IPC.adjmt_rsn_desc AS adjmt_rsn_desc,
        IPC.finalize_run_id AS finalize_run_id,
        IPC.comment_int AS comments,
        PO.gl_ora_major_cd,
        PO.gl_ora_minor_cd,
        IPC.ae,
        NULL AS bank_acct_num,
        P.ns_class_cd AS src_prodt_cd
    FROM
        slvr_reporting_ipc_view IPC
        LEFT JOIN manr_cte MANR ON MANR.invoice_no = IPC.invoice_no
        LEFT JOIN products P ON MANR.original_product_id = P.original_product_id
        LEFT JOIN products PO ON IPC.original_product_id = PO.original_product_id
        LEFT JOIN bill_to_accounts BTA ON BTA.bus_ent_id = IPC.bill_to_bus_ent_id
        LEFT JOIN bill_to_accounts BTAE ON BTAE.bus_ent_id = IPC.ae
    WHERE
        IPC.ppa_flag IN ('C', 'P')
        AND IPC.src_syst_cd = 'MANR'
        AND IPC.lob IN ('OACGNX', 'WCGNX', 'CLNGNX')
        AND IPC.amount != 0.0
),

le_code_assignment AS (
        SELECT
        CASE
            WHEN src_syst_cd = 'CMS' AND
                src_prodt_cd IN ('FCM', 'IME', 'TCM') AND
                cost_cntr IN ('0254', '0797', '0828') AND
                lob = 'CLNGNX'
            THEN '4'
            WHEN src_syst_cd = 'OAC' AND
                bank_acct_num = '711448148209'
            THEN '4'
            WHEN
                src_syst_cd IN ('MANR') AND
                (cost_cntr NOT IN ('4001') OR cost_cntr IS NULL) AND
                (src_prodt_cd NOT IN ('OCI') OR src_prodt_cd IS NULL) AND
                lob IN ('CLNGNX', 'WCGNX')
            THEN '5'
            WHEN
                src_syst_cd = 'CMS' AND
                (src_prodt_cd IN ('FCM', 'IME', 'MSA', 'TCM', 'UR') OR src_prodt_cd IS NULL) AND
                (cost_cntr NOT IN ('0254', '0797', '0828', '0831') OR cost_cntr IS NULL)
            THEN '5'
            WHEN
                src_syst_cd = 'NT24' AND
                src_prodt_cd = 'NT24'
            THEN '5'
            WHEN
                src_syst_cd = 'SAGNX'
            THEN '5'
            WHEN
                src_syst_cd = 'SSAM' AND
                src_prodt_cd IN ('SS')
            THEN '5'
            WHEN
                src_syst_cd = 'RITE' AND
                src_prodt_cd IN ('UR')
            THEN '5'
            WHEN
                src_syst_cd = 'UNITY' AND
                src_prodt_cd IN ('IME')
            THEN '5'
            WHEN
                src_syst_cd = 'W5' AND
                src_prodt_cd IN ('IME')
            THEN '5'
            WHEN
                src_syst_cd = 'OAC' AND
                ((bank_acct_num NOT IN ('518021576', '708354014', '708354592', 'NDS', '4125067124', '711448148209')) OR (bank_acct_num IS NULL))
            THEN '5'
            WHEN src_syst_cd = 'CMS' AND
                src_prodt_cd IN ('TCM') AND
                cost_cntr IN ('831') AND
                lob = 'CLNGNX'
            THEN '6'
            WHEN src_syst_cd = 'MANR' AND
                src_prodt_cd IN ('OCI') AND
                cost_cntr IN ('4001') AND
                lob = 'CLNGNX'
            THEN '7'
            WHEN src_syst_cd = 'OAC' AND
                bank_acct_num = '518021576'
            THEN '7'
            ELSE '0'
        END AS le_code,
        *
    FROM
        main_query
),

-- Final CTE
final AS (
    SELECT
        LE_CODE,
        TRNS_ID,
        BUS_ENT_ID,
        BUS_ENT_NM,
        GENEX_E_CODE,
        BE,
        BE_NAME,
        GENEX_C_CODE,
        SECTOR_CD,
        SRC_SYST_CD,
        PRCS_DESC,
        RECEIVABLE_CD,
        AGNG_DT,
        ACTV_DT,
        ACCTG_PERIOD,
        MOS,
        LOB,
        REVNU,
        REASON,
        VAL_TYP,
        BCB,
        GL_ACCT_NUM,
        NS_GL_ACCT_CD,
        GL_PRODT,
        CLASS_CD,
        COST_CNTR,
        LOCATION,
        GL_SEGMENT,
        AMOUNT,
        USER_CODE,
        ADJMT_RSN_CD,
        ADJMT_RSN_DESC,
        FINALIZE_RUN_ID,
        COMMENTS,
        GL_ORA_MAJOR_CD,
        GL_ORA_MINOR_CD,
        AE,
        BANK_ACCT_NUM,
        SRC_PRODT_CD
    FROM le_code_assignment

)

SELECT * FROM final