{#-
    flatten_adaptive_fact
    ---------------------
    Turns one Adaptive fact table (with a MONTHLY_DATA VARIANT of
    {"MM/YYYY": amount}) into a long, one-row-per-month staging relation.

    Month-agnostic by design: LATERAL FLATTEN reads whatever period keys exist
    in each row, so new months (e.g. 01/2027) flow through automatically and
    rolled-off months simply stop appearing -- no model change is ever required
    as the calendar advances.

    Args:
      source_name   dbt source name (e.g. 'adaptive')
      source_table  raw table name  (e.g. 'adaptive_actuals_raw')
      scenario      scenario literal ('ACTUAL' | 'BUDGET' | 'OUTLOOK')
      budget_year   optional int; set only for budget tables, else NULL
      version_name  Adaptive version this table was exported from; joins to
                    dim_adaptive_version.version_name
-#}
{% macro flatten_adaptive_fact(source_name, source_table, scenario, budget_year=none, version_name=none) %}

with source as (
    select * from {{ source(source_name, source_table) }}
),

-- Defensive: OpenFlow full-replaces per load, but if it ever appends we still
-- take only the most recent load so the mart reflects current state.
latest_load as (
    select *
    from source
    where load_timestamp = (select max(load_timestamp) from source)
),

flattened as (
    select
        account_code,
        account_name,
        level_code,
        level_name,
        nullif(item_code_name, '- None -')                         as item_code_name,
        clean_customer_name,
        '{{ scenario }}'::varchar                                  as scenario,
        {% if budget_year is not none %}{{ budget_year }}{% else %}null{% endif %}::number(4,0) as budget_year,
        {% if version_name is not none %}'{{ version_name }}'{% else %}null{% endif %}::varchar as version_name,
        to_date(m.key, 'MM/YYYY')                                 as period_month,
        m.value::float                                            as amount,
        '{{ source_table }}'::varchar                             as source_table,
        load_timestamp                                            as load_ts
    from latest_load,
         lateral flatten(input => monthly_data) m
    where m.key rlike '^[0-9]{2}/[0-9]{4}$'   -- months only; excludes quarter/year rollup keys if they ever appear
      and m.value is not null                  -- drop SQL NULLs
      and not is_null_value(m.value)           -- drop JSON nulls (VARIANT null is NOT sql null) -> would cast to NULL amount
)

select * from flattened

{% endmacro %}
