{{
    config(
        materialized='incremental',
        unique_key='LIN_OF_BUS_CD'
    )
}}

WITH

-- Import CTEs
stg_irmsods__lin_of_bus_r AS (
    SELECT * FROM {{ ref('stg_irmsods__lin_of_bus_r') }}
),
-- Logical CTEs

-- Final CTE
final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['LIN_OF_BUS_CD']) }} AS ID,
        LIN_OF_BUS_CD,
        NULL AS BUSINESS_UNIT_ID,
        LIN_OF_BUS_DESC AS NAME
    FROM stg_irmsods__lin_of_bus_r
)

SELECT * FROM final
WHERE LIN_OF_BUS_CD IS NOT NULL