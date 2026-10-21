-- Level (org structure) master. The raw table is attribute-exploded
-- (~12 attribute rows per level), so we collapse to one row per level_id.
--
-- IMPORTANT: in the raw table, LEVEL_NAME holds the Adaptive level *code*
-- (e.g. '032_XXX_620_132'), which is exactly what the fact tables carry in
-- LEVEL_CODE. We surface it as level_code so it joins to the facts. (The
-- fact's own LEVEL_NAME is a human label like 'CLNCL - IME - ... - EXAM REV'
-- and does NOT correspond to this table's LEVEL_NAME.)
--
-- Attribute detail is intentionally dropped here; add a bridge model later
-- if analysts need level attributes.
with source as (
    select * from {{ source('adaptive', 'adaptive_levels_raw') }}
),

deduped as (
    select
        level_name      as level_code,   -- raw LEVEL_NAME is the Adaptive level code
        level_id,
        currency,
        hierarchy_path,
        load_timestamp  as load_ts
    from source
    qualify row_number() over (partition by level_id order by load_timestamp desc) = 1
)

select * from deduped
