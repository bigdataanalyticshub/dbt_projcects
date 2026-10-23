{{ config(
    materialized = 'table',
    tags = ['cmo_prod', 'weekly_refresh']
) }}

WITH stg_nco AS (
    SELECT * FROM {{ ref('stg_dwctshex__nco_test_mapping') }}
),

stg_legal_entities AS (
    SELECT * FROM {{ ref('stg_anlyssandboxtemp_cr_legal_entities_ar') }}
),

stg_bill_hdr AS (
    SELECT * FROM {{ ref('stg_cvtdwmcpsrptng__mcps_bill_hdr_fact') }}
),

stg_ntwrk AS (
    SELECT * FROM {{ ref('stg_cvtdwcommon__ntwrk_prodt_rptng_usr_src') }}
),

stg_clnt_hrchy AS (
    SELECT * FROM {{ ref('stg_cvtdwconfmrt__conf_clnt_hrchy_mv') }}
),

le_deduped AS (
    SELECT
        clean_client_number,
        clean_client_name,
        BE_ID,
        AE_ID,
        ROW_NUMBER() OVER (PARTITION BY clean_client_number ORDER BY ACCTG_PERIOD_DT DESC) AS RN
    FROM stg_legal_entities
    WHERE ACCTG_PERIOD_DT >= '2025-01-01'
    QUALIFY RN = 1
),

nco_deduped AS (
    SELECT
        norm_other_names,
        sp_name,
        SALESFORCE_NAME,
        SALESFORCE_ID,
        sf_link_id,
        ROW_NUMBER() OVER (PARTITION BY norm_other_names ORDER BY rn_norm ASC) AS RN
    FROM stg_nco
    QUALIFY RN = 1
),

billing_base AS (
    SELECT
        bhf.BE_ID,
        bhf.acctg_yr_month_num,
        CASE
            WHEN bhf.PAYOR_NM ILIKE '%Allstate%' THEN 'allstate'
            WHEN EXISTS (SELECT 1 FROM stg_nco WHERE norm_other_names = REPLACE(LOWER(cc.lvl5_hrchy_val), ' ', ''))
                THEN REPLACE(LOWER(cc.lvl5_hrchy_val), ' ', '')
            ELSE REPLACE(LOWER(cc.be_nm), ' ', '')
        END AS nco_join_key,
        COUNT(*) AS BILL_VOLUME,
        SUM(bhf.bill_ppo_svngs_amnt) AS PPO_SAVINGS
    FROM stg_bill_hdr bhf
    LEFT JOIN stg_ntwrk np
        ON bhf.dw_ntwrk_prodt_rptng_row_id = np.dw_ntwrk_prodt_rptng_row_id
    LEFT JOIN stg_clnt_hrchy cc
        ON bhf.dw_conf_clnt_row_id = cc.dw_conf_clnt_row_id
    WHERE bhf.clm_status_cd = 'EOK'
      AND bhf.BILL_WC_TTL_FEE_AMNT > 0
      AND bhf.TRNS_TYPE_CD = 'C'
      AND bhf.BILL_END_DT IS NULL
      AND bhf.VOID_INDC = 0
      AND NVL(bhf.rept_exclusn_cd, '000') NOT IN ('APR','ADV','MOD','OCM','QLC','RVO','NFS','DME')
      AND bhf.lob IN ('AUTO', '3AUTO')
      AND np.ntwrk_rptng_class_desc IN ('DIRECT', 'PARTNER')
      AND bhf.acctg_yr_month_num >= TO_NUMBER(TO_CHAR(DATEADD(MONTH, -18, CURRENT_DATE), 'YYYYMM'))
    GROUP BY bhf.BE_ID, bhf.acctg_yr_month_num, nco_join_key
),

billing_with_nco AS (
    SELECT
        COALESCE(nco.sp_name, 'N/A') AS sp_name,
        nco.sf_link_id,
        nco.salesforce_name,
        nco.SALESFORCE_ID,
        le_deduped.clean_client_number,
        le_deduped.clean_client_name,
        bb.BE_ID,
        bb.acctg_yr_month_num AS ACCTG_YR_MONTH_NUM,
        TO_DATE(CONCAT('01', '-', SUBSTRING(bb.acctg_yr_month_num, 5, 2), '-', LEFT(bb.acctg_yr_month_num, 4)), 'DD-MM-YYYY') AS DATE_FORMATTED,
        bb.BILL_VOLUME,
        bb.PPO_SAVINGS
    FROM billing_base bb
    LEFT JOIN nco_deduped nco ON nco.norm_other_names = bb.nco_join_key
    LEFT JOIN le_deduped ON bb.BE_ID = le_deduped.be_id
)

SELECT
    sp_name,
    sf_link_id,
    salesforce_name,
    SALESFORCE_ID,
    LISTAGG(DISTINCT clean_client_number, ', ') WITHIN GROUP (ORDER BY clean_client_number) AS clean_client_number,
    LISTAGG(DISTINCT clean_client_name, ', ') WITHIN GROUP (ORDER BY clean_client_name) AS clean_client_name,
    LISTAGG(DISTINCT BE_ID, ', ') WITHIN GROUP (ORDER BY BE_ID) AS BE_ID,
    ACCTG_YR_MONTH_NUM,
    DATE_FORMATTED,
    TO_CHAR(DATE_FORMATTED, 'DD-MM-YYYY') AS DAY_MONTH_YEAR_FORMATTED,
    SUM(BILL_VOLUME) AS BILL_VOLUME,
    SUM(PPO_SAVINGS) AS PPO_SAVINGS
FROM billing_with_nco
WHERE sp_name != 'N/A'
GROUP BY sp_name, sf_link_id, salesforce_name, SALESFORCE_ID, ACCTG_YR_MONTH_NUM, DATE_FORMATTED
ORDER BY ACCTG_YR_MONTH_NUM DESC, BILL_VOLUME DESC
