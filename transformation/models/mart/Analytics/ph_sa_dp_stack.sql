{{ config(
    materialized = "table",
    tags = ['analytics']
) }}

WITH vw_claim_detail_bill AS (SELECT *
                              FROM {{ ref('stg_dwwcs__vw_claim_detail_bill') }}),


     vw_claim_detail_bill_acs AS (SELECT *
                                  FROM {{ ref('stg_dwacs__vw_claim_detail_bill') }}),

     prv_basedata_provider AS (SELECT *
                               FROM {{ ref("stg_cvtdwpporptng__prv_basedata_provider") }}),


     prv_basedata_provider_part_class AS (SELECT *
                                          FROM {{ ref("stg_cvtdwpporptng__prv_basedata_provider_part_class") }}),

     mcps_bill_hdr_fact AS (SELECT *
                            FROM {{ ref("stg_cvtdwmcpsrptng__mcps_bill_hdr_fact") }}),

     conf_clnt_hrchy_mv AS (SELECT *
                            FROM {{ ref("stg_cvtdwconfmrt__conf_clnt_hrchy_mv") }}),

     ntwrk_usr_src AS (SELECT *
                       FROM {{ ref("stg_cvtdwcommon__ntwrk_usr_src") }}),

     ntwrk_prodt_rptng_usr_src AS (SELECT *
                                   FROM {{ ref("stg_cvtdwcommon_ntwrk_prodt_rptng_usr_src") }}),

     prov_tin_hlth_syst_usr_src AS (SELECT * FROM {{ ref('stg_cvtdwprvrptng_prov_tin_hlth_syst_usr_src') }}),

     client_config_map_v2 AS (select * from {{ ref("stg_anlyssandboxcovtemp__client_config_map_v2") }}),

-- **STEP 1: Clean SA data**
     Clean_SA AS (SELECT *
                  FROM vw_claim_detail_bill
                  WHERE bill_status = 1
                    AND NOT duplicate_bill_flag
                    AND ods_customer_id <> 502
                    AND site_code <> '@@@'
                    AND claim_sys_subset NOT IN ('9999', '0000', 'XXXX', 'TEST')
                    AND claim_system_description NOT IN (
                                                         'SUPPORT TEST ACCOUNT-UC', 'TEST CLAIM SYSTEM', 'TEST - AMCC',
                                                         'TEST', 'TEST ACCOUNTS', 'TEST - BRICKSTREET', 'UCR TEST',
                                                         'MEDICARE TEST'
                      )
                    AND NOT (site_code = 'COV' AND sub_product_code = 'RE-EVAL CANCELLATION')
                    AND POST_DATE >= '2020-01-01 00:00:00.000'),

-- **STEP 2: Clean DP data**
     Clean_DP AS (
-- CTEs for Auto Direct and Partner providers

         WITH auto_direct AS (SELECT DISTINCT TO_CHAR(pbp.bdp_tax_id) AS provider_tin
                              FROM prv_basedata_provider AS pbp
                                       INNER JOIN prv_basedata_provider_part_class AS pbppc
                                                  ON pbppc.bdpc_prv_id = pbp.bdp_prv_id
                                                      AND pbppc.bdpc_loc_id = pbp.bdp_loc_id
                                                      AND pbppc.bdpc_tax_id = pbp.bdp_tax_id
                              WHERE pbp.bdp_directory_add_state IS NOT NULL
                                AND pbppc.bdpc_prod_prtcpt_class_cd IN
                                    ('AETDRAUT', 'AMCFHS', 'AMCS', 'AUTOCVTY', 'BNAUTO', 'CAMCS', 'COFDRAUT', 'COFINAU',
                                     'FHAAU', 'FOCUSAU', 'OKAU') -- DIRECT
                                AND pbppc.bdpc_directory_flag = 'Y'
                                AND pbppc.bdpc_prod_pcl_id = 8 -- (7=WC, 8=Auto, 9=Group Health)
         ),

              auto_partner AS (SELECT DISTINCT TO_CHAR(pbp.bdp_tax_id) AS provider_tin
                               FROM prv_basedata_provider AS pbp
                                        INNER JOIN prv_basedata_provider_part_class AS pbppc
                                                   ON pbppc.bdpc_prv_id = pbp.bdp_prv_id
                                                       AND pbppc.bdpc_loc_id = pbp.bdp_loc_id
                                                       AND pbppc.bdpc_tax_id = pbp.bdp_tax_id
                               WHERE pbp.bdp_directory_add_state IS NOT NULL
                                 AND pbppc.bdpc_prod_prtcpt_class_cd IN
                                     ('ADVNETAU', 'CORECHAU', 'CORCHAUT', 'HEOSAUTO', 'HSMRTAU', 'INPLNAU', 'MAGNAUTO',
                                      'MPIHPAUT', 'MULTIAUT', 'PRCOMPAU') -- PARTNER
                                 AND pbppc.bdpc_directory_flag = 'Y'
                                 AND pbppc.bdpc_prod_pcl_id = 8 -- (7=WC, 8=Auto, 9=Group Health)
              )

         SELECT c.*,
                -- Add the contract type calculation
                CASE
                    WHEN auto_direct.provider_tin IS NOT NULL AND auto_partner.provider_tin IS NOT NULL
                        THEN 'DIRECT_AND_PARTNER'
                    WHEN auto_direct.provider_tin IS NOT NULL THEN 'DIRECT'
                    WHEN auto_partner.provider_tin IS NOT NULL THEN 'PARTNER'
                    ELSE 'OTHER' END AS contract_type
         FROM vw_claim_detail_bill_acs c
                  LEFT JOIN auto_direct
                            ON TO_CHAR(REPLACE(REPLACE(c.provider_tin, '-', ''), ' ', '')) = auto_direct.provider_tin
                  LEFT JOIN auto_partner
                            ON TO_CHAR(REPLACE(REPLACE(c.provider_tin, '-', ''), ' ', '')) = auto_partner.provider_tin
         WHERE BILL_ID IS NOT NULL
           AND duplicate_bill_flag = 'No Duplicate'
           AND ods_customer_id <> 502
           AND (carrier_received_date IS NULL OR YEAR (carrier_received_date) != 1900)
    AND UPPER (pvd_state_abbr) NOT IN ('PR', 'VI', 'AP', 'TB', 'FN')
    AND bill_create_date >= '2020-01-01 00:00:00.000'
    ),

-- **STEP 3: Clean MCPS data with TWO row numbering strategies**
    Clean_MCPS AS (
SELECT *, m.MCPS_PRODT_CD as product_code,
    -- Row number for SA join (normalized partitioning)
    ROW_NUMBER() OVER (PARTITION BY REPLACE(EXTRNL_CLNT_BILL_ID, '-', '') ORDER BY BILL_CMPLTN_DT DESC, BILL_START_DT DESC) AS rn_sa,
    -- Row number for DP join (original partitioning)
    ROW_NUMBER() OVER (PARTITION BY EXTRNL_CLNT_BILL_ID ORDER BY BILL_CMPLTN_DT DESC, BILL_START_DT DESC) AS rn_dp, CASE
    WHEN CHARINDEX('-', EXTRNL_CLNT_BILL_ID) > 0
    THEN SPLIT_PART(EXTRNL_CLNT_BILL_ID, '-', 1)
    ELSE LEFT (EXTRNL_CLNT_BILL_ID, 3)
    END as parsed_site_code, CASE
    WHEN CHARINDEX('-', EXTRNL_CLNT_BILL_ID) > 0
    THEN SPLIT_PART(EXTRNL_CLNT_BILL_ID, '-', 2)
    ELSE SUBSTRING (EXTRNL_CLNT_BILL_ID, 4, 4)
    END as parsed_client_code, CASE
    WHEN CHARINDEX('-', EXTRNL_CLNT_BILL_ID) > 0
    AND CHARINDEX('-', EXTRNL_CLNT_BILL_ID, CHARINDEX('-', EXTRNL_CLNT_BILL_ID) + 1) > 0
    THEN COALESCE (TRY_TO_NUMBER(SPLIT_PART(EXTRNL_CLNT_BILL_ID, '-', 3)), 1)
    WHEN CHARINDEX('-', EXTRNL_CLNT_BILL_ID) > 0
    THEN 1
    ELSE COALESCE (TRY_TO_NUMBER(REGEXP_REPLACE(SUBSTRING (EXTRNL_CLNT_BILL_ID, 8), '[^0-9]', '')), 1)
    END as parsed_bill_seq
FROM mcps_bill_hdr_fact m    -- COVENTRY_DW.MCPSRPTNG.MCPS_BILL_HDR_FACT m
    LEFT JOIN conf_clnt_hrchy_mv cc -- COVENTRY_DW.confmrt.conf_clnt_hrchy_mv cc
ON m.dw_conf_clnt_row_id = cc.dw_conf_clnt_row_id
    LEFT JOIN ntwrk_usr_src n-- COVENTRY_DW.common.ntwrk_usr_src n
    ON m.dw_ntwrk_row_id = n.dw_ntwrk_row_id
    LEFT JOIN ntwrk_prodt_rptng_usr_src pb-- COVENTRY_DW.common.NTWRK_PRODT_RPTNG_USR_SRC pb
    ON m.DW_NTWRK_PRODT_RPTNG_ROW_ID = pb.DW_NTWRK_PRODT_RPTNG_ROW_ID
    LEFT JOIN prov_tin_hlth_syst_usr_src b-- COVENTRY_DW.PRVRPTNG.prov_tin_hlth_syst_usr_src b
    ON M.prov_tax_id = b.prov_tin
    LEFT JOIN client_config_map_v2 ccm-- analysis_sandbox.cov_temp.client_config_map_v2 ccm
    ON cc.ae_id = ccm.ae_id
WHERE clm_status_cd = 'EOK'
  AND BILL_WC_TTL_FEE_AMNT
    > 0
  AND TRNS_TYPE_CD = 'C'
  AND BILL_END_DT IS NULL
  AND VOID_INDC = 0
  AND NVL(rept_exclusn_cd
    , '000') NOT IN ('ADV'
    , 'APR'
    , 'OCM'
    , 'MOD'
    , 'NFS'
    , 'DME'
    , 'QLC')
  AND acctg_yr_month_num >= '202001'
    )
    , final as (
-- **STEP 4: THREE-WAY FULL OUTER JOIN - MCPS as HUB**
SELECT
    -- **SOURCE TRACKING**
    CASE
    WHEN SA.site_code IS NOT NULL AND DP.BILL_ID IS NOT NULL AND MCPS.EXTRNL_CLNT_BILL_ID IS NOT NULL THEN 'MCPS_SA_DP'
    WHEN SA.site_code IS NOT NULL AND MCPS.EXTRNL_CLNT_BILL_ID IS NOT NULL THEN 'MCPS_SA'
    WHEN DP.BILL_ID IS NOT NULL AND MCPS.EXTRNL_CLNT_BILL_ID IS NOT NULL THEN 'MCPS_DP'
    WHEN SA.site_code IS NOT NULL THEN 'SA_Only'
    WHEN DP.BILL_ID IS NOT NULL THEN 'DP_Only'
    ELSE 'MCPS_Only'
    END AS DATA_SOURCE,

    -- **MCPS COLUMNS**
    -- Business Identity
    MCPS.LOB, MCPS.LVL5_HRCHY_VAL as REPORTABLE_CLIENT, MCPS.BE_NM, MCPS.AE_NM,

    -- Bill Identifiers
    MCPS.mcps_bill_id, MCPS.EXTRNL_CLNT_BILL_ID,

    -- Key Dates
    MCPS.BILL_START_DT, MCPS.BILL_CMPLTN_DT, MCPS.BILL_END_DT, MCPS.PRCD_DT, MCPS.ACCTG_YR_MONTH_NUM,

    -- Financial Amounts
    MCPS.BILL_TTL_CHRG_AMNT, MCPS.BILL_PPO_SVNGS_AMNT, MCPS.BILL_REC_ALLWNC_AMNT, MCPS.BILL_WC_TTL_FEE_AMNT, MCPS.BILL_FEE_SCHED_SVNGS_AMNT, MCPS.BILL_OON_SVNGS_AMNT, MCPS.BILL_FEE_CHRGD_AMNT,

    -- Network/PPO Fields
    MCPS.NTWRK_PRODT_RPTNG_DESC, MCPS.NTWRK_RPTNG_CLASS_DESC, MCPS.ntwrk_class_desc, MCPS.product_intent,

    -- Provider Information
    MCPS.PROV_TAX_ID as MCPS_PROV_TAX_ID, MCPS.SVC_STATE_CD,

    -- Status/Classification
    MCPS.product_code, MCPS.CLM_STATUS_CD, MCPS.VOID_INDC, MCPS.TRNS_TYPE_CD, MCPS.BILL_TYPE_OF_SVC_CD, MCPS.REPT_EXCLUSN_CD,

    -- **SA COLUMNS**
    -- Business Identity
    SA.line_of_business as SA_LOB, SA.product_code_desc as SA_product_code_desc, SA.claim_product_code_description as SA_claim_product_code_desc, SA.ods_customer_id as SA_ods_customer_id, SA.CUSTOMER_NAME as SA_CUSTOMER_NAME,

    -- Bill Identifiers
    SA.site_code, SA.client_code, SA.bill_seq, SA.CLAIM_NO as SA_CLAIM_NO,

    -- Key Dates
    SA.POST_DATE as SA_POST_DATE, SA.carrier_received_date as SA_carrier_received_date,

    -- Financial Amounts
    SA.PROVIDER_CHARGES as SA_PROVIDER_CHARGES, SA.PPO_ADJUSTMENT as SA_PPO_ADJUSTMENT, SA.TOTAL_ALLOWED as SA_TOTAL_ALLOWED, SA.PAID_AMOUNT as SA_PAID_AMOUNT, SA.bill_review_allowed as SA_bill_review_allowed, SA.negotiated_reduction as SA_negotiated_reduction, SA.speciality_bill_review_reduction as SA_speciality_bill_review_reduction,

    -- Network/PPO Fields
    SA.ppo_network_id as SA_ppo_network_id, SA.ppo_network_name as SA_ppo_network_name, SA.PPO_SUBNETWORK_ID as SA_PPO_SUBNETWORK_ID, SA.PPO_SUBNETWORK_NAME as SA_PPO_SUBNETWORK_NAME, SA.PPO_STACKLIST as SA_PPO_STACKLIST,

    -- Provider Information
    SA.PROVIDER_TIN as SA_PROVIDER_TIN, SA.provider_type as SA_provider_type, case when nvl(SA.rendering_provider_state, '') <> '' then SA.rendering_provider_state else SA.billing_provider_practice_state end as SA_rendering_state_norm,

    -- Status/Classification
    SA.bill_status as SA_bill_status, SA.duplicate_bill_flag as SA_duplicate_bill_flag, SA.claim_sys_subset as SA_claim_sys_subset, SA.claim_system_description as SA_claim_system_description, SA.sub_product_code as SA_sub_product_code,

    -- **DP COLUMNS**
    -- Business Identity
    DP.line_of_business as DP_LOB, CASE
    WHEN DP.LINE_OF_BUSINESS = 'First Party' or DP.LINE_OF_BUSINESS = 'Third Party' then 'AUTO'
    WHEN DP.LINE_OF_BUSINESS = 'Other' then 'WC' END AS DP_LOB_Clean, DP.APPLIED_COVERAGE_ABBR as DP_APPLIED_COVERAGE_ABBR, DP.CLAIM_COVERAGE_TYPE_ABBR as DP_CLAIM_COVERAGE_TYPE_ABBR, DP.ods_customer_id as DP_ods_customer_id, DP.customer_name as DP_customer_name,

    -- Bill Identifiers
    DP.BILL_ID, CONCAT(DP.bill_id, '|', DP.ods_customer_id) as DP_unique_bill_id, CASE WHEN DP.repriced_network_name IS NOT NULL THEN CONCAT(DP.bill_id, '|', DP.ods_customer_id) end as DP_repriced_bill_id,

    -- Key Dates
    DP.bill_create_date as DP_bill_create_date, DP.carrier_received_date as DP_carrier_received_date, DP.PPO_RECEIVED_DATE, DP.PPO_RETURNED_DATE,

    -- Financial Amounts
    DP.PROVIDER_CHARGES as DP_PROVIDER_CHARGES,
    -- GREATEST(0, COALESCE(DP.TOTAL_VPN_REDUCTIONS, 0) - COALESCE(DP.ppo_credits, 0)) as DP_PPO_SAVINGS,
    CASE WHEN DP.repriced_network_name IS NOT NULL THEN GREATEST(0, COALESCE (DP.total_vpn_reductions, 0) - COALESCE (DP.ppo_credits, 0)) end as DP_PPO_SAVINGS, DP.PPO_ALLOWED, DP.TOTAL_ALLOWED as DP_TOTAL_ALLOWED, DP.bill_review_allowed as DP_bill_review_allowed, CASE WHEN DP.repriced_network_name IS NOT NULL THEN DP.bill_review_allowed END AS DP_repriced_bill_review_allowed,

    -- Network/PPO Fields
    DP.ELIGIBLE_FOR_PPO as DP_eligible_for_ppo, DP.sent_to_ppo as DP_sent_to_ppo, CASE WHEN DP.repriced_network_name IS NOT NULL THEN 1 ELSE 0 END AS DP_was_repriced, COALESCE (DP.repriced_network_name, 'No Repriced Network') as DP_repriced_network_name_clean, COALESCE (DP.ppo_network_name_set, 'No Network Stack') as DP_ppo_network_name_set_clean, DP.contract_type as DP_contract_type,

    -- Provider Information
    DP.PROVIDER_TIN as DP_PROVIDER_TIN, TO_CHAR(REPLACE(REPLACE(DP.provider_tin, '-', ''), ' ', '')) as DP_provider_tin_clean, DP.provider_type as DP_provider_type, DP.pvd_state_abbr as DP_pvd_state_abbr, CASE WHEN COALESCE (DP.provider_rendering_state, '') <> '' THEN DP.provider_rendering_state ELSE DP.pvd_state_abbr END as DP_rendering_state_norm,

    -- Status/Classification
    DP.duplicate_bill_flag as DP_duplicate_bill_flag, COALESCE (DP.inpatient_outpatient, 'Professional') as DP_type_of_bill_clean

FROM Clean_MCPS MCPS
    FULL OUTER JOIN Clean_SA SA
ON
    SA.site_code = MCPS.parsed_site_code
    AND SA.client_code = MCPS.parsed_client_code
    AND SA.bill_seq = MCPS.parsed_bill_seq
    AND MCPS.rn_sa = 1 -- Use SA-specific row numbering
    FULL OUTER JOIN Clean_DP DP ON
    TO_CHAR(DP.BILL_ID) = MCPS.EXTRNL_CLNT_BILL_ID
    AND TO_CHAR(REPLACE(REPLACE(DP.PROVIDER_TIN, '-', ''), ' ', '')) = TO_CHAR(REPLACE(REPLACE(MCPS.PROV_TAX_ID, '-', ''), ' ', ''))
    AND MCPS.BILL_START_DT BETWEEN DP.PPO_RECEIVED_DATE AND DP.PPO_RETURNED_DATE
    AND MCPS.rn_dp = 1 -- Use DP-specific row numbering
    )
SELECT *
FROM final
ORDER BY COALESCE(BILL_TTL_CHRG_AMNT, SA_PROVIDER_CHARGES, DP_PROVIDER_CHARGES) DESC