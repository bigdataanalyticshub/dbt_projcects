with source as (

    select * from {{ source('dwwcs', 'claim_detail_rrs_sa_mapping_output') }}

),

renamed as (

    select
        wcs_customer_name,
        wcs_site_code,
        rrs_billing_fein,
        rrs_cacn,
        wcs_ods_customer_id,
        wcs_claim_sys_subset,
        wcs_claim_seq,
        match_score,
        rrs_employee_first_name,
        wcs_patient_first_name,
        rrs_employee_last_name,
        wcs_patient_last_name,
        rrs_employee_phone_number,
        wcs_patient_primary_phone,
        rrs_employee_middle_name,
        wcs_patient_m_initial,
        rrs_employee_gender,
        wcs_patient_sex,
        rrs_doi,
        wcs_doi,
        rrs_dob,
        wcs_patient_dob,
        rrs_jurisdiction,
        wcs_jurisdiction

    from source

)

select * from renamed
