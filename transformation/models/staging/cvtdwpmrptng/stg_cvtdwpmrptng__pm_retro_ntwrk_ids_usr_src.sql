with source as (

    select * from {{ source('cvtdwpmrptng', 'pm_retro_ntwrk_ids_usr_src') }}

),

renamed as (

    select
        ppo_ntwrk_id,
        ntwrk_desc,
        dw_actv_indc,
        dw_created_dt,
        dw_updated_dt,
        dw_updated_by,
        comnt

    from source

)

select * from renamed