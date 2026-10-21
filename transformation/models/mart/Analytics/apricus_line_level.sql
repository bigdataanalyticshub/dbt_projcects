{{
  config(
    materialized='table'
  )
}}

WITH

stg_apricusods__aprcs_account as (
    select * from {{ ref('stg_apricusods__aprcs_account') }}
),

stg_apricusods__aprcs_case as (
    select * from {{ ref('stg_apricusods__aprcs_case') }}
),

stg_apricusods__aprcs_dme_bill_line_item as (
    select * from {{ ref('stg_apricusods__aprcs_dme_bill_line_item') }}
),

stg_apricusods__aprcs_dme_bill as (
    select * from {{ ref('stg_apricusods__aprcs_dme_bill') }}
),

stg_apricusods__aprcs_dme_injury as (
    select * from {{ ref('stg_apricusods__aprcs_dme_injury') }}
),

stg_apricusods__aprcs_dme_provider_contract as (
    select * from {{ ref('stg_apricusods__aprcs_dme_provider_contract') }}
),

stg_apricusods__aprcs_dme_provider_product as (
    select * from {{ ref('stg_apricusods__aprcs_dme_provider_product') }}
),

stg_apricusods__aprcs_dme_service_item as (
    select * from {{ ref('stg_apricusods__aprcs_dme_service_item') }}
),

stg_dwctshex__nco_test_mapping as (
    select * from {{ ref('stg_dwctshex__nco_test_mapping') }}
),

si_clean AS (
    SELECT
        si.bill_line_item_sysid,
        si.bill_sysid,
        si.order_sysid,
        si.staffing_category,
        si.quantity,
        si.wcfs_subtotal,
        si.u_c_subtotal,
        si.total_invoice_rate,
        si.hcpcs_code,
        si.margin,
        si.paid_date,
        si.total_apr,
        si.contracted_item_id,
        si.pp_contracted_item_id,
        COUNT(DISTINCT si.order_sysid) OVER (PARTITION BY si.bill_sysid) AS order_cnt,
        ROW_NUMBER() OVER (
            PARTITION BY si.bill_line_item_sysid
            ORDER BY si.createddate DESC
        ) as rn
    FROM stg_apricusods__aprcs_dme_service_item si
    WHERE si.dw_actv_indc = 1
    QUALIFY rn = 1 AND order_cnt = 1
),

smp_base_raw AS (
    SELECT
        -- Bill identifiers
        b.dme_bill_name AS smp_bill_id,
        bl.dme_bill_line_item_name AS smp_bill_line_id,

        -- Sequence numbers
        CAST(SUBSTR(b.dme_bill_name, 7, 80) AS DECIMAL) AS bill_seq_num,
        CAST(SUBSTR(bl.dme_bill_line_item_name, 7, 80) AS DECIMAL) AS line_seq_num,

        -- Date ranges (simplified from FIRST_VALUE/LAST_VALUE)
        MIN(bl.servicefrom) OVER (
            PARTITION BY b.dme_bill_sysid
        ) AS bill_first_svc_dt,
        MAX(COALESCE(bl.serviceto, bl.servicefrom)) OVER (
            PARTITION BY b.dme_bill_sysid
        ) AS bill_last_svc_dt,
        MIN(bl.servicefrom) OVER (
            PARTITION BY acct_be.be_id, b.claimnumber
        ) AS clm_first_svc_dt,
        MAX(COALESCE(bl.serviceto, bl.servicefrom)) OVER (
            PARTITION BY acct_be.be_id, b.claimnumber
        ) AS clm_last_svc_dt,

        -- Flags and indicators
        CASE
            WHEN c.status = 'POST-SCHEDULING' AND c.sub_status = 'PENDING BILL RECONCILIATION' THEN 1
            WHEN c.status IN ('PROVIDER PAYMENT', 'ORDER COMPLETE', 'CLIENT BILLING') THEN 1
            ELSE 0
        END AS closed_clm_rpt_indc,

        -- Client and account information
        nco.sp_name,
        acct_rev.account_name AS client,
        acct_be.be_id,
        acct_ae.be_id AS ae_id,

        -- Claim information
        b.claimnumber AS clm_num,
        c.status AS clm_status,
        c.sub_status AS clm_sub_status,
        i.claim_type AS bill_type,
        CASE
            WHEN i.claim_type = 'AUTO LIABILITY' THEN 'AUTO'
            WHEN i.claim_type = 'WORKERS COMP' THEN 'WC'
            ELSE 'OTHER'
        END AS lob,
        c.discharge_date AS dschg_dt,

        -- Service information
        si.staffing_category,
        bl.servicefrom AS line_svc_dt,
        COALESCE(bl.serviceto, bl.servicefrom) AS line_svc_end_dt,
        b.provider_statecode AS service_state,
        si.hcpcs_code AS svc_cd,

        -- Provider information
        b.provider_ftin AS bllng_prov_tin,
        prv.npi AS faclty_prov_npi,
        prv.account_name AS faclty_prov_nm,
        pc.contract_description,

        -- Payment information
        si.paid_date,
        b.check_date,
        b.bill_processed_date,
        b.status AS bill_status,

        -- Geographic information
        i.jurisdiction_state AS juris_state,

        -- Financial information
        COALESCE(bl.linecharge, 0) AS line_chrg_amnt,
        COALESCE(NULLIF(si.wcfs_subtotal, 0), si.u_c_subtotal, 0) AS line_br_allwd_amnt,
        COALESCE(si.total_invoice_rate, 0) AS line_allwd_amnt,
        COALESCE(si.total_apr, 0) AS total_apr,
        COALESCE(si.margin / 100, 0) AS margin_pct, -- total_apr - total_invoice_rate
        COALESCE(si.total_invoice_rate - si.total_apr, 0) AS margin_calc,
        CASE
            WHEN si.staffing_category = 'PHYSICAL MEDICINE' THEN COALESCE(bl.allowed_units, 0)
            ELSE COALESCE(si.quantity, 0)
        END AS line_units

    FROM stg_apricusods__aprcs_dme_bill b

    -- Core joins
    INNER JOIN stg_apricusods__aprcs_dme_bill_line_item bl
        ON b.dme_bill_sysid = bl.dme_bill_sysid
        AND bl.dw_actv_indc = 1

    INNER JOIN si_clean si
        ON b.dme_bill_sysid = si.bill_sysid
        AND bl.dme_bill_line_item_sysid = si.bill_line_item_sysid

    INNER JOIN stg_apricusods__aprcs_case c
        ON si.order_sysid = c.case_sysid
        AND c.dw_actv_indc = 1

    INNER JOIN stg_apricusods__aprcs_dme_injury i
        ON c.dme_injury_sysid = i.dme_injury_sysid
        AND i.dw_actv_indc = 1

    -- Account joins
    LEFT JOIN stg_apricusods__aprcs_account acct_ae
        ON i.client_sysid = acct_ae.account_sysid

    LEFT JOIN stg_apricusods__aprcs_account acct_be
        ON acct_ae.business_entity_sysid = acct_be.account_sysid

    -- Apricus revenue customer is a Salesforce sysid; resolve to the account name
    -- (UPPER on both sides: SF IDs are case-sensitive and casing differs across tables)
    LEFT JOIN stg_apricusods__aprcs_account acct_rev
        ON UPPER(i.apricus_revenue_customer_sysid) = UPPER(acct_rev.account_sysid)

    -- Provider join
    LEFT JOIN stg_apricusods__aprcs_account prv
        ON b.provider_sysid = prv.account_sysid
        AND prv.dw_actv_indc = 1

    -- External mapping joins
    LEFT JOIN stg_dwctshex__nco_test_mapping nco
        ON nco.norm_other_names = REPLACE(LOWER(acct_rev.account_name), ' ', '')
        AND nco.rn_norm = 1

    LEFT JOIN stg_apricusods__aprcs_dme_provider_product pp
        ON UPPER(COALESCE(si.contracted_item_id, si.pp_contracted_item_id)) = UPPER(pp.dme_provider_product_sysid)
        AND pp.dw_actv_indc = 1

    LEFT JOIN stg_apricusods__aprcs_dme_provider_contract pc
        ON pp.provider_contract_sysid = pc.dme_provider_contract_sysid
        AND pc.dw_actv_indc = 1

    WHERE b.dw_actv_indc = 1
        AND b.status NOT IN ('DENIED', 'VOID', 'REPRICING REJECTED')
),

-- Identify bills with positive BR allowed and units
bill_totals AS (
    SELECT
        SMP_BILL_ID
    FROM smp_base_raw
    GROUP BY SMP_BILL_ID
    HAVING SUM(LINE_BR_ALLWD_AMNT) > 0 AND SUM(LINE_UNITS) > 0
),

final AS (
    SELECT sb.*
    FROM smp_base_raw sb
    INNER JOIN bill_totals bt
        ON sb.SMP_BILL_ID = bt.SMP_BILL_ID
    WHERE sb.clm_first_svc_dt >= '2022-01-01'
)

SELECT * FROM final