with source as (
  select
    *
  from
    {{source('dwctshexraw', 'hex_auditlog') }}
),
renamed as (
  select
    file_name,
    raw_json,
    loaded_at
  from source
)
select
  *
from
  renamed
