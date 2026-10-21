with source as (

    select * from {{ source('cvtdwpmrptng', 'pm_pro_ntwrk_tins_usr_src') }}

),

renamed as (

    select
        prov_tin,
        pro_ntwrk,
        pro_ntwrk_desc,
        dw_actv_indc,
        dw_created_dt,
        dw_updated_dt,
        dw_updated_by,
        comnt

    from source

)

select * from renamed