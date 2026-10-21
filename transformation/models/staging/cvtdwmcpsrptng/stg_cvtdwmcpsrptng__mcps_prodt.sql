with source as (

    select * from {{ source('cvtdwmcpsrptng', 'mcps_prodt') }}

),

renamed as (

    select
        dw_mcps_prodt_row_id,
        mcps_prodt_cd,
        mcps_prodt_desc,
        edi_prodt_cd,
        edi_prodt_desc,
        prodt_type_cd,
        prodt_type_desc,
        prodt_form_type_cd,
        prodt_form_type_desc,
        prcng_meth_cd,
        prcng_meth_desc,
        svc_type_cd,
        svc_type_desc,
        case_type_cd,
        case_type_desc,
        market_rate_type_cd,
        market_rate_type_desc,
        excptn_cd,
        excptn_desc,
        msg_cd,
        msg_desc,
        prodt_lob_cd,
        prodt_lob_desc,
        ntwrk_catg_cd,
        ntwrk_catg_desc,
        adjmt_excptn_cd,
        adjmt_excptn_desc,
        idx_deflt_prodt_cd,
        idx_deflt_prodt_desc,
        jrsdctn_state_cd,
        spec_actn_rule_cd,
        rept_prodt_cd,
        prodt_eff_dt,
        prodt_trmntn_dt,
        severity_lvl_num,
        prodt_hrchy_rank,
        cntrctd_for_rptng_indc,
        override_no_prcng_indc,
        epsd_num_rqrd_indc,
        ntwrk_indc,
        ccmp_excptn_indc,
        market_rqrd_indc,
        cob_allwd_indc,
        prior_prodt_adjmt_indc,
        adjdctn_cntrctd_indc,
        use_anlys_state_indc,
        disable_if_prov_exclusn_indc,
        tx_hcn_indc,
        use_wcfs_for_svngs_indc,
        retain_prodt_cd_on_adjmt_indc,
        billl_lvl_svngs_indc,
        obn_fee_only_indc,
        out_of_ntwrk_indc,
        bypass_obn_indc,
        tin_switch_indc,
        dw_actv_indc,
        dw_chk_sum_key,
        dw_created_dt,
        dw_updated_dt,
        rtl_indc,
        extrnl_type_cd,
        ntwrk_cntrct_attrbt,
        obn_prodt_indc,
        prov_payment_indc

    from source

)

select * from renamed