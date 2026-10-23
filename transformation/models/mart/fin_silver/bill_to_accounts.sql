{{
    config(
        materialized='incremental',
        unique_key='BUS_ENT_ID'
    )
}}

WITH

-- Import CTEs
stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__bus_ent_clnt_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent_clnt_mpng') }}
),

-- Logical CTEs
bus_ent_clnt_mpng_filtered AS (
    SELECT
        bus_ent_id,
        clnt_cd,
        clnt_src
    FROM stg_irmsods__bus_ent_clnt_mpng
    WHERE CLNT_SRC = 'GNXECODE'
),

-- Final CTE
final AS (
    SELECT
        {{ dbt_utils.generate_surrogate_key(['BE.BUS_ENT_ID']) }} AS ID,
        BE.BUS_ENT_ID,
        BE.ADMIN_TYP_CD,
        BE.BUS_ENT_NM,
        BE.INV_NM,
        BE.SECTOR_CD,
        BE.LGL_ENT_CD,
        BE.DEPT,
        BE.OPRTNG_UNIT,
        BE.CNTRCT_ENT_FLG,
        BE.CNTRCTD_BUS_ENT_ID,
        BE.NS_CUST_ID,
        BEM.CLNT_SRC,
        BEM.CLNT_CD
    FROM stg_irmsods__bus_ent BE
    LEFT JOIN bus_ent_clnt_mpng_filtered BEM ON BE.BUS_ENT_ID = BEM.BUS_ENT_ID
)

SELECT * FROM final
WHERE BUS_ENT_ID IS NOT NULL
