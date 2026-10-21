{{ config(materialized='table',
    tags = ['auditpro']) }}

WITH stg_dwwcs__claim_detail_bill_pend_history AS (SELECT *
                                                   FROM {{ ref('stg_dwwcs__claim_detail_bill_pend_history') }}),

     stg_dwwcs__claim_detail_bill AS (SELECT *
                                      FROM {{ ref('stg_dwwcs__claim_detail_bill') }}),

     stg_dwwcs__claim_detail_billline AS (SELECT *
                                          FROM {{ ref('stg_dwwcs__claim_detail_billline') }}),

     stg_wcsodsadm__customer AS (SELECT *
                                 FROM {{ ref('stg_wcsodsadm__customer') }}),
     vw_auditpro_billmessages AS (SELECT *
                                  FROM {{ ref('vw_auditpro_billmessages') }}),
     auditpro_rules AS (SELECT *
                        FROM {{ ref('auditpro_rules') }}),
     final_output as (select AB.*
                           , CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then ac.bill_seq_cr else 0 end         as CreditBillSeq
                           , CASE
                                 WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.PROVIDER_CHARGES_CR
                                 else 0 end                                                                as PROVIDER_CHARGES_CR
                           , CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.BR_CR else 0 end               as BR_CR
                           , CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.APCR else 0 end                as APCR
                           , CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.PPO_CR else 0 end              as PPO_CR
                           , CASE
                                 WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.Total_Savings_CR
                                 else 0 end                                                                as Total_Savings_CR
                           , eor.AP_EOR_Codes
                           , eor.AP_EOR_Descriptions
                           , COALESCE(aps.AP_REVIEWED_LINE_COUNT, 0)                                       as AP_REVIEWED_LINE_COUNT
                           , COALESCE(aps.AP_IMPACTED_LINE_COUNT, 0)                                       as AP_IMPACTED_LINE_COUNT
                      from (SELECT CONCAT(b.BILL_SITE_CODE, '-', b.CLIENT_CODE, '-',
                                          TO_VARCHAR(b.BILL_SEQ))                                               AS "SA_BILL_ID"
                                 , CASE WHEN bp.PEND_TO_ID ILIKE ('%MAP%') THEN 1 ELSE 2 END                    AS "AP_PEND_ID_FIRST"
                                 , b.CUSTOMER_NAME
                                 , b.ods_customer_id
                                 , b.SHARED_CLIENT_NAME
                                 , b.CLIENT_CODE_DESCRIPTION
                                 , b.CLIENT_CODE
                                 , b.BILL_SEQ
                                 , b.bill_seq_org_rev
                                 , b.CLAIM_NO
                                 , TO_DATE(b.BILL_REVIEW_RECEIVED_DATE)                                         AS "BILL_REVIEW_RECEIVED_DATE"
                                 , bp.PEND_TO_ID
                                 , bp.PEND_DATE                                                                 AS "PEND_DATE"
                                 , bp.PEND_RELEASE_DATE                                                         AS "PEND_RELEASE_DATE"
                                 , bp.TAT_IN_DAYS
                                 , DATEDIFF(day, TO_DATE(bp.PEND_DATE), TO_DATE(b.rundate))                     AS "AGE"
                                 , CONCAT(TO_VARCHAR(b.ods_customer_id), b.CLIENT_CODE,
                                          TO_VARCHAR(b.BILL_SEQ))                                               AS "UNIQUE_BILL"
                                 , b.CLIENT_GEO_STATE                                                           AS "CLIENT_GEO_STATE_CODE"
                                 , b.CLIENT_GEOSTATE_DESCRIPTION                                                AS "CLIENT_GEO_STATE"
                                 , bp.RULE_ID
                                 , b.BILLING_PROVIDER_NAME
                                 , b.BILLING_PROVIDER_TIN
                                 , b.PROVIDER_CHARGES
                                 , b.BILL_REVIEW_ALLOWED
                                 , bp.RELEASE_FLAG
                                 , b.AUDITPRO_ELIGIBLE
                                 , b.BILL_SITE_CODE
                                 , bp.WORKFLOW_TASK
                                 , b.TYPE_OF_BILL_CODE
                                 , MIN(TO_DATE(bp.PEND_DATE))                                                      OVER(PARTITION BY bp.PEND_TO_ID, "UNIQUE_BILL") AS "MIN_PEND_DATE"
        , MAX(TO_DATE(bp.PEND_RELEASE_DATE)) OVER(PARTITION BY bp.PEND_TO_ID, "UNIQUE_BILL") AS "MAX_PEND_RELEASE_DATE"
        , DATEDIFF(day, "MIN_PEND_DATE", "MAX_PEND_RELEASE_DATE") AS "TAT"
                                 , ROW_NUMBER()                                                                    over (partition by bp.BILL_SITE_CODE,bp.PEND_TO_ID, "UNIQUE_BILL"
                         order by bp.BILL_SITE_CODE,bp.PEND_TO_ID, "AP_PEND_ID_FIRST", "UNIQUE_BILL") AS "ROWNUMBER_TAT"
        , CASE
                                                                                                                                      WHEN bp.RELEASE_FLAG = 'Y' AND bp.PEND_TO_ID ILIKE ('%MAP%') THEN CONCAT(
                                                                                                                                              TO_VARCHAR(b.ods_customer_id),
                                                                                                                                              bp.CLIENT_CODE,
                                                                                                                                              TO_VARCHAR(bp.BILL_SEQ))
                                                                                                                                      ELSE null END AS "UNIQUE_BILL_AUDITPRO_PENDED"
                                 , CASE
                                       WHEN b.auditpro_reduction <> 0 and b.Bill_Status in (1, 8, 14) THEN CONCAT(
                                               TO_VARCHAR(b.ods_customer_id), bp.CLIENT_CODE, TO_VARCHAR(bp.BILL_SEQ))
                                       ELSE null END                                                            AS "UNIQUE_BILL_AUDITPRO_IMPACTED"
                                 , CASE
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 0 THEN '<0'
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 0 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 4 THEN '0-3'
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 4 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 5 THEN '4'
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 5 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 6 THEN '5'
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 6 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 7 THEN '6'
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 7 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 11 THEN '7-10'
                                       ELSE '>10' END                                                           AS "PEND_AGE_CATEGORY"
                                 , CASE
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 0 THEN 1
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 0 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 4 THEN 2
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 4 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 5 THEN 3
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 5 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 6 THEN 4
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 6 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 7 THEN 5
                                       WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 7 AND
                                            DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 11 THEN 6
                                       ELSE 7 END                                                               AS "PEND_AGE_CATEGORY_ORDER"
                                 , b.bill_status
                                 , b.bill_status_description
                                 , b.re_eval_flag
                                 , TO_DATE(b.bill_post_date)                                                    AS "BILL_POST_DATE"
                                 , MONTH (b.bill_post_date) AS "BILL_POST_DATE_MONTH"
                                 , YEAR (b.bill_post_date) AS "BILL_POST_DATE_YEAR"
                                 , QUARTER(b.bill_post_date) AS "BILL_POST_DATE_QUARTER"
                                 , b.TYPE_OF_BILL_DESCRIPTION
                                 , b.BILL_REVIEW_REDUCTION
                                 , IFNULL(b.AUDITPRO_REDUCTION
                                 , 0.0) as AUDITPRO_REDUCTION
                                 , b.TOTAL_ALLOWED
                                 , b.PPO_REDUCTION
                                 , b.COMPLEX_BILL_REVIEW_REDUCTION
                                 , b.IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION
                                 , b.NURSE_CONSULTANT_REVIEW_REDUCTION
                                 , b.USUAL_CUSTOMARY_SPECIALTY_REDUCTION
                                 , CONCAT('Data as of: '
                                 , TO_VARCHAR(b.rundate
                                 , 'mm/dd/yyyy HH12:MI AM')
                                 , ' PT') AS "DATA_AS_OF"
                                 , CASE
                                WHEN YEAR (b.BILL_POST_DATE) >= (YEAR (CURRENT_TIMESTAMP ()) - 2) THEN 1 ELSE 0 END AS "POSTED_WINDOW_FLAG"
                                 , '© '||TO_VARCHAR(YEAR (CURRENT_TIMESTAMP ()))||', Enlyte Group, LLC. All rights reserved.  This document contains confidential and trade secret information of Enlyte Group, LLC.  Any use, reproduction or disclosure of the information herein without the prior express written approval of Enlyte Group, LLC is prohibited.'
                                AS "DISCLAIMER"
                                 , bp.PEND_SEQ
                                 , ROW_NUMBER() over (partition by bp.BILL_SITE_CODE
                                 , "UNIQUE_BILL"
                                order by bp.BILL_SITE_CODE
                                 , "AP_PEND_ID_FIRST"
                                 , "UNIQUE_BILL") AS "ROWNUMBER_UNIQUE_BILL"
                                 , bp.RELEASE_BY_USER_ID
                                 , bp.RELEASE_BY_USERNAME AS "RELEASE_BY_USERNAME" -- added 1/23/2025, new column in EDW
                                 , b.NET_AUDITPRO_REDUCTION as GiveBackBillAmount
                                 , ROW_NUMBER() OVER (partition by bp.BILL_SITE_CODE
                                 , "UNIQUE_BILL" ORDER BY "AP_PEND_ID_FIRST"
                                 , bp.AUDITPRO_RULE_PRIORITY ASC
                                 , bp.pend_release_date DESC ) as ROWNUMBER_APPHRULEID
                            -- AUDITPRO_RULE_PRIORITY added 1/23/2025, new EDW column
                                 , CASE WHEN "AP_PEND_ID_FIRST" = 1 OR ifnull(b.NET_AUDITPRO_REDUCTION
                                 , 0.0) <> 0.0
                                THEN 1 ELSE 0 END AS INCLUDE_IN_REEVAL_REPORT
                                 , ROW_NUMBER() OVER (partition by bp.RELEASE_BY_USER_ID
                                 , bp.BILL_SITE_CODE
                                 , "UNIQUE_BILL"
                                 , bp.PEND_TO_ID
                                ORDER BY bp.RELEASE_BY_USER_ID
                                 , bp.BILL_SITE_CODE
                                 , "AP_PEND_ID_FIRST"
                                 , "UNIQUE_BILL"
                                 , bp.PEND_TO_ID) as ROWNUMBER_REPEND
                                 , CASE WHEN "ROWNUMBER_REPEND"
                                 > 1 THEN 1 ELSE 0 END as RE_PENDED_COUNT
                                 , b.CLAIM_SYS_SUBSET
                            -- prior version of re-eval savings, etc.
                                 , ob.BILL_REVIEW_REDUCTION as ORIGINAL_BILL_REVIEW_REDUCTION
                                 , ob.COMPLEX_BILL_REVIEW_REDUCTION as ORIGINAL_COMPLEX_BILL_REVIEW_REDUCTION
                                 , ob.NURSE_CONSULTANT_REVIEW_REDUCTION as ORIGINAL_NURSE_CONSULTANT_REVIEW_REDUCTION
                                 , ob.USUAL_CUSTOMARY_SPECIALTY_REDUCTION as ORIGINAL_USUAL_CUSTOMARY_SPECIALTY_REDUCTION
                                 , ob.IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION as ORIGINAL_IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION
                                 , ob.PPO_REDUCTION as ORIGINAL_PPO_REDUCTION
                                 , IFNULL(ob.AUDITPRO_REDUCTION
                                 , 0.0) as ORIGINAL_AUDITPRO_REDUCTION
                                 , ob.TOTAL_ALLOWED as ORIGINAL_TOTAL_ALLOWED
                                 , ob.BILL_REVIEW_RECEIVED_DATE as ORIGINAL_BILL_REVIEW_RECEIVED_DATE
                                 , ob.BILL_POST_DATE as ORIGINAL_BILL_POST_DATE
                            FROM stg_dwwcs__claim_detail_bill_pend_history bp
                                RIGHT JOIN stg_dwwcs__claim_detail_bill b
                            ON
                                bp.ods_customer_id = b.ods_customer_id
                                AND bp.client_code = b.client_code
                                AND bp.bill_seq = b.bill_seq
                                -- prior version of re-eval savings, etc.
                                LEFT JOIN stg_dwwcs__claim_detail_bill ob ON
                                ob.BILL_STATUS in (1,8)
                                and ifnull(b.FIRST_BILL_IN_REEVAL_SEQUENCE, b.bill_seq) <> b.bill_seq
                                and ob.ods_customer_id = b.ods_customer_id
                                AND ob.client_code = b.client_code
                                AND ob.bill_seq = b.BILL_SEQ_ORG_REV -- prior version of re-eval
                            WHERE
                                1=1
                              AND b.BILL_STATUS <> 12
                              AND b.ods_customer_id NOT IN (502)
                              AND b.BILL_SITE_CODE <> '@@@'
                              AND (b.BILL_POST_DATE = '1900-01-01'
                               OR YEAR (b.BILL_POST_DATE) >= (YEAR (CURRENT_TIMESTAMP ()) - 2))
                              AND b.BILL_SEQ
                                > 0
                              AND bp.AUDITPRO_SITE_CODE_FLAG = TRUE) AB

                               LEFT JOIN (select b.ods_customer_id,
                                                 b.client_code,
                                                 b.bill_seq                                                     as bill_seq_cr,
                                                 b.bill_seq_org_rev,
                                                 b.PROVIDER_CHARGES                                             as PROVIDER_CHARGES_CR,
                                                 b.BILL_REVIEW_REDUCTION                                        as BR_CR,
                                                 b.auditpro_reduction                                           as APCR,
                                                 b.PPO_Reduction                                                as PPO_CR,
                                                 ifnull(b.PROVIDER_CHARGES, 0.0) - ifnull(b.TOTAL_ALLOWED, 0.0) as Total_Savings_CR
                                          from stg_dwwcs__claim_detail_bill b
                                          WHERE b.BILL_STATUS = 12) AC ON
                          AB.ods_customer_id = AC.ods_customer_id
                              AND AB.client_code = AC.client_code
                              AND AB.bill_seq_org_rev = AC.bill_seq_org_rev
                               LEFT JOIN vw_auditpro_billmessages eor on
                          ab.SA_BILL_ID = eor.SA_BILL_ID
-- AuditPro Line Save subquery
                               LEFT JOIN (SELECT bl.BILL_SITE_CODE,
                                                 bl.CLIENT_CODE,
                                                 bl.BILL_SEQ,
                                                 SUM(CASE WHEN ph.PENDTOID IS NOT NULL THEN 1 ELSE 0 END)                   as AP_REVIEWED_LINE_COUNT,
                                                 SUM(CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) <> 0.0 THEN 1 ELSE 0 END) as AP_IMPACTED_LINE_COUNT
                                          FROM stg_dwwcs__claim_detail_billLINE bl
                                                   -- first version of each re-eval bill line - blf
                                                   left JOIN stg_dwwcs__claim_detail_billLINE blf
                                                             ON blf.ODS_CUSTOMER_ID = bl.ODS_CUSTOMER_ID and
                                                                blf.CLIENT_CODE = bl.CLIENT_CODE and
                                                                blf.BILL_SEQ = bl.FIRST_BILL_IN_REEVAL_SEQUENCE and
                                                                blf.LINE_SEQ = bl.LINE_SEQ
                                                   JOIN WCSODS.ADM.CUSTOMER ac on ac.SITE_CODE = bl.BILL_SITE_CODE AND
                                                                                  ac.CUSTOMER_ID = bl.ODS_CUSTOMER_ID
                                              -- EITHER PENDED FOR AUDITPRO TEAM OR HAS AN AUDITPRO REDUCTION
                                                   join auditpro_rules ph ON bl.ODS_CUSTOMER_ID = ph.ods_customer_id and
                                                                             bl.CLIENT_CODE = ph.client_code and
                                                                             bl.BILL_SEQ = ph.bill_seq and
                                                                             bl.line_seq = ph.line_seq

                                          WHERE 1 = 1
                                                    AND bl.Bill_SEQ > 0
                                                    -- only AuditPro clients
                                                    AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
                                                    AND bl.ods_customer_id NOT IN (502)
                                                    AND bl.BILL_SITE_CODE <> '@@@'
                                                    AND YEAR (bl.BILL_POST_DATE) >= (YEAR (CURRENT_TIMESTAMP ()) - 2)
GROUP BY
    bl.BILL_SITE_CODE,
    bl.CLIENT_CODE,
    bl.BILL_SEQ
    ) aps
ON
    AB.BILL_SITE_CODE = aps.BILL_SITE_CODE
    AND AB.CLIENT_CODE = aps.CLIENT_CODE
    AND AB.BILL_SEQ = aps.BILL_SEQ
    )

select *
from final_output