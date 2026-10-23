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
        salesforce_name,
        salesforce_id,
        sf_link_id,
        ROW_NUMBER() OVER (PARTITION BY norm_other_names ORDER BY rn_norm ASC) AS RN
    FROM stg_nco
    QUALIFY RN = 1
)

SELECT
    COALESCE(nco.sp_name, 'N/A') AS sp_name,
    nco.salesforce_name,
    nco.salesforce_id,
    nco.sf_link_id,
    le_deduped.clean_client_number,
    le_deduped.clean_client_name,
    bhf.BE_ID,
    bhf.acctg_yr_month_num AS ACCTG_YR_MONTH_NUM,
    TO_DATE(CONCAT('01', '-', SUBSTRING(bhf.acctg_yr_month_num, 5, 2), '-', LEFT(bhf.acctg_yr_month_num, 4)), 'DD-MM-YYYY') AS DATE_FORMATTED,
    TO_CHAR(TO_DATE(CONCAT('01', '-', SUBSTRING(bhf.acctg_yr_month_num, 5, 2), '-', LEFT(bhf.acctg_yr_month_num, 4)), 'DD-MM-YYYY'), 'DD-MM-YYYY') AS DAY_MONTH_YEAR_FORMATTED,
    COUNT(*) AS BILL_VOLUME,
    SUM(bhf.bill_oon_svngs_amnt) AS OON_SAVINGS
FROM stg_bill_hdr bhf
LEFT JOIN stg_ntwrk np
    ON bhf.dw_ntwrk_prodt_rptng_row_id = np.dw_ntwrk_prodt_rptng_row_id
LEFT JOIN stg_clnt_hrchy cc
    ON bhf.dw_conf_clnt_row_id = cc.dw_conf_clnt_row_id
LEFT JOIN nco_deduped nco
    ON nco.norm_other_names =
        CASE
            WHEN EXISTS (SELECT 1 FROM stg_nco WHERE norm_other_names = REPLACE(LOWER(cc.lvl5_hrchy_val), ' ', ''))
                THEN REPLACE(LOWER(cc.lvl5_hrchy_val), ' ', '')
            ELSE REPLACE(LOWER(cc.be_nm), ' ', '')
        END
LEFT JOIN le_deduped ON bhf.BE_ID = le_deduped.be_id
WHERE bhf.clm_status_cd = 'EOK'
  AND bhf.BILL_WC_TTL_FEE_AMNT > 0
  AND bhf.TRNS_TYPE_CD = 'C'
  AND bhf.BILL_END_DT IS NULL
  AND bhf.VOID_INDC = 0
  AND NVL(bhf.rept_exclusn_cd, '000') NOT IN ('APR','ADV','MOD','OCM','QLC','RVO','NFS','DME')
  AND bhf.lob IN ('WC', 'AUTO', '3AUTO')
  AND np.ntwrk_rptng_class_desc IN ('OUT OF NETWORK')
  AND bhf.acctg_yr_month_num >= TO_NUMBER(TO_CHAR(DATEADD(MONTH, -18, CURRENT_DATE), 'YYYYMM'))
GROUP BY nco.sp_name, nco.salesforce_name, nco.salesforce_id, nco.sf_link_id,
         le_deduped.clean_client_number, le_deduped.clean_client_name,
         bhf.BE_ID, bhf.acctg_yr_month_num
ORDER BY bhf.acctg_yr_month_num DESC, bhf.BE_ID
