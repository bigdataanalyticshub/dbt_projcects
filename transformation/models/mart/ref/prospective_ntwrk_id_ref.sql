{{
  config(
    materialized='table'
  )
}}

WITH

stg_dwwcs__vw_claim_detail_billline as (
    select * from {{ ref('stg_dwwcs__vw_claim_detail_billline') }}
),

manual_network_name_mappings AS (
    SELECT
        'ADVA-NET' AS genex_network_name,
        'ADVANET' AS conformed_network_name
    UNION ALL
    SELECT
        'ONE CALL CARE MANAGEMENT',
        'ONECALL/ALIGN'
    UNION ALL
    SELECT
        'SELECT PT',
        'SELECT PROVIDER'
    UNION ALL
    SELECT
        'STREAMLINE DIAGNOSTICS',
        'STREAMLINE'
),

final as (
    SELECT
        p.genex_network_id AS ntwrk_id,
        p.genex_network_name AS src_ntwrk_name,
        p.genex_network_subtype_code,
        COALESCE(m.conformed_network_name, UPPER(p.genex_network_name))
            AS conf_ntwrk_name
    FROM stg_dwwcs__vw_claim_detail_billline AS p
    LEFT JOIN manual_network_name_mappings AS m
        ON UPPER(p.genex_network_name) = m.genex_network_name
    WHERE
        p.network_service_type = 'Prospective'
        AND p.genex_network_id IS NOT NULL
    GROUP BY
        p.genex_network_id,
        p.genex_network_name,
        p.genex_network_subtype_code,
        COALESCE(m.conformed_network_name, UPPER(p.genex_network_name))
    ORDER BY
        conf_ntwrk_name,
        src_ntwrk_name,
        ntwrk_id
)

SELECT * FROM final