{{ config(
    materialized = 'table',
    tags = ['cmo_prod', 'weekly_refresh']
) }}

WITH stg_nco AS (
    SELECT * FROM {{ ref('stg_dwctshex__nco_test_mapping') }}
),

stg_retro_par AS (
    SELECT * FROM {{ ref('stg_cvtdwapricusrptng_retro_par_pymt_v') }}
)

SELECT
    nco.SP_NAME,
    nco.SALESFORCE_NAME,
    nco.SALESFORCE_ID,
    nco.SF_LINK_ID,
    rpp.BILL_TO_CLIENT,
    YEAR(rpp.DEPOSIT_DATE) AS DEPOSIT_YEAR,
    MONTH(rpp.DEPOSIT_DATE) AS DEPOSIT_MONTH,
    COUNT(*) AS TRANSACTION_COUNT,
    COUNT(DISTINCT rpp.PO_ID) AS DISTINCT_PO_COUNT,
    COUNT(DISTINCT rpp.MCPS_BILL_ID) AS DISTINCT_BILL_COUNT,
    COUNT(DISTINCT rpp.CLIENT_CLAIM_NUM) AS DISTINCT_CLAIM_COUNT,
    SUM(rpp.ADJUSTMENT_INDC) AS ADJUSTMENT_COUNT,
    AVG(rpp.AR_TAT_DAYS) AS AVG_AR_TAT_DAYS,
    AVG(rpp.FULL_TAT_DAYS) AS AVG_FULL_TAT_DAYS,
    AVG(rpp.CALCULATED_TAT_DAYS) AS AVG_CALCULATED_TAT_DAYS,
    MIN(rpp.DEPOSIT_DATE) AS MIN_DEPOSIT_DATE,
    MAX(rpp.DEPOSIT_DATE) AS MAX_DEPOSIT_DATE
FROM stg_retro_par rpp
LEFT JOIN stg_nco nco
    ON nco.norm_other_names = REPLACE(LOWER(rpp.BILL_TO_CLIENT), ' ', '')
    AND nco.rn_norm = 1
WHERE rpp.DEPOSIT_DATE IS NOT NULL
GROUP BY nco.SP_NAME, nco.SALESFORCE_NAME, nco.SALESFORCE_ID, nco.SF_LINK_ID,
         rpp.BILL_TO_CLIENT, YEAR(rpp.DEPOSIT_DATE), MONTH(rpp.DEPOSIT_DATE)
