-- BILL CYCLE ANALYSIS: one row per (ods_customer_id, bill_cycle_id)
-- Full cycle timeline with bill context for savings movement analysis.

{{
  config(
    materialized='table'
  )
}}

WITH

stg_jupiterodsglobal__billcycle as (
    select * from {{ ref('stg_jupiterodsglobal__billcycle') }}
),

stg_jupiterodsglobal__billcycletype as (
    select * from {{ ref('stg_jupiterodsglobal__billcycletype') }}
),

stg_jupiterodsglobal__billcycleoutcome as (
    select * from {{ ref('stg_jupiterodsglobal__billcycleoutcome') }}
),

stg_jupiterodsstaging__billheader as (
    select * from {{ ref('stg_jupiterodsstaging__billheader') }}
),

stg_jupiterodsglobal__product as (
    select * from {{ ref('stg_jupiterodsglobal__product') }}
),

jupiter_bill_level as (
    select * from {{ ref('jupiter_bill_level') }}
),

-- Bills declined/sent back at intake never reach WorkInProgress, so they are
-- absent from jupiter_bill_level. Product comes from Staging BillHeader.PRODUCTGUID.
staging_bill_context as (
    select
        staging_bill.ODSCUSTOMERID as ods_customer_id,
        staging_bill.ID as bill_header_id,
        staging_bill.BILLID as bill_number,
        product.NAME as product_name,
        product.ABBREVIATION as product_code
    from stg_jupiterodsstaging__billheader staging_bill
    left join stg_jupiterodsglobal__product product
        on product.ID = staging_bill.PRODUCTGUID
        and product.ODSCUSTOMERID = staging_bill.ODSCUSTOMERID
),

cycle_detail as (
    select
        cycle.ODSCUSTOMERID as ods_customer_id,
        cycle.BILLHEADER as bill_header_id,
        cycle.ID as bill_cycle_id,
        cycle.AUTOID as cycle_auto_id,
        cycle.CYCLETYPE as cycle_type_id,
        cycle_type.CODE as cycle_type_code,
        cycle_type.DESCRIPTION as cycle_type_description,
        cycle.CYCLEOUTCOME as cycle_outcome_id,
        outcome.CODE as cycle_outcome_code,
        outcome.DESCRIPTION as cycle_outcome_description,
        cycle.CYCLEOUTCOMEREASON as cycle_outcome_reason_id,
        cycle.DATEFROM as cycle_started_at,
        cycle.DATETO as cycle_ended_at,
        cycle.SAVINGS as cycle_savings_snapshot,
        cycle.IMPACTONSAVINGS as cycle_savings_impact,
        cycle.LASTUPDATE as cycle_updated_at,
        cycle_type.ID is not null as cycle_type_matched,
        outcome.ID is not null as cycle_outcome_matched,
        ROW_NUMBER() over (
            partition by cycle.ODSCUSTOMERID, cycle.BILLHEADER
            order by cycle.DATEFROM asc nulls last, cycle.AUTOID asc nulls last, cycle.ID
        ) as cycle_sequence,
        ROW_NUMBER() over (
            partition by cycle.ODSCUSTOMERID, cycle.BILLHEADER
            order by cycle.DATEFROM desc nulls first, cycle.AUTOID desc nulls first, cycle.ID desc
        ) as reverse_cycle_sequence
    from stg_jupiterodsglobal__billcycle cycle
    left join stg_jupiterodsglobal__billcycletype cycle_type
        on cycle_type.ID = cycle.CYCLETYPE
        and cycle_type.ODSCUSTOMERID = cycle.ODSCUSTOMERID
    left join stg_jupiterodsglobal__billcycleoutcome outcome
        on outcome.ID = cycle.CYCLEOUTCOME
        and outcome.ODSCUSTOMERID = cycle.ODSCUSTOMERID
),

final as (
    select
        cycle.*,
        -- WIP = bill reached WorkInProgress (present in jupiter_bill_level).
        -- Staging - * = intake-only bill, labeled by the bill's latest cycle outcome.
        -- Orphan = bill header not found in WorkInProgress or Staging.
        case
            when bill.bill_header_id is not null then 'WIP'
            when staging_bill.bill_header_id is not null then
                case MAX(IFF(cycle.reverse_cycle_sequence = 1, cycle.cycle_outcome_code, null)) over (
                         partition by cycle.ods_customer_id, cycle.bill_header_id)
                    when 'DECL' then 'Staging - Declined'
                    when 'SNDBK' then 'Staging - Sent Back'
                    else 'Staging - Other'
                end
            else 'Orphan'
        end as bill_stage,
        COALESCE(bill.bill_number, staging_bill.bill_number) as bill_number,
        bill.claim_id,
        bill.client_claim_number,
        bill.client_id,
        bill.client_name,
        COALESCE(bill.product_name, staging_bill.product_name) as product_name,
        COALESCE(bill.product_code, staging_bill.product_code) as product_code,
        case
            when bill.bill_header_id is not null then bill.product_group
            when staging_bill.product_code = 'SBR' then 'FairPay'
            when staging_bill.product_code in ('KPN', 'MNS') then 'Negotiations'
            else 'Other'
        end as product_group,
        bill.jurisdiction_state,
        bill.provider_id,
        bill.provider_name,
        bill.provider_npi,
        bill.service_type,
        bill.has_legal_case_link,
        bill.legal_case_id
    from cycle_detail cycle
    left join jupiter_bill_level bill
        on bill.bill_header_id = cycle.bill_header_id
        and bill.ods_customer_id = cycle.ods_customer_id
    left join staging_bill_context staging_bill
        on staging_bill.bill_header_id = cycle.bill_header_id
        and staging_bill.ods_customer_id = cycle.ods_customer_id
)

select * from final