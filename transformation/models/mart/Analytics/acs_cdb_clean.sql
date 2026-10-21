{{ config(
    materialized = 'table',
    tags = ['analytics']
) }}

WITH prv_basedata_provider AS (SELECT *
                               FROM {{ ref("stg_cvtdwpporptng__prv_basedata_provider") }}),

     prv_basedata_provider_part_class AS (SELECT *
                                          FROM {{ ref("stg_cvtdwpporptng__prv_basedata_provider_part_class") }}),

     vw_claim_detail_bill AS (SELECT *
                              FROM {{ ref('stg_dwacs__vw_claim_detail_bill') }}),

     auto_direct AS (SELECT DISTINCT TO_CHAR(pbp.bdp_tax_id) AS provider_tin
                     FROM prv_basedata_provider AS pbp
                              INNER JOIN prv_basedata_provider_part_class AS pbppc
                                         ON pbppc.bdpc_prv_id = pbp.bdp_prv_id
                                             AND pbppc.bdpc_loc_id = pbp.bdp_loc_id
                                             AND pbppc.bdpc_tax_id = pbp.bdp_tax_id
                     WHERE pbp.bdp_directory_add_state IS NOT NULL
                       AND pbppc.bdpc_prod_prtcpt_class_cd IN (
                                                               'AETDRAUT', 'AMCFHS', 'AMCS', 'AUTOCVTY', 'BNAUTO',
                                                               'CAMCS',
                                                               'COFDRAUT', 'COFINAU', 'FHAAU', 'FOCUSAU', 'OKAU'
                         )
                       AND pbppc.bdpc_directory_flag = 'Y'
                       AND pbppc.bdpc_prod_pcl_id = 8),

     auto_partner AS (SELECT DISTINCT TO_CHAR(pbp.bdp_tax_id) AS provider_tin
                      FROM prv_basedata_provider AS pbp
                               INNER JOIN prv_basedata_provider_part_class AS pbppc
                                          ON pbppc.bdpc_prv_id = pbp.bdp_prv_id
                                              AND pbppc.bdpc_loc_id = pbp.bdp_loc_id
                                              AND pbppc.bdpc_tax_id = pbp.bdp_tax_id
                      WHERE pbp.bdp_directory_add_state IS NOT NULL
                        AND pbppc.bdpc_prod_prtcpt_class_cd IN (
                                                                'ADVNETAU', 'CORECHAU', 'CORCHAUT', 'HEOSAUTO',
                                                                'HSMRTAU',
                                                                'INPLNAU', 'MAGNAUTO', 'MPIHPAUT', 'MULTIAUT',
                                                                'PRCOMPAU'
                          )
                        AND pbppc.bdpc_directory_flag = 'Y'
                        AND pbppc.bdpc_prod_pcl_id = 8),

     clean_acs_cdb AS (SELECT c.*,

                              COALESCE(c.repriced_network_name, 'No Repriced Network')                     AS repriced_network_name_clean,
                              TO_CHAR(REPLACE(REPLACE(c.provider_tin, '-', ''), ' ', ''))                  AS provider_tin_clean,
                              COALESCE(c.inpatient_outpatient, 'Professional')                             AS type_of_bill_clean,
                              COALESCE(c.ppo_network_name_set, 'No Network Stack')                         AS ppo_network_name_set_clean,

                              CONCAT(c.bill_id, '|', c.ods_customer_id)                                    AS unique_bill_id,
                              CASE WHEN c.repriced_network_name IS NOT NULL THEN 1 ELSE 0 END              AS was_repriced,

                              CASE
                                  WHEN c.repriced_network_name IS NOT NULL
                                      THEN CONCAT(c.bill_id, '|', c.ods_customer_id) END                   AS repriced_bill_id,

                              CASE
                                  WHEN c.repriced_network_name IS NOT NULL
                                      THEN c.bill_review_allowed END                                       AS repriced_bill_review_allowed,

                              CASE
                                  WHEN c.repriced_network_name IS NOT NULL
                                      THEN GREATEST(0, COALESCE(c.total_vpn_reductions, 0) - COALESCE(c.ppo_credits, 0))
                                  END                                                                      AS ppo_savings,

                              CASE
                                  WHEN COALESCE(c.provider_rendering_state, '') <> ''
                                      THEN c.provider_rendering_state
                                  ELSE c.pvd_state_abbr
                                  END                                                                      AS rendering_state_norm,

                              CASE
                                  WHEN auto_direct.provider_tin IS NOT NULL AND auto_partner.provider_tin IS NOT NULL
                                      THEN 'DIRECT_AND_PARTNER'
                                  WHEN auto_direct.provider_tin IS NOT NULL THEN 'DIRECT'
                                  WHEN auto_partner.provider_tin IS NOT NULL THEN 'PARTNER'
                                  ELSE 'OTHER'
                                  END                                                                      AS contract_type,

                              CASE
                                  WHEN c.line_of_business IN ('First Party', 'Third Party') THEN 'AUTO'
                                  ELSE 'WC' END                                                            AS lob_clean

                       FROM vw_claim_detail_bill c
                                LEFT JOIN auto_direct
                                          ON TO_CHAR(REPLACE(REPLACE(c.provider_tin, '-', ''), ' ', '')) =
                                             auto_direct.provider_tin
                                LEFT JOIN auto_partner
                                          ON TO_CHAR(REPLACE(REPLACE(c.provider_tin, '-', ''), ' ', '')) =
                                             auto_partner.provider_tin

                       WHERE 1 = 1
                         AND c.duplicate_bill_flag = 'No Duplicate'
                         AND c.ods_customer_id <> 502
                         AND (c.carrier_received_date IS NULL OR YEAR (c.carrier_received_date) != 1900)
    AND UPPER (c.pvd_state_abbr) NOT IN ('PR', 'VI', 'AP', 'TB', 'FN')
    AND c.bill_create_date >= '2020-01-01'
    )

SELECT *
FROM clean_acs_cdb
