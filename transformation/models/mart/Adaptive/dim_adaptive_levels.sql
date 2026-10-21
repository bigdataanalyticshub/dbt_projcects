-- Level (org structure) dimension, one row per level.
-- Keyed on level_code, which joins to fct_adaptive_financials.level_code.
--
-- COMPLETENESS GUARANTEE: every level_code present in the facts resolves to a row
-- here, so an INNER JOIN from the fact can never silently drop financial value.
-- Members come from three places:
--
--   1. mapped   - the Adaptive levels export (the real org hierarchy).
--   2. pseudo   - curated entries for Adaptive data addresses that legitimately
--                 exist in exportData but that exportLevels cannot return. Today
--                 that is level_code 4066, the Top Level "(only)"/uncategorized
--                 address (~$620M of company-level figures: retained earnings,
--                 YTD earnings, pro forma adjustments). Adaptive's docs state
--                 "(only) levels don't have specific codes", so there is no real
--                 level row to join to. See docs/orphan-level-4066.md.
--   3. unmapped - a generic safety net for any OTHER code that shows up in the
--                 facts but is unknown here. Should normally be empty; the
--                 adaptive_unmapped_levels test warns if it is not.
--
-- Pseudo members are nested UNDER the real root ('Top_Level > ...') so they roll
-- up correctly in org-hierarchy reporting, while staying identifiable via
-- is_pseudo_level.
with mapped as (
    select
        level_code,
        level_id,
        currency,
        hierarchy_path,
        false as is_pseudo_level,
        false as is_unmapped_level
    from {{ ref('stg_adaptive__levels') }}
),

-- Curated pseudo-levels. Add a row here when Finance confirms another Adaptive
-- data address that the levels export cannot describe.
pseudo as (
    select
        p.level_code,
        cast(null as varchar) as level_id,
        cast(null as varchar) as currency,
        p.hierarchy_path,
        true                  as is_pseudo_level,
        false                 as is_unmapped_level
    from (
        select
            column1 as level_code,
            column2 as hierarchy_path
        from values
            ('4066', 'Top_Level > Top Level (Only)')
    ) p
    -- Never duplicate a code that the real export already provides.
    where not exists (select 1 from mapped m where m.level_code = p.level_code)
),

-- Safety net: anything in the facts we still cannot describe.
unmapped as (
    select
        f.level_code,
        cast(null as varchar)                                        as level_id,
        cast(null as varchar)                                        as currency,
        '(Unmapped) > ' || coalesce(max(f.level_name), f.level_code) as hierarchy_path,
        false                                                        as is_pseudo_level,
        true                                                         as is_unmapped_level
    from {{ ref('fct_adaptive_financials') }} f
    where f.level_code is not null
      and not exists (select 1 from mapped m where m.level_code = f.level_code)
      and not exists (select 1 from pseudo  p where p.level_code = f.level_code)
    group by f.level_code
)

select * from mapped
union all
select * from pseudo
union all
select * from unmapped
