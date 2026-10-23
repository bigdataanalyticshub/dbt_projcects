-- BILL LINE ANALYSIS: one row per (ods_customer_id, bill_line_id)
-- Line-level procedure codes, charges, and units with bill context.
-- No bill-level financial measures here; they are not additive across lines.

{{
  config(
    materialized='table'
  )
}}

WITH

stg_jupiterodsworkinprogress__billlineitem as (
    select * from {{ ref('stg_jupiterodsworkinprogress__billlineitem') }}
),

stg_jupiterodsglobal__psscode as (
    select * from {{ ref('stg_jupiterodsglobal__psscode') }}
),

stg_jupiterodsglobal__psscodetype as (
    select * from {{ ref('stg_jupiterodsglobal__psscodetype') }}
),

jupiter_bill_level as (
    select * from {{ ref('jupiter_bill_level') }}
),

line_detail as (
    select
        line.ODSCUSTOMERID as ods_customer_id,
        line.ID as bill_line_id,
        line.BILLHEADER as bill_header_id,
        line.ORDINAL as line_number,
        line.PSSCODE as procedure_code_id,
        line.CODEORMODIFIER as raw_code_and_modifiers,
        NULLIF(UPPER(TRIM(procedure.CODE)), '') as dictionary_procedure_code,
        LEFT(NULLIF(UPPER(TRIM(line.CODEORMODIFIER)), ''), 5) as raw_five_character_code_candidate,
        COALESCE(NULLIF(UPPER(TRIM(procedure.CODE)), ''),
            IFF(LENGTH(TRIM(line.CODEORMODIFIER)) >= 5,
                LEFT(NULLIF(UPPER(TRIM(line.CODEORMODIFIER)), ''), 5), null)) as procedure_code,
        case
            when NULLIF(TRIM(procedure.CODE), '') is not null then 'PSSCODE_LOOKUP'
            when LENGTH(TRIM(line.CODEORMODIFIER)) >= 5 then 'RAW_PREFIX_UNVALIDATED'
            else 'UNRESOLVED'
        end as procedure_code_resolution,
        procedure.ID is not null as procedure_lookup_matched,
        procedure.TYPE as procedure_type_id,
        procedure_type.ID is not null as procedure_type_matched,
        NULLIF(TRIM(procedure.CODE), '') is not null as procedure_code_is_dictionary_resolved,
        procedure.DESCRIPTION as procedure_description_raw,
        IFF(CONTAINS(procedure.SHORTDESCRIPTION, CHR(9)),
            NULLIF(TRIM(REGEXP_REPLACE(procedure.SHORTDESCRIPTION, '^.*\\t', '')), ''),
            procedure.SHORTDESCRIPTION) as procedure_short_description_raw,
        procedure_type.CODE as procedure_type_code,
        procedure_type.DESCRIPTION as procedure_type_description,
        case when LENGTH(TRIM(procedure.CODE)) = 5
                  and LEFT(UPPER(TRIM(line.CODEORMODIFIER)), 5) = UPPER(TRIM(procedure.CODE))
             then NULLIF(SUBSTR(UPPER(TRIM(line.CODEORMODIFIER)), 6), '')
        end as raw_modifier_suffix,
        line.DESCRIPTION as line_description,
        line.UNITS as line_units,
        line.CHARGES as line_charges,
        line.NONCOVEREDCHARGES as line_noncovered_charges,
        line.RATE as line_rate,
        line.SERVICEDATEFROM as service_from_date,
        line.SERVICEDATETO as service_through_date,
        line.NDC as ndc,
        line.NPI as line_npi,
        line.PLACEOFSERVICE as place_of_service_id,
        line.REVENUECODE as revenue_code_id,
        line.TYPEOFSERVICE as type_of_service_id,
        line.LASTUPDATE as line_updated_at
    from stg_jupiterodsworkinprogress__billlineitem line
    left join stg_jupiterodsglobal__psscode procedure
        on procedure.ID = line.PSSCODE and procedure.ODSCUSTOMERID = line.ODSCUSTOMERID
    left join stg_jupiterodsglobal__psscodetype procedure_type
        on procedure_type.ID = procedure.TYPE and procedure_type.ODSCUSTOMERID = procedure.ODSCUSTOMERID
),

final as (
    select
        line.*,
        bill.bill_number,
        bill.claim_id,
        bill.client_claim_number,
        bill.client_id,
        bill.client_name,
        bill.client_reporting_group_name,
        bill.product_name,
        bill.product_code,
        bill.product_group,
        bill.jurisdiction_state,
        bill.provider_id,
        bill.provider_name,
        bill.provider_npi,
        bill.bill_provider_tax_id,
        bill.provider_practice_state,
        bill.service_type,
        bill.bill_received_at,
        bill.has_legal_case_link,
        bill.legal_case_id,
        bill.first_legal_case_created_at,
        bill.bill_has_reconsideration
    from line_detail line
    left join jupiter_bill_level bill
        on bill.bill_header_id = line.bill_header_id
        and bill.ods_customer_id = line.ods_customer_id
)

select * from final