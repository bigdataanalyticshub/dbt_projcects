with source as (

    select * from {{ source('dwwcs', 'vw_provider_data_explorer') }}

),

renamed as (

    select
        bill_id,
        line_number,
        bill_seq,
        client_code,
        line_seq,
        bill_line_type,
        date_of_service,
        provider_charges,
        total_allowed,
        adjustment,
        form_type,
        dfform_type,
        sub_form_type,
        dfsub_form_type,
        exception_flag,
        service_code_type,
        service_code,
        dfservice_code,
        service_code_description,
        service_code_category,
        dfservice_code_category,
        service_code_sub_category,
        dfservice_code_sub_category,
        bill_injury_description,
        claim_id,
        claim_no,
        claim_seq,
        claim_sys_subset,
        date_of_injury,
        actual_tenure_in_days,
        expected_tenure_in_days,
        jurisdiction,
        dfjurisdiction,
        shared_client_name,
        claim_injury_description,
        dfclaim_injury_description,
        derived_cv_desc,
        dfcoverage_line,
        claim_minimum_dos,
        claim_maximum_dos,
        provider_tin,
        provider_name,
        dfprovider_name,
        provider_cluster_name,
        dfprovider_cluster_name,
        provider_practice_zip,
        provider_practice_state,
        provider_practice_county,
        provider_practice_city,
        provider_seq,
        provider_sub_set,
        place_of_service_code,
        ods_customer_id,
        create_date

    from source

)

select * from renamed

