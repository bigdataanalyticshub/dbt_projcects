with source as (
    select * from {{ source('anlyssandboxtemp', 'clinical_genex_be_c_code_mapping_extract') }}
),

renamed as (
    select
        be_id,
        be_name,
        genex_c_code,
        ae_id,
        ae_name,
        genex_e_code
    from source
)

select * from renamed