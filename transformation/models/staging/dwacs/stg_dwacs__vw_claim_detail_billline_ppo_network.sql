with source as (

    select * from {{ source('dwacs', 'vw_claim_detail_billline_ppo_network') }}

),

renamed as (

    select
        company,
        customer_name,
        ods_customer_id,
        office,
        run_date,
        applied_coverage_abbr,
        claim_date_of_loss,
        claim_date_of_loss_day,
        claim_date_of_loss_month,
        claim_date_of_loss_year,
        claim_date_of_loss_quarter,
        claim_id_no,
        claim_no,
        migrated_bill_flag,
        test_bill_flag,
        previous_coverage_type,
        soj,
        bill_create_date,
        bill_hdr_br_allowable,
        bill_hdr_provider_charges,
        bill_id,
        bill_line,
        cut_off_transaction_date,
        form_type,
        is_bill_manually_repriced,
        is_bill_recived_from_ppo,
        is_bill_sent_to_ppo,
        is_par,
        is_part_of_mtd_prediction,
        last_bill_received_date,
        last_bill_sent_date,
        last_manually_repriced_date,
        report_period,
        in_network_credits,
        in_network_credits_weekday,
        in_network_credits_weekend,
        in_network_dpallowed,
        in_network_dpallowed_weekday,
        in_network_dpallowed_weekend,
        in_network_netsavings,
        in_network_netsavings_weekday,
        in_network_netsavings_weekend,
        in_network_providercharges,
        in_network_providercharges_weekday,
        in_network_providercharges_weekend,
        in_network_savings,
        in_network_savings_weekday,
        in_network_savings_weekend,
        in_network_vpnallowed,
        in_network_vpnallowed_weekday,
        in_network_vpnallowed_weekend,
        claimant_header_id,
        claimant_id,
        is_pnel_log_weekday_flag,
        is_pnel_log_weekend_flag,
        is_vbh_transaction_weekdate_flag,
        is_vbh_transaction_weekend_flag,
        sub_network_name,
        vpn_network_id,
        vpn_network_name

    from source

)

select * from renamed