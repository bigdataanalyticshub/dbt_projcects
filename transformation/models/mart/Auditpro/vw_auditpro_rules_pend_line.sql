{{ config(materialized='table',
    tags = ['auditpro']) }}

WITH stg_dwwcs__claim_detail_billline AS (SELECT *
                                          FROM {{ ref('stg_dwwcs__claim_detail_billline') }}),

     stg_wcsodsdbo__modifier AS (SELECT *
                                 FROM {{ ref('stg_wcsodsdbo__modifier') }}),

     stg_wcsodsdbo__linemod AS (SELECT *
                                FROM {{ ref('stg_wcsodsdbo__linemod') }}),

     stg_wcsodsdbo__tablelookup AS (SELECT *
                                    FROM {{ ref('stg_wcsodsdbo__tablelookup') }}),

     stg_wcsodsadm__customer AS (SELECT *
                                 FROM {{ ref('stg_wcsodsadm__customer') }}),

     auditpro_rules AS (SELECT *
                        FROM {{ ref('auditpro_rules') }}),

     base AS (select bl.BILL_SITE_CODE,
                     bl.CLIENT_CODE,
                     bl.BILL_SEQ,
                     bl.LINE_SEQ,
                     -- message code and description for auditpro reductions only
                     blm.modifier,
                     mes.MODDESCRIPTION                                                                            as MODIFIER_DESCRIPTION,
                     TO_DATE(bl.BILL_POST_DATE)                                                                    AS BILL_POST_DATE,
                     bl.FIRST_BILL_IN_REEVAL_SEQUENCE,
                     bl.AUDITPRO_REDUCTION_TREND,
                     bl.CLAIM_SYS_SUBSET,
                     bl.CLAIM_SYSTEM_DESCRIPTION,
                     CASE
                         WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) <> 0.0 THEN 'Yes'
                         ELSE 'No' END                                                                             as LINE_HAS_AP_REDUCTION,
                     CASE
                         WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) <> 0.0 THEN CONCAT(bl.BILL_SITE_CODE, '-',
                                                                                    bl.CLIENT_CODE, '-',
                                                                                    TO_VARCHAR(bl.BILL_SEQ), '-',
                                                                                    TO_VARCHAR(bl.LINE_SEQ))
                         ELSE NULL END                                                                             as UNIQUE_LINE_HAS_AP_REDUCTION,
                     CASE
                         WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) <> 0.0 THEN CONCAT(bl.BILL_SITE_CODE, '-',
                                                                                    bl.CLIENT_CODE, '-',
                                                                                    TO_VARCHAR(bl.BILL_SEQ))
                         ELSE NULL END                                                                             as UNIQUE_BILL_HAS_AP_REDUCTION,
                     CASE
                         WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) = 0.0 THEN CONCAT(bl.BILL_SITE_CODE, '-',
                                                                                   bl.CLIENT_CODE, '-',
                                                                                   TO_VARCHAR(bl.BILL_SEQ), '-',
                                                                                   TO_VARCHAR(bl.LINE_SEQ))
                         ELSE NULL END                                                                             as UNIQUE_LINE_HAS_NO_AP_REDUCTION,

                     CASE
                         WHEN bl.RE_EVAL_FLAG = 0 THEN CONCAT(TO_VARCHAR(bl.ods_customer_id), '-', bl.CLIENT_CODE, '-',
                                                              TO_VARCHAR(bl.BILL_SEQ))
                         ELSE NULL END                                                                             as BILLID_NOREEVAL, -- UNIQUE bill_id for NON REEVAL
                     CASE
                         WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) <> 0.0 and BL.RE_EVAL_FLAG = 1 THEN CONCAT(
                                 bl.BILL_SITE_CODE, '-', bl.CLIENT_CODE, '-', TO_VARCHAR(bl.BILL_SEQ))
                         ELSE NULL END                                                                             as UNIQUE_REVAL_BILL_HAS_AP_REDUCTION,
                     CASE
                         WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) <> 0.0 and BL.RE_EVAL_FLAG = 0 THEN CONCAT(
                                 bl.BILL_SITE_CODE, '-', bl.CLIENT_CODE, '-', TO_VARCHAR(bl.BILL_SEQ))
                         ELSE NULL END                                                                             as UNIQUE__NOREEVAL_BILL_HAS_AP_REDUCTION,
                     CASE
                         WHEN IFNULL(bl.AUDITPRO_REDUCTION, 0.0) <> 0.0 and BL.RE_EVAL_FLAG = 1 THEN CONCAT(
                                 bl.BILL_SITE_CODE, '-', bl.CLIENT_CODE, '-', TO_VARCHAR(bl.BILL_SEQ), '-',
                                 TO_VARCHAR(bl.LINE_SEQ))
                         ELSE NULL END                                                                             as UNIQUE_REVAL_LINE_HAS_AP_REDUCTION,
                     bl.MESSAGE_205_OR_270_FLAG,
                     bl.MESSAGE_CODE_SET,
                     CASE
                         WHEN bl.AUDITPRO_REEVAL_FLAG > 0 OR bl.BILL_SEQ_ORG_REV IS NULL THEN 'Yes'
                         ELSE 'No' END                                                                             as NEW_LINE_OR_REEVAL_WITH_AP_REDUCTION,
                     bl.PRIOR_MESSAGE_CODE_SET,
                     ph.PENDTOID,
                     ph.RULEID                                                                                     as AUDITPRO_RULE_ID,
                     ph.AUDITPRO_RULE_DESCRIPTION,
                     ph.AUDITPRO_PEND_GROUP,
                     bl.RE_EVAL_FLAG,
                     CASE WHEN bl.RE_EVAL_FLAG = 1 THEN 'Yes' ELSE 'No' END                                        as RE_EVAL_FLAG_DESC,
                     bl.BILL_REEVAL_COUNT,
                     CASE
                         WHEN bl.RE_EVAL_FLAG = 1 THEN CONCAT(TO_VARCHAR(bl.ods_customer_id), '-', bl.CLIENT_CODE, '-',
                                                              TO_VARCHAR(bl.BILL_SEQ))
                         ELSE NULL END                                                                             as BILLID_REEVAL,   -- UNIQUE bill_id for re-eval
                     CASE
                         WHEN bl.BILL_STATUS in (1, 8) and bl.TOTAL_ALLOWED = 0 THEN 'Yes'
                         ELSE 'No' END                                                                             as TOTAL_DENIAL,
                     bl.AUDITPRO_REDUCTION,
                     bl.AUDITPRO_REEVAL_FLAG,
                     ifnull(bl.NET_AUDITPRO_REDUCTION, 0.0)                                                        as NET_AUDITPRO_REDUCTION,
                     ifnull(blF.AUDITPRO_REDUCTION, 0.0) -
                     ifnull(bL.AUDITPRO_REDUCTION, 0.0)                                                            as AUDITPRO_GIVEBACK,
                     case
                         when bl.AUDITPRO_REEVAL_FLAG <> TRUE then bl.AUDITPRO_REDUCTION
                         else ifnull(bl.NET_AUDITPRO_REDUCTION, 0.0) end                                           as REEVALNET_NOREEVALTOT_AUDITPROREDUCTION,
                     bl.INCREMENT_VALUE,                                                                                               -- This is not complete logic for bill level nor line level counts (will have dups for every line and audit pro pend record)
                     bl.BILL_STATUS,
                     CONCAT(bl.BILL_SITE_CODE, '-', bl.CLIENT_CODE, '-',
                            TO_VARCHAR(bl.BILL_SEQ))                                                               AS "UNIQUE_BILL",
                     CONCAT(bl.BILL_SITE_CODE, '-', bl.CLIENT_CODE, '-', TO_VARCHAR(bl.BILL_SEQ), '-',
                            TO_VARCHAR(bl.LINE_SEQ))                                                               AS "UNIQUE_LINE",
                     CASE
                         WHEN YEAR (bl.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2) THEN 1 ELSE 0 END AS "POSTED_WINDOW_FLAG",
    CONCAT('Data as of: ',TO_VARCHAR(bl.rundate,'mm/dd/yyyy HH12:MI AM'),' PT') AS "DATA_AS_OF",
      '� '||TO_VARCHAR(YEAR(CURRENT_TIMESTAMP()))||', Enlyte Group, LLC. All rights reserved.  This document contains confidential and trade secret information of Enlyte Group, LLC.  Any use, reproduction or
      disclosure of the information herein without the prior express written approval of Enlyte Group, LLC is prohibited.'
      AS "DISCLAIMER",
    bl.CUSTOMER_NAME,
    bl.SHARED_CLIENT_NAME,
    bl.CLIENT_GEO_STATE,
    bl.billing_provider_tin,
    bl.priced_service_code,
    bl.priced_service_code_description,
    bl.TYPE_OF_BILL_CODE,
    bl.TYPE_OF_BILL_DESCRIPTION,
    bl.BILL_STATUS_DESCRIPTION,
    CASE
        WHEN bl.RE_EVAL_FLAG = 1 AND bl.AUDITPRO_REDUCTION_TREND = 'INCREASE'    THEN 'ReEval Y/AP Increase'
        WHEN bl.RE_EVAL_FLAG = 1 AND bl.AUDITPRO_REDUCTION_TREND = 'DECREASE'    THEN 'ReEval Y/AP Decrease'
        WHEN bl.RE_EVAL_FLAG = 1 AND bl.AUDITPRO_REDUCTION_TREND = 'NONE'        THEN 'ReEval Y/AP None'
        WHEN bl.RE_EVAL_FLAG = 0 AND bl.AUDITPRO_REDUCTION_TREND = 'INCREASE'    THEN 'ReEval N/AP Increase'
        WHEN bl.RE_EVAL_FLAG = 0 AND bl.AUDITPRO_REDUCTION_TREND = 'DECREASE'    THEN 'ReEval N/AP Decrease'
        WHEN bl.RE_EVAL_FLAG = 0 AND bl.AUDITPRO_REDUCTION_TREND = 'NONE'        THEN 'ReEval N/AP None'
        ELSE NULL
END
AS REEVAL_APTREND,
    CASE WHEN bl.RE_EVAL_FLAG = 1 AND IFNULL(bl.NET_AUDITPRO_REDUCTION,0.0) <> 0.0 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) ELSE NULL
END as         UNIQUE_LINE_RE_EVAL_ADD_PAYMENT,
    CASE WHEN bl.RE_EVAL_FLAG = 1 THEN IFNULL(blf.AUDITPRO_REDUCTION,0.0) ELSE IFNULL(bl.AUDITPRO_REDUCTION,0.0)
END AS AUDITPRO_ORIG_REDUCTIONS, -- first billseq ap reduction
    ROW_NUMBER() over (partition by "UNIQUE_LINE"
                         order by bl.BILL_SITE_CODE, ph.RULEPRIORITY, "UNIQUE_LINE",
                          blm.modifier DESC, blm.REDUCTIONCODE DESC, ph.RULEID DESC) AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY",
    ROW_NUMBER() over (partition by "UNIQUE_BILL"
                         order by bl.BILL_SITE_CODE, ph.RULEPRIORITY, "UNIQUE_BILL",bl.LINE_SEQ DESC,
                          blm.modifier DESC, blm.REDUCTIONCODE DESC, ph.RULEID DESC) AS "ROWNUMBER_UNIQUE_BILL_RULEPRIORITY",
    ph.RULEPRIORITY AS RULE_PRIORITY,
    bl.PROVIDER_CHARGES
FROM stg_dwwcs__claim_detail_billline bl
-- first version of each re-eval bill line - blf
left JOIN stg_dwwcs__claim_detail_billline blf ON blf.ODS_CUSTOMER_ID = bl.ODS_CUSTOMER_ID and blf.CLIENT_CODE = bl.CLIENT_CODE and blf.BILL_SEQ = bl.FIRST_BILL_IN_REEVAL_SEQUENCE and blf.LINE_SEQ = bl.LINE_SEQ
JOIN stg_wcsodsadm__customer ac on ac.SITE_CODE = bl.BILL_SITE_CODE AND ac.CUSTOMER_ID = bl.ODS_CUSTOMER_ID
    -- EITHER PENDED FOR AUDITPRO TEAM OR HAS AN AUDITPRO REDUCTION
join  auditpro_rules ph ON bl.ODS_CUSTOMER_ID = ph.ods_customer_id and bl.CLIENT_CODE = ph.client_code and bl.BILL_SEQ = ph.bill_seq and bl.line_seq = ph.line_seq
  -- only AuditPro Reduction related message codes
join stg_wcsodsdbo__tablelookup ap on bl.BILL_SITE_CODE = ap.SITECODE
        and ap.TypeCode = 'AURC'
left join stg_wcsodsdbo__linemod blm
    on bl.ODS_CUSTOMER_ID = blm.ODSCUSTOMERID
        and bl.CLIENT_CODE = blm.CLIENTCODE
        and bl.BILL_SEQ = blm.BILLSEQ
        and bl.line_seq = blm.LINESEQ
        -- and bl.REDUCTIONCODE <> 0 -- not needed due to below condition
        and ap.CODE = blm.REDUCTIONCODE  -- only include AuditPro related messages
-- jurisdiction and sitecode specific
left join stg_wcsodsdbo__modifier mes
    on blm.MODIFIER = mes.CODE
        and ac.SERVER_NAME = mes.SERVERNAME
        and blm.MODSUBSET = mes.JURISDICTION
        and blm.MODSITECODE = mes.SITECODE
WHERE
    1=1
    AND bl.Bill_SEQ > 0
 -- only AuditPro clients
    AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
    AND bl.ods_customer_id NOT IN (502)
    AND bl.BILL_SITE_CODE <> '@@@'
    AND YEAR(bl.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2)
)

SELECT *
FROM base
