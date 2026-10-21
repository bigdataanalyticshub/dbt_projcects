-- Account master. One row per account_id in the raw table (already unique).
-- Note: account_code is NOT unique here (a few codes map to multiple ids);
-- the code-level dedup for fact joins happens in dim_adaptive_account.
with source as (
    select * from {{ source('adaptive', 'adaptive_accounts_raw') }}
),

renamed as (
    select
        account_id,
        account_code,
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
        has_formula,
        load_timestamp as load_ts
    from source
)

select * from renamed
