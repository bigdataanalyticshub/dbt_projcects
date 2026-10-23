-- JUPITER BILL LEVEL: one row per (ods_customer_id, bill_header_id)
-- Primary reporting table. All columns are scalar; no arrays or objects.
-- carrier_name walks the reporting-group tree to root, then normalizes
-- GENEX/INTRACORP-GENEX, Gallagher Bassett, Coventry, and Mitchell variants.
-- Firm names are the most recently linked firm per role; multi-firm flags indicate
-- when a bill's linked cases have more than one firm on the same side.
-- total_associated_disputed_amount is NOT additive across bills that share cases.
-- Placeholder disputed amounts (999,999,999.98/.99) are filtered to NULL.
--
-- Reporting:
--   SUM(bill_count), SUM(observed_savings_giveback), SUM(bill_total_charges)
--   Recon %: SUM(recon_bill_numerator) / NULLIF(SUM(recon_bill_denominator), 0)
--   Savings %: SUM(latest_observed_cycle_savings) / NULLIF(SUM(fee_schedule_amount), 0)
--              over bills where NOT is_sent_back (sent-back bills were never reviewed)
--   GROUP BY: client_name, provider_name, jurisdiction_state, service_type,
--             provider_attorney_firm_name, defense_attorney_firm_name

{{
  config(
    materialized='table'
  )
}}

WITH

-- STAGING IMPORTS

stg_jupiterodsglobal__billcycle as (
    select * from {{ ref('stg_jupiterodsglobal__billcycle') }}
),

stg_jupiterodsglobal__billcycletype as (
    select * from {{ ref('stg_jupiterodsglobal__billcycletype') }}
),

stg_jupiterodsglobal__billcycleoutcome as (
    select * from {{ ref('stg_jupiterodsglobal__billcycleoutcome') }}
),

stg_jupiterodsglobal__claim as (
    select * from {{ ref('stg_jupiterodsglobal__claim') }}
),

stg_jupiterodsglobal__claimant as (
    select * from {{ ref('stg_jupiterodsglobal__claimant') }}
),

stg_jupiterodsglobal__client as (
    select * from {{ ref('stg_jupiterodsglobal__client') }}
),

stg_jupiterodsglobal__clientreportinggroup as (
    select * from {{ ref('stg_jupiterodsglobal__clientreportinggroup') }}
),

stg_jupiterodsglobal__legalcase as (
    select * from {{ ref('stg_jupiterodsglobal__legalcase') }}
),

stg_jupiterodsglobal__legalcasebillheaderxref as (
    select * from {{ ref('stg_jupiterodsglobal__legalcasebillheaderxref') }}
),

stg_jupiterodsglobal__productclientxref as (
    select * from {{ ref('stg_jupiterodsglobal__productclientxref') }}
),

stg_jupiterodsglobal__product as (
    select * from {{ ref('stg_jupiterodsglobal__product') }}
),

stg_jupiterodsglobal__postaladdress as (
    select * from {{ ref('stg_jupiterodsglobal__postaladdress') }}
),

stg_jupiterodsglobal__provider as (
    select * from {{ ref('stg_jupiterodsglobal__provider') }}
),

stg_jupiterodsglobal__state as (
    select * from {{ ref('stg_jupiterodsglobal__state') }}
),

stg_jupiterodsglobal__typeofbillcode as (
    select * from {{ ref('stg_jupiterodsglobal__typeofbillcode') }}
),

stg_jupiterodsglobal__typeofbillcategory as (
    select * from {{ ref('stg_jupiterodsglobal__typeofbillcategory') }}
),

stg_jupiterodsworkinprogress__billheader as (
    select * from {{ ref('stg_jupiterodsworkinprogress__billheader') }}
),

stg_jupiterodsworkinprogress__billheaderextension as (
    select * from {{ ref('stg_jupiterodsworkinprogress__billheaderextension') }}
),

int_jupiter__case_firm_flattened as (
    select * from {{ ref('int_jupiter__case_firm_flattened') }}
),

int_jupiter__bill_line_summary as (
    select * from {{ ref('int_jupiter__bill_line_summary') }}
),

-- TRANSFORMATION CTEs

-- Recursive walk from every reporting group to its root ancestor.
-- inherited_carrier propagates down: if a node matches a known carrier
-- pattern, its children inherit that carrier even if their own names
-- don't match. This handles GB platform nodes (GB PowerTrak, etc.)
-- under the Coventry tree, and Genex nodes under Avizent/HFN.
reporting_group_tree as (
    select
        rg.ODSCUSTOMERID as ods_customer_id,
        rg.ID as reporting_group_id,
        rg.ID as root_reporting_group_id,
        rg.NAME as root_reporting_group_name,
        case
            when rg.NAME ilike 'GENEX%'
              or rg.NAME ilike 'INTRACORP%GENEX%' then 'GENEX'
            when rg.NAME ilike 'COVENTRY%' then 'COVENTRY'
            when rg.NAME ilike 'MITCHELL - Mitchell International%' then 'MITCHELL'
            when rg.NAME ilike 'GBSERVICES%' then 'GALLAGHER BASSETT'
            else null
        end as inherited_carrier,
        1 as tree_depth
    from stg_jupiterodsglobal__clientreportinggroup rg
    where rg.PARENT is null

    union all

    select
        child.ODSCUSTOMERID,
        child.ID,
        tree.root_reporting_group_id,
        tree.root_reporting_group_name,
        coalesce(
            case
                when child.NAME ilike 'GENEX%'
                  or child.NAME ilike 'GENX%' then 'GENEX'
                when child.NAME ilike 'GALLAGHER BASSETT%'
                  or child.NAME ilike 'GallagherBassett%'
                  or child.NAME = 'Gallagher Basset'
                  or child.NAME in ('GB PowerTrak', 'GB BR4', 'GB CGB', 'GB MCPS',
                                    'GB StrataWare', 'GB - Special Handling',
                                    'GB MCS PowerTrak') then 'GALLAGHER BASSETT'
                else null
            end,
            tree.inherited_carrier),
        tree.tree_depth + 1
    from stg_jupiterodsglobal__clientreportinggroup child
    join reporting_group_tree tree
        on tree.reporting_group_id = child.PARENT
        and tree.ods_customer_id = child.ODSCUSTOMERID
),

reporting_group_carrier as (
    select
        ods_customer_id,
        reporting_group_id,
        root_reporting_group_id,
        root_reporting_group_name,
        tree_depth,
        coalesce(inherited_carrier, root_reporting_group_name) as carrier_name
    from reporting_group_tree
),

claim_context as (
    select
        claim.ODSCUSTOMERID as ods_customer_id,
        claim.ID as claim_id,
        claim.CLAIMID as claim_number,
        claim.CLIENTCLAIMNUMBER as client_claim_number,
        claim.CLAIMDATE as claim_date,
        claim.CREATEDATE as claim_created_at,
        claim.LASTUPDATE as claim_updated_at,
        claim.INSURANCETYPE as insurance_type_id,
        claim.PRODUCTCLIENT as product_client_id,
        product_client.CLIENT as client_id,
        product_client.PRODUCT as product_id,
        product.NAME as product_name,
        product.ABBREVIATION as product_code,
        case
            when product.ABBREVIATION = 'SBR' then 'FairPay'
            when product.ABBREVIATION in ('KPN', 'MNS') then 'Negotiations'
            else 'Other'
        end as product_group,
        client.NAME as client_name,
        claim.CLIENTREPORTINGGROUP as client_reporting_group_id,
        reporting_group.NAME as client_reporting_group_name,
        reporting_group.PARENT as reporting_group_parent_id,
        carrier.root_reporting_group_name as carrier_reporting_group_name,
        carrier.carrier_name,
        carrier.tree_depth as reporting_group_depth,
        jurisdiction.ABBREVIATION as jurisdiction_state,
        jurisdiction.NAME as jurisdiction_state_name
    from stg_jupiterodsglobal__claim claim
    left join stg_jupiterodsglobal__productclientxref product_client
        on product_client.ID = claim.PRODUCTCLIENT
        and product_client.ODSCUSTOMERID = claim.ODSCUSTOMERID
    left join stg_jupiterodsglobal__product product
        on product.ID = product_client.PRODUCT
        and product.ODSCUSTOMERID = product_client.ODSCUSTOMERID
    left join stg_jupiterodsglobal__client client
        on client.ID = product_client.CLIENT
        and client.ODSCUSTOMERID = product_client.ODSCUSTOMERID
    left join stg_jupiterodsglobal__clientreportinggroup reporting_group
        on reporting_group.ID = claim.CLIENTREPORTINGGROUP
        and reporting_group.ODSCUSTOMERID = claim.ODSCUSTOMERID
    left join reporting_group_carrier carrier
        on carrier.reporting_group_id = claim.CLIENTREPORTINGGROUP
        and carrier.ods_customer_id = claim.ODSCUSTOMERID
    left join stg_jupiterodsglobal__state jurisdiction
        on jurisdiction.ID = claim.STATEOFJURISDICTION
        and jurisdiction.ODSCUSTOMERID = claim.ODSCUSTOMERID
),

bill_context as (
    select
        bill.ODSCUSTOMERID as ods_customer_id,
        bill.ID as bill_header_id,
        bill.BILLID as bill_number,
        bill.CLAIMANT as claimant_id,
        claimant.CLAIM as claim_id,
        claim.claim_number,
        claim.client_claim_number,
        claim.claim_date,
        claim.client_id,
        claim.client_name,
        claim.product_id,
        claim.product_name,
        claim.product_code,
        -- 'Other' also covers bills with no resolvable claim/product
        COALESCE(claim.product_group, 'Other') as product_group,
        bill.CLIENT as bill_client_id,
        claim.client_reporting_group_id,
        claim.client_reporting_group_name,
        claim.reporting_group_parent_id,
        claim.carrier_reporting_group_name,
        claim.carrier_name,
        claim.jurisdiction_state,
        claim.jurisdiction_state_name,
        bill.PROVIDER as provider_id,
        provider.NAME as provider_name,
        provider.NPI as provider_npi,
        bill.TAXID as bill_provider_tax_id,
        provider.TAXID as provider_master_tax_id,
        provider.ISINDIVIDUAL as provider_is_individual,
        provider.SPSPRIMARYPRACTICESTATE as provider_practice_state,
        facility_address.STATE as provider_facility_state,
        facility_address.CITY as provider_facility_city,
        facility_address.POSTALCODE as provider_facility_postal_code,
        bill.TYPEOFBILL as type_of_bill_id,
        bill_type.CODE as type_of_bill_code,
        bill_type.DESCRIPTION as type_of_bill_description,
        bill_category.DESCRIPTION as service_type,
        -- Bill's TOBC: manual override when set, otherwise the system selection.
        -- Category is the top-level ancestor (tree is at most 3 levels deep).
        COALESCE(tobc_grandparent.DESCRIPTION, tobc_parent.DESCRIPTION, tobc.DESCRIPTION) as type_of_bill_category,
        tobc.DESCRIPTION as type_of_bill_subcategory,
        bill.TOTALCHARGES as bill_total_charges,
        bill.WERECEIVED as bill_received_at,
        bill.STATEMENTFROMDATE as statement_from_date,
        bill.STATEMENTTHROUGHDATE as statement_through_date,
        bill.CREATEDATE as bill_created_at,
        bill.LASTUPDATE as bill_updated_at,
        claimant.ID is not null as claimant_matched,
        claim.claim_id is not null as claim_matched,
        provider.ID is not null as provider_matched,
        bill_type.ID is not null as bill_type_matched
    from stg_jupiterodsworkinprogress__billheader bill
    left join stg_jupiterodsglobal__claimant claimant
        on claimant.ID = bill.CLAIMANT
        and claimant.ODSCUSTOMERID = bill.ODSCUSTOMERID
    left join claim_context claim
        on claim.claim_id = claimant.CLAIM
        and claim.ods_customer_id = claimant.ODSCUSTOMERID
    left join stg_jupiterodsglobal__provider provider
        on provider.ID = bill.PROVIDER
        and provider.ODSCUSTOMERID = bill.ODSCUSTOMERID
    left join stg_jupiterodsglobal__postaladdress facility_address
        on facility_address.ID = bill.PROVIDERFACILITYPOSTALADDRESS
        and facility_address.ODSCUSTOMERID = bill.ODSCUSTOMERID
    left join stg_jupiterodsglobal__typeofbillcode bill_type
        on bill_type.ID = bill.TYPEOFBILL
        and bill_type.ODSCUSTOMERID = bill.ODSCUSTOMERID
    left join stg_jupiterodsglobal__typeofbillcategory bill_category
        on bill_category.ID = bill_type.CATEGORY
        and bill_category.ODSCUSTOMERID = bill_type.ODSCUSTOMERID
    left join stg_jupiterodsworkinprogress__billheaderextension bill_extension
        on bill_extension.ID = bill.ID
        and bill_extension.ODSCUSTOMERID = bill.ODSCUSTOMERID
    left join stg_jupiterodsglobal__typeofbillcategory tobc
        on tobc.ID = COALESCE(bill_extension.OVERRIDETYPEOFBILLCATEGORY, bill_extension.SELECTIONTYPEOFBILLCATEGORY)
        and tobc.ODSCUSTOMERID = bill_extension.ODSCUSTOMERID
    left join stg_jupiterodsglobal__typeofbillcategory tobc_parent
        on tobc_parent.ID = tobc.PARENT
        and tobc_parent.ODSCUSTOMERID = tobc.ODSCUSTOMERID
    left join stg_jupiterodsglobal__typeofbillcategory tobc_grandparent
        on tobc_grandparent.ID = tobc_parent.PARENT
        and tobc_grandparent.ODSCUSTOMERID = tobc_parent.ODSCUSTOMERID
),

legal_case_bill_bridge as (
    select
        ODSCUSTOMERID as ods_customer_id,
        LEGALCASE as legal_case_id,
        BILLHEADER as bill_header_id,
        BOOLOR_AGG(ISPRIMARY) as is_primary_bill_on_case,
        BOOLOR_AGG(EXCLUDEFROMSETTLEMENTPCNT) as exclude_from_settlement_percent,
        MIN(CREATEDATE) as first_link_created_at,
        MAX(LASTUPDATE) as link_updated_at,
        COUNT(*) as source_link_count
    from stg_jupiterodsglobal__legalcasebillheaderxref
    group by ODSCUSTOMERID, LEGALCASE, BILLHEADER
),

legal_case_context as (
    select
        legal_case.ODSCUSTOMERID as ods_customer_id,
        legal_case.ID as legal_case_id,
        legal_case.CASEID as legal_case_number,
        legal_case.CREATEDATE as case_created_at,
        IFF(legal_case.DISPUTEDAMOUNT >= 0 AND legal_case.DISPUTEDAMOUNT < 999999999,
            legal_case.DISPUTEDAMOUNT, null) as case_disputed_amount,
        legal_case.HEARINGDATE as hearing_at,
        legal_case.CASESTATUS as case_status_id,
        legal_case.CASEDISPOSITION as case_disposition_id
    from stg_jupiterodsglobal__legalcase legal_case
),

bill_legal_summary as (
    select
        bridge.ods_customer_id,
        bridge.bill_header_id,
        COUNT(*) as legal_case_link_count,
        -- Scalar ID for COUNT(DISTINCT); NULL when bill links to multiple cases.
        IFF(COUNT(*) = 1, MIN(bridge.legal_case_id), null) as legal_case_id,
        IFF(COUNT(*) = 1, MIN(legal_case.legal_case_number), null) as legal_case_number,
        ARRAY_AGG(distinct bridge.legal_case_id) as linked_legal_case_ids,
        ARRAY_AGG(distinct legal_case.legal_case_number) as legal_case_numbers,
        MIN(legal_case.case_created_at) as first_legal_case_created_at,
        MAX(legal_case.case_created_at) as latest_legal_case_created_at,
        MIN(legal_case.hearing_at) as next_hearing_at,
        SUM(legal_case.case_disputed_amount) as total_associated_disputed_amount
    from legal_case_bill_bridge bridge
    left join legal_case_context legal_case
        on legal_case.legal_case_id = bridge.legal_case_id
        and legal_case.ods_customer_id = bridge.ods_customer_id
    group by bridge.ods_customer_id, bridge.bill_header_id
),

cycle_detail as (
    select
        cycle.ODSCUSTOMERID as ods_customer_id,
        cycle.BILLHEADER as bill_header_id,
        cycle.ID as bill_cycle_id,
        cycle.CYCLETYPE as cycle_type_id,
        cycle_type.CODE as cycle_type_code,
        cycle.CYCLEOUTCOME as cycle_outcome_id,
        outcome.CODE as cycle_outcome_code,
        cycle.DATEFROM as cycle_started_at,
        cycle.DATETO as cycle_ended_at,
        cycle.SAVINGS as cycle_savings_snapshot,
        cycle.IMPACTONSAVINGS as cycle_savings_impact,
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

bill_cycle_summary as (
    select
        ods_customer_id,
        bill_header_id,
        COUNT(*) as total_cycle_count,
        COALESCE(COUNT_IF(cycle_type_code = 'N'), 0) as new_cycle_count,
        COALESCE(COUNT_IF(cycle_type_code = 'RR'), 0) as reconsideration_cycle_count,
        COALESCE(COUNT_IF(cycle_type_code = 'RC'), 0) as fee_adjustment_cycle_count,
        COALESCE(COUNT_IF(cycle_type_code = 'COR'), 0) as correction_cycle_count,
        COALESCE(COUNT_IF(cycle_type_code = 'DUP'), 0) as duplicate_cycle_count,
        COALESCE(COUNT_IF(cycle_ended_at is null), 0) as cycles_without_end_date,
        COALESCE(COUNT_IF(cycle_started_at is null), 0) as cycles_without_start_date,
        COALESCE(COUNT_IF(cycle_savings_impact is null), 0) as cycles_without_savings_impact,
        COALESCE(COUNT_IF(cycle_type_code is null), 0) as cycles_without_type_code,
        MAX(IFF(cycle_sequence = 1, bill_cycle_id, null)) as first_cycle_id,
        MAX(IFF(reverse_cycle_sequence = 1, bill_cycle_id, null)) as latest_cycle_id,
        MAX(IFF(cycle_sequence = 1, cycle_savings_snapshot, null)) as first_observed_cycle_savings,
        MAX(IFF(reverse_cycle_sequence = 1, cycle_savings_snapshot, null)) as latest_observed_cycle_savings,
        MAX(IFF(cycle_sequence = 1, cycle_started_at, null)) as original_cycle_started_at,
        MAX(IFF(cycle_sequence = 1, cycle_ended_at, null)) as original_cycle_ended_at,
        MAX(IFF(reverse_cycle_sequence = 1, cycle_started_at, null)) as latest_cycle_started_at,
        MAX(IFF(reverse_cycle_sequence = 1, cycle_ended_at, null)) as latest_cycle_ended_at,
        MAX(IFF(reverse_cycle_sequence = 1, cycle_outcome_code, null)) as latest_cycle_outcome_code,
        IFF(COUNT(cycle_savings_impact) = COUNT(*), SUM(cycle_savings_impact), null) as total_reported_cycle_impact
    from cycle_detail
    group by ods_customer_id, bill_header_id
),

bill_analysis as (
    select
        bill.*,
        COALESCE(legal.legal_case_link_count, 0) as legal_case_link_count,
        legal.legal_case_id,
        legal.legal_case_number,
        COALESCE(legal.legal_case_link_count, 0) > 0 as has_legal_case_link,
        COALESCE(legal.legal_case_numbers, ARRAY_CONSTRUCT()) as legal_case_numbers,
        legal.first_legal_case_created_at,
        legal.latest_legal_case_created_at,
        COALESCE(cycles.total_cycle_count, 0) as total_cycle_count,
        COALESCE(cycles.new_cycle_count, 0) as new_cycle_count,
        COALESCE(cycles.reconsideration_cycle_count, 0) as reconsideration_cycle_count,
        COALESCE(cycles.fee_adjustment_cycle_count, 0) as fee_adjustment_cycle_count,
        COALESCE(cycles.correction_cycle_count, 0) as correction_cycle_count,
        COALESCE(cycles.duplicate_cycle_count, 0) as duplicate_cycle_count,
        COALESCE(cycles.cycles_without_end_date, 0) as cycles_without_end_date,
        COALESCE(cycles.cycles_without_start_date, 0) as cycles_without_start_date,
        cycles.first_cycle_id,
        cycles.latest_cycle_id,
        cycles.first_observed_cycle_savings,
        cycles.latest_observed_cycle_savings,
        cycles.original_cycle_started_at,
        cycles.original_cycle_ended_at,
        cycles.latest_cycle_started_at,
        cycles.latest_cycle_ended_at,
        cycles.latest_cycle_outcome_code,
        COALESCE(cycles.cycles_without_savings_impact, 0) as cycles_without_savings_impact,
        COALESCE(cycles.cycles_without_type_code, 0) as cycles_without_type_code,
        case
            when cycles.reconsideration_cycle_count > 0 then true
            when cycles.cycles_without_type_code > 0 then null
            else false
        end as bill_has_reconsideration,
        cycles.total_reported_cycle_impact,
        IFF(cycles.cycles_without_start_date = 0,
            cycles.first_observed_cycle_savings - cycles.latest_observed_cycle_savings,
            null) as observed_savings_giveback
    from bill_context bill
    left join bill_legal_summary legal
        on legal.bill_header_id = bill.bill_header_id and legal.ods_customer_id = bill.ods_customer_id
    left join bill_cycle_summary cycles
        on cycles.bill_header_id = bill.bill_header_id and cycles.ods_customer_id = bill.ods_customer_id
),

bill_firm_summary as (
    select
        bridge.ods_customer_id,
        bridge.bill_header_id,
        COUNT(distinct IFF(roles.legal_firm_matched, roles.legal_firm_id, null)) as legal_firm_count,
        -- Scalar firm names for reporting (most recently linked when multiple)
        MAX_BY(IFF(roles.legal_firm_role_code = 'PROVATTRNY' and roles.legal_firm_matched,
            roles.legal_firm_name, null), roles.case_contact_linked_at) as provider_attorney_firm_name,
        MAX_BY(IFF(roles.legal_firm_role_code = 'DEFATTRNY' and roles.legal_firm_matched,
            roles.legal_firm_name, null), roles.case_contact_linked_at) as defense_attorney_firm_name,
        MAX_BY(IFF(roles.legal_firm_role_code = 'CLIENTREP' and roles.legal_firm_matched,
            roles.legal_firm_name, null), roles.case_contact_linked_at) as client_rep_firm_name,
        -- Multi-firm indicator (true when >1 distinct firm on the same side)
        COUNT(distinct IFF(roles.legal_firm_role_code = 'PROVATTRNY' and roles.legal_firm_matched,
            roles.legal_firm_id, null)) > 1 as has_multiple_provider_attorney_firms,
        COUNT(distinct IFF(roles.legal_firm_role_code = 'DEFATTRNY' and roles.legal_firm_matched,
            roles.legal_firm_id, null)) > 1 as has_multiple_defense_attorney_firms
    from legal_case_bill_bridge bridge
    join int_jupiter__case_firm_flattened roles
        on roles.legal_case_id = bridge.legal_case_id
        and roles.ods_customer_id = bridge.ods_customer_id
    group by bridge.ods_customer_id, bridge.bill_header_id
),

final as (
    select
        -- KEYS
        bill.ods_customer_id,
        bill.bill_header_id,
        bill.bill_number,

        -- CLAIM / CLIENT
        bill.claim_id,
        bill.claim_number,
        bill.client_claim_number,
        bill.client_id,
        bill.client_name,
        bill.product_id,
        bill.product_name,
        bill.product_code,
        bill.product_group,
        bill.client_reporting_group_name,
        bill.carrier_reporting_group_name,
        bill.carrier_name,
        bill.jurisdiction_state,
        bill.jurisdiction_state_name,

        -- PROVIDER
        bill.provider_id,
        bill.provider_name,
        bill.provider_npi,
        bill.bill_provider_tax_id,
        bill.provider_is_individual,
        bill.provider_practice_state,
        bill.provider_facility_state,
        bill.provider_facility_city,
        bill.provider_facility_postal_code,

        -- BILL ATTRIBUTES
        bill.type_of_bill_code,
        bill.type_of_bill_description,
        bill.service_type,
        bill.type_of_bill_category,
        bill.type_of_bill_subcategory,
        bill.bill_total_charges,
        lines.line_charges,
        lines.ambulance_line_charges,
        lines.dme_line_charges,
        lines.fee_schedule_amount,
        bill.bill_received_at,
        bill.statement_from_date,
        bill.statement_through_date,
        bill.bill_created_at,

        -- LEGAL CONTEXT
        bill.has_legal_case_link,
        bill.legal_case_link_count,
        bill.legal_case_id,
        bill.legal_case_number,
        bill.legal_case_numbers,
        bill.first_legal_case_created_at,
        bill.latest_legal_case_created_at,
        legal_extra.next_hearing_at,
        legal_extra.total_associated_disputed_amount,

        -- FIRM (scalar for reporting; use jupiter_legal_case_firm_roles for full detail)
        COALESCE(firms.legal_firm_count, 0) as legal_firm_count,
        firms.provider_attorney_firm_name,
        firms.defense_attorney_firm_name,
        firms.client_rep_firm_name,
        COALESCE(firms.has_multiple_provider_attorney_firms, false) as has_multiple_provider_attorney_firms,
        COALESCE(firms.has_multiple_defense_attorney_firms, false) as has_multiple_defense_attorney_firms,

        -- CYCLE SUMMARY
        bill.total_cycle_count,
        bill.new_cycle_count,
        bill.reconsideration_cycle_count,
        bill.fee_adjustment_cycle_count,
        bill.correction_cycle_count,
        bill.duplicate_cycle_count,
        bill.original_cycle_started_at,
        bill.original_cycle_ended_at,
        bill.latest_cycle_started_at,
        bill.latest_cycle_ended_at,
        bill.latest_cycle_outcome_code,
        COALESCE(bill.latest_cycle_outcome_code = 'SNDBK', false) as is_sent_back,

        -- SAVINGS / GIVEBACK
        bill.first_observed_cycle_savings,
        bill.latest_observed_cycle_savings,
        bill.observed_savings_giveback,
        bill.observed_savings_giveback / NULLIF(bill.first_observed_cycle_savings, 0) as observed_giveback_ratio,
        case
            when bill.total_cycle_count = 0 then 'No Review Cycles'
            when bill.cycles_without_start_date > 0 then 'Cycle Dates Missing'
            when bill.first_observed_cycle_savings is null then 'Initial Savings Missing'
            when bill.latest_observed_cycle_savings is null then 'Current Savings Missing'
            when bill.observed_savings_giveback > 0 then 'Savings Decreased'
            when bill.observed_savings_giveback < 0 then 'Savings Increased'
            else 'No Change'
        end as observed_giveback_status,

        -- PRE-BUILT KPI FIELDS (SUM these across rows; do not average ratios)
        1 as bill_count,
        bill.bill_has_reconsideration,
        IFF(bill.bill_has_reconsideration, 1, 0) as recon_bill_numerator,
        IFF(bill.bill_has_reconsideration is not null, 1, 0) as recon_bill_denominator,
        IFF(bill.observed_savings_giveback is not null, 1, 0) as bills_with_known_giveback,
        IFF(bill.observed_savings_giveback is null, 1, 0) as bills_with_unknown_giveback

    from bill_analysis bill
    left join bill_legal_summary legal_extra
        on legal_extra.bill_header_id = bill.bill_header_id
        and legal_extra.ods_customer_id = bill.ods_customer_id
    left join bill_firm_summary firms
        on firms.bill_header_id = bill.bill_header_id
        and firms.ods_customer_id = bill.ods_customer_id
    left join int_jupiter__bill_line_summary lines
        on lines.bill_header_id = bill.bill_header_id
        and lines.ods_customer_id = bill.ods_customer_id
)

select * from final