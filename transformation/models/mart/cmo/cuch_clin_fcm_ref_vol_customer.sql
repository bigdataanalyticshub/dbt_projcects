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

stg_cms_cases AS (
    SELECT * FROM {{ ref('stg_genexodsdmcmsusr__cms_cases_all_v_normalized') }}
),

stg_genex_mapping AS (
    SELECT * FROM {{ ref('stg_anlysandboxtemp_clinical_genex_be_c_code_mapping_extract') }}
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
)

SELECT
    nco.SP_NAME,
    nco.salesforce_name,
    nco.salesforce_id,
    nco.sf_link_id,
    YEAR(c.date_of_referral) AS REFERRAL_DATE_OF_LOSS_YEAR,
    MONTH(c.date_of_referral) AS REFERRAL_DATE_OF_LOSS_MONTH,
    TO_DATE(
        CONCAT('01', '-', LPAD(NVL(MONTH(c.date_of_referral), 1), 2, '0'), '-', NVL(YEAR(c.date_of_referral), YEAR(CURRENT_DATE()))),
        'DD-MM-YYYY'
    ) AS REFERRAL_CREATE_DATE,
    TO_CHAR(
        TO_DATE(
            CONCAT('01', '-', LPAD(NVL(MONTH(c.date_of_referral), 1), 2, '0'), '-', NVL(YEAR(c.date_of_referral), YEAR(CURRENT_DATE()))),
            'DD-MM-YYYY'
        ),
        'DD-MM-YYYY'
    ) AS REFERRAL_CREATE_DATE_FORMATTED,
    LISTAGG(DISTINCT
        CASE WHEN c.CUSTOMER_ACCOUNTING_NUMBER IN ('C93941','C00986','C95175','CGALLA') THEN c.EMPLOYER_NAME ELSE c.CUSTOMER_NAME END, ', '
    ) WITHIN GROUP (ORDER BY
        CASE WHEN c.CUSTOMER_ACCOUNTING_NUMBER IN ('C93941','C00986','C95175','CGALLA') THEN c.EMPLOYER_NAME ELSE c.CUSTOMER_NAME END
    ) AS CUSTOMER_NAMES,
    LISTAGG(DISTINCT c.customer_accounting_number, ', ') WITHIN GROUP (ORDER BY c.customer_accounting_number) AS C_CODES,
    LISTAGG(DISTINCT gen.BE_ID, ', ') WITHIN GROUP (ORDER BY gen.BE_ID) AS BE_IDS,
    LISTAGG(DISTINCT gen.BE_NAME, ', ') WITHIN GROUP (ORDER BY gen.BE_NAME) AS BE_NAMES,
    LISTAGG(DISTINCT gen.genex_e_code, ', ') WITHIN GROUP (ORDER BY gen.genex_e_code) AS E_CODES,
    COUNT(*) AS referral_volume_count,
    MIN(c.date_of_referral) AS first_referral_date,
    MAX(c.date_of_referral) AS latest_referral_date
FROM stg_cms_cases c
LEFT JOIN stg_nco nco
    ON nco.RN_NORM = 1
    AND nco.NORM_OTHER_NAMES =
        CASE WHEN c.CUSTOMER_ACCOUNTING_NUMBER IN ('C93941','C00986','C95175','CGALLA') THEN
            CASE
                WHEN EXISTS (SELECT 1 FROM stg_nco WHERE NORM_OTHER_NAMES = REPLACE(LOWER(c.EMPLOYER_NAME), ' ', '') AND RN_NORM = 1)
                    THEN REPLACE(LOWER(c.EMPLOYER_NAME), ' ', '')
                WHEN EXISTS (SELECT 1 FROM stg_nco WHERE NORM_OTHER_NAMES = LOWER(SPLIT_PART(c.EMPLOYER_NAME, ' ', 1) || SPLIT_PART(c.EMPLOYER_NAME, ' ', 2)) AND RN_NORM = 1)
                    THEN LOWER(SPLIT_PART(c.EMPLOYER_NAME, ' ', 1) || SPLIT_PART(c.EMPLOYER_NAME, ' ', 2))
                ELSE LOWER(SPLIT_PART(c.EMPLOYER_NAME, ' ', 1))
            END
        ELSE
            CASE
                WHEN EXISTS (SELECT 1 FROM stg_nco WHERE NORM_OTHER_NAMES = REPLACE(LOWER(c.CUSTOMER_NAME), ' ', '') AND RN_NORM = 1)
                    THEN REPLACE(LOWER(c.CUSTOMER_NAME), ' ', '')
                WHEN EXISTS (SELECT 1 FROM stg_nco WHERE NORM_OTHER_NAMES = LOWER(SPLIT_PART(c.CUSTOMER_NAME, ' ', 1) || SPLIT_PART(c.CUSTOMER_NAME, ' ', 2)) AND RN_NORM = 1)
                    THEN LOWER(SPLIT_PART(c.CUSTOMER_NAME, ' ', 1) || SPLIT_PART(c.CUSTOMER_NAME, ' ', 2))
                ELSE LOWER(SPLIT_PART(c.CUSTOMER_NAME, ' ', 1))
            END
        END
INNER JOIN stg_genex_mapping gen
    ON c.CUSTOMER_ACCOUNTING_NUMBER = gen.GENEX_C_CODE
LEFT JOIN le_deduped ON gen.BE_ID = le_deduped.BE_ID
WHERE c.date_of_referral >= '2025-01-01'
  AND c.date_of_referral < DATE_TRUNC('MONTH', CURRENT_DATE()) + INTERVAL '1 MONTH'
  AND c.exclude_case_flag IS NULL
  AND c.bob_exclude_case_flag IS NULL
  AND c.REFERRAL_TYPE_DESCRIPTION IN (
      'Referral Type Description','20/20 Claims','Alternative Transitional Duty','Audit',
      'CAT Rollover to Medical Field','CAT Reopened as Medical Field','Care Abroad Intl',
      'Crisis Intervention','COV Medical Director Review','COV Treatment Review',
      'Employer Dedicated Case Manager','Employer Services','Ergonomics','FCM Multiple Case Billing',
      'FCM Telephonic','FCM File Review','Life Care Plan','Medicare Setaside Cost Proj',
      'Long-Term CAT Assessment','MCO CAT Rollover Medical Field','MCO Medical Field','MCO Medical Task',
      'Medical - Field','Medical Field Billing','Medical - Catastrophic','Med Cat Reopened as Task',
      'FCM Medical Finite','Medical FCM Limited','Task Rollover to Med FCM Limited',
      'MEDLIM Rollover to Medical Field','Medical Field No Travel','Task Rollover to Medical Field',
      'Medical - Task Assignment','MN QRC Medical','MN QRC Vocational Intern','MN QRC Vocational',
      'Multiple Task Assignment','Narcotic Intervention Task FCM','Occupational Therapy/Kinesiology',
      'Physical Demands Analysis','Medication Management Task','Professional Review','Pharmacy Utilization Review',
      'Reserve Setting/Cost Projection','Return to Work Coordinator','RTW Program Development',
      'SFC Limited Assignment','TRAVELERS Telephonic F','Catastrophic Program Triage','TSA/LMS',
      'Urgent After Hours Task','Vocational','Vocational - Task Assignment'
  )
GROUP BY nco.SP_NAME, nco.salesforce_name, nco.salesforce_id, nco.sf_link_id,
         YEAR(c.date_of_referral), MONTH(c.date_of_referral), REFERRAL_CREATE_DATE
ORDER BY nco.SP_NAME, REFERRAL_CREATE_DATE DESC
