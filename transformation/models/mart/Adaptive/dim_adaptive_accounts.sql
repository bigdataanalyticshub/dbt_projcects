-- Account dimension for analyst joins. Keyed on account_code (the code the
-- fact carries). Raw accounts have a few codes shared across account_ids, so
-- we deterministically keep one row per code.
with accounts as (
    select * from {{ ref('stg_adaptive__accounts') }}
)

select
    account_code,
    account_id,
    account_name,
    account_description,
    hierarchy_path,
    account_type_code,
    sub_type,
    balance_type,
    data_entry_type,
    short_name,
    time_stratum,
    is_assumption,
    is_group,
    is_system,
    has_formula
from accounts
qualify row_number() over (partition by account_code order by account_id) = 1
