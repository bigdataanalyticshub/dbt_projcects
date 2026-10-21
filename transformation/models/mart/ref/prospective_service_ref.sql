{{
  config(
    materialized='table'
  )
}}

WITH

stg_dwwcs__vw_claim_detail_billline as (
    select * from {{ ref('stg_dwwcs__vw_claim_detail_billline') }}
),

mapped_services as (
    SELECT
        procedure_code,
        CASE
            WHEN
                service_code_group = 'Physical Medicine'
                THEN 'PM - Physical Medicine'
            WHEN
                service_code_category = 'DURABLE MEDICAL EQUIPMENT'
                THEN 'DME - Durable Medical Equipment'
            WHEN
                (
                    service_code_category
                    = 'AMBULANCE AND OTHER TRANSPORT SERVICES AND SUPPLIES'
                    OR procedure_code IN ('T1013', '0T1013')
                )
                THEN 'TT - Translation/Transportation'
            WHEN
                service_code_category = 'HOME HEALTH SERVICES'
                THEN 'HH - Home Health'
            WHEN
                service_code_sub_category IN (
                    'DIAGNOSTIC ULTRASOUND PROCEDURES',
                    'DIAGNOSTIC RADIOLOGY (DIAGNOSTIC IMAGING) PROCEDURES'
                )
                THEN 'DX - Diagnostics'
        END AS service_category
    FROM stg_dwwcs__vw_claim_detail_billline
    WHERE post_date >= DATEADD(MONTH, -14, CURRENT_DATE)
),

primary_mapping as (
    SELECT DISTINCT
        service_category,
        procedure_code
    FROM mapped_services
    WHERE service_category IS NOT NULL
),

remove_duplicates as (
    SELECT
        procedure_code,
        COUNT(DISTINCT service_category) AS apricus_category_count,
        LISTAGG(DISTINCT service_category, ', ')
        WITHIN GROUP (ORDER BY service_category) AS apricus_categories
    FROM primary_mapping
    GROUP BY procedure_code
    HAVING COUNT(DISTINCT service_category) > 1
),

final AS (
    SELECT *
    FROM primary_mapping
    WHERE
        procedure_code NOT IN (
            SELECT DISTINCT procedure_code FROM remove_duplicates
        )
)

SELECT * FROM final