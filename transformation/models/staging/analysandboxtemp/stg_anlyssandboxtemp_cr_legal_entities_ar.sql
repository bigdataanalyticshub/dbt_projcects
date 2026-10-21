with source as (
    select * from {{ source('anlyssandboxtemp', 'cr_legal_entities_ar') }}
),

renamed as (
    select
        acctg_period_dt,
        period,
        inv_dt,
        clean_client_number,
        clean_client_name,
        lgl_ent_cd,
        lgl_ent_desc,
        lob_cd,
        be_id,
        be_name,
        ae_id,
        src_syst_cd,
        total_balance,
        days_old,
        from_0_to_30,
        from_31_to_60,
        from_61_to_90,
        from_91_to_180,
        from_181_to_364,
        from_365_to_719,
        more_than_719,
        processed_date
    from source
)

select * from renamed