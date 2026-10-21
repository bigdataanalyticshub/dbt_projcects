with source as (

    select * from {{ source('apricusods', 'aprcs_dme_provider_contract') }}

),

renamed as (

    select
        dw_aprcs_dme_provider_contract_row_id,
        dme_provider_contract_sysid,
        owner_sysid,
        isdeleted,
        dme_provider_contract_name,
        createddate,
        createdby_sysid,
        lastmodifieddate,
        lastmodifiedby_sysid,
        systemmodstamp,
        lastvieweddate,
        lastreferenceddate,
        commercial_billed_charges_lesser_of_lang,
        commercial_contract_instructions,
        contract_description,
        contract_effective_date,
        contract_id,
        contract_instructions,
        contract_termination_date,
        federal_billed_charges_lesser_of_lang,
        federal_feca_lesser_of_language,
        lesser_of_language,
        source_created_date,
        source_last_updated_date,
        prompt_pay_discount,
        other_instructions,
        city,
        contact_email,
        contact_name,
        corporate_address_1,
        corporate_address_2,
        days_to_pay,
        facility_parent_id,
        facility_parent_name,
        fax_number,
        payment_terms,
        phone_number,
        state,
        zip,
        dw_actv_indc,
        dw_chk_sum_key,
        dw_created_dt,
        dw_updated_dt

    from source

)

select * from renamed