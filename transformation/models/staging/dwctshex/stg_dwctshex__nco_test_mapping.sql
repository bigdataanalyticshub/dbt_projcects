with source as (
  select
    *
  from
    {{source('dwctshex', 'nco_test_mapping') }}
),
renamed as (
  select
    SP_NAME,
    SP_NAME_LOB,
    SALESFORCE_NAME,
    SALESFORCE_ID,
    SF_LINK_ID,
    NAME_NO,
    OTHER_NAMES,
    OTHER_NAMES_LOWER,
    RN_LOWER,
    NORM_OTHER_NAMES,
    RN_NORM
  from source
)
select
  *
from
  renamed
