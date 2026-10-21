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

     final as (SELECT
-- Add reportable bill flag with dummy claim exclusion
CASE
    WHEN
        -- Requirement 1: Bill Status = Paid
        b.BILL_STATUS = 1 AND
        (b.PAID_AMOUNT IS NULL OR b.PAID_AMOUNT > 0) AND

            -- Requirement 2: Invoice End Date is not null / Invoice is posted
        b.POST_DATE IS NOT NULL AND

            -- Requirement 3: Pass Through Flag is null (Bill is not for review only)
        b.BILL_STATUS != 4 AND -- Only exclude duplicates (4), not original bills (8)
b.DUPLICATE_BILL_FLAG = FALSE AND

    -- Requirement 4: Send back status is null (Bill has not been sent back)
b.BILL_STATUS != 3 AND

     -- Additional requirement: Exclude manual credits
    b.BILL_STATUS != 14 AND

     -- Additional requirement: Exclude fake/test bills (example for EMC Insurance)
    NOT (b.SITE_CODE = 'EC1' AND b.CLAIM_NO LIKE 'EMC%99')
    THEN 'Y'
    ELSE 'N'
END
AS genex_reportable_bill_flag,

CASE WHEN
    -- Requirement 1: Bill Status = Paid
    b.BILL_STATUS IN (1,8,12) AND
    (b.PAID_AMOUNT IS NULL OR b.PAID_AMOUNT > 0) AND

    -- Requirement 2: Invoice End Date is not null / Invoice is posted
    b.POST_DATE IS NOT NULL AND

    -- Requirement 3: Pass Through Flag is null (Bill is not for review only)
    b.BILL_STATUS != 4 AND  -- Only exclude duplicates (4), not original bills (8)
    b.DUPLICATE_BILL_FLAG = FALSE AND

    -- Requirement 4: Send back status is null (Bill has not been sent back)
    b.BILL_STATUS != 3 AND

    -- Additional requirement: Exclude manual credits
    b.BILL_STATUS != 14 AND

    -- Additional requirement: Exclude fake/test bills (example for EMC Insurance)
    NOT (b.SITE_CODE = 'EC1' AND b.CLAIM_NO LIKE 'EMC%99')

THEN 'Y'
ELSE 'N'
END
AS mitchell_reportable_bill_flag,

case when nvl(b.rendering_provider_state,'') <> '' then b.rendering_provider_state else b.billing_provider_practice_state
end as rendering_state_norm,
case when nvl(ppos.GroupCode,'') <> '' then ppos.groupcode else ppoc.groupcode
end AS ppo_sub_network_code,
case when nvl(ppos.GroupName,'') <> '' then ppos.groupname else ppoc.groupname
end AS ppo_sub_network_name,

-- Main normalized columns (removed _norm suffix)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'FP'
    else l.ppo_network_id
end ppo_network_id
,

case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'FAIRPAY'
    else l.ppo_network_name
end ppo_network_name
,

case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'Fairpay'
    else l.genex_network_name
end genex_network_name
,

case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'FP'
    else l.genex_network_id
end genex_network_id
,

case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
    or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
    or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
    or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
    or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
    then 'SPEC'
    else l.genex_network_subtype_code
end genex_network_subtype_code
,

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
end bill_review_allowed
,

-- Networks math: Provider Charges minus Bill Review Adjustment
nvl(l.provider_charges, 0.0) - nvl(l.bill_review_adjustment, 0.0) AS bill_review_allowed_networks,

-- Smart Advisor: Provider Charges minus Bill Review Reduction
nvl(l.provider_charges, 0.0) - nvl(br_reduction, 0.0) AS bill_review_allowed_smart_advisor,

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
end bill_review_adjustment
,

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
end
+ nvl(l.ppo_adjustment,0.0) ppo_adjustment,

nvl(l.ppo_allowed,0.0) - case when move_specialty_to_ppo then nvl(specialtybr_reduction,0.0) else 0.0
end ppo_allowed,

case when move_specialty_to_ppo then nvl(l.other_adjustments,0.0) - nvl(specialtybr_reduction,0.0) else l.other_adjustments
end other_adjustments,

br_reduction,
ur_reduction,
clinical_reduction,
uc_reduction,
auditpro_reduction,
widb_reduction,

-- Main normalized reduction columns (removed _norm suffix)
case
    when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(cbr_reduction,0.0)<>0.0)
    or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
    or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
    then 0.0
    else cbr_reduction
end cbr_reduction
,

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
end
+ nvl(ppo_reduction,0.0) ppo_reduction,

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
end specialtybr_reduction
,

custombr_reduction,
financial_reduction,
adjuster_reduction,
unknown_reduction,
case when b.tob_code='M' then 'Medical'  when b.tob_code='O' then 'Outpatient' when b.tob_code='P' then 'Pharmacy' when b.tob_code='N' then 'NonMedical' when b.tob_code='I' then 'Inpatient' when b.tob_code='S' then 'Supplies' when b.tob_code='D' then 'Dental' when b.tob_code='O' then 'Other' else 'Unknown'
end tob_norm,
b3.post_date first_post_date_in_bill_seq,
case when l.genex_network_name is not null and l.genex_network_subtype_code is null then True else False
end hit_ppo_network,
case when l.genex_network_name is not null and l.genex_network_subtype_code is not null then True else False
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
year(l.post_date) post_date_year,
quarter(l.post_date) post_date_qtr,
year(l.dos_first) dos_year,
quarter(l.dos_first) dos_qtr,
1 lines,
l.ADJUSTMENT,
l.BILL_INJURY_DESCRIPTION,
l.BILL_LINE_TYPE,
l.BILL_POST_DATE_MONTH,
l.BILL_POST_DATE_YEAR,
l.BILL_REEVAL_COUNT,
l.BILL_REVIEW_REDUCTION,
l.BILL_SEQ,
l.BILL_STATUS,
l.BILL_STATUS_DESCRIPTION,
l.BILLED_SERVICE_CODE,
l.CLAIM_INJURY_DESCRIPTION,
l.CLAIM_JURISDICTION,
l.CLAIM_MAXIMUM_DOS,
l.CLAIM_MINIMUM_DOS,
l.CLAIM_NO,
l.CLAIM_PRODUCT_CODE,
l.CLAIM_PRODUCT_CODE_DESCRIPTION,
l.CLAIM_SEQ,
l.CLAIM_STATUS,
l.CLIENT_CODE,
l.CLIENT_NAME,
l.CUSTOMER_NAME,
l.DIAGNOSIS_CODE_1,
l.DOI,
l.DOS_FIRST,
l.DOS_LAST,
l.EDI_JURISDICTION,
l.FIRST_BILL_IN_REEVAL_SEQUENCE,
l.INSURER_NAME,
l.INSURER_TIN,
l.LINE_DOS,
l.LINE_OF_BUSINESS,
l.LINE_SEQ,
l.ODS_CUSTOMER_ID,
l.POST_DATE,
l.PPO_CONTRACT_ID,
l.PPO_NETWORK_TYPE,
l.PPO_SUBNETWORK_ID,
l.PPO_SUBNETWORK_NAME,
l.PRODUCT_CODE,
l.PROVIDER_CHARGES,
l.PRICED_SERVICE_CODE,
l.SITE_CODE AS BILL_SITE_CODE,
l.TOB,
l.TOTAL_ALLOWED,
l.TYPE_OF_BILL_CODE,

-- Add the individual reduction fields (NEW - this creates the Line + Reduction level)
adj.ADJUSTMENT as REDUCTION,
adj.REDUCTION_BUCKET,
case
    when adj.reduction_bucket in ('Bill Review') then '2000'
    when adj.reduction_bucket in ('Utilization Review','UTILIZATION REVIEW','Nurse Consultant Review','Paradigm Review','Physician Advisor Review') then '2100'
    when adj.reduction_bucket in ('Clinical Review') then '2200'
    when adj.reduction_bucket in ('U&C Specialty Review') then '2300'
    when adj.reduction_bucket in ('AuditPro Code Review','AuditPro','Mitchell AuditPro','AUDITPRO SAVINGS') then '3000'
    when adj.reduction_bucket in ('WISCONSIN (WI) CERTIFIED DATABASE') then '3100'
    when adj.reduction_bucket in ('Complex Bill Review','ComplexBillReview') then '2400'
    when adj.reduction_bucket in ('Physician Advisor Review') then '2500'
    when adj.reduction_bucket in ('Adjuster Reductions','Examiner Review','Adjuster Bill Review','LM ADJUSTMENTS') then '4000'
    when adj.reduction_bucket in ('Implant Complex Bill Review') then '2600'
    when adj.reduction_bucket in ('PPO') then '5000'
    when adj.reduction_bucket in ('NGD SERVICES','Out of Network Review') then '6000'
    when adj.reduction_bucket in ('Negotiated Discount','Pre-Cert Penalty','CLIENT DIRECTED PPO','Reduction Bucket 8800','IMPLANTS SPECIALTY REVIEW','Negotiations',
                                 'Reduction Bucket 8850','Voluntary Utilization Network Pena','Health Care Offset','Reduction Bucket 8900','IMPLANT SAVINGS') then '7000'
    when adj.reduction_bucket in ('APPORTIONMENT','Copay','Deductible','Financial Limit') then '8000'
    when adj.reduction_bucket in ('Adjuster Review') then '9000'
    else '9999'
end
as REDUCTION_CODE,

-- Legacy columns (added _LEGACY suffix)
l.BILL_REVIEW_ADJUSTMENT AS BILL_REVIEW_ADJUSTMENT_LEGACY,
l.BILL_REVIEW_ALLOWED AS BILL_REVIEW_ALLOWED_LEGACY,
l.PPO_ADJUSTMENT AS PPO_ADJUSTMENT_LEGACY,
l.PPO_ALLOWED AS PPO_ALLOWED_LEGACY,
l.PPO_NETWORK_ID AS PPO_NETWORK_ID_LEGACY,
l.PPO_NETWORK_NAME AS PPO_NETWORK_NAME_LEGACY,
l.GENEX_NETWORK_ID AS GENEX_NETWORK_ID_LEGACY,
l.GENEX_NETWORK_NAME AS GENEX_NETWORK_NAME_LEGACY,
l.GENEX_NETWORK_SUBTYPE_CODE AS GENEX_NETWORK_SUBTYPE_CODE_LEGACY,
l.OTHER_ADJUSTMENTS AS OTHER_ADJUSTMENTS_LEGACY

from vw_claim_detail_bill b
left join bill b2 on (b.ods_customer_id=b2.odscustomerid and b.site_code=b2.sitecode and b.client_code=b2.clientcode and b.bill_seq=b2.billseq)
join customer c on b2.odscustomerid = c.customer_id
left join ppocontract ppoc  ON (ppoc.PPONetworkID = b2.PPONetworkID AND ppoc.PPOContractID = b2.PPOContractID and ppoc.sitecode=b2.sitecode and c.server_name = ppoc.servername)
left join pposubnetwork ppos ON (ppos.PPONetworkID = ppoc.PPONetworkID AND ppos.GroupCode = ppoc.GroupCode and ppos.sitecode=ppoc.sitecode and ppos.servername=ppoc.servername)
left join vw_claim_detail_bill b3 on (b.ods_customer_id=b3.ods_customer_id and b.site_code=b3.site_code and b.client_code=b3.client_code and b.first_bill_in_reeval_sequence=b3.bill_seq)
left join (select ods_customer_id, site_code, client_code, ppo_network_id, bill_seq, case when (site_code in ('BRS','FP1') and ppo_network_id in ('FP','KP','NQ')) or (site_code in ('CPI') and ppo_network_id in ('FP','KP')) or (site_code in ('GUA','SEN') and ppo_network_id in ('FP','NQ')) then True else False end move_specialty_to_ppo from vw_claim_detail_bill) b4 on (b.ods_customer_id=b4.ods_customer_id and b.site_code=b4.site_code and b.client_code=b4.client_code and b.bill_seq=b4.bill_seq)
left join provider p on (b2.odscustomerid=p.odscustomerid and b2.otherbillingproviderseq=p.providerseq and b2.otherbillingprovidersubset=p.providersubset)
join vw_claim_detail_billline l on b.ods_customer_id = l.ods_customer_id and b.site_code=l.site_code and b.client_code=l.client_code and b.bill_seq=l.bill_seq
left join (
    select
        site_code, ods_customer_id, client_code, bill_seq, line_seq,
        sum(br_reduction) as br_reduction,
        sum(ur_reduction) as ur_reduction,
        sum(clinical_reduction) as clinical_reduction,
        sum(uc_reduction) as uc_reduction,
        sum(auditpro_reduction) as auditpro_reduction,
        sum(widb_reduction) as widb_reduction,
        sum(cbr_reduction) as cbr_reduction,
        sum(physreview_reduction) as physreview_reduction,
        sum(adjusterbr_reduction) as adjusterbr_reduction,
        sum(implantcbr_reduction) as implantcbr_reduction,
        sum(ppo_reduction) as ppo_reduction,
        sum(specialtybr_reduction) as specialtybr_reduction,
        sum(custombr_reduction) as custombr_reduction,
        sum(financial_reduction) as financial_reduction,
        sum(adjuster_reduction) as adjuster_reduction,
        sum(unknown_reduction) as unknown_reduction
    from (
        select
            site_code, ods_customer_id, client_code, bill_seq, line_seq,
            case when reduction_bucket = 'br_reduction' then adjustment else 0 end as br_reduction,
            case when reduction_bucket = 'ur_reduction' then adjustment else 0 end as ur_reduction,
            case when reduction_bucket = 'clinical_reduction' then adjustment else 0 end as clinical_reduction,
            case when reduction_bucket = 'uc_reduction' then adjustment else 0 end as uc_reduction,
            case when reduction_bucket = 'auditpro_reduction' then adjustment else 0 end as auditpro_reduction,
            case when reduction_bucket = 'widb_reduction' then adjustment else 0 end as widb_reduction,
            case when reduction_bucket = 'cbr_reduction' then adjustment else 0 end as cbr_reduction,
            case when reduction_bucket = 'physreview_reduction' then adjustment else 0 end as physreview_reduction,
            case when reduction_bucket = 'adjusterbr_reduction' then adjustment else 0 end as adjusterbr_reduction,
            case when reduction_bucket = 'implantcbr_reduction' then adjustment else 0 end as implantcbr_reduction,
            case when reduction_bucket = 'ppo_reduction' then adjustment else 0 end as ppo_reduction,
            case when reduction_bucket = 'specialtybr_reduction' then adjustment else 0 end as specialtybr_reduction,
            case when reduction_bucket = 'custombr_reduction' then adjustment else 0 end as custombr_reduction,
            case when reduction_bucket = 'financial_reduction' then adjustment else 0 end as financial_reduction,
            case when reduction_bucket = 'adjuster_reduction' then adjustment else 0 end as adjuster_reduction,
            case when reduction_bucket = 'unknown_reduction' then adjustment else 0 end as unknown_reduction
        from (
            select
                site_code, ods_customer_id, client_code, bill_seq, line_seq,
                case
                    when reduction_bucket in ('Bill Review') then 'br_reduction'
                    when reduction_bucket in ('Utilization Review','UTILIZATION REVIEW','Nurse Consultant Review','Paradigm Review','Physician Advisor Review') then 'ur_reduction'
                    when reduction_bucket in ('Clinical Review') then 'clinical_reduction'
                    when reduction_bucket in ('U&C Specialty Review') then 'uc_reduction'
                    when reduction_bucket in ('AuditPro Code Review','AuditPro','Mitchell AuditPro','AUDITPRO SAVINGS','AuditPro','AuditPro') then 'auditpro_reduction'
                    when reduction_bucket in ('WISCONSIN (WI) CERTIFIED DATABASE') then 'widb_reduction'
                    when reduction_bucket in ('Complex Bill Review','ComplexBillReview') then 'cbr_reduction'
                    when reduction_bucket in ('Physician Advisor Review') then 'physreview_reduction'
                    when reduction_bucket in ('Adjuster Reductions','Examiner Review','Adjuster Bill Review','LM ADJUSTMENTS') then 'adjusterbr_reduction'
                    when reduction_bucket in ('Implant Complex Bill Review') then 'implantcbr_reduction'
                    when reduction_bucket in ('PPO') then 'ppo_reduction'
                    when reduction_bucket in ('NGD SERVICES','Out of Network Review') then 'specialtybr_reduction'
                    when reduction_bucket in ('Negotiated Discount','Pre-Cert Penalty','CLIENT DIRECTED PPO','Reduction Bucket 8800','IMPLANTS SPECIALTY REVIEW','Negotiations',
                                             'Reduction Bucket 8850','Voluntary Utilization Network Pena','Health Care Offset','Reduction Bucket 8900','IMPLANT SAVINGS') then 'custombr_reduction'
                    when reduction_bucket in ('APPORTIONMENT','Copay','Deductible','Financial Limit') then 'financial_reduction'
                    when reduction_bucket in ('Adjuster Review') then 'adjuster_reduction'
                    else 'unknown_reduction'
                end as reduction_bucket,
                adjustment
            from vw_claim_detail_billline_adjsubcatname
        )
    )
    group by site_code, ods_customer_id, client_code, bill_seq, line_seq
) ladj on l.site_code=ladj.site_code and l.ods_customer_id=ladj.ods_customer_id and l.client_code=ladj.client_code and l.bill_seq=ladj.bill_seq and l.line_seq=ladj.line_seq
-- ADD THIS JOIN FOR LINE + REDUCTION LEVEL
join vw_claim_detail_billline_adjsubcatname adj on l.site_code=adj.site_code and l.ods_customer_id=adj.ods_customer_id and l.client_code=adj.client_code and l.bill_seq=adj.bill_seq and l.line_seq=adj.line_seq

where 1=1 and b.ods_customer_id <> 502 and b.site_code <> '@@@'
and b.claim_sys_subset not in ('9999','0000','XXXX','TEST')
and b.claim_system_description not in ('SUPPORT TEST ACCOUNT-UC', 'TEST CLAIM SYSTEM', 'TEST - AMCC','TEST', 'TEST ACCOUNTS', 'TEST - BRICKSTREET', 'UCR TEST','MEDICARE TEST')
and not (b.site_code='COV' and b.sub_product_code = 'RE-EVAL CANCELLATION')
and b.duplicate_bill_flag = False
and l.duplicate_line_flag = False
--Exclude SF1 Test bills
and b.client_code != 'UTST'  -- Excludes client code UTST
and b.claim_sys_subset != 'TRNG'  -- Excludes claim system subset TRNG
and (b.CARRIER_RECEIVED_DATE is null or year(b.CARRIER_RECEIVED_DATE) != 1900)  -- Excludes carrier received date in 1900
)

select distinct *
from final