{{ config(severity = 'warn') }}

-- Warns when a level code appears in the fact but is unknown to
-- dim_adaptive_level -- i.e. it is neither in the Adaptive levels export nor a
-- curated pseudo-level.
--
-- Such codes are still absorbed as synthetic "(Unmapped)" dimension members so
-- that no financial value is lost on an INNER JOIN, but they represent an
-- org-hierarchy gap that should be reviewed and then either mapped upstream or
-- added to the `pseudo` list in dim_adaptive_level.
--
-- EXPECTED BASELINE: zero rows. Level 4066 (Top Level "(only)", ~$620M) is now a
-- curated pseudo-level, so it does NOT appear here. Anything showing up is new.
-- See docs/orphan-level-4066.md.
select
    level_code,
    hierarchy_path
from {{ ref('dim_adaptive_level') }}
where is_unmapped_level
