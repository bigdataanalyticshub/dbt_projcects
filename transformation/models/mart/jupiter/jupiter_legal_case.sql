-- LEGAL CASE ANALYSIS: one row per (ods_customer_id, legal_case_id)
-- Case-level dates, status, disputed amounts, and attorney-firm associations.
-- Includes cases with no bill links.

{{
  config(
    materialized='table'
  )
}}

WITH

stg_jupiterodsglobal__legalcase as (
    select * from {{ ref('stg_jupiterodsglobal__legalcase') }}
),

stg_jupiterodsglobal__legalcasebillheaderxref as (
    select * from {{ ref('stg_jupiterodsglobal__legalcasebillheaderxref') }}
),

int_jupiter__case_firm_flattened as (
    select * from {{ ref('int_jupiter__case_firm_flattened') }}
),

case_firms as (
    select
        ods_customer_id,
        legal_case_id,
        ARRAY_AGG(distinct IFF(legal_firm_role_code = 'PROVATTRNY' and legal_firm_matched, legal_firm_id, null)) as provider_attorney_firm_ids,
        ARRAY_AGG(distinct IFF(legal_firm_role_code = 'PROVATTRNY' and legal_firm_matched, legal_firm_name, null)) as provider_attorney_firm_names,
        ARRAY_AGG(distinct IFF(legal_firm_role_code = 'DEFATTRNY' and legal_firm_matched, legal_firm_id, null)) as defense_attorney_firm_ids,
        ARRAY_AGG(distinct IFF(legal_firm_role_code = 'DEFATTRNY' and legal_firm_matched, legal_firm_name, null)) as defense_attorney_firm_names,
        ARRAY_AGG(distinct IFF(legal_firm_role_code = 'CLIENTREP' and legal_firm_matched, legal_firm_id, null)) as client_representative_firm_ids,
        ARRAY_AGG(distinct IFF(legal_firm_role_code = 'CLIENTREP' and legal_firm_matched, legal_firm_name, null)) as client_representative_firm_names
    from int_jupiter__case_firm_flattened
    group by ods_customer_id, legal_case_id
),

case_link_summary as (
    select
        ODSCUSTOMERID as ods_customer_id,
        LEGALCASE as legal_case_id,
        COUNT(distinct BILLHEADER) as linked_bill_count
    from stg_jupiterodsglobal__legalcasebillheaderxref
    group by ODSCUSTOMERID, LEGALCASE
),

final as (
    select
        legal_case.ODSCUSTOMERID as ods_customer_id,
        legal_case.ID as legal_case_id,
        legal_case.CASEID as legal_case_number,
        legal_case.CASESTATUS as case_status_id,
        legal_case.CASEDISPOSITION as case_disposition_id,
        IFF(legal_case.DISPUTEDAMOUNT >= 0 AND legal_case.DISPUTEDAMOUNT < 999999999,
            legal_case.DISPUTEDAMOUNT, null) AS case_disputed_amount,
        legal_case.CREATEDATE as case_created_at,
        legal_case.DUEDATE as case_due_at,
        legal_case.HEARINGDATE as hearing_at,
        legal_case.STATEFILINGDATE as state_filing_at,
        legal_case.LASTUPDATE as case_updated_at,
        legal_case.ISHIDDENONREPORTS as case_is_hidden_on_reports,
        legal_case.NEEDSATTORNEYATTENTION as needs_attorney_attention,
        COALESCE(links.linked_bill_count, 0) as linked_bill_count,
        COALESCE(firms.provider_attorney_firm_ids, ARRAY_CONSTRUCT()) as provider_attorney_firm_ids,
        COALESCE(firms.provider_attorney_firm_names, ARRAY_CONSTRUCT()) as provider_attorney_firm_names,
        COALESCE(firms.defense_attorney_firm_ids, ARRAY_CONSTRUCT()) as defense_attorney_firm_ids,
        COALESCE(firms.defense_attorney_firm_names, ARRAY_CONSTRUCT()) as defense_attorney_firm_names,
        COALESCE(firms.client_representative_firm_ids, ARRAY_CONSTRUCT()) as client_representative_firm_ids,
        COALESCE(firms.client_representative_firm_names, ARRAY_CONSTRUCT()) as client_representative_firm_names
    from stg_jupiterodsglobal__legalcase legal_case
    left join case_firms firms
        on firms.legal_case_id = legal_case.ID
        and firms.ods_customer_id = legal_case.ODSCUSTOMERID
    left join case_link_summary links
        on links.legal_case_id = legal_case.ID
        and links.ods_customer_id = legal_case.ODSCUSTOMERID
)

select * from final