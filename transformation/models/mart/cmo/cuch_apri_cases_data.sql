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

stg_aprcs_case AS (
    SELECT * FROM {{ ref('stg_apricusods__aprcs_case') }}
),

ods_deduped AS (
    SELECT
        COUNT(casenumber) AS case_count,
        ACCOUNT_SYSID,
        LPAD(MONTH(CLOSEDDATE), 2, '0') || YEAR(CLOSEDDATE) AS CLOSED_MONTH_YEAR,
        beid
    FROM stg_aprcs_case
    GROUP BY ACCOUNT_SYSID, CLOSED_MONTH_YEAR, beid
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

date_prep AS (
    SELECT
        nco.SP_NAME,
        nco.salesforce_name,
        nco.salesforce_id,
        nco.sf_link_id,
        le_deduped.clean_client_number,
        le_deduped.clean_client_name,
        ods_deduped.beid AS BE_ID,
        le_deduped.AE_ID,
        ods_deduped.ACCOUNT_SYSID,
        ods_deduped.CLOSED_MONTH_YEAR,
        SUM(ods_deduped.case_count) AS CASE_COUNT
    FROM ods_deduped
    LEFT JOIN le_deduped
        ON ods_deduped.beid = le_deduped.be_id
    LEFT JOIN stg_nco nco
        ON nco.NORM_OTHER_NAMES = REPLACE(LOWER(le_deduped.clean_client_name), ' ', '')
        AND nco.RN_NORM = 1
    GROUP BY nco.SP_NAME, nco.salesforce_name, nco.salesforce_id, nco.sf_link_id,
             clean_client_number, clean_client_name, ods_deduped.beid, le_deduped.AE_ID,
             ods_deduped.ACCOUNT_SYSID, ods_deduped.CLOSED_MONTH_YEAR
)

SELECT
    dp.SP_NAME,
    dp.salesforce_name,
    dp.salesforce_id,
    dp.sf_link_id,
    dp.clean_client_number,
    dp.clean_client_name,
    dp.BE_ID AS BE_ID,
    dp.AE_ID,
    dp.CLOSED_MONTH_YEAR,
    TO_DATE(
        CONCAT('01', '-', LEFT(dp.CLOSED_MONTH_YEAR, LEN(dp.CLOSED_MONTH_YEAR) - 4), '-', RIGHT(dp.CLOSED_MONTH_YEAR, 4)),
        'DD-MM-YYYY'
    ) AS CLOSED_MONTH_YEAR_FORMAT,
    TO_CHAR(
        TO_DATE(
            CONCAT('01', '-', LEFT(dp.CLOSED_MONTH_YEAR, LEN(dp.CLOSED_MONTH_YEAR) - 4), '-', RIGHT(dp.CLOSED_MONTH_YEAR, 4)),
            'DD-MM-YYYY'
        ),
        'DD-MM-YYYY'
    ) AS CLOSED_MONTH_YEAR_FORMATTED,
    LISTAGG(DISTINCT dp.ACCOUNT_SYSID, ', ') WITHIN GROUP (ORDER BY dp.ACCOUNT_SYSID) AS ACCOUNT_SYSID,
    SUM(dp.CASE_COUNT) AS CASE_COUNT
FROM date_prep dp
GROUP BY dp.SP_NAME, dp.salesforce_name, dp.salesforce_id, dp.sf_link_id,
         dp.clean_client_number, dp.clean_client_name, dp.BE_ID, dp.AE_ID, dp.CLOSED_MONTH_YEAR
ORDER BY CASE_COUNT DESC
