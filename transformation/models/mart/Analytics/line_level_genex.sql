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

vw_claim_detail_billline_adjsubcatname AS (
    SELECT *
    FROM {{ ref('stg_dwwcs__vw_claim_detail_billline_adjsubcatname') }}
),

/* ---------------- Line-level reductions ---------------- */
ladj AS (
    SELECT
        site_code,
        ods_customer_id,
        client_code,
        bill_seq,
        line_seq,

        SUM(CASE WHEN reduction_bucket = 'br_reduction' THEN adjustment ELSE 0 END) AS br_reduction,
        SUM(CASE WHEN reduction_bucket = 'ur_reduction' THEN adjustment ELSE 0 END) AS ur_reduction,
        SUM(CASE WHEN reduction_bucket = 'clinical_reduction' THEN adjustment ELSE 0 END) AS clinical_reduction,
        SUM(CASE WHEN reduction_bucket = 'uc_reduction' THEN adjustment ELSE 0 END) AS uc_reduction,
        SUM(CASE WHEN reduction_bucket = 'auditpro_reduction' THEN adjustment ELSE 0 END) AS auditpro_reduction,
        SUM(CASE WHEN reduction_bucket = 'widb_reduction' THEN adjustment ELSE 0 END) AS widb_reduction,
        SUM(CASE WHEN reduction_bucket = 'cbr_reduction' THEN adjustment ELSE 0 END) AS cbr_reduction,
        SUM(CASE WHEN reduction_bucket = 'physreview_reduction' THEN adjustment ELSE 0 END) AS physreview_reduction,
        SUM(CASE WHEN reduction_bucket = 'adjusterbr_reduction' THEN adjustment ELSE 0 END) AS adjusterbr_reduction,
        SUM(CASE WHEN reduction_bucket = 'implantcbr_reduction' THEN adjustment ELSE 0 END) AS implantcbr_reduction,
        SUM(CASE WHEN reduction_bucket = 'ppo_reduction' THEN adjustment ELSE 0 END) AS ppo_reduction,
        SUM(CASE WHEN reduction_bucket = 'specialtybr_reduction' THEN adjustment ELSE 0 END) AS specialtybr_reduction,
        SUM(CASE WHEN reduction_bucket = 'custombr_reduction' THEN adjustment ELSE 0 END) AS custombr_reduction,
        SUM(CASE WHEN reduction_bucket = 'financial_reduction' THEN adjustment ELSE 0 END) AS financial_reduction,
        SUM(CASE WHEN reduction_bucket = 'adjuster_reduction' THEN adjustment ELSE 0 END) AS adjuster_reduction,
        SUM(CASE WHEN reduction_bucket = 'unknown_reduction' THEN adjustment ELSE 0 END) AS unknown_reduction
    FROM (
        SELECT
            site_code,
            ods_customer_id,
            client_code,
            bill_seq,
            line_seq,
            CASE
                WHEN reduction_bucket IN ('Bill Review') THEN 'br_reduction'
                WHEN reduction_bucket IN ('Utilization Review','UTILIZATION REVIEW','Nurse Consultant Review',
                                          'Paradigm Review','Physician Advisor Review') THEN 'ur_reduction'
                WHEN reduction_bucket IN ('Clinical Review') THEN 'clinical_reduction'
                WHEN reduction_bucket IN ('U&C Specialty Review') THEN 'uc_reduction'
                WHEN reduction_bucket IN ('AuditPro Code Review','AuditPro','Mitchell AuditPro','AUDITPRO SAVINGS') THEN 'auditpro_reduction'
                WHEN reduction_bucket IN ('WISCONSIN (WI) CERTIFIED DATABASE') THEN 'widb_reduction'
                WHEN reduction_bucket IN ('Complex Bill Review','ComplexBillReview') THEN 'cbr_reduction'
                WHEN reduction_bucket IN ('Physician Advisor Review') THEN 'physreview_reduction'
                WHEN reduction_bucket IN ('Adjuster Reductions','Examiner Review','Adjuster Bill Review','LM ADJUSTMENTS') THEN 'adjusterbr_reduction'
                WHEN reduction_bucket IN ('Implant Complex Bill Review') THEN 'implantcbr_reduction'
                WHEN reduction_bucket IN ('PPO') THEN 'ppo_reduction'
                WHEN reduction_bucket IN ('NGD SERVICES','Out of Network Review') THEN 'specialtybr_reduction'
                WHEN reduction_bucket IN (
                    'Negotiated Discount','Pre-Cert Penalty','CLIENT DIRECTED PPO',
                    'Reduction Bucket 8800','IMPLANTS SPECIALTY REVIEW',
                    'Negotiations','Reduction Bucket 8850','Reduction Bucket 8900'
                ) THEN 'custombr_reduction'
                WHEN reduction_bucket IN ('APPORTIONMENT','Copay','Deductible','Financial Limit') THEN 'financial_reduction'
                WHEN reduction_bucket IN ('Adjuster Review') THEN 'adjuster_reduction'
                ELSE 'unknown_reduction'
            END AS reduction_bucket,
            adjustment
        FROM vw_claim_detail_billline_adjsubcatname
    )
    GROUP BY site_code, ods_customer_id, client_code, bill_seq, line_seq
),
genex_special_instructions AS (SELECT * FROM {{ref('stg_dwctshex__genex_special_instructions')}}),
final AS (
SELECT
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
case
when max(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then 1 else 0
end) over (partition by b.ods_customer_id, b.site_code, b.client_code, b.bill_seq) = 1
then 'FP'
else l.ppo_network_id
end ppo_network_id,
l.PPO_NETWORK_ID AS PPO_NETWORK_ID_LEGACY,
case
when max(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then 1 else 0
end) over (partition by b.ods_customer_id, b.site_code, b.client_code, b.bill_seq) = 1
then 'FAIRPAY'
else l.ppo_network_name
end ppo_network_name,
l.PPO_NETWORK_NAME AS PPO_NETWORK_NAME_LEGACY,
case
when max(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then 1 else 0
end) over (partition by b.ods_customer_id, b.site_code, b.client_code, b.bill_seq) = 1
then 'Fairpay'
else l.genex_network_name
end genex_network_name,
l.GENEX_NETWORK_NAME AS GENEX_NETWORK_NAME_LEGACY,
case
when max(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then 1 else 0
end) over (partition by b.ods_customer_id, b.site_code, b.client_code, b.bill_seq) = 1
then 'FP'
else l.genex_network_id
end genex_network_id,
l.GENEX_NETWORK_ID AS GENEX_NETWORK_ID_LEGACY,
case
when max(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then 1 else 0
end) over (partition by b.ods_customer_id, b.site_code, b.client_code, b.bill_seq) = 1
then 'SPEC'
else l.genex_network_subtype_code
end genex_network_subtype_code,
l.GENEX_NETWORK_SUBTYPE_CODE AS GENEX_NETWORK_SUBTYPE_CODE_LEGACY,

-- Bill Review Allowed (normalized and legacy)
case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(l.bill_review_allowed,0.0)+nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(l.bill_review_allowed,0.0)+nvl(specialtybr_reduction,0.0)
else l.bill_review_allowed
end bill_review_allowed,
l.BILL_REVIEW_ALLOWED AS BILL_REVIEW_ALLOWED_LEGACY,

-- Bill Review Adjustment (normalized and legacy)
case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(l.bill_review_adjustment,0.0)-nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(l.bill_review_adjustment,0.0)-nvl(specialtybr_reduction,0.0)
else l.bill_review_adjustment
end bill_review_adjustment,
l.BILL_REVIEW_ADJUSTMENT AS BILL_REVIEW_ADJUSTMENT_LEGACY,

-- PPO Adjustment (normalized and legacy)
case
when move_specialty_to_ppo then nvl(specialtybr_reduction,0.0)
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(specialtybr_reduction,0.0)
else 0.0
end + nvl(l.ppo_adjustment,0.0) ppo_adjustment,
l.PPO_ADJUSTMENT AS PPO_ADJUSTMENT_LEGACY,

-- PPO Allowed (normalized and legacy)
nvl(l.ppo_allowed,0.0) - case when move_specialty_to_ppo then nvl(specialtybr_reduction,0.0) else 0.0 end ppo_allowed,
l.PPO_ALLOWED AS PPO_ALLOWED_LEGACY,

-- Other Adjustments (normalized and legacy)
case when move_specialty_to_ppo then nvl(l.other_adjustments,0.0) - nvl(specialtybr_reduction,0.0) else l.other_adjustments end other_adjustments,
l.OTHER_ADJUSTMENTS AS OTHER_ADJUSTMENTS_LEGACY,

-- CALCULATED COLUMNS
-- Helper columns
case when nvl(b.rendering_provider_state,'') <> '' then b.rendering_provider_state else b.billing_provider_practice_state end as rendering_state_norm,
case when nvl(ppos.GroupCode,'') <> '' then ppos.groupcode else ppoc.groupcode end AS ppo_sub_network_code,
case when nvl(ppos.GroupName,'') <> '' then ppos.groupname else ppoc.groupname end AS ppo_sub_network_name,

-- Networks math: Provider Charges minus Bill Review Adjustment
nvl(l.provider_charges, 0.0) - nvl(l.bill_review_adjustment, 0.0) AS bill_review_allowed_networks,

-- Smart Advisor: Provider Charges minus Bill Review Reduction
nvl(l.provider_charges, 0.0) - nvl(br_reduction, 0.0) AS bill_review_allowed_smart_advisor,

-- Reduction columns
br_reduction,
ur_reduction,
clinical_reduction,
uc_reduction,
auditpro_reduction,
widb_reduction,

-- Main normalized reduction columns
case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then 0.0
else cbr_reduction
end cbr_reduction,

physreview_reduction,
adjusterbr_reduction,
implantcbr_reduction,

case
when move_specialty_to_ppo then nvl(specialtybr_reduction,0.0)
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(specialtybr_reduction,0.0)
else 0.0
end + nvl(ppo_reduction,0.0) ppo_reduction,

case
when move_specialty_to_ppo then 0.0
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then 0.0
else specialtybr_reduction
end specialtybr_reduction,

custombr_reduction,
financial_reduction,
adjuster_reduction,
unknown_reduction,

-- Additional helper columns
case when b.tob_code='M' then 'Medical' when b.tob_code='O' then 'Outpatient' when b.tob_code='P' then 'Pharmacy' when b.tob_code='N' then 'NonMedical' when b.tob_code='I' then 'Inpatient' when b.tob_code='S' then 'Supplies' when b.tob_code='D' then 'Dental' when b.tob_code='O' then 'Other' else 'Unknown' end tob_norm,
b3.post_date first_post_date_in_bill_seq,
case when l.genex_network_name is not null and l.genex_network_subtype_code is null then True else False end hit_ppo_network,
case when l.genex_network_name is not null and l.genex_network_subtype_code is not null then True else False end hit_specialty_network,
case when b.negotiated_reduction > 0 or b.speciality_bill_review_reduction > 0 then True else False end hit_reprice_service,
case when b2.otherbillingproviderseq is not null then 1 else 0 end tin_flip,
b2.ppostacklist,
case when p.tin is not null then p.tin else b.provider_tin end provider_tin_orig,
case when b.site_code in ('COV','N02','TES') then b.claim_system_description when b.site_code in ('FIC','FP1','IC1') then initcap(b.claim_system_description) else b.customer_name end shared_customer_name,
year(l.post_date) post_date_year,
quarter(l.post_date) post_date_qtr,
year(l.dos_first) dos_year,
quarter(l.dos_first) dos_qtr,
1 lines,

-- FAIRPAY BUCKET CALCULATIONS (POSITIVE VALUES)
(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(l.bill_review_allowed,0.0)+nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(l.bill_review_allowed,0.0)+nvl(specialtybr_reduction,0.0)
else l.bill_review_allowed
end - l.BILL_REVIEW_ALLOWED) AS fairpay_bill_review_allowed,

((case
when move_specialty_to_ppo then nvl(specialtybr_reduction,0.0)
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(specialtybr_reduction,0.0)
else 0.0
end + nvl(l.ppo_adjustment,0.0)) - l.PPO_ADJUSTMENT) AS fairpay_ppo_adjustment,

-- Total Fairpay Bucket Amount (POSITIVE)
(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(l.bill_review_allowed,0.0)+nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(l.bill_review_allowed,0.0)+nvl(specialtybr_reduction,0.0)
else l.bill_review_allowed
end - l.BILL_REVIEW_ALLOWED) +
((case
when move_specialty_to_ppo then nvl(specialtybr_reduction,0.0)
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(specialtybr_reduction,0.0)
else 0.0
end + nvl(l.ppo_adjustment,0.0)) - l.PPO_ADJUSTMENT) AS total_fairpay_bucket,

-- Flag to identify records with fairpay bucket amounts
CASE WHEN
(case
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(l.bill_review_allowed,0.0)+nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(l.bill_review_allowed,0.0)+nvl(specialtybr_reduction,0.0)
else l.bill_review_allowed
end - l.BILL_REVIEW_ALLOWED) != 0 OR
((case
when move_specialty_to_ppo then nvl(specialtybr_reduction,0.0)
when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
then nvl(cbr_reduction,0.0)
when (b.site_code='ARC' and b.ppo_network_id='NQ')
or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
then nvl(specialtybr_reduction,0.0)
else 0.0
end + nvl(l.ppo_adjustment,0.0)) - l.PPO_ADJUSTMENT) != 0
THEN 'Y' ELSE 'N' END AS has_fairpay_bucket,

-- Breakdown of what's driving the fairpay bucket
CASE
WHEN (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
OR (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
OR (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
THEN nvl(cbr_reduction,0.0)

WHEN (b.site_code='ARC' and b.ppo_network_id='NQ')
OR (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
OR (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
OR (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
OR (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
OR (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
THEN nvl(specialtybr_reduction,0.0)

ELSE 0.0
END AS fairpay_source_reduction,
b.genex_claim_type_code,
b.genex_claim_type_description,
-- ALL REMAINING WCS COLUMNS (all 298 columns from VW_CLAIM_DETAIL_BILLLINE)
l.ODS_CUSTOMER_ID,
l.CUSTOMER_NAME,
l.DATABASE_UNIQUE_ID,
l.INCLUDE_IN_INDUSTRY_FLAG,
l.SOURCE_SERVER,
l.CLAIM_SEQ,
l.CLAIM_NO,
l.CLAIM_SYS_SUBSET,
l.CLAIM_SYSTEM_DESCRIPTION,
l.DOI,
l.CLAIM_DATE_OF_INJURY_DAY,
l.CLAIM_DATE_OF_INJURY_MONTH,
l.CLAIM_DATE_OF_INJURY_QUARTER,
l.CLAIM_DATE_OF_INJURY_YEAR,
l.CLAIM_FIRST_BILL_CREATE_DATE,
l.CLAIM_TYPE,
l.CLAIM_TYPE_DESCRIPTION,
l.CLAIM_JURISDICTION,
l.CLAIM_INJURY_DESCRIPTION,
l.CONFORMED_CLAIM_INJURY_NATURE_ID,
l.CONFORMED_CLAIM_INJURY_NATURE_DESCRIPTION,
l.CLAIM_PRODUCT_CODE,
l.CLAIM_PRODUCT_CODE_DESCRIPTION,
l.CLAIM_STATUS,
l.CLAIM_MINIMUM_DOS,
l.CLAIM_MINIMUM_DOS_DAY,
l.CLAIM_MINIMUM_DOS_MONTH,
l.CLAIM_MINIMUM_DOS_YEAR,
l.CLAIM_MAXIMUM_DOS,
l.CLAIM_MAXIMUM_DOS_DAY,
l.CLAIM_MAXIMUM_DOS_MONTH,
l.CLAIM_MAXIMUM_DOS_YEAR,
l.CLAIM_CREATE_DATE,
l.CLAIM_CREATE_DATE_DAY,
l.CLAIM_CREATE_DATE_MONTH,
l.CLAIM_CREATE_DATE_YEAR,
l.GB_PROGRAM_NUMBER,
l.GB_PROGRAM_NAME,
l.EXTERNAL_CLAIM_ID,
l.EXTERNAL_POLICY_ID,
l.CLIENT_CODE,
l.CLIENT_NAME,
l.CLIENT_CLAIM_SYS_SUBSET,
l.GEO_STATE,
l.CLIENT_EDI_JURISDICTION_DESCRIPTION,
l.CONTROL_NUMBER,
l.SHARED_CLIENT_NAME,
l.SUB_PRODUCT_CODE,
l.EDI_JURISDICTION,
l.PRODUCT_CODE,
l.PRODUCT_CODE_DESC,
l.ACTUAL_TENURE_IN_DAYS,
l.EXPECTED_TENURE_IN_DAYS,
l.BILL_PROVIDER_SEQ,
l.PROVIDER_SUB_SET,
l.PROVIDER_TIN,
l.PROVIDER_TIN_SUFFIX,
l.PROVIDER_TYPE,
l.BILLING_PROVIDER_NPI,
l.PVD_FIRST_NAME,
l.PVD_LAST_NAME,
l.BILLING_PROVIDER_MIDDLE_NAME,
l.PROVIDER_NAME,
l.BILLING_PROVIDER_PHYSICAL_ADDRESS_1,
l.BILLING_PROVIDER_PHYSICAL_ADDRESS_2,
l.BILLING_PROVIDER_PHYSICAL_CITY,
l.BILLING_PROVIDER_PHYSICAL_COUNTY,
l.BILLING_PROVIDER_PHYSICAL_STATE,
l.BILLING_PROVIDER_ZIP_CODE,
l.BILLING_PROVIDER_PRACTICE_ADDRESS_1,
l.BILLING_PROVIDER_PRACTICE_ADDRESS_2,
l.PROVIDER_PRACTICE_CITY,
l.PROVIDER_PRACTICE_COUNTY,
l.PROVIDER_PRACTICE_STATE,
l.PROVIDER_PRACTICE_ZIP,
l.FACILITY_PROVIDER_NPI,
l.PROVIDER_CLUSTER_NAME,
l.RENDERING_PROVIDER_FIRST_NAME,
l.RENDERING_PROVIDER_MIDDLE_NAME,
l.RENDERING_PROVIDER_LAST_NAME,
l.RENDERING_PROVIDER_STATE,
l.RENDERING_PROVIDER_NPI,
l.RENDERING_PROVIDER_LICENSE_NUMBER,
l.RENDERING_PROVIDER_INVOICE,
l.REFERRING_PROVIDER_LAST_NAME,
l.REFERRING_PROVIDER_MIDDLE_NAME,
l.REFERRING_PROVIDER_FIRST_NAME,
l.REFERRING_PROVIDER_SUFFIX,
l.BILL_OTHER_BILLING_PROVIDER_SEQ,
l.BILL_OTHER_BILLING_PROVIDER_SUBSET,
l.BILL_PROVIDER_BILLING_TAXONOMY,
l.BILL_PROVIDER_RENDERING_TAXONOMY,
l.BILL_PROVIDER_FACILITY_TAXONOMY,
l.BILL_PROVIDER_MEDICARE_NUMBER,
l.BILL_PROVIDER_ZIP_CODE,
l.PROVIDER_SPECIALTY_1,
l.PROVIDER_MEDICARE_NUMBER,
l.PROVIDER_CREATE_DATE,
l.PROVIDER_MOD_DATE,
l.ADJUSTER_FIRST_NAME,
l.ADJUSTER_LAST_NAME,
l.ADMISSION_DATE,
l.CREATE_DATE,
l.BILL_CREATE_DATE_DAY,
l.BILL_CREATE_DATE_MONTH,
l.BILL_CREATE_DATE_QUARTER,
l.BILL_CREATE_DATE_WEEK,
l.BILL_CREATE_DATE_YEAR,
l.DOS_FIRST,
l.DOS_LAST,
l.DUE_DATE,
l.BILL_INJURY_DESCRIPTION,
l.BILL_LINE_TYPE,
l.PAID_DATE,
l.POST_DATE,
l.BILL_POST_DATE_MONTH,
l.BILL_POST_DATE_YEAR,
l.BILL_REEVAL_COUNT,
l.BILL_REVIEW_RECEIVED_DATE,
l.BILL_SEQ,
l.BILL_SEQ_ORG_REV,
l.SITE_CODE,
l.AUDITPRO_SITE_CODE_FLAG,
l.BILL_STATUS,
l.BILL_STATUS_DESCRIPTION,
l.CARRIER_RECEIVED_DATE,
l.CHECK_NUMBER,
l.JURISDICTION,
l.DOCUMENT_ID,
l.DUPLICATE_BILL_FLAG,
l.FIRST_BILL_IN_REEVAL_SEQUENCE,
l.FOREIGN_BILL_ID,
l.INCREMENT_VALUE,
l.INSURER_NAME,
l.INSURER_TIN,
l.INVOICE_END_DATE,
l.MESSAGE_205_OR_270_FLAG,
l.MESSAGE_CODE_SET,
l.MODIFIER_SETS,
l.PLACE_OF_SERVICE_CODE,
b.pos_description,
l.SUB_FORM_TYPE,
l.PRIOR_BILL_POST_DATE,
l.PRIOR_MESSAGE_CODE_SET,
l.PRIOR_TOTAL_ALLOWED,
l.PROVIDER_CHARGES,
l.RE_EVAL_FLAG,
l.BRAND_GENERIC_CODE,
l.TOTAL_ALLOWED,
l.TOTAL_UNITS,
l.TYPE_OF_BILL_CODE,
l.TOB,
l.UB_TYPE_OF_BILL,
l.UB_TYPE_OF_BILL_DESCRIPTION,
l.BILL_STATEMENT_FROM_DATE,
l.BILL_STATEMENT_THROUGH_DATE,
l.DRG_CALCULATED,
l.EOB_COMMENTS,
l.ORIGINAL_BILL_FLAG,
l.ADJUSTOR_DENIAL_FLAG,
l.REVIEW_ONLY_FLAG,
l.HIGHEST_POSITIVE_FLAG,
l.BILLED_SERVICE_CODE,
l.PRICED_SERVICE_CODE,
l.PRICED_SERVICE_CODE_DESCRIPTION,
l.SERVICE_CODE_CATEGORY,
l.SERVICE_CODE_SUB_CATEGORY,
l.SERVICE_CODE_GROUP,
l.SERVICE_CODE_TYPE,
l.SERVICE_CODE_TYPE_DESCRIPTION,
l.REVENUE_CODE,
l.REVENUE_CODE_DESCRIPTION,
l.PROCEDURE_CODE,
l.PROCEDURE_CODE_NEW,
l.LINE_SEQ,
l.LINE_SEQ_ORG_REV,
l.LINE_DOS,
l.ENCOUNTER_TYPE,
l.LINE_OF_BUSINESS,
l.DAYS_SUPPLY,
l.DUPLICATE_LINE_FLAG,
l.DIAGNOSIS_POINTER_SET,
l.LINEMOD_USERENTERED_SET,
l.PATIENT_FIRST_NAME,
l.PATIENT_LAST_NAME,
l.PATIENT_MIDDLE_NAME,
l.PATIENT_GENDER,
l.PATIENT_DOB,
l.PATIENT_CITY,
l.PATIENT_STATE,
l.PATIENT_SSN,
l.PRIMARY_CLAIM_DIAGNOSIS_CODE,
l.DIAGNOSIS_CODE_1,
l.DIAGNOSIS_CODE_1_DESCRIPTION,
l.DIAGNOSIS_CODE_2,
l.DIAGNOSIS_CODE_2_DESCRIPTION,
l.DIAGNOSIS_CODE_3,
l.DIAGNOSIS_CODE_3_DESCRIPTION,
l.DIAGNOSIS_CODE_4,
l.DIAGNOSIS_CODE_4_DESCRIPTION,
l.DIAGNOSIS_CODE_5,
l.DIAGNOSIS_CODE_5_DESCRIPTION,
l.DIAGNOSIS_CODE_6,
l.DIAGNOSIS_CODE_6_DESCRIPTION,
l.DIAGNOSIS_SET,
l.DIAGNOSIS_SET_DESCRIPTION,
l.AUDITPRO_ELIGIBLE,
l.AUDITPRO_REDUCTION_TREND,
l.AUDITPRO_REEVAL_FLAG,
l.AUDITPRO_REVIEW_TYPE,
l.AUDITPRO_RULE_DESCRIPTION,
l.AUDITPRO_RULE_ID,
l.POLICY_ADMIN_KEY,
l.POLICY_EFFECTIVE_DATE,
l.POLICY_ID,
l.POLICY_NAICS_CODE,
l.POLICY_NAME,
l.POLICY_SELF_INSURED_FLAG,
l.POLICY_STATE_TAX_ID,
l.POLICY_TERMINATION_DATE,
l.POLICY_TIN,
l.POLICY_TX_NON_SUBSCRIBER_FLAG,
l.GENEX_PRIMARY_DX_BODY_PART,
l.GENEX_PROCEDURE_CODE_CATEGORY,
l.GENEX_PROCEDURE_CODE_SUBCATEGORY,
l.GENEX_SURGERY_CATEGORY,
l.PEND_DATE,
l.PEND_RELEASE_DATE,
l.PEND_RELEASE_FLAG,
l.PEND_TO_ID,
l.ADJUSTER_BILL_REVIEW_REDUCTION,
l.ADJUSTER_REVIEW_REDUCTION,
l.AUDITPRO_SAVINGS,
l.BILL_REVIEW_REDUCTION,
l.CLIENT_SPECIFIC_8800_REDUCTION,
l.CLIENT_SPECIFIC_8850_REDUCTION,
l.CLIENT_SPECIFIC_8900_REDUCTION,
l.CLINICAL_REVIEW_REDUCTION,
l.CO_PAY_REDUCTION,
l.COMPLEX_BILL_REVIEW_REDUCTION,
l.CUSTOM_ADJUSTER_DENIAL_REDUCTION,
l.CUSTOM_BILL_REVIEW_REDUCTION,
l.CUSTOM_CLINICAL_VALIDATION_REDUCTION,
l.CUSTOM_DUPLICATE_REDUCTION,
l.CUSTOM_ENHANCED_SYSTEM_SAVINGS_REDUCTION,
l.CUSTOM_EXCLUSION_REDUCTION,
l.CUSTOM_FEE_SCHEDULE_REDUCTION,
l.CUSTOM_FORESIGHT_REDUCTION,
l.CUSTOM_NEGOTIATED_REDUCTION,
l.CUSTOM_OON_REDUCTION,
l.CUSTOM_PPO_REDUCTION,
l.DEDUCTIBLE_REDUCTION,
l.ENHANCED_SYSTEM_SAVINGS_REDUCTION,
l.FEE_SCHEDULE_REDUCTIONS,
l.FINANCIAL_LIMIT_REDUCTION,
l.IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION,
l.NEGOTIATED_REDUCTION,
l.NEGOTIATIONS_ADJUSTMENT,
l.NET_AUDITPRO_REDUCTION,
l.NURSE_CONSULTANT_REVIEW_REDUCTION,
l.TOTAL_OVERRIDE_AMOUNT,
l.PHYSICIAN_ADVISOR_REVIEW_REDUCTION,
l.ADJUSTMENT,
l.REPRICING_NETWORK_REDUCTION,
l.SPECIALITY_BILL_REVIEW_REDUCTION,
l.USUAL_CUSTOMARY_SPECIALTY_REDUCTION,
l.UTILIZATION_REVIEW_REDUCTION,
l.PAYMENT_AUTH_CODE,
l.PAYMENT_EXPORT_DATE,
l.EXCEPTION_COMMENTS,
l.EXCEPTION_FLAG,
l.NEGOTIATIONS_SUCCESSFUL_FLAG,
l.WORKFLOW_TASK,
l.TASK_MESSAGE,
l.PPO_CONTRACT_ID,
l.PPO_CONTRACT_PRODUCT_CODE,
l.PPO_IN_NETWORK_FLAG,
l.PPO_NETWORK_TYPE,
l.PPO_SUBNETWORK_ID,
l.PPO_SUBNETWORK_NAME,
l.NETWORK_SERVICE_TYPE,
l.PPO_STACKLIST,
l.TAT_BILL_REVIEW_RECEIVED_TO_POST_DATE,
l.TAT_CARRIER_RECEIVED_TO_POST_DATE,
l.RRS_CACN_MATCH_SCORE_SET,
l.RRS_CACN_SET,
l.RUNDATE,
l.UNITS_PER_LINE_OUTLIER_FLAG,
l.CHARGES_PER_UNIT_OUTLIER_FLAG,
l.ALLOWED_PER_UNIT_OUTLIER_FLAG

FROM vw_claim_detail_bill b
LEFT JOIN genex_special_instructions si ON CONCAT_WS('-', b.SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ) = si.item_id
LEFT JOIN bill b2 ON (b.ods_customer_id=b2.odscustomerid and b.site_code=b2.sitecode and b.client_code=b2.clientcode and b.bill_seq=b2.billseq)
JOIN customer c ON b2.odscustomerid = c.customer_id
LEFT JOIN ppocontract ppoc ON (ppoc.PPONetworkID = b2.PPONetworkID AND ppoc.PPOContractID = b2.PPOContractID and ppoc.sitecode=b2.sitecode and c.server_name = ppoc.servername)
LEFT JOIN pposubnetwork ppos ON (ppos.PPONetworkID = ppoc.PPONetworkID AND ppos.GroupCode = ppoc.GroupCode and ppos.sitecode=ppoc.sitecode and ppos.servername=ppoc.servername)
LEFT JOIN vw_claim_detail_bill b3 ON (b.ods_customer_id=b3.ods_customer_id and b.site_code=b3.site_code and b.client_code=b3.client_code and b.first_bill_in_reeval_sequence=b3.bill_seq)
LEFT JOIN (SELECT ods_customer_id, site_code, client_code, ppo_network_id, bill_seq, case when (site_code in ('BRS','FP1') and ppo_network_id in ('FP','KP','NQ')) or (site_code in ('CPI') and ppo_network_id in ('FP','KP')) or (site_code in ('GUA','SEN') and ppo_network_id in ('FP','NQ')) then True else False end move_specialty_to_ppo from vw_claim_detail_bill) b4 ON (b.ods_customer_id=b4.ods_customer_id and b.site_code=b4.site_code and b.client_code=b4.client_code and b.bill_seq=b4.bill_seq)
LEFT JOIN provider p ON (b2.odscustomerid=p.odscustomerid and b2.otherbillingproviderseq=p.providerseq and b2.otherbillingprovidersubset=p.providersubset)
LEFT JOIN vw_claim_detail_billline l ON b.ods_customer_id = l.ods_customer_id AND b.site_code=l.site_code AND b.client_code=l.client_code AND b.bill_seq=l.bill_seq
LEFT JOIN ladj ON l.site_code=ladj.site_code AND l.ods_customer_id=ladj.ods_customer_id AND l.client_code=ladj.client_code AND l.bill_seq=ladj.bill_seq AND l.line_seq=ladj.line_seq
WHERE 1=1
AND l.ods_customer_id <> 502
AND l.site_code <> '@@@'
AND l.claim_sys_subset NOT IN ('9999','0000','XXXX','TEST')
AND l.claim_system_description NOT IN ('SUPPORT TEST ACCOUNT-UC', 'TEST CLAIM SYSTEM', 'TEST - AMCC','TEST', 'TEST ACCOUNTS', 'TEST - BRICKSTREET', 'UCR TEST','MEDICARE TEST')
AND NOT (l.site_code='COV' AND l.sub_product_code = 'RE-EVAL CANCELLATION')
AND b.duplicate_bill_flag = FALSE
AND l.duplicate_line_flag = FALSE
AND l.client_code != 'UTST'
AND l.claim_sys_subset != 'TRNG'
AND (b.CARRIER_RECEIVED_DATE IS NULL OR year(b.CARRIER_RECEIVED_DATE) != 1900)
)

select distinct *
from final