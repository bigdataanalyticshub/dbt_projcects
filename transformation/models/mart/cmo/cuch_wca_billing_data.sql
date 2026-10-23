{{ config(
    materialized = 'table',
    tags = ['cmo_prod', 'weekly_refresh']
) }}

WITH stg_nco AS (
    SELECT * FROM {{ ref('stg_dwctshex__nco_test_mapping') }}
),

stg_ns_customer AS (
    SELECT * FROM {{ ref('stg_anlysandboxtemp_ns_customer_raw_april_28') }}
),

stg_legal_entities AS (
    SELECT * FROM {{ ref('stg_anlyssandboxtemp_cr_legal_entities_ar') }}
),

stg_wcs_bill AS (
    SELECT * FROM {{ ref('stg_dwwcs__vw_claim_detail_bill') }}
),

stg_wcs_breakouts AS (
    SELECT * FROM {{ ref('stg_dwctshex__wcs_client_breakouts') }}
),

wcs_deduped AS (
    SELECT
        ODS_CUSTOMER_ID,
        site_code,
        control_number,
        claim_system_description,
        product_code,
        CUSTOMER_NAME,
        BILL_CREATE_DATE_YEAR,
        BILL_CREATE_DATE_MONTH,
        COUNT(*) AS BILL_COUNT,
        SUM(provider_charges) AS TOTAL_CHARGES
    FROM stg_wcs_bill
    WHERE BILL_CREATE_DATE_YEAR >= 2025
      AND (BILL_CREATE_DATE_YEAR * 100 + BILL_CREATE_DATE_MONTH) <= (YEAR(CURRENT_DATE()) * 100 + MONTH(CURRENT_DATE()))
      AND CLAIM_DATE_OF_INJURY_YEAR >= 2025
      AND product_code IN ('U', 'P', 'F')
      AND bill_status IN (1, 8, 12)
      AND NOT duplicate_bill_flag
      AND ods_customer_id <> 502
      AND site_code <> '@@@'
      AND claim_sys_subset NOT IN ('9999', '0000', 'XXXX', 'TEST')
      AND claim_system_description NOT IN (
          'SUPPORT TEST ACCOUNT-UC', 'TEST CLAIM SYSTEM', 'TEST - AMCC', 'TEST',
          'TEST ACCOUNTS', 'TEST - BRICKSTREET', 'UCR TEST', 'MEDICARE TEST'
      )
      AND NOT (site_code = 'COV' AND sub_product_code = 'RE-EVAL CANCELLATION')
    GROUP BY ODS_CUSTOMER_ID, site_code, control_number, claim_system_description, product_code,
             CUSTOMER_NAME, BILL_CREATE_DATE_YEAR, BILL_CREATE_DATE_MONTH
),

NS_CUSTOMER AS (
    SELECT normalized_company, CUSTENTITY_MI_CLEAN_CLIENT_NAME
    FROM (
        SELECT DISTINCT
            REPLACE(LOWER(COMPANYNAME), ' ', '') AS normalized_company,
            CUSTENTITY_MI_CLEAN_CLIENT_NAME,
            ROW_NUMBER() OVER (
                PARTITION BY REPLACE(LOWER(COMPANYNAME), ' ', '')
                ORDER BY CUSTENTITY_MI_CLEAN_CLIENT_NAME
            ) AS RN
        FROM stg_ns_customer
        WHERE CUSTENTITY_MI_CLEAN_CLIENT_NAME IS NOT NULL
    )
    WHERE RN = 1
),

le_deduped AS (
    SELECT
        clean_client_number,
        clean_client_name,
        BE_ID,
        ROW_NUMBER() OVER (PARTITION BY clean_client_number ORDER BY ACCTG_PERIOD_DT DESC) AS RN
    FROM stg_legal_entities
    WHERE ACCTG_PERIOD_DT >= '2025-01-01'
    QUALIFY RN = 1
),

date_prep AS (
    SELECT
        COALESCE(nco.SP_NAME, 'N/A') AS SP_NAME,
        COALESCE(nco.salesforce_name, 'N/A') AS SALESFORCE_NAME,
        nco.salesforce_id,
        nco.sf_link_id,
        wcs_deduped.ODS_CUSTOMER_ID,
        wcs_deduped.CUSTOMER_NAME,
        le.clean_client_name,
        le.BE_ID,
        wcs_deduped.BILL_CREATE_DATE_YEAR,
        wcs_deduped.BILL_CREATE_DATE_MONTH,
        LPAD(wcs_deduped.BILL_CREATE_DATE_MONTH, 2, '0') || wcs_deduped.BILL_CREATE_DATE_YEAR AS BILL_MONTH_YEAR,
        TO_DATE(
            CONCAT('01', '-', LPAD(NVL(wcs_deduped.BILL_CREATE_DATE_MONTH, 1), 2, '0'), '-', NVL(wcs_deduped.BILL_CREATE_DATE_YEAR, YEAR(CURRENT_DATE()))),
            'DD-MM-YYYY'
        ) AS BILL_CREATE_MONTH_DATE,
        TO_CHAR(
            TO_DATE(
                CONCAT('01', '-', LPAD(NVL(wcs_deduped.BILL_CREATE_DATE_MONTH, 1), 2, '0'), '-', NVL(wcs_deduped.BILL_CREATE_DATE_YEAR, YEAR(CURRENT_DATE()))),
                'DD-MM-YYYY'
            ),
            'DD-MM-YYYY'
        ) AS BILL_CREATE_CUSTOM_DATE_FORMATTED,
        wcs_deduped.BILL_COUNT,
        wcs_deduped.TOTAL_CHARGES
    FROM wcs_deduped
    LEFT JOIN stg_wcs_breakouts m
        ON (m.GROUPINGTYPE = 'Ctrl' AND wcs_deduped.site_code = m.SITECODE AND wcs_deduped.control_number = m.CONTROLNUM)
        OR (m.GROUPINGTYPE != 'Ctrl' AND wcs_deduped.site_code = m.SITECODE)
    LEFT JOIN stg_nco nco
        ON nco.norm_other_names =
            CASE
                WHEN EXISTS (SELECT 1 FROM stg_nco WHERE norm_other_names = REPLACE(LOWER(CASE WHEN m.GROUPINGTYPE = 'Clm' THEN CONCAT(m.FINAL_NAME, ' - ', wcs_deduped.claim_system_description) ELSE m.FINAL_NAME END), ' ', ''))
                    THEN REPLACE(LOWER(CASE WHEN m.GROUPINGTYPE = 'Clm' THEN CONCAT(m.FINAL_NAME, ' - ', wcs_deduped.claim_system_description) ELSE m.FINAL_NAME END), ' ', '')
                ELSE REPLACE(LOWER(wcs_deduped.customer_name), ' ', '')
            END
        AND nco.rn_norm = 1
    LEFT JOIN NS_CUSTOMER cust ON cust.normalized_company = REPLACE(LOWER(wcs_deduped.CUSTOMER_NAME), ' ', '')
    LEFT JOIN le_deduped le ON le.clean_client_name = cust.CUSTENTITY_MI_CLEAN_CLIENT_NAME
)

SELECT
    dp.SP_NAME,
    dp.SALESFORCE_NAME,
    dp.salesforce_id,
    dp.sf_link_id,
    dp.clean_client_name,
    dp.BE_ID,
    dp.BILL_CREATE_DATE_YEAR,
    dp.BILL_CREATE_DATE_MONTH,
    dp.BILL_MONTH_YEAR,
    dp.BILL_CREATE_MONTH_DATE,
    dp.BILL_CREATE_CUSTOM_DATE_FORMATTED,
    LISTAGG(DISTINCT dp.ODS_CUSTOMER_ID, ', ') WITHIN GROUP (ORDER BY dp.ODS_CUSTOMER_ID) AS ODS_CUSTOMER_IDS,
    LISTAGG(DISTINCT dp.CUSTOMER_NAME, ', ') WITHIN GROUP (ORDER BY dp.CUSTOMER_NAME) AS CUSTOMER_NAMES,
    SUM(dp.BILL_COUNT) AS BILL_COUNT,
    SUM(dp.TOTAL_CHARGES) AS TOTAL_CHARGES
FROM date_prep dp
GROUP BY dp.SP_NAME, dp.SALESFORCE_NAME, dp.salesforce_id, dp.sf_link_id,
         dp.clean_client_name, dp.BE_ID,
         dp.BILL_CREATE_DATE_YEAR, dp.BILL_CREATE_DATE_MONTH, dp.BILL_MONTH_YEAR,
         dp.BILL_CREATE_MONTH_DATE, dp.BILL_CREATE_CUSTOM_DATE_FORMATTED
