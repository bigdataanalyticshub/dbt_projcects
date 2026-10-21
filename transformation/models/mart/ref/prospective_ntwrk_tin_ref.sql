{{
  config(
    materialized='table'
  )
}}

WITH

stg_cvtdwpmrptng__pm_pro_ntwrk_tins_usr_src as (
    select * from {{ ref('stg_cvtdwpmrptng__pm_pro_ntwrk_tins_usr_src') }}
),

apricus_mappings AS (
    SELECT
        prov_tin,
        pro_ntwrk,
        pro_ntwrk_desc
    FROM stg_cvtdwpmrptng__pm_pro_ntwrk_tins_usr_src
),

manual_tin_network_mappings AS (
    SELECT
        '852636784' AS provider_tin,
        'STREAMLINE' AS source_network_name
    UNION ALL
    SELECT
        '460721022',
        'PHYSNET'
    UNION ALL
    SELECT
        '421571782',
        'HEALTH E SYSTEMS'
),

tin_network_mappings AS (
    SELECT
        prov_tin AS provider_tin,
        UPPER(pro_ntwrk) AS source_network_name,
        pro_ntwrk_desc AS source_network_description
    FROM apricus_mappings

    UNION ALL

    SELECT
        m.provider_tin,
        UPPER(m.source_network_name) AS source_network_name,
        'Manual mapping' AS source_network_description
    FROM manual_tin_network_mappings AS m
    WHERE NOT EXISTS (
        SELECT 1
        FROM apricus_mappings AS p
        WHERE p.prov_tin = m.provider_tin
    )
),

final AS (
    SELECT
        provider_tin AS ntwrk_tin,
        source_network_name AS src_ntwrk_name,
        source_network_description AS apricus_ntwrk_desc,
        source_network_name AS conf_ntwrk_name
    FROM tin_network_mappings
    ORDER BY
        conf_ntwrk_name,
        src_ntwrk_name,
        ntwrk_tin
)

SELECT * FROM final