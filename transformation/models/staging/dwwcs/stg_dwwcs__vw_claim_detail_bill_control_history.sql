with source as (

    select * from {{ source('dwwcs', 'vw_claim_detail_bill_control_history') }}

),

renamed as (

    select
        ods_customer_id,
        client_code,
        bill_control_seq,
        bill_seq,
        external_id,
        create_date,
        bill_control_history_seq,
        control,
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
        insurer_name

    from source

)

select * from renamed
