{{
  config(
    materialized='table'
  )
}}

WITH

stg_dwwcs__vw_claim_detail_bill as (
    select * from {{ ref('stg_dwwcs__vw_claim_detail_bill') }}
),

stg_dwwcs__vw_claim_detail_billline as (
    select * from {{ ref('stg_dwwcs__vw_claim_detail_billline') }}
),

stg_dwctshex__nco_test_mapping as (
    select * from {{ ref('stg_dwctshex__nco_test_mapping') }}
),

stg_dwctshex__wcs_client_breakouts as (
    select * from {{ ref('stg_dwctshex__wcs_client_breakouts') }}
),

prospective_ntwrk_id_ref as (
    select * from {{ ref('prospective_ntwrk_id_ref') }}
),

prospective_ntwrk_tin_ref as (
    select * from {{ ref('prospective_ntwrk_tin_ref') }}
),

prospective_service_ref as (
    select * from {{ ref('prospective_service_ref') }}
),

stg_cvtdwpmrptng__pm_retro_ntwrk_ids_usr_src as (
    select * from {{ ref('stg_cvtdwpmrptng__pm_retro_ntwrk_ids_usr_src') }}
),

stg_dwctsref__prospective_pos_ref as (
    select * from {{ ref('stg_dwctsref__prospective_pos_ref') }}
),

current_bills AS (
    SELECT
        site_code,
        client_code,
        bill_seq,
        post_date,
        ppo_subnetwork_name,
        place_of_service,
        pos_description
    FROM stg_dwwcs__vw_claim_detail_bill
    WHERE bill_status = 1
        AND NOT duplicate_bill_flag
        AND post_date >= DATEADD(month, -38, CURRENT_DATE())
),

final AS (
    SELECT
        -- KEY IDENTIFIERS
        CONCAT(wc.site_code, '-', wc.client_code, '-', wc.bill_seq) AS bill_id,
        CONCAT(wc.site_code, '-', wc.client_code, '-', wc.bill_seq, '-', wc.line_seq) AS line_id,
        wc.claim_seq,
        wc.claim_no,

        -- DATES
        b.post_date,
        DATE_TRUNC('month', b.post_date) AS post_month,
        wc.line_dos,
        wc.dos_first,
        wc.dos_last,
        wc.doi,

        -- CLIENT / ENTITY
        nco.sp_name AS sp_name,
        CASE
            WHEN m.groupingtype = 'Clm'
                THEN CONCAT(m.final_name, ' - ', wc.claim_system_description)
            WHEN m.final_name IS NOT NULL THEN m.final_name
            ELSE wc.shared_client_name
        END AS client_name,

        -- CLASSIFICATION
        CASE
            WHEN wc.product_code IN ('A', 'O') THEN 'Auto 1P'
            WHEN wc.product_code IN ('U', 'P', 'F') THEN 'Worker''s Comp'
            ELSE 'Other'
        END AS lob,
        wc.product_code,
        wc.claim_status,
        CASE WHEN LENGTH(TRIM(wc.ub_type_of_bill)) > 0 THEN 'U' ELSE 'H' END AS form_type,
        CASE
            WHEN wc.type_of_bill_code = 'I' THEN 'Inpatient'
            WHEN wc.type_of_bill_code = 'O' THEN 'Outpatient'
            WHEN wc.type_of_bill_code = 'M' THEN 'Professional'
            ELSE 'Other'
        END AS type_of_bill,

        -- GEOGRAPHY
        wc.geo_state AS juris_state,
        wc.rendering_provider_state AS service_state,

        -- PROVIDER
        wc.provider_tin,
        wc.provider_name,
        wc.billing_provider_npi,
        wc.rendering_provider_npi,
        wc.ppo_network_name AS ppo_network_name,
        CASE
            WHEN b.ppo_subnetwork_name IS NULL OR LENGTH(b.ppo_subnetwork_name) = 0
                THEN 'N/A'
            ELSE b.ppo_subnetwork_name
        END AS ppo_subnetwork,
        wc.ppo_stacklist,

        -- SPECIALTY
        COALESCE(tin.conf_ntwrk_name, id.conf_ntwrk_name) AS prospective_ntwrk_name,
        service_ref.service_category AS prospective_svc_type,
        CASE
            WHEN pro_pos.service_category IS NOT NULL THEN 1
            ELSE 0
        END AS pro_qualified_pos,
        retro.ntwrk_desc AS retro_ntwrk_name,

        -- CODES
        wc.procedure_code,
        wc.service_code_group,
        wc.service_code_category,
        wc.service_code_sub_category,
        wc.priced_service_code,
        wc.priced_service_code_description,
        wc.service_code_type,
        wc.service_code_type_description,
        CASE
            WHEN wc.revenue_code IS NULL AND wc.service_code_type = 'R'
                THEN wc.procedure_code
            ELSE SUBSTR(wc.revenue_code, 1, 4)
        END AS revenue_code,
        wc.revenue_code_description,
        wc.modifier_sets AS modifier_code_set,
        wc.message_code_set,
        b.place_of_service AS place_of_service_code,
        b.pos_description AS place_of_service_description,

        -- NUMERICAL
        wc.total_units,
        wc.provider_charges,
        wc.bill_review_adjustment AS bill_review_reductions,
        wc.bill_review_allowed,
        wc.provider_charges - wc.bill_review_adjustment AS pre_ppo_allowed,
        wc.ppo_adjustment AS ppo_savings,
        wc.total_allowed,
        wc.fee_schedule_reductions,
        wc.clinical_review_reduction,
        wc.speciality_bill_review_reduction,
        wc.complex_bill_review_reduction

    FROM stg_dwwcs__vw_claim_detail_billline AS wc

    INNER JOIN current_bills AS b
        ON wc.site_code = b.site_code
        AND wc.client_code = b.client_code
        AND wc.bill_seq = b.bill_seq

    LEFT JOIN prospective_ntwrk_tin_ref AS tin
        ON wc.provider_tin = tin.ntwrk_tin

    LEFT JOIN prospective_ntwrk_id_ref AS id
        ON wc.ppo_network_id = id.ntwrk_id

    LEFT JOIN prospective_service_ref AS service_ref
        ON wc.procedure_code = service_ref.procedure_code

    LEFT JOIN stg_cvtdwpmrptng__pm_retro_ntwrk_ids_usr_src AS retro
        ON wc.ppo_network_id = retro.ppo_ntwrk_id

    LEFT JOIN stg_dwctsref__prospective_pos_ref AS pro_pos
        ON service_ref.service_category = pro_pos.service_category
        AND b.place_of_service = pro_pos.pos_code

    LEFT JOIN stg_dwctshex__wcs_client_breakouts AS m
        ON (
            (
                m.groupingtype = 'Ctrl'
                AND wc.site_code = m.sitecode
                AND wc.control_number = m.controlnum
            )
            OR
            (m.groupingtype != 'Ctrl' AND wc.site_code = m.sitecode)
        )

    -- S&P Mapping join, can be excluded or deleted if not needed (applies standard naming scheme across entire Enlyte business)
    -- This looks extra complex because of the client breakout logic.
    LEFT JOIN stg_dwctshex__nco_test_mapping AS nco
        ON nco.norm_other_names =
            CASE
                WHEN EXISTS (
                    SELECT 1
                    FROM stg_dwctshex__nco_test_mapping
                    WHERE norm_other_names = REPLACE(
                        LOWER(
                            CASE
                                WHEN m.groupingtype = 'Clm'
                                    THEN CONCAT(m.final_name, ' - ', wc.claim_system_description)
                                ELSE m.final_name
                            END
                        ),
                        ' ',
                        ''
                    )
                )
                    THEN REPLACE(
                        LOWER(
                            CASE
                                WHEN m.groupingtype = 'Clm'
                                    THEN CONCAT(m.final_name, ' - ', wc.claim_system_description)
                                ELSE m.final_name
                            END
                        ),
                        ' ',
                        ''
                    )
                ELSE REPLACE(LOWER(wc.customer_name), ' ', '')
            END
        AND nco.rn_norm = 1

    WHERE
        NOT wc.duplicate_line_flag
        AND wc.ods_customer_id <> 502
        AND wc.site_code <> '@@@'
        AND wc.claim_sys_subset NOT IN ('9999', '0000', 'XXXX', 'TEST')
        AND wc.claim_system_description NOT IN (
            'SUPPORT TEST ACCOUNT-UC',
            'TEST CLAIM SYSTEM',
            'TEST - AMCC',
            'TEST',
            'TEST ACCOUNTS',
            'TEST - BRICKSTREET',
            'UCR TEST',
            'MEDICARE TEST'
        )
        AND NOT (
            wc.site_code = 'COV'
            AND wc.sub_product_code = 'RE-EVAL CANCELLATION'
        )

    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY wc.site_code, wc.client_code, wc.bill_seq, wc.line_seq
        ORDER BY
            CASE WHEN m.groupingtype = 'Ctrl' THEN 0 ELSE 1 END,
            m.final_name NULLS LAST
    ) = 1
)

SELECT * FROM final