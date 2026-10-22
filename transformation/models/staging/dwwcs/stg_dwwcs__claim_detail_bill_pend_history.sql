with source as (

    select * from {{ source('dwwcs', 'claim_detail_bill_pend_history') }}

),

renamed as (

    select
        customer_name,
        ods_customer_id,
        claim_create_date,
        claim_create_date_day,
        claim_create_date_month,
        claim_create_date_year,
        claim_date_of_injury,
        claim_date_of_injury_day,
        claim_date_of_injury_month,
        claim_date_of_injury_quarter,
        claim_date_of_injury_year,
        claim_jurisdiction,
        claim_no,
        claim_seq,
        claim_sys_subset,
        client_code,
        client_code_description,
        client_edi_jurisdiction,
        client_geo_state,
        shared_client_name,
        billing_provider_name,
        billing_provider_tin,
        bill_create_date,
        bill_dos_first,
        bill_dos_last,
        bill_post_date,
        bill_post_date_month,
        bill_post_date_year,
        bill_reeval_count,
        bill_review_allowed,
        bill_review_received_date,
        bill_seq,
        bill_site_code,
        auditpro_site_code_flag,
        bill_status_description,
        bill_zero_allowed_flag,
        message_205_or_270_flag,
        prior_bill_post_date,
        prior_bill_zero_allowed_flag,
        provider_charges,
        reason_code,
        type_of_bill_code,
        auditpro_eligible,
        auditpro_reeval_flag,
        auditpro_rule_priority,
        auto_pend_flag,
        pend_by_user_id,
        pend_date,
        pend_release_date,
        pend_seq,
        pend_to_id,
        release_by_user_id,
        release_by_username,
        release_flag,
        released_by_external_user_name,
        pend_comment,
        rule_id,
        wf_task_seq,
        workflow_task,
        priority,
        source_database,
        source_server,
        tat_in_days

    from source

)

select * from renamed
