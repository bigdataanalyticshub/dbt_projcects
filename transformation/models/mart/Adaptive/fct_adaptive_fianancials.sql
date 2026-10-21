-- Unified long financial fact for analysts: one row per
-- (scenario, budget_year, account, level, item, customer, month).
--
-- Extensible by design: to add a future budget year (e.g. 2027), create
-- stg_adaptive__budget_2027 and add one ref() line to fact_models below.
{% set fact_models = [
    ref('stg_adaptive__actuals'),
    ref('stg_adaptive__budget_2025'),
    ref('stg_adaptive__budget_2026'),
    ref('stg_adaptive__outlook'),
] %}

with unioned as (
{% for m in fact_models %}
    select * from {{ m }}
    {%- if not loop.last %}
    union all
    {% endif %}
{% endfor %}
)

select
    {{ dbt_utils.generate_surrogate_key([
        'scenario',
        'budget_year',
        'account_code',
        'level_code',
        'item_code_name',
        'clean_customer_name',
        'period_month'
    ]) }} as financial_key,
    scenario,
    budget_year,
    version_name,
    account_code,
    account_name,
    level_code,
    level_name,
    item_code_name,
    clean_customer_name,
    period_month,
    amount,
    source_table,
    load_ts
from unioned
