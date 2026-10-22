with source as (

    select * from {{ source('dwctshex', 'wcs_client_breakouts') }}

),

renamed as (

    select
        "SiteCode" AS sitecode,
        "SiteCodeDescription" AS sitecodedescription,
        "ControlNum" AS controlnum,
        "ControlNumDescription" AS controlnumdescription,
        groupingtype,
        final_name

    from source

)

select * from renamed