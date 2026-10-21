with source as (

    select * from {{ source('cvtdwcommon', 'clnt_br_system_usr_src') }}

),

renamed as (

    select
        be_id,
        clnt_nm,
        br_system_nm,
        dw_created_dt,
        dw_updated_dt,
        dw_updated_by,
        comnt

    from source

)

select * from renamed