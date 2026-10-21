{{
  config(
    materialized='table'
  )
}}

WITH

smartadvisor_line_level as (
    select * from {{ ref('smartadvisor_line_level') }}
),

eligible_claims AS (
    select
        distinct claim_no
    from
        smartadvisor_line_level
    where
        doi >= '2024-01-01'
),

filtered_lines AS (
    -- Apply all base filters first, then compute the 50% threshold on this set
    select
        *
    from
        smartadvisor_line_level
    where
        prospective_svc_type is not null
        and retro_ntwrk_name IS NULL
        and (
            place_of_service_code IN (
                select
                    distinct place_of_service_code
                from
                    smartadvisor_line_level
                where
                    pro_qualified_pos = 1
            )
            or pro_qualified_pos = 1
        )
        and claim_no IN (
            select
                claim_no
            from
                eligible_claims
        )
),

eligibility_windows AS (
    -- Compute bill-level totals and per-service-type totals using window functions
    select
        *,
        sum(total_allowed) over (partition by bill_id) as bill_total_allowed,
        sum(total_allowed) over (partition by bill_id, prospective_svc_type) as svc_type_allowed
    from
        filtered_lines
),

final AS (
    -- Keep only lines where their service type is >= 50% of the bill's total allowed
    select
        bill_id || '_' || line_dos as visit_id,
        *
    from
        eligibility_windows
    where
        bill_total_allowed > 0
        and svc_type_allowed >= 0.5 * bill_total_allowed
)

select
    *
from
    final