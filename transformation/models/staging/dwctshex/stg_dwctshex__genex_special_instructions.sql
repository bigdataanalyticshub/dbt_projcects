with source as (
  select
    *
  from
    {{source('dwctshex', 'genex_special_instructions') }}
),
renamed as (
  select
    ITEM_ID,
    ITEM_TYPE,
    HOST_ENTITY,
    ACTIVE_DATE,
    EXPIRE_DATE,
    INSERTED_BY,
    COMMENTS
  from source
)
select
  *
from
  renamed
