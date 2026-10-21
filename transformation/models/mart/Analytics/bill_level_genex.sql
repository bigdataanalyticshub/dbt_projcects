{{ config(
    materialized = "table",
    tags = ['analytics']
) }}

WITH vw_claim_detail_bill AS (SELECT *
                              FROM {{ ref('stg_dwwcs__vw_claim_detail_bill') }}),

     bill AS (SELECT *
              FROM {{ ref('stg_wcsodsdbo__bill') }}),

     customer AS (SELECT *
                  FROM {{ ref('stg_wcsodsadm__customer') }}),

     ppocontract AS (SELECT *
                     FROM {{ ref('stg_wcsodsdbo__ppocontract') }}),

     pposubnetwork AS (SELECT *
                       FROM {{ ref('stg_wcsodsdbo__pposubnetwork') }}),

     vw_claim_detail_billline AS (SELECT *
                                  FROM {{ ref('stg_dwwcs__vw_claim_detail_billline') }}),

     provider AS (SELECT *
                  FROM {{ ref('stg_wcsodsdbo__provider') }}),

     vw_claim_detail_billline_adjsubcatname AS (SELECT *
                                                FROM {{ ref('stg_dwwcs__vw_claim_detail_billline_adjsubcatname') }}),

     genex_special_instructions AS (SELECT * FROM {{ref('stg_dwctshex__genex_special_instructions')}}),

     final as (SELECT
    CASE
    -- Special instructions override all normal criteria for the Genex book of business only
    WHEN b.SITE_CODE IN ('IC1', 'NMI') AND si.comments = 'DELETED BILL' THEN 'N'
    WHEN b.SITE_CODE IN ('IC1', 'NMI') AND si.comments = 'Set REPORTABLE_BILL_FLAG = N' THEN 'N'
    WHEN b.SITE_CODE IN ('IC1', 'NMI') AND si.comments = 'Set REPORTABLE_BILL_FLAG = Y' THEN 'Y'

    -- Functional guards: all normally reportable Genex bills must be finalized
    WHEN COALESCE(b.BILL_STATUS, -1) <> 1 THEN 'N'
    WHEN b.SITE_CODE = 'IC1' AND b.INVOICE_END_DATE IS NULL THEN 'N'

    -- ============================================================
    -- SECTION B: Specific conditions
    -- ============================================================

    -- NEW Beth 8/27 Addition
    WHEN (
    b.SITE_CODE = 'IC1'
    AND LEFT(b.CLIENT_CODE, 2) IN ('00', 'Z0', 'Z7', 'Z8')
    ) THEN 'N'

    -- B1: Westfield Zero Pay
    -- Now Gated to IC1 only
    WHEN (
    b.SITE_CODE = 'IC1'
    AND LEFT(b.CLIENT_CODE, 2) IN ('WF', '79')
    AND b.SUB_PRODUCT_CODE = 'Zero Pay'
    ) THEN 'N'

    -- B10: 18-char composite key with ARC foreign bill
    -- Now Gated to IC1 only
    WHEN (
    b.SITE_CODE = 'IC1'
    AND LENGTH(
        CONCAT_WS(
        '-', b.SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ
        )
    ) = 18
    AND SUBSTR(b.FOREIGN_BILL_ID, 1, 3) = 'ARC'
    AND SUBSTR(b.FOREIGN_BILL_ID, 4, 1) <> '-'
    ) THEN 'N'

    -- B11: CA Joint Powers (IC1 + JC)
    WHEN (
    (
        b.SITE_CODE = 'IC1'
        AND LEFT(b.CLIENT_CODE, 2) = 'JC'
    )
    AND b.CLAIM_SYS_SUBSET = '0374'
    AND SUBSTR(
        CONCAT_WS(
        '-', b.SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ
        ),
        10
    ):: DOUBLE >= 900000000
    ) THEN 'N'

    -- B12: Nationwide IC1
    -- Genex reportable bills must have BILL_STATUS = 1.
    WHEN (
    b.SITE_CODE = 'IC1'
    AND b.BILL_STATUS = 1
    AND LEFT(b.CLIENT_CODE, 2) IN (
        'AO', 'BF', 'GW', 'GX', '50', 'EJ', 'BE',
        'EZ', 'FM'
    )
    ) THEN 'Y'

    -- B13: Nationwide NMI
    -- Genex reportable bills must have BILL_STATUS = 1.
    WHEN (
    b.SITE_CODE = 'NMI'
    AND b.BILL_STATUS = 1
    AND LEFT(b.CLIENT_CODE, 2) IN ('GW', 'GX', 'AO')
    ) THEN 'Y'

    -- ============================================================
    -- SECTION A: Main qualifying condition → 'Y'
    -- Equates to GRDW bill_status_flag = 'P'
    -- 5/1 revised: site-specific BILL_STATUS lists with site-specific date reqs
    -- ============================================================

    WHEN (
    -- IC1: INVOICE_END_DATE NOT NULL AND BILL_STATUS = 1
    (
        b.SITE_CODE = 'IC1'
        AND b.INVOICE_END_DATE IS NOT NULL
        AND b.BILL_STATUS = 1
    )

    -- NMI: BILL_STATUS in (1)
    OR (
        b.SITE_CODE = 'NMI'
        AND b.BILL_STATUS IN (1)
    )
    )
    THEN 'Y' ELSE 'N' END AS genex_reportable_bill_flag,
CASE
        -- Special instructions override all normal criteria for the Mitchell book of business only
        WHEN b.SITE_CODE NOT IN ('IC1', 'NMI') AND si.comments = 'DELETED BILL' THEN 'N'
        WHEN b.SITE_CODE NOT IN ('IC1', 'NMI') AND si.comments = 'Set REPORTABLE_BILL_FLAG = N' THEN 'N'
        WHEN b.SITE_CODE NOT IN ('IC1', 'NMI') AND si.comments = 'Set REPORTABLE_BILL_FLAG = Y' THEN 'Y'

        -- Functional guard: all normally reportable Mitchell bills must have an allowed status
        WHEN COALESCE(b.BILL_STATUS, -1) NOT IN (1, 8, 12) THEN 'N'

        -- B3: Specific FIC-IWNC bill exclusion
        WHEN (
        b.SITE_CODE = 'FIC'
        AND b.CLIENT_CODE = 'IWNC'
        AND b.BILL_SEQ = 21375
        ) THEN 'N'

        -- B4: Sub product code 'V' with COV prefix
        WHEN (
        b.SUB_PRODUCT_CODE = 'V'
        AND SUBSTR(
            CONCAT_WS(
            '-', b.SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ
            ),
            1,
            3
        ) = 'COV'
        ) THEN 'N'

        -- B5: Payment auth codes R/B/2 scoped to specific sites
        WHEN (
        b.PAYMENT_AUTH_CODE IN ('R', 'B', '2')
        AND (
            b.SITE_CODE IN ('SU1', 'FRM', 'FP1', 'SF1')
            OR (
            b.SITE_CODE = 'FIC'
            AND b.SHARED_CLIENT_NAME LIKE 'ICW%'
            )
            OR (
            b.SITE_CODE = 'FIC'
            AND b.CLAIM_SYS_SUBSET = 'GAIC'
            )
        )
        ) THEN 'N'

        -- B6: FP1 claim system AMRV
        WHEN (
        b.SITE_CODE = 'FP1'
        AND b.CLAIM_SYS_SUBSET = 'AMRV'
        ) THEN 'N'

        -- B7: FIC + IW client codes with IWXX substring
        WHEN (
        (
            b.SITE_CODE = 'FIC'
            AND LEFT(b.CLIENT_CODE, 2) = 'IW'
        )
        AND SUBSTR(
            CONCAT_WS(
            '-', b.SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ
            ),
            5,
            4
        ) = 'IWXX'
        ) THEN 'N'

        -- B8: FIC client code USXX
        WHEN (
        b.SITE_CODE = 'FIC'
        AND SUBSTR(
            CONCAT_WS(
                '-', b.SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ
            ),
            5,
            4
        ) = 'USXX'
        ) THEN 'N'

        -- B9: Great American with SCI555555 claim
        WHEN (
        (
            b.SITE_CODE = 'FIC'
            AND LEFT(b.CLIENT_CODE, 2) IN (
            '11', '48', '55', '60', '64', '66', '67',
            '68'
            )
        )
        AND b.CLAIM_NO = 'SCI555555'
        ) THEN 'N'

        -- B14: EMC test bills
        WHEN (
        b.SITE_CODE = 'EC1'
        AND b.CLAIM_NO LIKE 'EMC%99'
        ) THEN 'N'

        -- NEW Beth 8/12 Addition
        WHEN (
        b.SITE_CODE = 'FP1'
        AND LEFT(b.CLIENT_CODE, 2) IN ('GE', 'GX')
        ) THEN 'N'

        -- ============================================================
        -- SECTION A: Main qualifying condition → 'Y'
        -- Equates to GRDW bill_status_flag = 'P'
        -- 5/1 revised: site-specific BILL_STATUS lists with site-specific date reqs
        -- ============================================================

        WHEN (
        -- SU1, FP1, SF1: POST_DATE NOT NULL AND BILL_STATUS in (1,8,12)
        (
            b.SITE_CODE IN ('SU1', 'FP1', 'SF1')
            AND b.POST_DATE IS NOT NULL
            AND b.BILL_STATUS IN (1, 8, 12)
        )

        -- FIC + IW client codes: BILL_STATUS in (1,8,12)
        OR (
            b.SITE_CODE = 'FIC'
            AND LEFT(b.CLIENT_CODE, 2) = 'IW'
            AND b.BILL_STATUS IN (1, 8, 12)
        )

        -- FRM: Mitchell reportable bills must have BILL_STATUS in (1,8,12)
        -- Previously (1,8,12,14)
        OR (
            b.SITE_CODE = 'FRM'
            AND b.BILL_STATUS IN (1, 8, 12)
        )

        -- FIC + Great American number-prefix codes: POST_DATE NOT NULL; Mitchell BILL_STATUS in (1,8,12)
        -- Previously (1,8,12,14)
        OR (
            b.SITE_CODE = 'FIC'
            AND LEFT(b.CLIENT_CODE, 2) IN (
            '11', '48', '55', '60', '64', '66', '67',
            '68'
            )
            AND b.POST_DATE IS NOT NULL
            AND b.BILL_STATUS IN (1, 8, 12)
        )
        ) THEN 'Y'

        ELSE 'N'
    END AS mitchell_reportable_bill_flag,
-- NORMALIZED COLUMNS WITH LEGACY ADJACENT
-- PPO Network ID (normalized and legacy)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'FP'
    else b.ppo_network_id
end ppo_network_id
,
b.PPO_NETWORK_ID AS PPO_NETWORK_ID_LEGACY,

-- PPO Network Name (normalized and legacy)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'FAIRPAY'
    else b.ppo_network_name
end ppo_network_name
,
b.PPO_NETWORK_NAME AS PPO_NETWORK_NAME_LEGACY,

-- Genex Network Name (normalized and legacy)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'Fairpay'
    else b.genex_network_name
end genex_network_name
,
b.GENEX_NETWORK_NAME AS GENEX_NETWORK_NAME_LEGACY,

-- Genex Network ID (normalized and legacy)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'FP'
    else b.genex_network_id
end genex_network_id
,
b.GENEX_NETWORK_ID AS GENEX_NETWORK_ID_LEGACY,

-- Genex Network Subtype Code (normalized and legacy)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'SPEC'
    else b.genex_network_subtype_code
end genex_network_subtype_code
,
b.GENEX_NETWORK_SUBTYPE_CODE AS GENEX_NETWORK_SUBTYPE_CODE_LEGACY,

-- Bill Review Allowed (normalized and legacy)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.cbr_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    else b.bill_review_allowed
end bill_review_allowed
,
b.BILL_REVIEW_ALLOWED AS BILL_REVIEW_ALLOWED_LEGACY,

-- Bill Review Adjustment (normalized and legacy)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(b.bill_review_adjustment,0.0)-nvl(COALESCE(ladj.cbr_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(b.bill_review_adjustment,0.0)-nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    else b.bill_review_adjustment
end bill_review_adjustment
,
b.BILL_REVIEW_ADJUSTMENT AS BILL_REVIEW_ADJUSTMENT_LEGACY,

-- PPO Adjustment (normalized and legacy)
case
    when COALESCE(b4.move_specialty_to_ppo,false) then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(COALESCE(ladj.cbr_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    else 0.0
end
+ nvl(b.ppo_adjustment,0.0) ppo_adjustment,
b.PPO_ADJUSTMENT AS PPO_ADJUSTMENT_LEGACY,

-- PPO Allowed (normalized and legacy)
nvl(b.ppo_allowed,0.0) - case when COALESCE(b4.move_specialty_to_ppo,false) then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0) else 0.0
end ppo_allowed,
b.PPO_ALLOWED AS PPO_ALLOWED_LEGACY,

-- Other Adjustments (normalized and legacy)
case when COALESCE(b4.move_specialty_to_ppo,false) then nvl(b.other_adjustments,0.0) - nvl(COALESCE(ladj.specialtybr_reduction,0),0.0) else b.other_adjustments
end other_adjustments,
b.OTHER_ADJUSTMENTS AS OTHER_ADJUSTMENTS_LEGACY,

-- CALCULATED COLUMNS
-- Helper columns
case when nvl(b.rendering_provider_state,'') <> '' then b.rendering_provider_state else b.billing_provider_practice_state
end as rendering_state_norm,
case when nvl(ppos.GroupCode,'') <> '' then ppos.groupcode else ppoc.groupcode
end AS ppo_sub_network_code,
case when nvl(ppos.GroupName,'') <> '' then ppos.groupname else ppoc.groupname
end AS ppo_sub_network_name,

-- Networks math: Provider Charges minus Bill Review Adjustment
nvl(b.provider_charges, 0.0) - nvl(b.bill_review_adjustment, 0.0) AS bill_review_allowed_networks,

-- Smart Advisor: Provider Charges minus Bill Review Reduction
nvl(b.provider_charges, 0.0) - nvl(COALESCE(ladj.br_reduction,0), 0.0) AS bill_review_allowed_smart_advisor,

-- Reduction columns from ladj
COALESCE(ladj.br_reduction,0) as br_reduction,
COALESCE(ladj.ur_reduction,0) as ur_reduction,
COALESCE(ladj.clinical_reduction,0) as clinical_reduction,
COALESCE(ladj.uc_reduction,0) as uc_reduction,
COALESCE(ladj.auditpro_reduction,0) as auditpro_reduction,
COALESCE(ladj.widb_reduction,0) as widb_reduction,
COALESCE(ladj.physreview_reduction,0) as physreview_reduction,
COALESCE(ladj.adjusterbr_reduction,0) as adjusterbr_reduction,
COALESCE(ladj.implantcbr_reduction,0) as implantcbr_reduction,
COALESCE(ladj.custombr_reduction,0) as custombr_reduction,
COALESCE(ladj.financial_reduction,0) as financial_reduction,
COALESCE(ladj.adjuster_reduction,0) as adjuster_reduction,
COALESCE(ladj.unknown_reduction,0) as unknown_reduction,

-- Main normalized reduction columns
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then 0.0
    else COALESCE(ladj.cbr_reduction,0)
end cbr_reduction
,

case
    when COALESCE(b4.move_specialty_to_ppo,false) then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0) + nvl(COALESCE(ladj.ppo_reduction,0),0.0)
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(COALESCE(ladj.cbr_reduction,0),0.0) + nvl(COALESCE(ladj.ppo_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0) + nvl(COALESCE(ladj.ppo_reduction,0),0.0)
    else nvl(COALESCE(ladj.ppo_reduction,0),0.0)
end ppo_reduction
,

case
    when COALESCE(b4.move_specialty_to_ppo,false) then 0.0
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 0.0
    else COALESCE(ladj.specialtybr_reduction,0)
end specialtybr_reduction
,

-- Additional helper columns
case when b.tob_code='M' then 'Medical'  when b.tob_code='O' then 'Outpatient' when b.tob_code='P' then 'Pharmacy' when b.tob_code='N' then 'NonMedical' when b.tob_code='I' then 'Inpatient' when b.tob_code='S' then 'Supplies' when b.tob_code='D' then 'Dental' when b.tob_code='O' then 'Other' else 'Unknown'
end tob_norm,
b3.post_date first_post_date_in_bill_seq,
case when b.genex_network_name is not null and b.genex_network_subtype_code is null then True else False
end hit_ppo_network,
case when b.genex_network_name is not null and b.genex_network_subtype_code is not null then True else False
end hit_specialty_network,
case when b.negotiated_reduction > 0 or b.speciality_bill_review_reduction > 0 then True else False
end hit_reprice_service,
case when b2.otherbillingproviderseq is not null then 1 else 0
end tin_flip,
b2.ppostacklist,
case when p.tin is not null then p.tin else b.provider_tin
end provider_tin_orig,
case when b.site_code in ('COV','N02','TES') then b.claim_system_description when b.site_code in ('FIC','FP1','IC1') then initcap(b.claim_system_description) else b.customer_name
end shared_customer_name,
year(b.post_date) post_date_year,
quarter(b.post_date) post_date_qtr,
year(b.dos_first) dos_year,
quarter(b.dos_first) dos_qtr,

b.BILL_REVIEW_REDUCTION + COALESCE(b.BILL_REVIEW_FEES, 0.0) as BILL_REVIEW_REDUCTION,

-- FAIRPAY BUCKET CALCULATIONS (POSITIVE VALUES)
(case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.cbr_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    else b.bill_review_allowed
end - b.BILL_REVIEW_ALLOWED) AS fairpay_bill_review_allowed,

((case
    when COALESCE(b4.move_specialty_to_ppo,false) then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(COALESCE(ladj.cbr_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    else 0.0
end + nvl(b.ppo_adjustment,0.0)) - b.PPO_ADJUSTMENT) AS fairpay_ppo_adjustment,

-- Total Fairpay Bucket Amount (POSITIVE)
(case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.cbr_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    else b.bill_review_allowed
end - b.BILL_REVIEW_ALLOWED)
+
((case
    when COALESCE(b4.move_specialty_to_ppo,false) then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then nvl(COALESCE(ladj.cbr_reduction,0),0.0)
    when (b.site_code='ARC' and b.ppo_network_id='NQ')
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
    else 0.0
end + nvl(b.ppo_adjustment,0.0)) - b.PPO_ADJUSTMENT) AS total_fairpay_bucket,

-- Flag to identify records with fairpay bucket amounts
CASE WHEN
  (case
      when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
      or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
      or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
      then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.cbr_reduction,0),0.0)
      when (b.site_code='ARC' and b.ppo_network_id='NQ')
      or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
      or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
      or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
      or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
      or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
      then nvl(b.bill_review_allowed,0.0)+nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
      else b.bill_review_allowed
  end - b.BILL_REVIEW_ALLOWED) != 0 OR
  ((case
      when COALESCE(b4.move_specialty_to_ppo,false) then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
      when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
      or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
      or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
      then nvl(COALESCE(ladj.cbr_reduction,0),0.0)
      when (b.site_code='ARC' and b.ppo_network_id='NQ')
      or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
      or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
      or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
      or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
      or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
      then nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)
      else 0.0
  end + nvl(b.ppo_adjustment,0.0)) - b.PPO_ADJUSTMENT) != 0
THEN 'Y' ELSE 'N'
END AS has_fairpay_bucket,

-- Breakdown of what's driving the fairpay bucket
CASE
    WHEN (b.site_code='ZU1' and b.ppo_network_id='' and nvl(COALESCE(ladj.cbr_reduction,0),0.0)<>0.0)
         OR (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
         OR (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    THEN nvl(COALESCE(ladj.cbr_reduction,0),0.0)

    WHEN (b.site_code='ARC' and b.ppo_network_id='NQ')
         OR (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
         OR (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
         OR (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
         OR (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
         OR (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    THEN nvl(COALESCE(ladj.specialtybr_reduction,0),0.0)

    ELSE 0.0
END
AS fairpay_source_reduction,
b.genex_claim_type_code,
b.genex_claim_type_description,
-- ALL REMAINING WCS COLUMNS (not used in normalized sections above)
b.ODS_CUSTOMER_ID,
b.CUSTOMER_NAME,
b.DATABASE_UNIQUE_ID,
b.INCLUDE_IN_INDUSTRY_FLAG,
b.SOURCE_SERVER,
b.CLIENT_CODE,
b.CLIENT_NAME,
b.CLIENT_CLAIM_SYS_SUBSET,
b.GEO_STATE,
b.JURISDICTION_DESCRIPTION,
b.EDI_JURISDICTION,
b.PRODUCT_CODE,
b.PRODUCT_CODE_DESC,
b.CONTROL_NUMBER,
b.SHARED_CLIENT_NAME,
b.CONFORMED_CLAIM_INJURY_NATURE_DESCRIPTION,
b.CONFORMED_CLAIM_INJURY_NATURE_ID,
b.CLAIM_SEQ,
b.CLAIM_NO,
b.CLAIM_SYS_SUBSET,
b.CLAIM_SYSTEM_DESCRIPTION,
b.LINE_OF_BUSINESS,
b.DOI,
b.CLAIM_DATE_OF_INJURY_DAY,
b.CLAIM_DATE_OF_INJURY_MONTH,
b.CLAIM_DATE_OF_INJURY_QUARTER,
b.CLAIM_DATE_OF_INJURY_YEAR,
b.CLAIM_FIRST_BILL_CREATE_DATE,
b.CLAIM_TYPE,
b.CLAIM_TYPE_DESCRIPTION,
b.CLAIM_INJURY_DESCRIPTION,
b.CLAIM_JURISDICTION,
b.DERIVED_JURISDICTION,
b.CLAIM_PRODUCT_CODE,
b.CLAIM_PRODUCT_CODE_DESCRIPTION,
b.CLAIM_STATUS,
b.CLAIMANT_EXPECTED_TENURE_IN_DAYS,
b.CLAIM_MINIMUM_DOS,
b.CLAIM_MAXIMUM_DOS,
b.INSURER_NAME,
b.INSURER_TIN,
b.EXTERNAL_CLAIM_ID,
b.EXTERNAL_POLICY_ID,
b.CLAIM_CREATE_DATE,
b.CLAIM_CREATE_DATE_DAY,
b.CLAIM_CREATE_DATE_MONTH,
b.CLAIM_CREATE_DATE_YEAR,
b.GB_PROGRAM_NUMBER,
b.GB_PROGRAM_NAME,
b.BILL_PROVIDER_SEQ,
b.PROVIDER_SUB_SET,
b.PROVIDER_FIRST_NAME,
b.PROVIDER_MIDDLE_NAME,
b.PROVIDER_LAST_NAME,
b.RENDERING_PROVIDER_NPI,
b.RENDERING_PROVIDER_STATE,
b.RENDERING_PROVIDER_LICENSE_NUMBER,
b.RENDERING_PROVIDER_INVOICE,
b.PROVIDER_TIN,
b.PROVIDER_TIN_SUFFIX,
b.PVD_FIRST_NAME,
b.BILLING_PROVIDER_MIDDLE_NAME,
b.PVD_LAST_NAME,
b.PROVIDER_NAME,
b.BILLING_PROVIDER_NPI,
b.PROVIDER_TYPE,
b.BILLING_PROVIDER_PHYSICAL_ADDRESS_1,
b.BILLING_PROVIDER_PHYSICAL_ADDRESS_2,
b.BILLING_PROVIDER_PHYSICAL_CITY,
b.BILLING_PROVIDER_PHYSICAL_COUNTY,
b.BILLING_PROVIDER_ZIP_CODE,
b.FACILITY_PROVIDER_NPI,
b.PROVIDER_PHYSICAL_STATE,
b.BILLING_PROVIDER_PRACTICE_ADDRESS_1,
b.BILLING_PROVIDER_PRACTICE_ADDRESS_2,
b.BILLING_PROVIDER_PRACTICE_CITY,
b.BILLING_PROVIDER_PRACTICE_COUNTY,
b.BILLING_PROVIDER_PRACTICE_STATE,
b.BILLING_PROVIDER_PRACTICE_ZIP,
b.REFERRING_PROVIDER_FIRST_NAME,
b.REFERRING_PROVIDER_LAST_NAME,
b.REFERRING_PROVIDER_MIDDLE_NAME,
b.REFERRING_PROVIDER_SUFFIX,
b.BILL_OTHER_BILLING_PROVIDER_SEQ,
b.BILL_OTHER_BILLING_PROVIDER_SUBSET,
b.BILL_PROVIDER_BILLING_TAXONOMY,
b.BILL_PROVIDER_RENDERING_TAXONOMY,
b.BILL_PROVIDER_FACILITY_TAXONOMY,
b.BILL_PROVIDER_MEDICARE_NUMBER,
b.BILL_PROVIDER_ZIP_CODE,
b.PROVIDER_SPECIALTY_1,
b.PROVIDER_MEDICARE_NUMBER,
b.PROVIDER_CREATE_DATE,
b.PROVIDER_MOD_DATE,
b.PEND_DATE,
b.PEND_RELEASE_DATE,
b.PEND_RELEASE_FLAG,
b.PEND_TO_ID,
b.ADJUSTER_FIRST_NAME,
b.ADJUSTER_LAST_NAME,
b.BILL_SEQ,
b.SITE_CODE,
b.AUDITPRO_SITE_CODE_FLAG,
b.LINE_COUNT,
b.TOTAL_UNITS,
b.TOTAL_ALLOWED,
b.DUPLICATE_BILL_FLAG,
b.PLACE_OF_SERVICE,
b.POS_DESCRIPTION,
b.SUB_PRODUCT_CODE,
b.TOB_CODE,
b.TOB,
b.UB_TYPE_OF_BILL,
b.UB_TYPE_OF_BILL_DESCRIPTION,
b.PAID_AMOUNT,
b.CARRIER_RECEIVED_DATE,
b.BILL_STATUS,
b.BILL_STATUS_DESCRIPTION,
b.DOS_FIRST,
b.DOS_LAST,
b.BILL_INJURY_DESCRIPTION,
b.DOCUMENT_ID,
b.DUE_DATE,
b.CREATE_DATE,
b.BILL_CREATE_DATE_DAY,
b.BILL_CREATE_DATE_MONTH,
b.BILL_CREATE_DATE_QUARTER,
b.BILL_CREATE_DATE_WEEK,
b.BILL_CREATE_DATE_YEAR,
b.POST_DATE,
b.BILL_POST_DATE_MONTH,
b.BILL_POST_DATE_YEAR,
b.PAID_DATE,
b.BILL_REVIEW_RECEIVED_DATE,
b.BILL_SEQ_ORG_REV,
b.BILL_REEVAL_COUNT,
b.FIRST_BILL_IN_REEVAL_SEQUENCE,
b.LAST_BILL_IN_REEVAL_SEQUENCE,
b.RE_EVAL_FLAG,
b.PRIOR_TOTAL_ALLOWED,
b.PRIOR_BILL_ZERO_ALLOWED_FLAG,
b.PRIOR_BILL_POST_DATE,
b.BILL_ZERO_ALLOWED_FLAG,
b.BILLED_SERVICE_CODE,
b.CHECK_NUMBER,
b.DAYS_SUPPLY,
b.FOREIGN_BILL_ID,
b.INCREMENT_VALUE,
b.INVOICE_END_DATE,
b.MESSAGE_205_OR_270_FLAG,
b.AUDITPRO_REEVAL_FLAG,
b.AUDITPRO_ELIGIBLE,
b.ADMISSION_DATE,
b.PROVIDER_CHARGES,
b.BILL_STATEMENT_FROM_DATE,
b.BILL_STATEMENT_THROUGH_DATE,
b.DRG_CALCULATED,
b.EOB_COMMENTS,
b.ORIGINAL_BILL_FLAG,
b.ADJUSTOR_DENIAL_FLAG,
b.REVIEW_ONLY_FLAG,
b.HIGHEST_POSITIVE_FLAG,
b.ADJUSTER_BILL_REVIEW_REDUCTION,
b.ADJUSTER_REVIEW_REDUCTION,
b.AUDITPRO_SAVINGS,
b.AUDITPRO_REDUCTION_TREND,
b.BILL_REVIEW_FEES,
b.BILL_REVIEW_RETAIL_FEES,
b.BILL_REVIEW_WHOLESALE_FEES,
b.CLIENT_SPECIFIC_8800_REDUCTION,
b.CLIENT_SPECIFIC_8850_REDUCTION,
b.CLIENT_SPECIFIC_8900_REDUCTION,
b.CLINICAL_REVIEW_REDUCTION,
b.CO_PAY_REDUCTION,
b.COMPLEX_BILL_REVIEW_REDUCTION,
b.CUSTOM_ADJUSTER_DENIAL_REDUCTION,
b.CUSTOM_BILL_REVIEW_REDUCTION,
b.CUSTOM_BILL_REVIEW_RETAIL_FEE,
b.CUSTOM_BILL_REVIEW_WHOLESALE_FEE,
b.CUSTOM_CLINICAL_VALIDATION_REDUCTION,
b.CUSTOM_CLINICAL_VALIDATION_RETAIL_FEE,
b.CUSTOM_CLINICAL_VALIDATION_WHOLESALE_FEE,
b.CUSTOM_DUPLICATE_REDUCTION,
b.CUSTOM_ENHANCED_SYSTEM_SAVINGS_REDUCTION,
b.CUSTOM_ENHANCED_SYSTEM_SAVINGS_RETAIL_FEE,
b.CUSTOM_ENHANCED_SYSTEM_SAVINGS_WHOLESALE_FEE,
b.CUSTOM_EXCLUSION_REDUCTION,
b.CUSTOM_EXCLUSION_SAVINGS_RETAIL_FEE,
b.CUSTOM_EXCLUSION_SAVINGS_WHOLESALE_FEE,
b.CUSTOM_FEE_SCHEDULE_REDUCTION,
b.CUSTOM_FORESIGHT_REDUCTION,
b.CUSTOM_FORESIGHT_RETAIL_FEES,
b.CUSTOM_FORESIGHT_WHOLESALE_FEES,
b.CUSTOM_ICBR_RETAIL_FEE,
b.CUSTOM_ICBR_WHOLESALE_FEE,
b.CUSTOM_NEGOTIATED_REDUCTION,
b.CUSTOM_OON_REDUCTION,
b.CUSTOM_OON_RETAIL_FEE,
b.CUSTOM_OON_WHOLESALE_FEE,
b.CUSTOM_PPO_REDUCTION,
b.CUSTOM_PPO_RETAIL_FEE,
b.CUSTOM_PPO_WHOLESALE_FEE,
b.DEDUCTIBLE_REDUCTION,
b.ENHANCED_SYSTEM_SAVINGS_REDUCTION,
b.FEE_SCHEDULE_REDUCTIONS,
b.FINANCIAL_LIMIT_REDUCTION,
b.IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION,
b.NEGOTIATED_REDUCTION,
b.NEGOTIATIONS_ADJUSTMENT,
b.NEGOTIATIONS_RETAIL_FEES,
b.NEGOTIATIONS_SUCCESSFUL_FLAG,
b.NEGOTIATIONS_WHOLESALE_FEES,
b.NET_AUDITPRO_REDUCTION,
b.NURSE_CONSULTANT_REVIEW_REDUCTION,
b.TOTAL_OVERRIDE_AMOUNT,
b.OTHER_RETAIL_FEES,
b.OTHER_WHOLESALE_FEES,
b.PHYSICIAN_ADVISOR_REVIEW_REDUCTION,
b.PPO_RETAIL_FEES,
b.PPO_WHOLESALE_FEES,
b.ADJUSTMENT,
b.REDUCTION_WITHOUT_RETAIL_FEE,
b.REDUCTION_WITHOUT_WHOLSALE_FEE,
b.REPRICING_NETWORK_REDUCTION,
b.SPECIALITY_BILL_REVIEW_REDUCTION,
b.TOTAL_COMPLEX_BILL_REVIEW_RETAIL_FEE,
b.TOTAL_COMPLEX_BILL_REVIEW_WHOLESALE_FEE,
b.TOTAL_NURSE_CONSULTANT_REVIEW_RETAIL_FEE,
b.TOTAL_NURSE_CONSULTANT_REVIEW_WHOLESALE_FEE,
b.TOTAL_RETAIL_FEES,
b.TOTAL_WHOLESALE_FEES,
b.USUAL_CUSTOMARY_SPECIALTY_REDUCTION,
b.UTILIZATION_REVIEW_REDUCTION,
b.PATIENT_FIRST_NAME,
b.PATIENT_LAST_NAME,
b.PATIENT_MIDDLE_NAME,
b.PATIENT_DOB,
b.PATIENT_CITY,
b.PATIENT_STATE,
b.PATIENT_ID,
b.PATIENT_GENDER,
b.PRIMARY_CLAIM_DIAGNOSIS_CODE,
b.DIAGNOSIS_CODE_1,
b.DIAGNOSIS_CODE_1_DESCRIPTION,
b.DIAGNOSIS_CODE_2,
b.DIAGNOSIS_CODE_2_DESCRIPTION,
b.DIAGNOSIS_CODE_3,
b.DIAGNOSIS_CODE_3_DESCRIPTION,
b.DIAGNOSIS_CODE_4,
b.DIAGNOSIS_CODE_4_DESCRIPTION,
b.DIAGNOSIS_CODE_5,
b.DIAGNOSIS_CODE_5_DESCRIPTION,
b.DIAGNOSIS_CODE_6,
b.DIAGNOSIS_CODE_6_DESCRIPTION,
b.DIAGNOSIS_SET,
b.DIAGNOSIS_SET_DESCRIPTION,
b.PPO_CONTRACT_ID,
b.PPO_CONTRACT_PRODUCT_CODE,
b.PPO_IN_NETWORK_FLAG,
b.PPO_NETWORK_TYPE,
b.PPO_SUBNETWORK_ID,
b.PPO_SUBNETWORK_NAME,
b.NETWORK_SERVICE_TYPE,
b.PPO_STACKLIST,
b.POLICY_ID,
b.POLICY_NAME,
b.POLICY_EFFECTIVE_DATE,
b.POLICY_ADMIN_KEY,
b.POLICY_TIN,
b.POLICY_TERMINATION_DATE,
b.POLICY_STATE_TAX_ID,
b.POLICY_SELF_INSURED_FLAG,
b.POLICY_TX_NON_SUBSCRIBER_FLAG,
b.POLICY_NAICS_CODE,
b.PAYMENT_AUTH_CODE,
b.PAYMENT_EXPORT_DATE,
b.WORKFLOW_TASK,
b.TASK_MESSAGE,
b.GENEX_PRIMARY_DX_BODY_PART,
b.END_TO_END_TAT_EX,
b.TAT_BILL_REVIEW_RECEIVED_TO_POST_DATE,
b.TAT_CARRIER_RECEIVED_TO_POST_DATE,
b.RRS_CACN_MATCH_SCORE_SET,
b.RRS_CACN_SET,
b.RUNDATE

FROM vw_claim_detail_bill b
LEFT JOIN genex_special_instructions si ON CONCAT_WS('-', b.SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ) = si.item_id
LEFT JOIN bill b2 ON (b.ods_customer_id=b2.odscustomerid and b.site_code=b2.sitecode and b.client_code=b2.clientcode and b.bill_seq=b2.billseq)
JOIN customer c ON b2.odscustomerid = c.customer_id
LEFT JOIN ppocontract ppoc ON (ppoc.PPONetworkID = b2.PPONetworkID AND ppoc.PPOContractID = b2.PPOContractID and ppoc.sitecode=b2.sitecode and c.server_name = ppoc.servername)
LEFT JOIN pposubNetwork ppos ON (ppos.PPONetworkID = ppoc.PPONetworkID AND ppos.GroupCode = ppoc.GroupCode and ppos.sitecode=ppoc.sitecode and ppos.servername=ppoc.servername)
LEFT JOIN vw_claim_detail_bill b3 ON (b.ods_customer_id=b3.ods_customer_id and b.site_code=b3.site_code and b.client_code=b3.client_code and b.first_bill_in_reeval_sequence=b3.bill_seq)
LEFT JOIN (SELECT ods_customer_id, site_code, client_code, ppo_network_id, bill_seq, case when (site_code in ('BRS','FP1') and ppo_network_id in ('FP','KP','NQ')) or (site_code in ('CPI') and ppo_network_id in ('FP','KP')) or (site_code in ('GUA','SEN') and ppo_network_id in ('FP','NQ')) then True else False end move_specialty_to_ppo from vw_claim_detail_bill) b4 ON (b.ods_customer_id=b4.ods_customer_id and b.site_code=b4.site_code and b.client_code=b4.client_code and b.bill_seq=b4.bill_seq)
LEFT JOIN provider p ON (b2.odscustomerid=p.odscustomerid and b2.otherbillingproviderseq=p.providerseq and b2.otherbillingprovidersubset=p.providersubset)
LEFT JOIN (
    SELECT
        site_code, ods_customer_id, client_code, bill_seq,
        SUM(br_reduction) as br_reduction,
        SUM(ur_reduction) as ur_reduction,
        SUM(clinical_reduction) as clinical_reduction,
        SUM(uc_reduction) as uc_reduction,
        SUM(auditpro_reduction) as auditpro_reduction,
        SUM(widb_reduction) as widb_reduction,
        SUM(cbr_reduction) as cbr_reduction,
        SUM(physreview_reduction) as physreview_reduction,
        SUM(adjusterbr_reduction) as adjusterbr_reduction,
        SUM(implantcbr_reduction) as implantcbr_reduction,
        SUM(ppo_reduction) as ppo_reduction,
        SUM(specialtybr_reduction) as specialtybr_reduction,
        SUM(custombr_reduction) as custombr_reduction,
        SUM(financial_reduction) as financial_reduction,
        SUM(adjuster_reduction) as adjuster_reduction,
        SUM(unknown_reduction) as unknown_reduction
    FROM (
        SELECT
            site_code, ods_customer_id, client_code, bill_seq, line_seq,
            CASE WHEN reduction_bucket = 'br_reduction' THEN adjustment ELSE 0 END as br_reduction,
            CASE WHEN reduction_bucket = 'ur_reduction' THEN adjustment ELSE 0 END as ur_reduction,
            CASE WHEN reduction_bucket = 'clinical_reduction' THEN adjustment ELSE 0 END as clinical_reduction,
            CASE WHEN reduction_bucket = 'uc_reduction' THEN adjustment ELSE 0 END as uc_reduction,
            CASE WHEN reduction_bucket = 'auditpro_reduction' THEN adjustment ELSE 0 END as auditpro_reduction,
            CASE WHEN reduction_bucket = 'widb_reduction' THEN adjustment ELSE 0 END as widb_reduction,
            CASE WHEN reduction_bucket = 'cbr_reduction' THEN adjustment ELSE 0 END as cbr_reduction,
            CASE WHEN reduction_bucket = 'physreview_reduction' THEN adjustment ELSE 0 END as physreview_reduction,
            CASE WHEN reduction_bucket = 'adjusterbr_reduction' THEN adjustment ELSE 0 END as adjusterbr_reduction,
            CASE WHEN reduction_bucket = 'implantcbr_reduction' THEN adjustment ELSE 0 END as implantcbr_reduction,
            CASE WHEN reduction_bucket = 'ppo_reduction' THEN adjustment ELSE 0 END as ppo_reduction,
            CASE WHEN reduction_bucket = 'specialtybr_reduction' THEN adjustment ELSE 0 END as specialtybr_reduction,
            CASE WHEN reduction_bucket = 'custombr_reduction' THEN adjustment ELSE 0 END as custombr_reduction,
            CASE WHEN reduction_bucket = 'financial_reduction' THEN adjustment ELSE 0 END as financial_reduction,
            CASE WHEN reduction_bucket = 'adjuster_reduction' THEN adjustment ELSE 0 END as adjuster_reduction,
            CASE WHEN reduction_bucket = 'unknown_reduction' THEN adjustment ELSE 0 END as unknown_reduction
        FROM (
            SELECT
                site_code, ods_customer_id, client_code, bill_seq, line_seq,
                CASE
                    WHEN reduction_bucket in ('Bill Review') THEN 'br_reduction'
                    WHEN reduction_bucket in ('Utilization Review','UTILIZATION REVIEW','Nurse Consultant Review','Paradigm Review','Physician Advisor Review') THEN 'ur_reduction'
                    WHEN reduction_bucket in ('Clinical Review') THEN 'clinical_reduction'
                    WHEN reduction_bucket in ('U&C Specialty Review') THEN 'uc_reduction'
                    WHEN reduction_bucket in ('AuditPro Code Review','AuditPro','Mitchell AuditPro','AUDITPRO SAVINGS','AuditPro','AuditPro') THEN 'auditpro_reduction'
                    WHEN reduction_bucket in ('WISCONSIN (WI) CERTIFIED DATABASE') THEN 'widb_reduction'
                    WHEN reduction_bucket in ('Complex Bill Review','ComplexBillReview') THEN 'cbr_reduction'
                    WHEN reduction_bucket in ('Physician Advisor Review') THEN 'physreview_reduction'
                    WHEN reduction_bucket in ('Adjuster Reductions','Examiner Review','Adjuster Bill Review','LM ADJUSTMENTS') THEN 'adjusterbr_reduction'
                    WHEN reduction_bucket in ('Implant Complex Bill Review') THEN 'implantcbr_reduction'
                    WHEN reduction_bucket in ('PPO') THEN 'ppo_reduction'
                    WHEN reduction_bucket in ('NGD SERVICES','Out of Network Review') THEN 'specialtybr_reduction'
                    WHEN reduction_bucket in ('Negotiated Discount','Pre-Cert Penalty','CLIENT DIRECTED PPO','Reduction Bucket 8800','IMPLANTS SPECIALTY REVIEW','Negotiations',
                                             'Reduction Bucket 8850','Voluntary Utilization Network Pena','Health Care Offset','Reduction Bucket 8900','IMPLANT SAVINGS') THEN 'custombr_reduction'
                    WHEN reduction_bucket in ('APPORTIONMENT','Copay','Deductible','Financial Limit') THEN 'financial_reduction'
                    WHEN reduction_bucket in ('Adjuster Review') THEN 'adjuster_reduction'
                    ELSE 'unknown_reduction'
                END as reduction_bucket,
                adjustment
            FROM vw_claim_detail_billline_adjsubcatname
        )
    )
    GROUP BY site_code, ods_customer_id, client_code, bill_seq
) ladj ON b.site_code=ladj.site_code AND b.ods_customer_id=ladj.ods_customer_id AND b.client_code=ladj.client_code AND b.bill_seq=ladj.bill_seq

WHERE 1=1
AND b.ods_customer_id <> 502
AND b.site_code <> '@@@'
AND b.claim_sys_subset NOT IN ('9999','0000','XXXX','TEST')
AND b.claim_system_description NOT IN ('SUPPORT TEST ACCOUNT-UC', 'TEST CLAIM SYSTEM', 'TEST - AMCC','TEST', 'TEST ACCOUNTS', 'TEST - BRICKSTREET', 'UCR TEST','MEDICARE TEST')
AND NOT (b.site_code='COV' AND b.sub_product_code = 'RE-EVAL CANCELLATION')
AND b.duplicate_bill_flag = FALSE
AND b.client_code != 'UTST'
AND b.claim_sys_subset != 'TRNG'
AND (b.CARRIER_RECEIVED_DATE IS NULL OR year(b.CARRIER_RECEIVED_DATE) != 1900)
)

select distinct *
from final