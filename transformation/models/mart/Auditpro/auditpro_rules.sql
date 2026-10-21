{{ config(materialized='table',
   tags=['auditpro'])}}

WITH stg_dwwcs__claim_detail_billline AS (SELECT *
                                          FROM {{ ref('stg_dwwcs__claim_detail_billline') }}),

     stg_wcsodsdbo__billrulefire AS (SELECT *
                                     FROM {{ ref('stg_wcsodsdbo__billrulefire') }}),

     stg_wcsodsdbo__tablelookup AS (SELECT *
                                    FROM {{ ref('stg_wcsodsdbo__tablelookup') }}),

     stg_wcsodsdbo__pend AS (SELECT *
                             FROM {{ ref('stg_wcsodsdbo__pend') }}),
     final_output as (select bl.ODS_CUSTOMER_ID,
                             bl.CLIENT_CODE,
                             bl.BILL_SEQ,
                             bl.LINE_SEQ,
                             brf.RULEID,
                             rid.SHORTDESC                   as AUDITPRO_RULE_DESCRIPTION,
                             rid.OLDCODE                     as AUDITPRO_PEND_GROUP,
                             brf.PENDTOID,
                             brf.DATERULEFIRED,
                             rid.PRIORITY                    as RulePriority,
-- ExactLineSeq match
                             1                               as APRuleType,
                             pnd.MINPENDDATE                 as PEND_DATE,
                             pnd.MAXRELEASEDATE              as PEND_RELEASE_DATE,
                             pnd.MINRELEASEFLAG              as PEND_RELEASE_FLAG,
                             CONCAT(bl.ODS_CUSTOMER_ID, '-', bl.CLIENT_CODE, '-', TO_VARCHAR(bl.BILL_SEQ), '-',
                                    TO_VARCHAR(bl.LINE_SEQ)) AS "UNIQUE_LINE",
                             ROW_NUMBER()                       over (partition by "UNIQUE_LINE"
                      order by "UNIQUE_LINE", "RULEPRIORITY",DATERULEFIRED DESC, brf.RULEID desc) AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY", CONCAT(
                 'Data as of: ', TO_VARCHAR(bl.rundate, 'mm/dd/yyyy HH12:MI AM'), ' PT') AS "DATA_AS_OF"
                      FROM stg_dwwcs__claim_detail_billline bl
                               -- auditpro eligible
--join  WCSODS.TableLookup ae on ae.CodeType = 'PT' and (ae.Code like '%MAP%' or ae.SHORTDESC LIKE '%MAP%' or ae.LONGDESC LIKE '%MAP%'
                               join stg_wcsodsdbo__billrulefire brf
                                    on bl.ODS_CUSTOMER_ID = brf.ODSCUSTOMERID and bl.CLIENT_CODE = brf.CLIENTCODE and
                                       bl.BILL_SEQ = brf.BILLSEQ and bl.LINE_SEQ = brf.LINeSEQ
                                        AND (brf.PENDTOID ilike '%MAP%'
        OR brf.ruleid ilike '%MAP%')
                          -- RULE_ID description:
                               left JOIN stg_wcsodsdbo__tablelookup rid
                                         on rid.TypeCode = 'AUPR' and rid.SiteCode = 'ZZZ' and brf.RULEID = rid.CODE and
                                            rid.SERVERNAME LIKE '%SCPROD1'
                               left join
                           (select ODSCUSTOMERID,
                                   CLIENTCODE,
                                   BILLSEQ,
                                   PENDTOID,
                                   RULEID,
                                   min(PENDDATE)    AS MINPENDDATE,
                                   MAX(RELEASEDATE) AS MAXRELEASEDATE,
                                   min(RELEASEFLAG) AS MINRELEASEFLAG
                            FROM stg_wcsodsdbo__pend
                            WHERE PENDTOID LIKE '%MAP%' AND YEAR (PENDDATE) >= YEAR (CURRENT_TIMESTAMP ()) - 3
group by ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID) AS pnd
on brf.ODSCUSTOMERID = pnd.ODSCUSTOMERID and brf.CLIENTCODe = pnd.CLIENTCODE and brf.BILLSEQ = pnd.BILLSEQ and concat('#',brf.PENDTOID) = pnd.PENDTOID and brf.RULEID = pnd.RULEID
WHERE
    1=1
  AND bl.Bill_SEQ
    > 0
-- only AuditPro clients
  AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
  AND bl.BILL_SITE_CODE <> '@@@'
  AND YEAR (bl.BILL_POST_DATE) >= (YEAR (CURRENT_TIMESTAMP ()) - 2)


UNION ALL

-- add in lines where billrulefire lineseq = 0 (bill level rules)
select bl.ODS_CUSTOMER_ID,
       bl.CLIENT_CODE,
       bl.BILL_SEQ,
       bl.LINE_SEQ,
       brf.RULEID,
       rid.SHORTDESC                                                                                               as AUDITPRO_RULE_DESCRIPTION,
       rid.OLDCODE                                                                                                 as AUDITPRO_PEND_GROUP,
       brf.PENDTOID,
       brf.DATERULEFIRED,
       rid.PRIORITY                                                                                                as RulePriority,
-- 'BillLevelRule'
       2                                                                                                           as APRuleType,
       pnd.MINPENDDATE                                                                                             as PEND_DATE,
       pnd.MAXRELEASEDATE                                                                                          as PEND_RELEASE_DATE,
       pnd.MINRELEASEFLAG                                                                                          as PEND_RELEASE_FLAG,
       CONCAT(bl.ODS_CUSTOMER_ID, '-', bl.CLIENT_CODE, '-', TO_VARCHAR(bl.BILL_SEQ), '-',
              TO_VARCHAR(bl.LINE_SEQ))                                                                             AS "UNIQUE_LINE",
       ROW_NUMBER()                                                                                                   over (partition by "UNIQUE_LINE"
                      order by "UNIQUE_LINE", "RULEPRIORITY",DATERULEFIRED DESC, brf.RULEID desc) AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY", CONCAT(
        'Data as of: ', TO_VARCHAR(bl.rundate, 'mm/dd/yyyy HH12:MI AM'), ' PT') AS "DATA_AS_OF"
FROM stg_dwwcs__claim_detail_billline bl
         -- auditpro eligible
--join  WCSODS.TableLookup ae as ae.CodeType = 'PT' and (ae.Code like '%MAP%' or ae.SHORTDESC LIKE '%MAP%' or ae.LONGDESC LIKE '%MAP%'
         join stg_wcsodsdbo__billrulefire brf
              on bl.ODS_CUSTOMER_ID = brf.ODSCUSTOMERID and bl.CLIENT_CODE = brf.CLIENTCODE and
                 bl.BILL_SEQ = brf.BILLSEQ and brf.lineseq = 0
                  AND (brf.PENDTOID ilike '%MAP%'
        OR brf.ruleid ilike '%MAP%')
-- RULE_ID description:
         left JOIN stg_wcsodsdbo__tablelookup rid
                   on rid.TypeCode = 'AUPR' and rid.SiteCode = 'ZZZ' and brf.RULEID = rid.CODE and
                      rid.SERVERNAME LIKE '%SCPROD1'
         left join
     (select ODSCUSTOMERID,
             CLIENTCODE,
             BILLSEQ,
             PENDTOID,
             RULEID,
             min(PENDDATE)    AS MINPENDDATE,
             MAX(RELEASEDATE) AS MAXRELEASEDATE,
             min(RELEASEFLAG) AS MINRELEASEFLAG
      FROM stg_wcsodsdbo__pend
      WHERE PENDTOID LIKE '%MAP%' AND YEAR (PENDDATE) >= YEAR(CURRENT_TIMESTAMP()) - 3
group by ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID) AS pnd
on brf.ODSCUSTOMERID = pnd.ODSCUSTOMERID and brf.CLIENTCODe = pnd.CLIENTCODE and brf.BILLSEQ = pnd.BILLSEQ and concat('#',brf.PENDTOID) = pnd.PENDTOID and brf.RULEID = pnd.RULEID
WHERE
    1=1
  AND bl.Bill_SEQ
    > 0
-- only AuditPro clients
  AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
  AND bl.BILL_SITE_CODE <> '@@@'
  AND YEAR (bl.BILL_POST_DATE) >= (YEAR (CURRENT_TIMESTAMP ()) - 2)

UNION ALL

-- find lines that have an auditpro reduction but are not in either of the above two inserts
-- add the ones with the max priority

select bl.ODS_CUSTOMER_ID,
       bl.CLIENT_CODE,
       bl.BILL_SEQ,
       bl.LINE_SEQ,
       brf.RULEID,
       rid.SHORTDESC                                                                                               as AUDITPRO_RULE_DESCRIPTION,
       rid.OLDCODE                                                                                                 as AUDITPRO_PEND_GROUP,
       brf.PENDTOID,
       brf.DATERULEFIRED,
       rid.PRIORITY                                                                                                as RulePriority,
-- 'OtherLineSeq ' match
       3                                                                                                           as APRuleType,
       pnd.MINPENDDATE                                                                                             as PEND_DATE,
       pnd.MAXRELEASEDATE                                                                                          as PEND_RELEASE_DATE,
       pnd.MINRELEASEFLAG                                                                                          as PEND_RELEASE_FLAG,
       CONCAT(bl.ODS_CUSTOMER_ID, '-', bl.CLIENT_CODE, '-', TO_VARCHAR(bl.BILL_SEQ), '-',
              TO_VARCHAR(bl.LINE_SEQ))                                                                             AS "UNIQUE_LINE",
       1                                                                                                           AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY",
       CONCAT('Data as of: ', TO_VARCHAR(bl.rundate, 'mm/dd/yyyy HH12:MI AM'),
              ' PT')                                                                                               AS "DATA_AS_OF"
FROM stg_dwwcs__claim_detail_billline bl
         join stg_wcsodsdbo__billrulefire brf
              on bl.ODS_CUSTOMER_ID = brf.ODSCUSTOMERID and bl.CLIENT_CODE = brf.CLIENTCODE and
                 bl.BILL_SEQ = brf.BILLSEQ and brf.lineseq <> 0 and bl.LINE_SEQ <> brf.LINeSEQ
                  AND (brf.PENDTOID ilike '%MAP%'
        OR brf.ruleid ilike '%MAP%')
-- RULE_ID description:
         left JOIN stg_wcsodsdbo__tablelookup rid
                   on rid.TypeCode = 'AUPR' and rid.SiteCode = 'ZZZ' and brf.RULEID = rid.CODE and
                      rid.SERVERNAME LIKE '%SCPROD1'
         left join
     (select ODSCUSTOMERID,
             CLIENTCODE,
             BILLSEQ,
             PENDTOID,
             RULEID,
             min(PENDDATE)    AS MINPENDDATE,
             MAX(RELEASEDATE) AS MAXRELEASEDATE,
             min(RELEASEFLAG) AS MINRELEASEFLAG
      FROM stg_wcsodsdbo__pend
      WHERE PENDTOID LIKE '%MAP%' AND YEAR (PENDDATE) >= YEAR(CURRENT_TIMESTAMP()) - 3
group by ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID)
    AS pnd
on brf.ODSCUSTOMERID = pnd.ODSCUSTOMERID and brf.CLIENTCODe = pnd.CLIENTCODE and brf.BILLSEQ = pnd.BILLSEQ and concat('#',brf.PENDTOID) = pnd.PENDTOID and brf.RULEID = pnd.RULEID
WHERE
    1=1
  AND bl.Bill_SEQ
    > 0
-- only AuditPro clients
  AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
  AND bl.BILL_SITE_CODE <> '@@@'
  and ifnull(bl.AUDITPRO_REDUCTION
    , 0.0) <> 0.0
  AND YEAR (bl.BILL_POST_DATE) >= (YEAR (CURRENT_TIMESTAMP ()) - 2)
-- not in two above queries
  AND NOT EXISTS (
    SELECT 1
    FROM stg_dwwcs__claim_detail_billline bl2
    JOIN stg_wcsodsdbo__billrulefire brf2
    ON bl2.ODS_CUSTOMER_ID = brf2.ODSCUSTOMERID
  AND bl2.CLIENT_CODE = brf2.CLIENTCODE
  AND bl2.BILL_SEQ = brf2.BILLSEQ
  AND (bl2.LINE_SEQ = brf2.LINESEQ
   OR brf2.LINESEQ = 0)
  AND (brf2.PENDTOID ilike '%MAP%'
   OR brf2.ruleid ilike '%MAP%')
    WHERE
    bl.ODS_CUSTOMER_ID = bl2.ODS_CUSTOMER_ID
  AND bl.CLIENT_CODE = bl2.CLIENT_CODE
  AND bl.BILL_SEQ = bl2.BILL_SEQ
  AND bl.LINE_SEQ = bl2.LINE_SEQ
    )
    QUALIFY ROW_NUMBER() OVER (
    PARTITION BY bl.ODS_CUSTOMER_ID
    , bl.CLIENT_CODE
    , bl.BILL_SEQ
    , bl.LINE_SEQ
    ORDER BY rid.PRIORITY, brf.DATERULEFIRED DESC,brf.RULEID desc
    ) = 1 -- Only keep highest priority rule
    )

select *
from final_output

