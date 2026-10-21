{{
  config(
    materialized='table'
  )
}}

WITH

stg_dwacs__vw_claim_detail_billline as (
    select * from {{ ref('stg_dwacs__vw_claim_detail_billline') }}
),

stg_dwctshex__nco_test_mapping as (
    select * from {{ ref('stg_dwctshex__nco_test_mapping') }}
),

stg_dwacs__vw_claim_detail_billline_ppo_network as (
    select * from {{ ref('stg_dwacs__vw_claim_detail_billline_ppo_network') }}
),

dp_subnetwork AS (
    SELECT DISTINCT
        bill_id,
        ods_customer_id,
        sub_network_name
    FROM stg_dwacs__vw_claim_detail_billline_ppo_network
    WHERE bill_id IS NOT NULL
        AND ods_customer_id <> 502
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY bill_id, ods_customer_id
        ORDER BY last_bill_sent_date DESC
    ) = 1
),

final as (
    SELECT
        -- KEY IDENTIFIERS
        CONCAT(ac.ods_customer_id, '-', ac.bill_id) AS bill_id,
        CONCAT(ac.ods_customer_id, '-', ac.bill_id, '-', ac.bill_line) AS line_id,
        ac.bill_line AS line_seq,
        ac.claim_id_no AS claim_seq,
        ac.claim_no,

        -- DATES
        ac.bill_create_date,
        DATE_TRUNC('month', ac.bill_create_date) AS bill_create_month,
        ac.line_start_date_of_service AS dos_first,
        ac.line_end_date_of_service AS dos_last,
        ac.claim_date_of_loss AS doi,

        -- CLIENT / ENTITY
        nco.sp_name,
        ac.customer_name AS client_name,

        -- CLASSIFICATION
        CASE
            WHEN ac.line_of_business = 'First Party' THEN 'Auto 1P'
            WHEN ac.line_of_business = 'Third Party' THEN 'Auto 3P'
            WHEN ac.line_of_business = 'Other' THEN 'Worker''s Comp'
        END AS lob,
        ac.applied_coverage_abbr,
        ac.bill_status,
        ac.form_type,
        COALESCE(ac.inpatient_outpatient, 'Professional') AS type_of_bill,

        -- GEOGRAPHY: matches ACS Base null handling
        COALESCE(ac.soj_abbr, 'N/A') AS juris_state,
        COALESCE(ac.provider_zos_state_abbr, 'N/A') AS service_state,

        -- PROVIDER
        ac.provider_tin,
        ac.derived_billing_provider_name AS billing_provider_name,
        ac.provider_npi AS rendering_provider_npi,
        COALESCE(ac.repriced_network_name, 'N/A') AS ppo_network_name,
        COALESCE(sub.sub_network_name, 'No Subnetwork') AS ppo_subnetwork,
        ac.ppo_network_name_set AS ppo_stacklist,

        -- CODES
        ac.procedure_code,
        ac.rev_code AS revenue_code,
        ac.revenue_code_description,
        ac.modifier AS modifier_code_set,
        ac.endnote_set AS message_code_set,
        ac.pos_code AS place_of_service_code,
        ac.pos_description AS place_of_service_description,

        -- NUMERICAL: definitions match ACS Base
        ac.total_units,
        ac.provider_charges,
        ac.bill_review_adjustment AS bill_review_reductions,
        CASE
            WHEN ac.repriced_network_name IS NOT NULL
                THEN GREATEST(
                    0,
                    COALESCE(ac.total_vpn_reductions, 0) - COALESCE(ac.ppo_credits, 0)
                )
            ELSE 0
        END AS ppo_savings,
        ac.total_allowed,
        ac.bill_review_allowed,
        CASE
            WHEN ac.repriced_network_name IS NOT NULL
                AND GREATEST(
                    0,
                    COALESCE(ac.total_vpn_reductions, 0) - COALESCE(ac.ppo_credits, 0)
                ) <> 0
                THEN 1
            ELSE 0
        END AS ppo_line_indicator,
        ac.pre_ppo_allowed,
        ac.provider_charges - ac.total_allowed AS total_reductions,
        ac.ppo_allowed,
        ac.fee_schedule_reductions,
        ac.nurse_review_reductions AS nurse_review_reductions,
        ac.sentry_reductions

    FROM stg_dwacs__vw_claim_detail_billline AS ac

    -- S&P mapping matches ACS Base.
    LEFT JOIN stg_dwctshex__nco_test_mapping AS nco
        ON nco.norm_other_names = REPLACE(LOWER(ac.customer_name), ' ', '')
        AND nco.rn_norm = 1

    LEFT JOIN dp_subnetwork AS sub
        ON ac.bill_id = sub.bill_id
        AND ac.ods_customer_id = sub.ods_customer_id

    WHERE
        ac.duplicate_bill_flag = 'No Duplicate'
        AND ac.ods_customer_id <> 502
        AND (
            ac.carrier_received_date IS NULL
            OR YEAR(ac.carrier_received_date) NOT IN (1899, 1900)
        )
        AND UPPER(ac.pvd_state_abbr) NOT IN ('PR', 'VI', 'AP', 'TB', 'FN')
        AND ac.bill_create_date >= DATEADD(month, -38, CURRENT_DATE())
)

select * from final