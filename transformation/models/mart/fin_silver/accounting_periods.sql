{{
    config(
        materialized='incremental',
        unique_key='ORIGINAL_ACCOUNTING_ID'
    )
}}

WITH

-- Import CTEs
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

-- Logical CTEs
distinct_accounting_periods AS (
    SELECT DISTINCT ACCTG_PERIOD_ID AS API
    FROM stg_irmsods__irms_transaction
),

-- Final CTE
final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['API']) }} AS ID,
        CAST(API AS VARCHAR) AS ORIGINAL_ACCOUNTING_ID,
        CAST('MONTHLY' AS VARCHAR) AS PERIOD_TYPE,
        TO_CHAR(TO_DATE(CONCAT(SUBSTRING(API,1,4),SUBSTRING(API,5,2), '01'), 'YYYYMMDD'), 'YYYYMMDD') AS START_DATE,
        TO_CHAR(LAST_DAY(TO_DATE(CONCAT(SUBSTRING(API,1,4),SUBSTRING(API,5,2), '01'), 'YYYYMMDD' )), 'YYYYMMDD') AS END_DATE
    FROM distinct_accounting_periods
)

SELECT * FROM final
WHERE ORIGINAL_ACCOUNTING_ID IS NOT NULL