with source as (

    select * from {{ source('cvtdwcprrptng', 'cpr_clnt_prodt_state') }}

),

renamed as (

    select
        ae_id,
        prodt_cd,
        state_cd,
        clnt_acro,
        ae_nm,
        be_id,
        be_nm,
        ntwrk_prodt_rptng_desc,
        ntwrk_rptng_class_desc,
        prodt_config,
        prodt_intent,
        rptng_exclusn_cd,
        state_cnt,
        ntwrk_cnt,
        acro_eff_dt,
        acro_end_dt,
        dw_created_dt,
        dw_updated_dt

    from source

)

select * from renamed