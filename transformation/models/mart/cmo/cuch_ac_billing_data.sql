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

stg_claim_detail_bill AS (
    SELECT * FROM {{ ref('stg_dwacs__vw_claim_detail_bill') }}
),

nco_deduped AS (
    SELECT
        norm_other_names,
        SP_NAME,
        salesforce_name,
        salesforce_id,
        sf_link_id,
        ROW_NUMBER() OVER (PARTITION BY norm_other_names ORDER BY rn_norm ASC) AS RN
    FROM stg_nco
    QUALIFY RN = 1
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
        clean_client_name,
        BE_ID,
        AE_ID,
        ROW_NUMBER() OVER (PARTITION BY clean_client_name ORDER BY ACCTG_PERIOD_DT DESC) AS RN
    FROM stg_legal_entities
    WHERE ACCTG_PERIOD_DT >= '2025-01-01'
    QUALIFY RN = 1
),

base_data AS (
    SELECT
        ac.ODS_CUSTOMER_ID,
        ac.CUSTOMER_NAME,
        ac.COMPANY,
        ac.BILL_ID,
        ac.PROVIDER_CHARGES,
        ac.BILL_CREATE_DATE_MONTH,
        ac.BILL_CREATE_DATE_YEAR
    FROM stg_claim_detail_bill ac
    WHERE ac.BILL_CREATE_DATE >= '2025-01-01'
      AND ac.BILL_CREATE_DATE < DATE_TRUNC('MONTH', CURRENT_DATE()) + INTERVAL '1 MONTH'
      AND ac.COMPANY_ID >= 0
),

joined AS (
    SELECT
        nco.SP_NAME,
        nco.salesforce_name,
        nco.salesforce_id,
        nco.sf_link_id,
        cust.CUSTENTITY_MI_CLEAN_CLIENT_NAME AS clean_client_name,
        le_deduped.BE_ID,
        bd.ODS_CUSTOMER_ID,
        bd.CUSTOMER_NAME,
        bd.COMPANY,
        bd.BILL_ID,
        bd.PROVIDER_CHARGES,
        bd.BILL_CREATE_DATE_MONTH,
        bd.BILL_CREATE_DATE_YEAR
    FROM base_data bd
    LEFT JOIN nco_deduped nco
        ON nco.norm_other_names = REPLACE(LOWER(bd.CUSTOMER_NAME), ' ', '')
    LEFT JOIN NS_CUSTOMER cust
        ON cust.normalized_company = REPLACE(LOWER(bd.COMPANY), ' ', '')
    LEFT JOIN le_deduped
        ON le_deduped.clean_client_name = cust.CUSTENTITY_MI_CLEAN_CLIENT_NAME
)

SELECT
    SP_NAME,
    salesforce_name AS SALESFORCE_NAME,
    salesforce_id AS SALESFORCE_ID,
    sf_link_id AS SF_LINK_ID,
    LISTAGG(DISTINCT clean_client_name, ', ') WITHIN GROUP (ORDER BY clean_client_name) AS CLEAN_CLIENT_NAME,
    MAX(BE_ID) AS BE_ID,
    TO_DATE(
        CONCAT('01', '-', LPAD(NVL(BILL_CREATE_DATE_MONTH, 1), 2, '0'), '-', NVL(BILL_CREATE_DATE_YEAR, YEAR(CURRENT_DATE()))),
        'DD-MM-YYYY'
    ) AS BILL_CREATE_DATE,
    TO_CHAR(
        TO_DATE(
            CONCAT('01', '-', LPAD(NVL(BILL_CREATE_DATE_MONTH, 1), 2, '0'), '-', NVL(BILL_CREATE_DATE_YEAR, YEAR(CURRENT_DATE()))),
            'DD-MM-YYYY'
        ),
        'DD-MM-YYYY'
    ) AS BILL_CREATE_DATE_FORMATTED,
    LISTAGG(DISTINCT ODS_CUSTOMER_ID, ', ') WITHIN GROUP (ORDER BY ODS_CUSTOMER_ID) AS ODS_CUSTOMER_IDS,
    LISTAGG(DISTINCT CUSTOMER_NAME, ', ') WITHIN GROUP (ORDER BY CUSTOMER_NAME) AS CUSTOMER_NAMES,
    LISTAGG(DISTINCT COMPANY, ', ') WITHIN GROUP (ORDER BY COMPANY) AS COMPANIES,
    COUNT(DISTINCT BILL_ID) AS BILL_COUNT,
    SUM(PROVIDER_CHARGES) AS TOTAL_PROVIDER_CHARGES
FROM joined
WHERE SP_NAME IS NOT NULL
GROUP BY SP_NAME, salesforce_name, salesforce_id, sf_link_id, BILL_CREATE_DATE_MONTH, BILL_CREATE_DATE_YEAR
ORDER BY BILL_COUNT DESC
