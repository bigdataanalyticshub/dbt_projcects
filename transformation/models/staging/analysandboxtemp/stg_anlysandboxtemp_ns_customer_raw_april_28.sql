with source as (
    select * from {{ source('anlyssandboxtemp', 'ns_customer_raw_april_28') }}
),

renamed as (
    select
        companyname,
        custentity_mi_clean_client_name,
        entitynumber,
        custentity_mi_sfdc_org_id,
        category,
        id
    from source
)

select * from renamed