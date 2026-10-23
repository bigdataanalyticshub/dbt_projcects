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

stg_cid_reviews AS (
    SELECT * FROM {{ ref('stg_genexodscidreporting__rpt_cid_reviews_t') }}
),

nco_deduped AS (
    SELECT
        REGEXP_REPLACE(norm_other_names, '[^a-z0-9]', '') AS norm_other_names_clean,
        norm_other_names,
        SP_NAME,
        salesforce_name,
        salesforce_id,
        sf_link_id,
        ROW_NUMBER() OVER (PARTITION BY REGEXP_REPLACE(norm_other_names, '[^a-z0-9]', '') ORDER BY rn_norm ASC) AS RN
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
        ROW_NUMBER() OVER (PARTITION BY clean_client_name ORDER BY ACCTG_PERIOD_DT DESC) AS RN
    FROM stg_legal_entities
    WHERE ACCTG_PERIOD_DT >= '2025-01-01'
    QUALIFY RN = 1
),

base_data AS (
    SELECT
        CID_REVIEW_ID,
        C_CODE,
        CUSTOMER,
        EMPLOYER,
        E_CODE,
        UR_DECISION_DATE,
        YEAR(UR_DECISION_DATE) AS UR_YEAR,
        MONTH(UR_DECISION_DATE) AS UR_MONTH
    FROM stg_cid_reviews
    WHERE UR_DECISION_DATE >= '2025-01-01'
      AND UR_DECISION_DATE < DATE_TRUNC('MONTH', CURRENT_DATE()) + INTERVAL '1 MONTH'
      AND REVIEW_TYPE IN ('Initial Clinical Review', 'Peer Clinical Review')
      AND REVIEW_GROUP NOT IN ('Withdrawn', 'Decision Modified')
),

joined AS (
    SELECT
        nco.SP_NAME,
        nco.salesforce_name,
        nco.salesforce_id,
        nco.sf_link_id,
        cust.CUSTENTITY_MI_CLEAN_CLIENT_NAME AS clean_client_name,
        le.BE_ID,
        bd.CID_REVIEW_ID,
        bd.C_CODE,
        bd.CUSTOMER,
        bd.EMPLOYER,
        bd.E_CODE,
        bd.UR_DECISION_DATE,
        bd.UR_YEAR,
        bd.UR_MONTH
    FROM base_data bd
    LEFT JOIN nco_deduped nco ON nco.norm_other_names_clean = REGEXP_REPLACE(LOWER(bd.CUSTOMER), '[^a-z0-9]', '')
    LEFT JOIN NS_CUSTOMER cust ON cust.normalized_company = REPLACE(LOWER(bd.CUSTOMER), ' ', '')
    LEFT JOIN le_deduped le ON le.clean_client_name = cust.CUSTENTITY_MI_CLEAN_CLIENT_NAME
)

SELECT
    SP_NAME,
    salesforce_name AS SALESFORCE_NAME,
    salesforce_id AS SALESFORCE_ID,
    sf_link_id AS SF_LINK_ID,
    LISTAGG(DISTINCT clean_client_name, ', ') WITHIN GROUP (ORDER BY clean_client_name) AS CLEAN_CLIENT_NAME,
    MAX(BE_ID) AS BE_ID,
    UR_YEAR,
    UR_MONTH,
    LPAD(UR_MONTH, 2, '0') || UR_YEAR AS UR_MONTH_YEAR,
    TO_DATE(
        CONCAT('01', '-', LPAD(NVL(UR_MONTH, 1), 2, '0'), '-', NVL(UR_YEAR, YEAR(CURRENT_DATE()))),
        'DD-MM-YYYY'
    ) AS UR_MONTH_DATE,
    TO_CHAR(
        TO_DATE(
            CONCAT('01', '-', LPAD(NVL(UR_MONTH, 1), 2, '0'), '-', NVL(UR_YEAR, YEAR(CURRENT_DATE()))),
            'DD-MM-YYYY'
        ),
        'DD-MM-YYYY'
    ) AS UR_CUSTOM_DATE_FORMATTED,
    LISTAGG(DISTINCT C_CODE, ', ') WITHIN GROUP (ORDER BY C_CODE) AS C_CODES,
    LISTAGG(DISTINCT CUSTOMER, ', ') WITHIN GROUP (ORDER BY CUSTOMER) AS CUSTOMERS,
    COUNT(CID_REVIEW_ID) AS TOTAL_UR_REVIEWS
FROM joined
WHERE SP_NAME IS NOT NULL
GROUP BY SP_NAME, salesforce_name, salesforce_id, sf_link_id, UR_YEAR, UR_MONTH
ORDER BY SALESFORCE_NAME, UR_YEAR, UR_MONTH
