with source as (

    select * from {{ source('apricusods', 'aprcs_dme_provider_product') }}

),

renamed as (

    select
        dw_aprcs_dme_provider_product_row_id,
        dme_provider_product_sysid,
        owner_sysid,
        isdeleted,
        dme_provider_product_name,
        createddate,
        createdby_sysid,
        lastmodifieddate,
        lastmodifiedby_sysid,
        systemmodstamp,
        lastvieweddate,
        lastreferenceddate,
        contract_description,
        contract_item_id,
        contract_jurisdiction_type,
        contracted_rate,
        hcpcs_code,
        product_sysid,
        provider_contract_sysid,
        provider_service_description,
        rate_instruction,
        state,
        inactive_date,
        sequential_item,
        contract_effective_date,
        contract_termination_date,
        dw_actv_indc,
        dw_chk_sum_key,
        dw_created_dt,
        dw_updated_dt

    from source

)

select * from renamed