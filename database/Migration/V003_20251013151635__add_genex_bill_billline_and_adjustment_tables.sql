CREATE OR REPLACE VIEW ANALYTICS_STG.BILL_LEVEL_GENEX AS
SELECT
    -- Bill Identifiers
    b.SITE_CODE,
    b.ODS_CUSTOMER_ID,
    b.CLIENT_CODE,
    b.BILL_SEQ,

    -- Bill-Level Business Logic (reportable flags)
    CASE WHEN
        b.BILL_STATUS = 1 AND
        (b.PAID_AMOUNT IS NULL OR b.PAID_AMOUNT > 0) AND
        b.POST_DATE IS NOT NULL AND
        b.BILL_STATUS != 4 AND
        b.DUPLICATE_BILL_FLAG = FALSE AND
        b.BILL_STATUS != 3 AND
        b.BILL_STATUS != 14 AND
        NOT (b.SITE_CODE = 'EC1' AND b.CLAIM_NO LIKE 'EMC%99')
    THEN 'Y' ELSE 'N'
    END AS genex_reportable_bill_flag,

    CASE WHEN
        b.BILL_STATUS IN (1,8,12) AND
        (b.PAID_AMOUNT IS NULL OR b.PAID_AMOUNT > 0) AND
        b.POST_DATE IS NOT NULL AND
        b.BILL_STATUS != 4 AND
        b.DUPLICATE_BILL_FLAG = FALSE AND
        b.BILL_STATUS != 3 AND
        b.BILL_STATUS != 14 AND
        NOT (b.SITE_CODE = 'EC1' AND b.CLAIM_NO LIKE 'EMC%99')
    THEN 'Y' ELSE 'N'
    END AS mitchell_reportable_bill_flag,

    -- Network Normalizations (using bill-level fields with business logic)
    case when nvl(b.rendering_provider_state,'') <> '' then b.rendering_provider_state else b.billing_provider_practice_state end as rendering_state_norm,
    case when nvl(ppos.GroupCode,'') <> '' then ppos.groupcode else ppoc.groupcode end AS ppo_sub_network_code,
    case when nvl(ppos.GroupName,'') <> '' then ppos.groupname else ppoc.groupname end AS ppo_sub_network_name,

    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then 'FP'
        else b.PPO_NETWORK_ID
    end ppo_network_id_norm,

    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then 'FAIRPAY'
        else b.PPO_NETWORK_NAME
    end ppo_network_name_norm,

    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then 'Fairpay'
        else b.GENEX_NETWORK_NAME
    end genex_network_name_norm,

    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then 'FP'
        else b.GENEX_NETWORK_ID
    end genex_network_id_norm,

    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM','NQ'))
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then 'SPEC'
        else b.GENEX_NETWORK_SUBTYPE_CODE
    end genex_network_subtype_code_norm,

    -- Financial Normalizations (using bill-level totals)
    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
        then nvl(b.BILL_REVIEW_ALLOWED,0.0)+nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)
        when (b.site_code='ARC' and b.ppo_network_id='NQ')
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then nvl(b.BILL_REVIEW_ALLOWED,0.0)+nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0)
        else b.BILL_REVIEW_ALLOWED
    end bill_review_allowed_norm,

    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
        then nvl(b.BILL_REVIEW_ADJUSTMENT,0.0)-nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)
        when (b.site_code='ARC' and b.ppo_network_id='NQ')
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then nvl(b.BILL_REVIEW_ADJUSTMENT,0.0)-nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0)
        else b.BILL_REVIEW_ADJUSTMENT
    end bill_review_adjustment_norm,

    case
        when b4.move_specialty_to_ppo then nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0)
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
        then nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)
        when (b.site_code='ARC' and b.ppo_network_id='NQ')
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0)
        else 0.0
    end + nvl(b.PPO_ADJUSTMENT,0.0) ppo_adjustment_norm,

    nvl(b.PPO_ALLOWED,0.0) - case when b4.move_specialty_to_ppo then nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0) else 0.0 end ppo_allowed_norm,

    case when b4.move_specialty_to_ppo then nvl(b.ADJUSTMENT,0.0) - nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0) else b.ADJUSTMENT end other_adjustments_norm,

    -- Bill-Level Reduction Totals (pre-calculated)
    b.BILL_REVIEW_REDUCTION as br_reduction,
    b.UTILIZATION_REVIEW_REDUCTION as ur_reduction,
    b.CLINICAL_REVIEW_REDUCTION as clinical_reduction,
    b.USUAL_CUSTOMARY_SPECIALTY_REDUCTION as uc_reduction,
    b.AUDITPRO_SAVINGS as auditpro_reduction,
    nvl(b.CLIENT_SPECIFIC_8800_REDUCTION,0) + nvl(b.CLIENT_SPECIFIC_8850_REDUCTION,0) + nvl(b.CLIENT_SPECIFIC_8900_REDUCTION,0) as widb_reduction,
    b.COMPLEX_BILL_REVIEW_REDUCTION as cbr_reduction,

    case
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
        then 0.0
        else b.COMPLEX_BILL_REVIEW_REDUCTION
    end cbr_reduction_norm,

    b.PHYSICIAN_ADVISOR_REVIEW_REDUCTION as physreview_reduction,
    b.ADJUSTER_BILL_REVIEW_REDUCTION as adjusterbr_reduction,
    b.IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION as implantcbr_reduction,
    b.CUSTOM_PPO_REDUCTION as ppo_reduction,

    case
        when b4.move_specialty_to_ppo then nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0)
        when (b.site_code='ZU1' and b.ppo_network_id='' and nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)<>0.0)
        or (b.site_code='ZU1' and b.ppo_network_id in ('FP','KP','QM'))
        or (b.site_code='ARC' and b.ppo_network_id in ('FP','KP','QM'))
        then nvl(b.COMPLEX_BILL_REVIEW_REDUCTION,0.0)
        when (b.site_code='ARC' and b.ppo_network_id='NQ')
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then nvl(b.SPECIALITY_BILL_REVIEW_REDUCTION,0.0)
        else 0.0
    end + nvl(b.CUSTOM_PPO_REDUCTION,0.0) ppo_reduction_norm,

    b.SPECIALITY_BILL_REVIEW_REDUCTION as specialtybr_reduction,

    case
        when b4.move_specialty_to_ppo then 0.0
        when (b.site_code='ARC' and b.ppo_network_id='NQ')
        or (b.site_code='BRS' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='CPI' and b.ppo_network_id in ('FP','KP'))
        or (b.site_code='FP1' and b.ppo_network_id in ('FP','KP','NQ'))
        or (b.site_code='GUA' and b.ppo_network_id in ('FP','NQ'))
        or (b.site_code='SEN' and b.ppo_network_id in ('FP','NQ'))
        then 0.0
        else b.SPECIALITY_BILL_REVIEW_REDUCTION
    end specialtybr_reduction_norm,

    b.CUSTOM_BILL_REVIEW_REDUCTION as custombr_reduction,
    nvl(b.DEDUCTIBLE_REDUCTION,0) + nvl(b.CO_PAY_REDUCTION,0) + nvl(b.FINANCIAL_LIMIT_REDUCTION,0) as financial_reduction,
    b.ADJUSTER_REVIEW_REDUCTION as adjuster_reduction,
    0 as unknown_reduction,

    -- Bill-Level Derived Fields
    case when b.tob_code='M' then 'Medical' when b.tob_code='O' then 'Outpatient' when b.tob_code='P' then 'Pharmacy' when b.tob_code='N' then 'NonMedical' when b.tob_code='I' then 'Inpatient' when b.tob_code='S' then 'Supplies' when b.tob_code='D' then 'Dental' else 'Unknown' end tob_norm,
    b3.post_date first_post_date_in_bill_seq,
    case when b.GENEX_NETWORK_NAME is not null and b.GENEX_NETWORK_SUBTYPE_CODE is null then True else False end hit_ppo_network,
    case when b.GENEX_NETWORK_NAME is not null and b.GENEX_NETWORK_SUBTYPE_CODE is not null then True else False end hit_specialty_network,
    case when b.negotiated_reduction > 0 or b.speciality_bill_review_reduction > 0 then True else False end hit_reprice_service,
    case when b2.otherbillingproviderseq is not null then 1 else 0 end tin_flip,
    b2.ppostacklist,
    case when p.tin is not null then p.tin else b.provider_tin end provider_tin_orig,
    case when b.site_code in ('COV','N02','TES') then b.claim_system_description when b.site_code in ('FIC','FP1','IC1') then initcap(b.claim_system_description) else b.customer_name end shared_customer_name,

    -- Date Extractions (bill-level)
    year(b.post_date) as post_date_year,
    quarter(b.post_date) as post_date_qtr,
    year(b.dos_first) as dos_year,
    quarter(b.dos_first) as dos_qtr,

    -- Bill summary
    b.LINE_COUNT as lines,

    -- Bill-Level Fields
    b.ADJUSTMENT,
    b.BILL_INJURY_DESCRIPTION,
    'BILL' as BILL_LINE_TYPE,
    b.BILL_POST_DATE_MONTH,
    b.BILL_POST_DATE_YEAR,
    b.BILL_REEVAL_COUNT,
    b.BILL_REVIEW_ADJUSTMENT,
    b.BILL_REVIEW_ALLOWED,
    b.BILL_REVIEW_REDUCTION,
    b.BILL_STATUS,
    b.BILL_STATUS_DESCRIPTION,
    b.BILLED_SERVICE_CODE,
    b.CLAIM_INJURY_DESCRIPTION,
    b.CLAIM_JURISDICTION,
    b.CLAIM_MAXIMUM_DOS,
    b.CLAIM_MINIMUM_DOS,
    b.CLAIM_NO,
    b.CLAIM_PRODUCT_CODE,
    b.CLAIM_PRODUCT_CODE_DESCRIPTION,
    b.CLAIM_SEQ,
    b.CLAIM_STATUS,
    b.CLIENT_NAME,
    b.CUSTOMER_NAME,
    b.DIAGNOSIS_CODE_1,
    b.DOI,
    b.DOS_FIRST,
    b.DOS_LAST,
    b.EDI_JURISDICTION,
    b.FIRST_BILL_IN_REEVAL_SEQUENCE,
    b.GENEX_NETWORK_ID,
    b.GENEX_NETWORK_NAME,
    b.GENEX_NETWORK_SUBTYPE_CODE,
    b.INSURER_NAME,
    b.INSURER_TIN,
    b.DOS_FIRST as LINE_DOS,
    b.LINE_OF_BUSINESS,
    NULL as LINE_SEQ,
    b.POST_DATE,
    b.PPO_ADJUSTMENT,
    b.PPO_ALLOWED,
    b.PPO_CONTRACT_ID,
    b.PPO_NETWORK_ID,
    b.PPO_NETWORK_NAME,
    b.PPO_NETWORK_TYPE,
    b.PPO_SUBNETWORK_ID,
    b.PPO_SUBNETWORK_NAME,
    b.PRODUCT_CODE,
    b.PROVIDER_CHARGES,
    b.BILLED_SERVICE_CODE as SERVICE_CODE,
    b.TOB,
    b.TOTAL_ALLOWED,
    b.TOB_CODE as TYPE_OF_BILL_CODE

FROM DATAWAREHOUSE.WCS.VW_CLAIM_DETAIL_BILL b
LEFT JOIN wcsods.dbo.bill b2 ON (b.ods_customer_id=b2.odscustomerid AND b.site_code=b2.sitecode AND b.client_code=b2.clientcode AND b.bill_seq=b2.billseq)
JOIN wcsods.adm.customer c ON b2.odscustomerid = c.customer_id
LEFT JOIN wcsods.dbo.PPOContract ppoc ON (ppoc.PPONetworkID = b2.PPONetworkID AND ppoc.PPOContractID = b2.PPOContractID AND ppoc.sitecode=b2.sitecode AND c.server_name = ppoc.servername)
LEFT JOIN wcsods.dbo.PPOSubNetwork ppos ON (ppos.PPONetworkID = ppoc.PPONetworkID AND ppos.GroupCode = ppoc.GroupCode AND ppos.sitecode=ppoc.sitecode AND ppos.servername=ppoc.servername)
LEFT JOIN DATAWAREHOUSE.WCS.VW_CLAIM_DETAIL_BILL b3 ON (b.ods_customer_id=b3.ods_customer_id AND b.site_code=b3.site_code AND b.client_code=b3.client_code AND b.first_bill_in_reeval_sequence=b3.bill_seq)
LEFT JOIN (
    SELECT ods_customer_id, site_code, client_code, ppo_network_id, bill_seq,
    CASE WHEN (site_code IN ('BRS','FP1') AND ppo_network_id IN ('FP','KP','NQ'))
         OR (site_code IN ('CPI') AND ppo_network_id IN ('FP','KP'))
         OR (site_code IN ('GUA','SEN') AND ppo_network_id IN ('FP','NQ'))
    THEN True ELSE False END move_specialty_to_ppo
    FROM DATAWAREHOUSE.WCS.VW_CLAIM_DETAIL_BILL
) b4 ON (b.ods_customer_id=b4.ods_customer_id AND b.site_code=b4.site_code AND b.client_code=b4.client_code AND b.bill_seq=b4.bill_seq)
LEFT JOIN wcsods.dbo.provider p ON (b2.odscustomerid=p.odscustomerid AND b2.otherbillingproviderseq=p.providerseq AND b2.otherbillingprovidersubset=p.providersubset)

WHERE 1=1
    AND b.ods_customer_id <> 502
    AND b.site_code <> '@@@'
    AND b.claim_sys_subset NOT IN ('9999','0000','XXXX','TEST')
    AND b.claim_system_description NOT IN ('SUPPORT TEST ACCOUNT-UC', 'TEST CLAIM SYSTEM', 'TEST - AMCC','TEST', 'TEST ACCOUNTS', 'TEST - BRICKSTREET', 'UCR TEST','MEDICARE TEST')
    AND NOT (b.site_code='COV' AND b.sub_product_code = 'RE-EVAL CANCELLATION')
    AND b.duplicate_bill_flag = False
    AND b.client_code != 'UTST'
    AND b.claim_sys_subset != 'TRNG'
    AND (b.CARRIER_RECEIVED_DATE IS NULL OR year(b.CARRIER_RECEIVED_DATE) != 1900)
;

CREATE OR REPLACE VIEW ANALYTICS_STG.LINE_LEVEL_GENEX AS
SELECT
    -- Line Identifiers
    l.SITE_CODE,
    l.ODS_CUSTOMER_ID,
    l.CLIENT_CODE,
    l.BILL_SEQ,
    l.LINE_SEQ,

    -- Line-Specific Reductions (from ladj - actual line reductions)
    nvl(ladj.br_reduction, 0) as br_reduction,
    nvl(ladj.ur_reduction, 0) as ur_reduction,
    nvl(ladj.clinical_reduction, 0) as clinical_reduction,
    nvl(ladj.uc_reduction, 0) as uc_reduction,
    nvl(ladj.auditpro_reduction, 0) as auditpro_reduction,
    nvl(ladj.widb_reduction, 0) as widb_reduction,
    nvl(ladj.cbr_reduction, 0) as cbr_reduction,
    nvl(ladj.physreview_reduction, 0) as physreview_reduction,
    nvl(ladj.adjusterbr_reduction, 0) as adjusterbr_reduction,
    nvl(ladj.implantcbr_reduction, 0) as implantcbr_reduction,
    nvl(ladj.ppo_reduction, 0) as ppo_reduction,
    nvl(ladj.specialtybr_reduction, 0) as specialtybr_reduction,
    nvl(ladj.custombr_reduction, 0) as custombr_reduction,
    nvl(ladj.financial_reduction, 0) as financial_reduction,
    nvl(ladj.adjuster_reduction, 0) as adjuster_reduction,
    nvl(ladj.unknown_reduction, 0) as unknown_reduction,

    -- Pure Line Fields (no bill-level business logic)
    l.ADJUSTMENT,
    l.BILL_INJURY_DESCRIPTION,
    l.BILL_LINE_TYPE,
    l.BILL_POST_DATE_MONTH,
    l.BILL_POST_DATE_YEAR,
    l.BILL_REEVAL_COUNT,
    l.BILL_REVIEW_ADJUSTMENT,
    l.BILL_REVIEW_ALLOWED,
    l.BILL_REVIEW_REDUCTION,
    l.BILL_STATUS,
    l.BILL_STATUS_DESCRIPTION,
    l.BILLED_SERVICE_CODE,
    l.PRICED_SERVICE_CODE,
    l.CLAIM_INJURY_DESCRIPTION,
    l.CLAIM_JURISDICTION,
    l.CLAIM_MAXIMUM_DOS,
    l.CLAIM_MINIMUM_DOS,
    l.CLAIM_NO,
    l.CLAIM_PRODUCT_CODE,
    l.CLAIM_PRODUCT_CODE_DESCRIPTION,
    l.CLAIM_SEQ,
    l.CLAIM_STATUS,
    l.CLIENT_NAME,
    l.CUSTOMER_NAME,
    l.DIAGNOSIS_CODE_1,
    l.DOI,
    l.DOS_FIRST,
    l.DOS_LAST,
    l.EDI_JURISDICTION,
    l.FIRST_BILL_IN_REEVAL_SEQUENCE,
    l.GENEX_NETWORK_ID,
    l.GENEX_NETWORK_NAME,
    l.GENEX_NETWORK_SUBTYPE_CODE,
    l.INSURER_NAME,
    l.INSURER_TIN,
    l.LINE_DOS,
    l.LINE_OF_BUSINESS,
    l.POST_DATE,
    l.PPO_ADJUSTMENT,
    l.PPO_ALLOWED,
    l.PPO_CONTRACT_ID,
    l.PPO_NETWORK_ID,
    l.PPO_NETWORK_NAME,
    l.PPO_NETWORK_TYPE,
    l.PPO_SUBNETWORK_ID,
    l.PPO_SUBNETWORK_NAME,
    l.PRODUCT_CODE,
    l.PROVIDER_CHARGES,
    l.TOB,
    l.TOTAL_ALLOWED,
    l.TYPE_OF_BILL_CODE,

    -- Simple Line-Level Calculations (no bill logic)
    year(l.post_date) as post_date_year,
    quarter(l.post_date) as post_date_qtr,
    year(l.dos_first) as dos_year,
    quarter(l.dos_first) as dos_qtr,

    1 as lines

FROM DATAWAREHOUSE.WCS.VW_CLAIM_DETAIL_BILLLINE l

-- Only join for line-specific reductions (no bill business logic)
LEFT JOIN (
    SELECT
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
    FROM (
        SELECT
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
        FROM (
            SELECT
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
            FROM DATAWAREHOUSE.WCS.VW_CLAIM_DETAIL_BILLLINE_ADJSUBCATNAME
        )
    )
    GROUP BY site_code, ods_customer_id, client_code, bill_seq, line_seq
) ladj ON l.site_code=ladj.site_code
    AND l.ods_customer_id=ladj.ods_customer_id
    AND l.client_code=ladj.client_code
    AND l.bill_seq=ladj.bill_seq
    AND l.line_seq=ladj.line_seq

WHERE 1=1
    AND l.ods_customer_id <> 502
    AND l.site_code <> '@@@'
    AND l.claim_sys_subset NOT IN ('9999','0000','XXXX','TEST')
    AND l.claim_system_description NOT IN ('SUPPORT TEST ACCOUNT-UC', 'TEST CLAIM SYSTEM', 'TEST - AMCC','TEST', 'TEST ACCOUNTS', 'TEST - BRICKSTREET', 'UCR TEST','MEDICARE TEST')
    AND NOT (l.site_code='COV' AND l.sub_product_code = 'RE-EVAL CANCELLATION')
    AND l.duplicate_line_flag = False
    AND l.client_code != 'UTST'
    AND l.claim_sys_subset != 'TRNG'
    AND (l.CARRIER_RECEIVED_DATE IS NULL OR year(l.CARRIER_RECEIVED_DATE) != 1900)
;

CREATE OR REPLACE VIEW ANALYTICS_STG.ADJUSTMENT_LEVEL_GENEX AS
SELECT
    -- Adjustment Identifiers
    adj.SITE_CODE,
    adj.ODS_CUSTOMER_ID,
    adj.CLIENT_CODE,
    adj.BILL_SEQ,
    adj.LINE_SEQ,
    -- Note: If there's an adjustment sequence/ID field, include it here

    -- Pure Adjustment Fields
    adj.reduction_bucket as reduction_bucket_raw,
    adj.adjustment as adjustment_amount,

    -- Adjustment Categorization Logic (adjustment-level business logic)
    case
        when adj.reduction_bucket in ('Bill Review') then 'br_reduction'
        when adj.reduction_bucket in ('Utilization Review','UTILIZATION REVIEW','Nurse Consultant Review','Paradigm Review','Physician Advisor Review') then 'ur_reduction'
        when adj.reduction_bucket in ('Clinical Review') then 'clinical_reduction'
        when adj.reduction_bucket in ('U&C Specialty Review') then 'uc_reduction'
        when adj.reduction_bucket in ('AuditPro Code Review','AuditPro','Mitchell AuditPro','AUDITPRO SAVINGS','AuditPro','AuditPro') then 'auditpro_reduction'
        when adj.reduction_bucket in ('WISCONSIN (WI) CERTIFIED DATABASE') then 'widb_reduction'
        when adj.reduction_bucket in ('Complex Bill Review','ComplexBillReview') then 'cbr_reduction'
        when adj.reduction_bucket in ('Physician Advisor Review') then 'physreview_reduction'
        when adj.reduction_bucket in ('Adjuster Reductions','Examiner Review','Adjuster Bill Review','LM ADJUSTMENTS') then 'adjusterbr_reduction'
        when adj.reduction_bucket in ('Implant Complex Bill Review') then 'implantcbr_reduction'
        when adj.reduction_bucket in ('PPO') then 'ppo_reduction'
        when adj.reduction_bucket in ('NGD SERVICES','Out of Network Review') then 'specialtybr_reduction'
        when adj.reduction_bucket in ('Negotiated Discount','Pre-Cert Penalty','CLIENT DIRECTED PPO','Reduction Bucket 8800','IMPLANTS SPECIALTY REVIEW','Negotiations',
                                     'Reduction Bucket 8850','Voluntary Utilization Network Pena','Health Care Offset','Reduction Bucket 8900','IMPLANT SAVINGS') then 'custombr_reduction'
        when adj.reduction_bucket in ('APPORTIONMENT','Copay','Deductible','Financial Limit') then 'financial_reduction'
        when adj.reduction_bucket in ('Adjuster Review') then 'adjuster_reduction'
        else 'unknown_reduction'
    end as reduction_category,

    -- Adjustment Type Flags (pure adjustment logic)
    case when adj.reduction_bucket in ('Bill Review') then adj.adjustment else 0 end as br_reduction,
    case when adj.reduction_bucket in ('Utilization Review','UTILIZATION REVIEW','Nurse Consultant Review','Paradigm Review','Physician Advisor Review') then adj.adjustment else 0 end as ur_reduction,
    case when adj.reduction_bucket in ('Clinical Review') then adj.adjustment else 0 end as clinical_reduction,
    case when adj.reduction_bucket in ('U&C Specialty Review') then adj.adjustment else 0 end as uc_reduction,
    case when adj.reduction_bucket in ('AuditPro Code Review','AuditPro','Mitchell AuditPro','AUDITPRO SAVINGS','AuditPro','AuditPro') then adj.adjustment else 0 end as auditpro_reduction,
    case when adj.reduction_bucket in ('WISCONSIN (WI) CERTIFIED DATABASE') then adj.adjustment else 0 end as widb_reduction,
    case when adj.reduction_bucket in ('Complex Bill Review','ComplexBillReview') then adj.adjustment else 0 end as cbr_reduction,
    case when adj.reduction_bucket in ('Physician Advisor Review') then adj.adjustment else 0 end as physreview_reduction,
    case when adj.reduction_bucket in ('Adjuster Reductions','Examiner Review','Adjuster Bill Review','LM ADJUSTMENTS') then adj.adjustment else 0 end as adjusterbr_reduction,
    case when adj.reduction_bucket in ('Implant Complex Bill Review') then adj.adjustment else 0 end as implantcbr_reduction,
    case when adj.reduction_bucket in ('PPO') then adj.adjustment else 0 end as ppo_reduction,
    case when adj.reduction_bucket in ('NGD SERVICES','Out of Network Review') then adj.adjustment else 0 end as specialtybr_reduction,
    case when adj.reduction_bucket in ('Negotiated Discount','Pre-Cert Penalty','CLIENT DIRECTED PPO','Reduction Bucket 8800','IMPLANTS SPECIALTY REVIEW','Negotiations',
                                     'Reduction Bucket 8850','Voluntary Utilization Network Pena','Health Care Offset','Reduction Bucket 8900','IMPLANT SAVINGS') then adj.adjustment else 0 end as custombr_reduction,
    case when adj.reduction_bucket in ('APPORTIONMENT','Copay','Deductible','Financial Limit') then adj.adjustment else 0 end as financial_reduction,
    case when adj.reduction_bucket in ('Adjuster Review') then adj.adjustment else 0 end as adjuster_reduction,
    case when adj.reduction_bucket not in ('Bill Review','Utilization Review','UTILIZATION REVIEW','Nurse Consultant Review','Paradigm Review','Physician Advisor Review',
                                          'Clinical Review','U&C Specialty Review','AuditPro Code Review','AuditPro','Mitchell AuditPro','AUDITPRO SAVINGS',
                                          'WISCONSIN (WI) CERTIFIED DATABASE','Complex Bill Review','ComplexBillReview','Physician Advisor Review',
                                          'Adjuster Reductions','Examiner Review','Adjuster Bill Review','LM ADJUSTMENTS','Implant Complex Bill Review',
                                          'PPO','NGD SERVICES','Out of Network Review','Negotiated Discount','Pre-Cert Penalty','CLIENT DIRECTED PPO',
                                          'Reduction Bucket 8800','IMPLANTS SPECIALTY REVIEW','Negotiations','Reduction Bucket 8850',
                                          'Voluntary Utilization Network Pena','Health Care Offset','Reduction Bucket 8900','IMPLANT SAVINGS',
                                          'APPORTIONMENT','Copay','Deductible','Financial Limit','Adjuster Review') then adj.adjustment else 0 end as unknown_reduction,

    -- Simple Adjustment Indicators
    case when adj.adjustment > 0 then 'POSITIVE' when adj.adjustment < 0 then 'NEGATIVE' when adj.adjustment = 0 then 'ZERO' else 'NULL' end as adjustment_direction,
    abs(adj.adjustment) as adjustment_absolute_amount,

    -- Adjustment counter
    1 as adjustments

FROM DATAWAREHOUSE.WCS.VW_CLAIM_DETAIL_BILLLINE_ADJSUBCATNAME adj

WHERE 1=1
    AND adj.ods_customer_id <> 502
    AND adj.site_code <> '@@@'
    -- Add any adjustment-specific filters here
    AND adj.adjustment IS NOT NULL
;

-- Let's update our CREATE_TABLES_FROM_VIEWS procedure to log errors and continue processing other views.
CREATE OR REPLACE PROCEDURE ADM.CREATE_TABLES_FROM_VIEWS (
    source_schema STRING ,
    target_schema STRING ,
    view_list STRING DEFAULT NULL
)
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'main'
AS
$$
def main(session, source_schema, target_schema, view_list):
    import json

    results = {
        'successful_tables': [],
        'failed_tables': [],
        'total_views_requested': 0,
        'total_tables_created': 0,
        'errors': [],
        'warnings': []
    }

    # Flag to track if we should throw an error at the end
    has_critical_errors = False

    try:
        # Get current database name
        current_db_result = session.sql("SELECT CURRENT_DATABASE()").collect()
        current_database = current_db_result[0][0]

        if not current_database:
            error_msg = 'No current database set. Please USE a database first.'
            results['errors'].append(error_msg)
            has_critical_errors = True
            raise Exception(error_msg)

        # Check if target schema exists - fail if it doesn''t
        try:
            schema_check_query = f"""
            SELECT SCHEMA_NAME
            FROM INFORMATION_SCHEMA.SCHEMATA
            WHERE SCHEMA_NAME = '{target_schema.upper()}'
            AND CATALOG_NAME = '{current_database}'
            """
            schema_result = session.sql(schema_check_query).collect()

            if len(schema_result) == 0:
                error_msg = f"Target schema '{target_schema}' does not exist in database '{current_database}'. Please create the schema first."
                results['errors'].append(error_msg)
                has_critical_errors = True
                raise Exception(error_msg)

        except Exception as e:
            if "does not exist" not in str(e):  # Don''t double-log the schema not found error
                error_msg = f"Failed to check if target schema {target_schema} exists: {str(e)}"
                results['errors'].append(error_msg)
                has_critical_errors = True
            raise e

        # Check if ANALYSIS role exists
        try:
            role_check_query = "SELECT ROLE_NAME FROM INFORMATION_SCHEMA.APPLICABLE_ROLES WHERE ROLE_NAME = 'ANALYSIS'"
            role_result = session.sql(role_check_query).collect()

            if len(role_result) == 0:
                results['warnings'].append("ANALYSIS role does not exist or is not accessible. Grants will be skipped.")
                grant_permissions = False
            else:
                grant_permissions = True

        except Exception as e:
            results['warnings'].append(f"Could not verify ANALYSIS role exists: {str(e)}. Grants will be skipped.")
            grant_permissions = False

        # Process view list
        if view_list is None or view_list.strip() == '':
            # If no view list provided, get all views from source schema
            views_query = f"""
            SELECT TABLE_NAME
            FROM INFORMATION_SCHEMA.VIEWS
            WHERE TABLE_SCHEMA = '{source_schema.upper()}'
            AND TABLE_CATALOG = '{current_database}'
            ORDER BY TABLE_NAME
            """

            try:
                views_result = session.sql(views_query).collect()
                ordered_views = [row[0] for row in views_result]

                if len(ordered_views) == 0:
                    error_msg = f"No views found in schema {source_schema}"
                    results['errors'].append(error_msg)
                    has_critical_errors = True
                    raise Exception(error_msg)

            except Exception as e:
                if "No views found" not in str(e):  # Don''t double-log
                    error_msg = f"Failed to query views in schema {source_schema}: {str(e)}"
                    results['errors'].append(error_msg)
                    has_critical_errors = True
                raise e
        else:
            # Parse the comma-separated view list
            ordered_views = [name.strip() for name in view_list.split(',') if name.strip()]

            if not ordered_views:
                error_msg = "View list is empty or invalid"
                results['errors'].append(error_msg)
                has_critical_errors = True
                raise Exception(error_msg)

        results['total_views_requested'] = len(ordered_views)
        results['execution_order'] = [{'order': i+1, 'view_name': view} for i, view in enumerate(ordered_views)]

        # Verify all requested views exist in source schema
        existing_views_query = f"""
        SELECT TABLE_NAME
        FROM INFORMATION_SCHEMA.VIEWS
        WHERE TABLE_SCHEMA = '{source_schema.upper()}'
        AND TABLE_CATALOG = '{current_database}'
        """

        try:
            existing_views_result = session.sql(existing_views_query).collect()
            existing_views = {row[0].upper() for row in existing_views_result}

            # Check for non-existent views
            missing_views = []
            for view_name in ordered_views:
                if view_name.upper() not in existing_views:
                    missing_views.append(view_name)

            if missing_views:
                error_msg = f"The following views do not exist in schema {source_schema}: {', '.join(missing_views)}"
                results['errors'].append(error_msg)
                has_critical_errors = True
                raise Exception(error_msg)

        except Exception as e:
            if "do not exist in schema" not in str(e):  # Don''t double-log
                error_msg = f"Failed to verify views exist in schema {source_schema}: {str(e)}"
                results['errors'].append(error_msg)
                has_critical_errors = True
            raise e

        # Process each view in the order specified - CONTINUE ON ERRORS
        for i, view_name in enumerate(ordered_views):
            table_result = {
                'table_name': view_name,
                'execution_order': i + 1,
                'table_created': False,
                'grant_applied': False
            }

            try:
                # Create the table from the view
                create_table_sql = f"""
                CREATE OR REPLACE TABLE {target_schema}.{view_name}
                AS SELECT * FROM {source_schema}.{view_name}
                """

                session.sql(create_table_sql).collect()
                table_result['table_created'] = True

                # Verify the table was created and get row count
                count_sql = f"SELECT COUNT(*) FROM {target_schema}.{view_name}"
                count_result = session.sql(count_sql).collect()
                row_count = count_result[0][0]
                table_result['row_count'] = row_count

                # Grant SELECT permission to ANALYSIS role
                if grant_permissions:
                    try:
                        grant_sql = f"GRANT SELECT ON TABLE {target_schema}.{view_name} TO ROLE ANALYSIS"
                        session.sql(grant_sql).collect()
                        table_result['grant_applied'] = True

                    except Exception as grant_error:
                        grant_error_msg = f"Table {view_name} created successfully, but failed to grant SELECT to ANALYSIS role: {str(grant_error)}"
                        results['warnings'].append(grant_error_msg)
                        table_result['grant_error'] = str(grant_error)
                else:
                    table_result['grant_skipped'] = "ANALYSIS role not accessible"

                results['successful_tables'].append(table_result)
                results['total_tables_created'] += 1

            except Exception as e:
                # Record error but CONTINUE processing other views
                error_msg = f"Failed to create table {view_name}: {str(e)}"
                table_result['error'] = str(e)
                results['failed_tables'].append(table_result)
                results['errors'].append(error_msg)
                has_critical_errors = True  # Mark that we had errors
                continue  # Continue to next view

        # Add summary message
        successful_grants = sum(1 for table in results['successful_tables'] if table.get('grant_applied', False))
        summary = f"Process completed. Created {results['total_tables_created']} tables out of {results['total_views_requested']} views requested."

        if grant_permissions:
            summary += f" Applied SELECT grants to ANALYSIS role for {successful_grants} tables."
        else:
            summary += " No grants applied (ANALYSIS role not accessible)."

        results['summary'] = summary

        # If we had any critical errors during processing, throw an exception with full details
        if has_critical_errors:
            error_summary = f"Procedure completed with errors. {len(results['errors'])} error(s) occurred. "
            error_summary += f"Successfully created {results['total_tables_created']} out of {results['total_views_requested']} requested tables. "
            error_summary += f"Failed tables: {len(results['failed_tables'])}. "
            error_summary += f"See full results for details: {json.dumps(results, indent=2)}"
            raise Exception(error_summary)

        return json.dumps(results, indent=2)

    except Exception as e:
        # If this is our intentional error with full results, re-raise it
        if "Procedure completed with errors" in str(e):
            raise e

        # For unexpected errors, add to results and throw
        if f"Unexpected error in main process: {str(e)}" not in results['errors']:
            results['errors'].append(f"Unexpected error in main process: {str(e)}")

        error_with_results = f"Procedure failed with error: {str(e)}. Results: {json.dumps(results, indent=2)}"
        raise Exception(error_with_results)
$$;

CREATE OR REPLACE TASK ANALYTICS.REFRESH_ANALYTICS_TABLES
	warehouse=WH_TAG_L
	schedule='USING CRON 15 3 * * * America/Los_Angeles'
	USER_TASK_TIMEOUT_MS=10800000
	AS CALL ADM.CREATE_TABLES_FROM_VIEWS('ANALYTICS_STG', 'ANALYTICS');

ALTER TASK ANALYTICS.REFRESH_ANALYTICS_TABLES RESUME;
