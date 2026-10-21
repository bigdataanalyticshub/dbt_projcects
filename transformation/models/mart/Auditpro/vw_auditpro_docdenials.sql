{{ config(materialized='table',
    tags = ['auditpro']) }}

WITH stg_dwwcs__claim_detail_bill AS (SELECT *
                                      FROM {{ ref('stg_dwwcs__claim_detail_bill') }}),

     stg_wcsodsdbo__linemod AS (SELECT *
                                FROM {{ ref('stg_wcsodsdbo__linemod') }}),

     stg_wcsodsdbo__tablelookup AS (SELECT *
                                    FROM {{ ref('stg_wcsodsdbo__tablelookup') }}),

     fd as
         (select DISTINCT b.ODS_CUSTOMER_ID,
                          b.BILL_SITE_CODE,
                          b.CLIENT_CODE,
                          b.BILL_SEQ
          from stg_dwwcs__claim_detail_bill b
                   -- only bills where at least one line has a "205"  or "270" ("270" added 9/2025) modifier for the AuditPro reduction
                   -- distinct because AuditPro can have more than one reduction category
                   JOIN (select distinct Sitecode, Code from stg_wcsodsdbo__tablelookup where TypeCode = 'AURC') as ap
                        ON b.bill_site_code = ap.sitecode
                   JOIN stg_wcsodsdbo__linemod lm
                        on b.ODS_CUSTOMER_ID = lm.ODSCUSTOMERID and b.CLIENT_CODE = lm.CLIENTCODE and
                           b.BILL_SEQ = lm.BILLSEQ
                            -- only look at auditpro reduction codes
                            and ap.Code = lm.REDUCTIONCODE and lm.MODIFIER in ('205', '270')
          where 1 = 1
                    AND
                AUDITPRO_SITE_CODE_FLAG = TRUE -- added new EDW column 1/23/2025, replaced old join to ODS LookupTable
                    and b.BILL_STATUS in (1, 8)
                    and b.FIRST_BILL_IN_REEVAL_SEQUENCE = b.BILL_SEQ --billseqorgrev is null in original code
                    and ifnull(b.TOTAL_ALLOWED, 0.0) = 0.0 --full denial
                    and ifnull(b.AUDITPRO_REDUCTION, 0.0) > 0.0
                    --and MODIFIER_SET
                    AND b.Bill_SEQ > 0
                    AND b.ods_customer_id NOT IN (502)
                    AND b.BILL_SITE_CODE <> '@@@'
                    AND YEAR (b.BILL_POST_DATE) >= YEAR (CURRENT_TIMESTAMP ()) - 2
    )
        , fbs as
    (
select
    ODS_CUSTOMER_ID, BILL_SITE_CODE, CLIENT_CODE, FIRST_BILL_IN_REEVAL_SEQUENCE, MAX (BILL_SEQ) as FinalBillSeq
from
    stg_dwwcs__claim_detail_bill b
where
    1=1
  and b.BILL_STATUS in (1
    , 8)
  and b.FIRST_BILL_IN_REEVAL_SEQUENCE <> b.BILL_SEQ --billseqorgrev is null in original code
  AND b.Bill_SEQ
    > 0
  AND b.BILL_SEQ
    < 900000000                                     -- don't need historical bills
  AND b.ods_customer_id NOT IN (502)
  AND b.BILL_SITE_CODE <> '@@@'
  AND YEAR (b.BILL_POST_DATE) >= YEAR (CURRENT_TIMESTAMP ()) - 2
-- only AuditPro clients
  AND AUDITPRO_SITE_CODE_FLAG = TRUE                -- added new EDW column 1/23/2025; replaced old join to ODS LookupTable
group by
    ODS_CUSTOMER_ID,
    BILL_SITE_CODE,
    CLIENT_CODE,
    FIRST_BILL_IN_REEVAL_SEQUENCE
    ),
    rb as
    (
select
    ODS_CUSTOMER_ID, BILL_SITE_CODE, CLIENT_CODE, FIRST_BILL_IN_REEVAL_SEQUENCE, BILL_SEQ as FinalBillSeq, BILL_POST_DATE as LastPostDate, BILL_REEVAL_COUNT as ReevalCount, AUDITPRO_REDUCTION as LastAuditProReduction
from
    stg_dwwcs__claim_detail_bill
WHERE
    1=1
  AND AUDITPRO_SITE_CODE_FLAG = TRUE -- added new EDW column 1/23/2025;
  AND BILL_SEQ <> FIRST_BILL_IN_REEVAL_SEQUENCE
  AND BILL_STATUS in (1
    , 8)
  and BILL_POST_DATE
    >'1/1/1900'
    )
    , final_output as
    (
select
    b.CUSTOMER_NAME, b.SHARED_CLIENT_NAME, b.CLIENT_GEO_STATE, b.CLIENT_GEOSTATE_DESCRIPTION, b.TYPE_OF_BILL_DESCRIPTION, b.BILL_STATUS_DESCRIPTION, b.ODS_CUSTOMER_ID, b.BILL_SITE_CODE, b.CLIENT_CODE, b.BILL_SEQ as OriginalBillSeq, fbs.FinalBillSeq as FinalBillSeq, -- added 1/23/2025, should be b.LAST_BILL_IN_REEVAL_SEQUENCE
    concat(b.BILL_SITE_CODE, '-', b.CLIENT_CODE, '-', TO_VARCHAR(b.BILL_SEQ)) as OriginalBillID,                                                                                                                                                                          -- added 1/23/2025
    concat(b.BILL_SITE_CODE, '-', b.CLIENT_CODE, '-', TO_VARCHAR(fbs.FinalBillSeq)) as FinalBillID,                                                                                                                                                                       -- added 1/23/2025
    CASE WHEN ifnull(b.AUDITPRO_REDUCTION, 0.0) > 25000 THEN 'Yes' ELSE 'No' END as Over25K, b.BILL_POST_DATE, b.BILL_POST_DATE as POSTDATE, case when fbs.FinalBillSeq is not NULL then 1 else 0 end as Reevaluated, case when fbs.FinalBillSeq is not NULL then 0 else 1 end as NotReevaluated, b.AUDITPRO_REDUCTION as OriginalAPReductions, rb.LastAuditProReduction, case when fd.BILL_SEQ is NULL then 0 else 1 end as FullDenialWith205270, case when fbs.FinalBillSeq is not NULL then DATEDIFF( day, b.BILL_POST_DATE, rb.LastPostDate) else 0 end as DaysToReeval, rb.LastPostDate, rb.ReevalCount, CASE WHEN fbs.FinalBillSeq is not NULL and b.AUDITPRO_REDUCTION - rb.LastAuditProReduction <> 0.0 then 1 else 0 end as GiveBack, CASE WHEN fbs.FinalBillSeq is not NULL then rb.LastAuditProReduction - b.AUDITPRO_REDUCTION else NULL end as GiveBackAmount, CASE WHEN fbs.FinalBillSeq is not NULL then rb.LastAuditProReduction else b.AUDITPRO_REDUCTION end as KeptReductions, CONCAT('Data as of: ', TO_VARCHAR(b.rundate, 'mm/dd/yyyy HH12:MI AM'), ' PT') AS "DATA_AS_OF", '� '||TO_VARCHAR(YEAR (CURRENT_TIMESTAMP ()))||', Enlyte Group, LLC. All rights reserved.  This document contains confidential and trade secret information of Enlyte Group, LLC.  Any use, reproduction or disclosure of the information herein without the prior express written approval of Enlyte Group, LLC is prohibited.'
    AS "DISCLAIMER", b.CLAIM_SYS_SUBSET, b.BILLING_PROVIDER_TIN
from
    DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL b
    JOIN
    -- this query may return duplicates because clients may have more than one REDUCTION_CODE for AuditPro so selecting DISTINCT to avoid that
    fd
on b.bill_site_code = fd.bill_site_code and b.client_code = fd.client_code and b.bill_seq = fd.bill_seq
-- find final re-evaluation billseq for original bill (missing in edw for original bill), -- added 1/23/2025
    LEFT JOIN
    fbs on b.ODS_CUSTOMER_ID = fbs.ODS_CUSTOMER_ID and b.CLIENT_CODE = fbs.CLIENT_CODE and b.FIRST_BILL_IN_REEVAL_SEQUENCE = fbs.FIRST_BILL_IN_REEVAL_SEQUENCE

-- re-eval version of bill, if exists, need final ap reduction
    LEFT JOIN
    rb on b.ODS_CUSTOMER_ID = rb.ODS_CUSTOMER_ID and b.CLIENT_CODE = rb.CLIENT_CODE and fbs.FinalBillSeq = rb.FinalBillSeq

where
    1=1
  and b.BILL_STATUS in (1
    , 8)
  and b.FIRST_BILL_IN_REEVAL_SEQUENCE = b.BILL_SEQ --billseqorgrev is null in original code
  and ifnull(b.TOTAL_ALLOWED
    , 0.0) = 0.0                                   --full denial
  and ifnull(b.AUDITPRO_REDUCTION
    , 0.0)
    > 0.0
  AND b.Bill_SEQ
    > 0
  AND b.ods_customer_id NOT IN (502)
  AND b.BILL_SITE_CODE <> '@@@'
  AND YEAR (b.BILL_POST_DATE) >= YEAR (CURRENT_TIMESTAMP ()) - 2
-- only AuditPro clients
  AND AUDITPRO_SITE_CODE_FLAG = TRUE               -- added new EDW column 1/23/2025; replaced old join to ODS LookupTable
    )

SELECT *
FROM final_output
