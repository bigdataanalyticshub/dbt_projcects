-- Fails if a new table appears in EBT_ODS.ADAPTIVE that is not declared as a
-- source here. Protects against a future ADAPTIVE_* table (e.g. a new budget
-- year) silently going missing from the pipeline.
with existing as (
    select table_name
    from EBT_ODS.information_schema.tables
    where table_schema = 'ADAPTIVE'
      and table_type = 'BASE TABLE'
),

modeled as (
    select column1 as table_name from values
        ('ADAPTIVE_ACTUALS_RAW'),
        ('ADAPTIVE_BUDGET_2025_RAW'),
        ('ADAPTIVE_BUDGET_2026_RAW'),
        ('ADAPTIVE_OUTLOOK_RAW'),
        ('ADAPTIVE_ACCOUNTS_RAW'),
        ('ADAPTIVE_LEVELS_RAW'),
        ('ADAPTIVE_DIMENSIONS_RAW'),
        ('ADAPTIVE_VERSIONS_RAW')
)

select e.table_name
from existing e
left join modeled m on upper(e.table_name) = m.table_name
where m.table_name is null
