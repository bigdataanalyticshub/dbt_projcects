with source as (

    select * from {{ source('dwwcs', 'vw_claim_detail_edixmit_control') }}

),

renamed as (

    select
        ods_customer_id,
        customer_name,
        client_code,
        bill_seq,
        source_id,
        reeval_allow,
        bill_seq_new_rev,
        ub92tob,
        bill_provider_seq,
        policy_seq,
        policy_tin,
        insurer_type,
        insurer_seq,
        claim_sys_subset,
        claim_seq,
        ncci_group_code,
        ncci_carrier_code,
        insurer_name,
        edi_control_seq,
        special_process_flag,
        edi_sender_identifier,
        edixmit_bill_seq,
        edi_test_indicator,
        edixmit_seq,
        transmission_status,
        resubmit_date,
        date_from,
        xmit_date,
        file_spec,
        external_batch_date,
        ack_note_code,
        site_code,
        jurisdiction

    from source

)

select * from renamed

