-- Fails if any Adaptive fact table has a MONTHLY_DATA key that is NOT a
-- MM/YYYY month yet still carries a non-null value. Those keys (e.g. quarter
-- or year rollup keys from Adaptive's timeRollups) are intentionally dropped
-- by the staging flatten; this test surfaces them so a silent data drop is
-- caught rather than missed.
{% set fact_sources = [
    'adaptive_actuals_raw',
    'adaptive_budget_2025_raw',
    'adaptive_budget_2026_raw',
    'adaptive_outlook_raw',
] %}

{% for tbl in fact_sources %}
select
    '{{ tbl }}'::varchar as source_table,
    m.key               as offending_key,
    m.value             as offending_value
from {{ source('adaptive', tbl) }},
     lateral flatten(input => monthly_data) m
where not m.key rlike '^[0-9]{2}/[0-9]{4}$'
  and m.value is not null
  and not is_null_value(m.value)
{% if not loop.last %}union all{% endif %}
{% endfor %}
