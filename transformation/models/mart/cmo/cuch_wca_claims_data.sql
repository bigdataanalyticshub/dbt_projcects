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

stg_wcs_bill AS (
    SELECT * FROM {{ ref('stg_dwwcs__vw_claim_detail_bill') }}
),

stg_wcs_breakouts AS (
    SELECT * FROM {{ ref('stg_dwctshex__wcs_client_breakouts') }}
),

wcs_base AS (
    SELECT
        ODS_CUSTOMER_ID,
        CUSTOMER_NAME,
        site_code,
        control_number,
        claim_system_description,
        product_code,
        CLAIM_NO,
        BILL_CREATE_DATE_YEAR,
        BILL_CREATE_DATE_MONTH,
        provider_charges
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

joined AS (
    SELECT
        nco.sp_name AS SP_NAME,
        nco.sp_name_lob AS SP_NAME_LOB,
        nco.salesforce_name AS SALESFORCE_NAME,
        nco.salesforce_id AS SALESFORCE_ID,
        nco.sf_link_id AS SF_LINK_ID,
        wcs_base.ODS_CUSTOMER_ID,
        wcs_base.CUSTOMER_NAME,
        le_deduped.clean_client_number AS CLEAN_CLIENT_NUMBER,
        le_deduped.clean_client_name AS CLEAN_CLIENT_NAME,
        le_deduped.BE_ID,
        le_deduped.AE_ID,
        wcs_base.CLAIM_NO,
        wcs_base.BILL_CREATE_DATE_YEAR,
        wcs_base.BILL_CREATE_DATE_MONTH,
        wcs_base.provider_charges
    FROM wcs_base
    LEFT JOIN stg_wcs_breakouts m
        ON (m.GROUPINGTYPE = 'Ctrl' AND wcs_base.site_code = m.SITECODE AND wcs_base.control_number = m.CONTROLNUM)
        OR (m.GROUPINGTYPE != 'Ctrl' AND wcs_base.site_code = m.SITECODE)
    LEFT JOIN stg_nco nco
        ON nco.norm_other_names =
            CASE
                WHEN EXISTS (SELECT 1 FROM stg_nco WHERE norm_other_names = REPLACE(LOWER(CASE WHEN m.GROUPINGTYPE = 'Clm' THEN CONCAT(m.FINAL_NAME, ' - ', wcs_base.claim_system_description) ELSE m.FINAL_NAME END), ' ', ''))
                    THEN REPLACE(LOWER(CASE WHEN m.GROUPINGTYPE = 'Clm' THEN CONCAT(m.FINAL_NAME, ' - ', wcs_base.claim_system_description) ELSE m.FINAL_NAME END), ' ', '')
                ELSE REPLACE(LOWER(wcs_base.customer_name), ' ', '')
            END
        AND nco.rn_norm = 1
    LEFT JOIN le_deduped ON wcs_base.ODS_CUSTOMER_ID = le_deduped.clean_client_number
)

SELECT
    SP_NAME,
    SP_NAME_LOB,
    SALESFORCE_NAME,
    SALESFORCE_ID,
    SF_LINK_ID,
    MAX(CLEAN_CLIENT_NUMBER) AS CLEAN_CLIENT_NUMBER,
    MAX(CLEAN_CLIENT_NAME) AS CLEAN_CLIENT_NAME,
    MAX(BE_ID) AS BE_ID,
    MAX(AE_ID) AS AE_ID,
    BILL_CREATE_DATE_YEAR,
    BILL_CREATE_DATE_MONTH,
    LPAD(BILL_CREATE_DATE_MONTH, 2, '0') || BILL_CREATE_DATE_YEAR AS BILL_MONTH_YEAR,
    TO_DATE(
        CONCAT('01', '-', LPAD(NVL(BILL_CREATE_DATE_MONTH, 1), 2, '0'), '-', NVL(BILL_CREATE_DATE_YEAR, YEAR(CURRENT_DATE()))),
        'DD-MM-YYYY'
    ) AS BILL_CREATE_MONTH_DATE,
    TO_CHAR(
        TO_DATE(
            CONCAT('01', '-', LPAD(NVL(BILL_CREATE_DATE_MONTH, 1), 2, '0'), '-', NVL(BILL_CREATE_DATE_YEAR, YEAR(CURRENT_DATE()))),
            'DD-MM-YYYY'
        ),
        'DD-MM-YYYY'
    ) AS BILL_CREATE_CUSTOM_DATE_FORMATTED,
    LISTAGG(DISTINCT ODS_CUSTOMER_ID, ', ') WITHIN GROUP (ORDER BY ODS_CUSTOMER_ID) AS ODS_CUSTOMER_IDS,
    LISTAGG(DISTINCT CUSTOMER_NAME, ', ') WITHIN GROUP (ORDER BY CUSTOMER_NAME) AS CUSTOMER_NAMES,
    COUNT(DISTINCT CLAIM_NO) AS CLAIM_COUNT,
    SUM(provider_charges) AS TOTAL_CHARGES
FROM joined
WHERE SP_NAME IS NOT NULL
GROUP BY SP_NAME, SP_NAME_LOB, SALESFORCE_NAME, SALESFORCE_ID, SF_LINK_ID,
         BILL_CREATE_DATE_YEAR, BILL_CREATE_DATE_MONTH
ORDER BY SP_NAME, SALESFORCE_ID, BILL_CREATE_DATE_YEAR, BILL_CREATE_DATE_MONTH
