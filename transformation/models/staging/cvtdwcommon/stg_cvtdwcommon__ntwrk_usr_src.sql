with source as (

    select * from {{ source('cvtdwcommon', 'ntwrk_usr_src') }}

),

renamed as (

    select
        dw_ntwrk_row_id,
        ntwrk_cd,
        ntwrk_desc,
        sbntwrk_cd,
        sbntwrk_desc,
        dw_eff_dt,
        dw_trmntn_dt,
        ref_data_revw_cd,
        revw_by_user_login_nm_cd,
        revw_dt,
        revw_comnt,
        override_contract_flag,
        ntwrk_secure_ind,
        ntwrk_type_desc,
        ntwrk_class_desc

    from source

)

select * from renamed