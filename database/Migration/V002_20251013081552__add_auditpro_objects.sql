CREATE SCHEMA IF NOT EXISTS ADM;
GRANT OWNERSHIP ON SCHEMA ADM TO ROLE CTS_OPS COPY CURRENT GRANTS;

CREATE SCHEMA IF NOT EXISTS AUDITPRO;
GRANT OWNERSHIP ON SCHEMA AUDITPRO TO ROLE CTS_OPS COPY CURRENT GRANTS;

CREATE SCHEMA IF NOT EXISTS AUDITPRO_STG;
GRANT OWNERSHIP ON SCHEMA AUDITPRO_STG TO ROLE CTS_OPS COPY CURRENT GRANTS;


-- We're creating this procedure in ADM schema to recreate our views in _STG as tables in
-- the schema users will access. It can be run from any schema, but the source and target schemas
-- must be specified. View list is optional, although you'll need to specify it if you don't want all views
-- or there's a dependency order to follow.

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

    try:
        # Get current database name
        current_db_result = session.sql("SELECT CURRENT_DATABASE()").collect()
        current_database = current_db_result[0][0]

        if not current_database:
            return json.dumps({
                'error': 'No current database set. Please USE a database first.',
                'successful_tables': [],
                'failed_tables': [],
                'total_views_requested': 0,
                'total_tables_created': 0
            })

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
                results['errors'].append(f"Target schema '{target_schema}' does not exist in database '{current_database}'. Please create the schema first.")
                return json.dumps(results)

        except Exception as e:
            results['errors'].append(f"Failed to check if target schema {target_schema} exists: {str(e)}")
            return json.dumps(results)

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
                    results['errors'].append(f"No views found in schema {source_schema}")
                    return json.dumps(results)

            except Exception as e:
                results['errors'].append(f"Failed to query views in schema {source_schema}: {str(e)}")
                return json.dumps(results)
        else:
            # Parse the comma-separated view list
            ordered_views = [name.strip() for name in view_list.split(',') if name.strip()]

            if not ordered_views:
                results['errors'].append("View list is empty or invalid")
                return json.dumps(results)

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
                results['errors'].append(f"The following views do not exist in schema {source_schema}: {', '.join(missing_views)}")
                return json.dumps(results)

        except Exception as e:
            results['errors'].append(f"Failed to verify views exist in schema {source_schema}: {str(e)}")
            return json.dumps(results)

        # Process each view in the order specified
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
                error_msg = f"Failed to create table {view_name}: {str(e)}"
                table_result['error'] = str(e)
                results['failed_tables'].append(table_result)
                results['errors'].append(error_msg)
                continue

        # Add summary message
        successful_grants = sum(1 for table in results['successful_tables'] if table.get('grant_applied', False))
        summary = f"Process completed. Created {results['total_tables_created']} tables out of {results['total_views_requested']} views requested."

        if grant_permissions:
            summary += f" Applied SELECT grants to ANALYSIS role for {successful_grants} tables."
        else:
            summary += " No grants applied (ANALYSIS role not accessible)."

        results['summary'] = summary

        return json.dumps(results, indent=2)

    except Exception as e:
        results['errors'].append(f"Unexpected error in main process: {str(e)}")
        return json.dumps(results, indent=2)
$$;


-- AUDITPRO_STG.VW_AUDITPRO_BillMessages

/*
    select * from ANALYSIS_SANDBOX.TEMP.VW_AUDITPRO_BillMessages
*/

CREATE OR REPLACE VIEW AUDITPRO_STG.VW_AUDITPRO_BillMessages
AS

  -- Source for PowerBI AuditPro Reports that require bill level message code/description
  -- information using the AUDITPRO line table as a source. Only include message codes for
  -- AuditPro Reduction codes.
SELECT
    SA_BILL_ID
    ,ODS_CUSTOMER_ID
    ,LISTAGG(EORCode , ' ; ')
        WITHIN GROUP (ORDER BY EORCode) as AP_EOR_Codes
    ,LISTAGG(EORDescription , ' ; ')
        WITHIN GROUP (ORDER BY EORCode) as AP_EOR_Descriptions
FROM
(
  select
    DISTINCT
    CONCAT(b.BILL_SITE_CODE, '-',b.CLIENT_CODE,'-', TO_VARCHAR(b.BILL_SEQ)) AS "SA_BILL_ID"
    ,b.ODS_CUSTOMER_ID
    --,c.SERVER_NAME
    --,bl.MODSITECODE
    --,bl.MODSUBSET
    ,bl.MODIFIER as EORCode
    ,mes.MODDESCRIPTION as EORDescription
  FROM DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL b
  -- only AuditPro Reduction related message codes
  join WCSODS.DBO.TABLELOOKUP ap on b.BILL_SITE_CODE = ap.SITECODE
        and ap.TypeCode = 'AURC'
  join WCSODS.DBO.LINEMOD bl
    on b.ODS_CUSTOMER_ID = bl.ODSCUSTOMERID
        and b.CLIENT_CODE = bl.CLIENTCODE
        and b.BILL_SEQ = bl.BILLSEQ
        -- and bl.REDUCTIONCODE <> 0 -- not needed due to below condition
        and ap.CODE = bl.REDUCTIONCODE  -- only include AuditPro related messages
  join WCSODS.ADM.CUSTOMER c
    on b.ODS_CUSTOMER_ID = c.CUSTOMER_ID
-- jurisdiction and sitecode specific
  left join WCSODS.DBO.MODIFIER mes
    on bl.MODIFIER = mes.CODE
        and c.SERVER_NAME = mes.SERVERNAME
        and bl.MODSUBSET = mes.JURISDICTION
        and bl.MODSITECODE = mes.SITECODE
  WHERE
    1=1
    AND b.BILL_STATUS <> 12
    AND b.ods_customer_id NOT IN (502)
    AND b.BILL_SITE_CODE <> '@@@'
    AND YEAR(b.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2)
    AND b.BILL_SEQ > 0
    AND b.AUDITPRO_SITE_CODE_FLAG = TRUE
)
GROUP BY
    SA_BILL_ID
    ,ODS_CUSTOMER_ID
;

-- AUDITPRO_STG.AUDITPRO_RULES

CREATE OR REPLACE VIEW AUDITPRO_STG.AUDITPRO_RULES
AS

-- drop view ANALYSIS_SANDBOX.TEMP.AUDITPRO_RULES
-- New WCS EDW table for all rules at line level for AuditPro
-- Obtain all rules at line level for AuditPro

-- add lines where billrulefire lineseq matches the Pend LineSeq (line level rules)
select
bl.ODS_CUSTOMER_ID,
bl.CLIENT_CODE,
bl.BILL_SEQ,
bl.LINE_SEQ,
brf.RULEID,
rid.SHORTDESC as AUDITPRO_RULE_DESCRIPTION,
rid.OLDCODE as AUDITPRO_PEND_GROUP,
brf.PENDTOID,
brf.DATERULEFIRED,
rid.PRIORITY as RulePriority,
-- ExactLineSeq match
1 as APRuleType,
pnd.MINPENDDATE as PEND_DATE,
pnd.MAXRELEASEDATE as PEND_RELEASE_DATE,
pnd.MINRELEASEFLAG as PEND_RELEASE_FLAG,
CONCAT(bl.ODS_CUSTOMER_ID,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) AS "UNIQUE_LINE",
ROW_NUMBER() over (partition by "UNIQUE_LINE"
                      order by "UNIQUE_LINE", "RULEPRIORITY") AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY",
CONCAT('Data as of: ',TO_VARCHAR(bl.rundate,'mm/dd/yyyy HH12:MI AM'),' PT') AS "DATA_AS_OF"
FROM DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILLLINE bl
-- auditpro eligible
--join  WCSODS.TableLookup ae on ae.CodeType = 'PT' and (ae.Code like '%MAP%' or ae.SHORTDESC LIKE '%MAP%' or ae.LONGDESC LIKE '%MAP%'
join WCSODS.DBO.BILLRULEFIRE brf on bl.ODS_CUSTOMER_ID = brf.ODSCUSTOMERID and bl.CLIENT_CODE = brf.CLIENTCODE and bl.BILL_SEQ = brf.BILLSEQ and bl.LINE_SEQ = brf.LINeSEQ
    AND (brf.PENDTOID ilike '%MAP%'
        OR brf.ruleid ilike '%MAP%')
    -- RULE_ID description:
left JOIN WCSODS.DBO.TABLELOOKUP rid on  rid.TypeCode = 'AUPR' and rid.SiteCode = 'ZZZ' and brf.RULEID = rid.CODE and rid.SERVERNAME LIKE '%SCPROD1'
left join
    (select ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID, min(PENDDATE) AS MINPENDDATE, MAX(RELEASEDATE) AS MAXRELEASEDATE, min(RELEASEFLAG) AS MINRELEASEFLAG FROM WCSODS.DBO.PEND
        WHERE PENDTOID LIKE '%MAP%' AND YEAR(PENDDATE) >= YEAR(CURRENT_TIMESTAMP()) - 3
        group by ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID) AS pnd on brf.ODSCUSTOMERID = pnd.ODSCUSTOMERID and brf.CLIENTCODe = pnd.CLIENTCODE and brf.BILLSEQ = pnd.BILLSEQ and  concat('#',brf.PENDTOID) = pnd.PENDTOID and brf.RULEID = pnd.RULEID
WHERE
    1=1
    AND bl.Bill_SEQ > 0
 -- only AuditPro clients
    AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
    AND bl.BILL_SITE_CODE <> '@@@'
    AND YEAR(bl.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2)


UNION ALL

-- add in lines where billrulefire lineseq = 0 (bill level rules)
select
bl.ODS_CUSTOMER_ID,
bl.CLIENT_CODE,
bl.BILL_SEQ,
bl.LINE_SEQ,
brf.RULEID,
rid.SHORTDESC as AUDITPRO_RULE_DESCRIPTION,
rid.OLDCODE as AUDITPRO_PEND_GROUP,
brf.PENDTOID,
brf.DATERULEFIRED,
rid.PRIORITY as RulePriority,
-- 'BillLevelRule'
2 as APRuleType,
pnd.MINPENDDATE as PEND_DATE,
pnd.MAXRELEASEDATE as PEND_RELEASE_DATE,
pnd.MINRELEASEFLAG as PEND_RELEASE_FLAG,
CONCAT(bl.ODS_CUSTOMER_ID,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) AS "UNIQUE_LINE",
ROW_NUMBER() over (partition by "UNIQUE_LINE"
                      order by "UNIQUE_LINE", "RULEPRIORITY") AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY",
CONCAT('Data as of: ',TO_VARCHAR(bl.rundate,'mm/dd/yyyy HH12:MI AM'),' PT') AS "DATA_AS_OF"
FROM DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILLLINE bl
-- auditpro eligible
--join  WCSODS.TableLookup ae as ae.CodeType = 'PT' and (ae.Code like '%MAP%' or ae.SHORTDESC LIKE '%MAP%' or ae.LONGDESC LIKE '%MAP%'
join WCSODS.DBO.BILLRULEFIRE brf on bl.ODS_CUSTOMER_ID = brf.ODSCUSTOMERID and bl.CLIENT_CODE = brf.CLIENTCODE and bl.BILL_SEQ = brf.BILLSEQ and brf.lineseq = 0
    AND (brf.PENDTOID ilike '%MAP%'
        OR brf.ruleid ilike '%MAP%')
-- RULE_ID description:
left JOIN WCSODS.DBO.TABLELOOKUP rid on  rid.TypeCode = 'AUPR' and rid.SiteCode = 'ZZZ' and brf.RULEID = rid.CODE and rid.SERVERNAME LIKE '%SCPROD1'
left join
    (select ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID, min(PENDDATE) AS MINPENDDATE, MAX(RELEASEDATE) AS MAXRELEASEDATE, min(RELEASEFLAG) AS MINRELEASEFLAG FROM WCSODS.DBO.PEND
        WHERE PENDTOID LIKE '%MAP%' AND YEAR(PENDDATE) >= YEAR(CURRENT_TIMESTAMP()) - 3
        group by ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID) AS pnd on brf.ODSCUSTOMERID = pnd.ODSCUSTOMERID and brf.CLIENTCODe = pnd.CLIENTCODE and brf.BILLSEQ = pnd.BILLSEQ and  concat('#',brf.PENDTOID) = pnd.PENDTOID and brf.RULEID = pnd.RULEID
WHERE
    1=1
    AND bl.Bill_SEQ > 0
 -- only AuditPro clients
    AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
    AND bl.BILL_SITE_CODE <> '@@@'
    AND YEAR(bl.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2)

UNION ALL

-- find lines that have an auditpro reduction but are not in either of the above two inserts
-- add the ones with the max priority

select
bl.ODS_CUSTOMER_ID,
bl.CLIENT_CODE,
bl.BILL_SEQ,
bl.LINE_SEQ,
brf.RULEID,
rid.SHORTDESC as AUDITPRO_RULE_DESCRIPTION,
rid.OLDCODE as AUDITPRO_PEND_GROUP,
brf.PENDTOID,
brf.DATERULEFIRED,
rid.PRIORITY as RulePriority,
-- 'OtherLineSeq ' match
3 as APRuleType,
pnd.MINPENDDATE as PEND_DATE,
pnd.MAXRELEASEDATE as PEND_RELEASE_DATE,
pnd.MINRELEASEFLAG as PEND_RELEASE_FLAG,
CONCAT(bl.ODS_CUSTOMER_ID,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) AS "UNIQUE_LINE",
1 AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY",
CONCAT('Data as of: ',TO_VARCHAR(bl.rundate,'mm/dd/yyyy HH12:MI AM'),' PT') AS "DATA_AS_OF"
FROM DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILLLINE bl
join WCSODS.DBO.BILLRULEFIRE brf on bl.ODS_CUSTOMER_ID = brf.ODSCUSTOMERID and bl.CLIENT_CODE = brf.CLIENTCODE and bl.BILL_SEQ = brf.BILLSEQ and brf.lineseq <> 0 and bl.LINE_SEQ <> brf.LINeSEQ
    AND (brf.PENDTOID ilike '%MAP%'
        OR brf.ruleid ilike '%MAP%')
-- RULE_ID description:
left JOIN WCSODS.DBO.TABLELOOKUP rid on  rid.TypeCode = 'AUPR' and rid.SiteCode = 'ZZZ' and brf.RULEID = rid.CODE and rid.SERVERNAME LIKE '%SCPROD1'
left join
    (select ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID, min(PENDDATE) AS MINPENDDATE, MAX(RELEASEDATE) AS MAXRELEASEDATE, min(RELEASEFLAG) AS MINRELEASEFLAG FROM WCSODS.DBO.PEND
        WHERE PENDTOID LIKE '%MAP%' AND YEAR(PENDDATE) >= YEAR(CURRENT_TIMESTAMP()) - 3
        group by ODSCUSTOMERID, CLIENTCODE, BILLSEQ, PENDTOID, RULEID)
    AS pnd on brf.ODSCUSTOMERID = pnd.ODSCUSTOMERID and brf.CLIENTCODe = pnd.CLIENTCODE and brf.BILLSEQ = pnd.BILLSEQ and  concat('#',brf.PENDTOID) = pnd.PENDTOID and brf.RULEID = pnd.RULEID
WHERE
    1=1
    AND bl.Bill_SEQ > 0
 -- only AuditPro clients
    AND BL.AUDITPRO_SITE_CODE_FLAG = 'true'
    AND bl.BILL_SITE_CODE <> '@@@'
    and ifnull(bl.AUDITPRO_REDUCTION,0.0) <> 0.0
    AND YEAR(bl.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2)
-- not in two above queries
    AND NOT EXISTS (
        SELECT 1
        FROM DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILLLINE bl2
        JOIN WCSODS.DBO.BILLRULEFIRE brf2
            ON bl2.ODS_CUSTOMER_ID = brf2.ODSCUSTOMERID
            AND bl2.CLIENT_CODE = brf2.CLIENTCODE
            AND bl2.BILL_SEQ = brf2.BILLSEQ
            AND (bl2.LINE_SEQ = brf2.LINESEQ OR brf2.LINESEQ = 0)
            AND (brf2.PENDTOID ilike '%MAP%'
                     OR brf2.ruleid ilike '%MAP%')
        WHERE
            bl.ODS_CUSTOMER_ID = bl2.ODS_CUSTOMER_ID
            AND bl.CLIENT_CODE = bl2.CLIENT_CODE
            AND bl.BILL_SEQ = bl2.BILL_SEQ
            AND bl.LINE_SEQ = bl2.LINE_SEQ
    )

QUALIFY ROW_NUMBER() OVER (
    PARTITION BY bl.ODS_CUSTOMER_ID, bl.CLIENT_CODE, bl.BILL_SEQ, bl.LINE_SEQ
    ORDER BY rid.PRIORITY
) = 1  -- Only keep highest priority rule
;


-- AUDITPRO_STG.VW_AUDITPRO_BillLevel

CREATE OR REPLACE VIEW AUDITPRO_STG.VW_AUDITPRO_BillLevel
AS

  -- Source for PowerBI AuditPro Reports that use the AUDITPRO bill table as a source

select
 AB.*
, CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then ac.bill_seq_cr else 0 end as CreditBillSeq
, CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.PROVIDER_CHARGES_CR else 0 end as PROVIDER_CHARGES_CR
, CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.BR_CR else 0 end as BR_CR
, CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.APCR else 0 end as APCR
, CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.PPO_CR else 0 end as PPO_CR
, CASE WHEN AB.ROWNUMBER_UNIQUE_BILL = 1 then AC.Total_Savings_CR else 0 end as Total_Savings_CR
, eor.AP_EOR_Codes
, eor.AP_EOR_Descriptions
from (SELECT
        CONCAT(b.BILL_SITE_CODE, '-',b.CLIENT_CODE,'-', TO_VARCHAR(b.BILL_SEQ)) AS "SA_BILL_ID"
        , CASE WHEN bp.PEND_TO_ID ILIKE ('%MAP%') THEN 1 ELSE 2 END AS "AP_PEND_ID_FIRST"
        , b.CUSTOMER_NAME
        , b.ods_customer_id
        , b.SHARED_CLIENT_NAME
        , b.CLIENT_CODE_DESCRIPTION
        , b.CLIENT_CODE
        , b.BILL_SEQ
        , b.bill_seq_org_rev
        , b.CLAIM_NO
        , TO_DATE(b.BILL_REVIEW_RECEIVED_DATE) AS "BILL_REVIEW_RECEIVED_DATE"
        , bp.PEND_TO_ID
        , bp.PEND_DATE AS "PEND_DATE"
        , bp.PEND_RELEASE_DATE AS "PEND_RELEASE_DATE"
        , bp.TAT_IN_DAYS
        , DATEDIFF(day, TO_DATE(bp.PEND_DATE), TO_DATE(b.rundate)) AS "AGE"
        , CONCAT(TO_VARCHAR(b.ods_customer_id),b.CLIENT_CODE, TO_VARCHAR(b.BILL_SEQ)) AS "UNIQUE_BILL"
        , b.CLIENT_GEO_STATE AS "CLIENT_GEO_STATE_CODE"
        , b.CLIENT_GEOSTATE_DESCRIPTION AS "CLIENT_GEO_STATE"
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
        , MIN(TO_DATE(bp.PEND_DATE)) OVER(PARTITION BY bp.PEND_TO_ID, "UNIQUE_BILL") AS "MIN_PEND_DATE"
        , MAX(TO_DATE(bp.PEND_RELEASE_DATE)) OVER(PARTITION BY bp.PEND_TO_ID, "UNIQUE_BILL") AS "MAX_PEND_RELEASE_DATE"
        , DATEDIFF(day, "MIN_PEND_DATE","MAX_PEND_RELEASE_DATE")  AS "TAT"
        , ROW_NUMBER() over (partition by bp.BILL_SITE_CODE,bp.PEND_TO_ID, "UNIQUE_BILL"
                         order by bp.BILL_SITE_CODE,bp.PEND_TO_ID, "AP_PEND_ID_FIRST", "UNIQUE_BILL") AS "ROWNUMBER_TAT"
        , CASE
            WHEN bp.RELEASE_FLAG = 'Y' AND bp.PEND_TO_ID ILIKE ('%MAP%') THEN CONCAT(TO_VARCHAR(b.ods_customer_id),bp.CLIENT_CODE, TO_VARCHAR(bp.BILL_SEQ))
            ELSE null END AS "UNIQUE_BILL_AUDITPRO_PENDED"
        ,  CASE
            WHEN b.auditpro_reduction <> 0 and b.Bill_Status in (1,8,14) THEN CONCAT(TO_VARCHAR(b.ods_customer_id),bp.CLIENT_CODE, TO_VARCHAR(bp.BILL_SEQ))
            ELSE null END AS "UNIQUE_BILL_AUDITPRO_IMPACTED"
        , CASE
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 0 THEN '<0'
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 0 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 4 THEN '0-3'
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 4 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 5 THEN '4'
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 5 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 6 THEN '5'
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 6 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 7 THEN '6'
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 7 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 11 THEN '7-10'
            ELSE '>10' END AS "PEND_AGE_CATEGORY"
        , CASE
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 0 THEN 1
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 0 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 4 THEN 2
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 4 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 5 THEN 3
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 5 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 6 THEN 4
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 6 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 7 THEN 5
            WHEN DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) >= 7 AND DATEDIFF(day, bp.PEND_DATE, b.RUNDATE) < 11 THEN 6
            ELSE 7 END AS "PEND_AGE_CATEGORY_ORDER"
        , b.bill_status
        , b.bill_status_description
        , b.re_eval_flag
        , TO_DATE(b.bill_post_date) AS "BILL_POST_DATE"
        , MONTH(b.bill_post_date) AS "BILL_POST_DATE_MONTH"
        , YEAR(b.bill_post_date) AS "BILL_POST_DATE_YEAR"
        , QUARTER(b.bill_post_date) AS "BILL_POST_DATE_QUARTER"
        , b.TYPE_OF_BILL_DESCRIPTION
        , b.BILL_REVIEW_REDUCTION
        , IFNULL(b.AUDITPRO_REDUCTION, 0.0) as AUDITPRO_REDUCTION
        , b.TOTAL_ALLOWED
        , b.PPO_REDUCTION
        , b.COMPLEX_BILL_REVIEW_REDUCTION
        , b.IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION
        , b.NURSE_CONSULTANT_REVIEW_REDUCTION
        , b.USUAL_CUSTOMARY_SPECIALTY_REDUCTION
        , CONCAT('Data as of: ',TO_VARCHAR(b.rundate,'mm/dd/yyyy HH12:MI AM'),' PT') AS "DATA_AS_OF"
        , CASE
            WHEN YEAR(b.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2) THEN 1 ELSE 0 END AS "POSTED_WINDOW_FLAG"
            , '© '||TO_VARCHAR(YEAR(CURRENT_TIMESTAMP()))||', Enlyte Group, LLC. All rights reserved.  This document contains confidential and trade secret information of Enlyte Group, LLC.  Any use, reproduction or disclosure of the information herein without the prior express written approval of Enlyte Group, LLC is prohibited.'
            AS "DISCLAIMER"
        , bp.PEND_SEQ
        , ROW_NUMBER() over (partition by bp.BILL_SITE_CODE, "UNIQUE_BILL"
                         order by bp.BILL_SITE_CODE, "AP_PEND_ID_FIRST", "UNIQUE_BILL") AS "ROWNUMBER_UNIQUE_BILL"
        , bp.RELEASE_BY_USER_ID
        , bp.RELEASE_BY_USERNAME AS "RELEASE_BY_USERNAME" -- added 1/23/2025, new column in EDW
        , b.NET_AUDITPRO_REDUCTION  as GiveBackBillAmount
        , ROW_NUMBER() OVER (partition by bp.BILL_SITE_CODE, "UNIQUE_BILL" ORDER BY "AP_PEND_ID_FIRST", bp.AUDITPRO_RULE_PRIORITY ASC, bp.pend_release_date DESC  ) as ROWNUMBER_APPHRULEID
        -- AUDITPRO_RULE_PRIORITY added 1/23/2025, new EDW column
        , CASE WHEN "AP_PEND_ID_FIRST" = 1 OR ifnull(b.NET_AUDITPRO_REDUCTION,0.0) <> 0.0
        THEN 1 ELSE 0 END AS INCLUDE_IN_REEVAL_REPORT
        , ROW_NUMBER() OVER (partition by bp.RELEASE_BY_USER_ID, bp.BILL_SITE_CODE, "UNIQUE_BILL", bp.PEND_TO_ID
                        ORDER BY bp.RELEASE_BY_USER_ID, bp.BILL_SITE_CODE, "AP_PEND_ID_FIRST", "UNIQUE_BILL", bp.PEND_TO_ID) as ROWNUMBER_REPEND
        , CASE WHEN "ROWNUMBER_REPEND" > 1 THEN 1 ELSE 0 END as RE_PENDED_COUNT
        , b.CLAIM_SYS_SUBSET
        -- prior version of re-eval savings, etc.
        , ob.BILL_REVIEW_REDUCTION as ORIGINAL_BILL_REVIEW_REDUCTION
        , ob.COMPLEX_BILL_REVIEW_REDUCTION as ORIGINAL_COMPLEX_BILL_REVIEW_REDUCTION
        , ob.NURSE_CONSULTANT_REVIEW_REDUCTION as ORIGINAL_NURSE_CONSULTANT_REVIEW_REDUCTION
        , ob.USUAL_CUSTOMARY_SPECIALTY_REDUCTION as ORIGINAL_USUAL_CUSTOMARY_SPECIALTY_REDUCTION
        , ob.IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION as ORIGINAL_IMPLANT_COMPLEX_BILL_REVIEW_REDUCTION
        , ob.PPO_REDUCTION as ORIGINAL_PPO_REDUCTION
        , IFNULL(ob.AUDITPRO_REDUCTION,0.0) as ORIGINAL_AUDITPRO_REDUCTION
        , ob.TOTAL_ALLOWED as ORIGINAL_TOTAL_ALLOWED
        , ob.BILL_REVIEW_RECEIVED_DATE as ORIGINAL_BILL_REVIEW_RECEIVED_DATE
        , ob.BILL_POST_DATE as ORIGINAL_BILL_POST_DATE
    FROM DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL_PEND_HISTORY bp
    RIGHT JOIN DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL b ON
        bp.ods_customer_id = b.ods_customer_id
        AND bp.client_code = b.client_code
        AND bp.bill_seq = b.bill_seq
    -- prior version of re-eval savings, etc.
    LEFT JOIN DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL ob ON
        ob.BILL_STATUS in (1,8)
        and ifnull(b.FIRST_BILL_IN_REEVAL_SEQUENCE, b.bill_seq) <> b.bill_seq
        and ob.ods_customer_id = b.ods_customer_id
        AND ob.client_code = b.client_code
        AND ob.bill_seq = b.BILL_SEQ_ORG_REV    -- prior version of re-eval
    WHERE
        1=1
        AND b.BILL_STATUS <> 12
        AND b.ods_customer_id NOT IN (502)
        AND b.BILL_SITE_CODE <> '@@@'
        AND (b.BILL_POST_DATE = '1900-01-01' OR YEAR(b.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2))
        AND b.BILL_SEQ > 0
        AND bp.AUDITPRO_SITE_CODE_FLAG = TRUE) AB

LEFT JOIN (select b.ods_customer_id,
                b.client_code,
                b.bill_seq as bill_seq_cr,
                b.bill_seq_org_rev,
                b.PROVIDER_CHARGES as PROVIDER_CHARGES_CR,
                b.BILL_REVIEW_REDUCTION as BR_CR, b.auditpro_reduction as APCR,
                b.PPO_Reduction as PPO_CR, ifnull(b.PROVIDER_CHARGES,0.0) - ifnull(b.TOTAL_ALLOWED,0.0) as Total_Savings_CR
          from DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL b
          WHERE b.BILL_STATUS = 12
          ) AC ON
                                        AB.ods_customer_id = AC.ods_customer_id
                                        AND AB.client_code = AC.client_code
                                        AND AB.bill_seq_org_rev = AC.bill_seq_org_rev
LEFT JOIN AUDITPRO_STG.VW_AUDITPRO_BillMessages eor on
            ab.SA_BILL_ID = eor.SA_BILL_ID
;

-- AUDITPRO_STG.VW_AUDITPRO_DocDenials

CREATE OR REPLACE VIEW AUDITPRO_STG.VW_AUDITPRO_DocDenials
AS


-- documentation denials for AuditPro initial bills in reeval seq

select
    b.CUSTOMER_NAME,
    b.SHARED_CLIENT_NAME,
    b.CLIENT_GEO_STATE,
    b.CLIENT_GEOSTATE_DESCRIPTION,
    b.TYPE_OF_BILL_DESCRIPTION,
    b.BILL_STATUS_DESCRIPTION,
    b.ODS_CUSTOMER_ID,
    b.BILL_SITE_CODE,
    b.CLIENT_CODE,
    b.BILL_SEQ as OriginalBillSeq,
    fbs.FinalBillSeq as FinalBillSeq,      -- added 1/23/2025, should be b.LAST_BILL_IN_REEVAL_SEQUENCE
    concat(b.BILL_SITE_CODE,'-',b.CLIENT_CODE,'-',TO_VARCHAR(b.BILL_SEQ)) as OriginalBillID ,     -- added 1/23/2025
    concat(b.BILL_SITE_CODE,'-',b.CLIENT_CODE,'-',TO_VARCHAR(fbs.FinalBillSeq)) as FinalBillID,     -- added 1/23/2025
    CASE WHEN ifnull(b.AUDITPRO_REDUCTION,0.0) > 25000 THEN 'Yes' ELSE 'No' END as Over25K,
    b.BILL_POST_DATE,
    b.BILL_POST_DATE as POSTDATE,
    case when fbs.FinalBillSeq is not NULL then 1 else 0 end as Reevaluated,
    case when fbs.FinalBillSeq is not NULL then 0 else 1 end as NotReevaluated,
    b.AUDITPRO_REDUCTION as OriginalAPReductions,
    rb.LastAuditProReduction,
    case when fd.BILL_SEQ is NULL then 0 else 1 end as FullDenialWith205270,
    case when fbs.FinalBillSeq is not NULL then DATEDIFF( day, b.BILL_POST_DATE, rb.LastPostDate) else 0 end as DaysToReeval,
    rb.LastPostDate,
    rb.ReevalCount,
    CASE WHEN fbs.FinalBillSeq is not NULL and b.AUDITPRO_REDUCTION - rb.LastAuditProReduction <> 0.0 then 1 else 0 end as GiveBack,
    CASE WHEN fbs.FinalBillSeq is not NULL then rb.LastAuditProReduction - b.AUDITPRO_REDUCTION else NULL end as GiveBackAmount,
    CASE WHEN fbs.FinalBillSeq is not NULL then rb.LastAuditProReduction else b.AUDITPRO_REDUCTION  end as KeptReductions,
    CONCAT('Data as of: ',TO_VARCHAR(b.rundate,'mm/dd/yyyy HH12:MI AM'),' PT') AS "DATA_AS_OF",
    '� '||TO_VARCHAR(YEAR(CURRENT_TIMESTAMP()))||', Enlyte Group, LLC. All rights reserved.  This document contains confidential and trade secret information of Enlyte Group, LLC.  Any use, reproduction or disclosure of the information herein without the prior express written approval of Enlyte Group, LLC is prohibited.'
        AS "DISCLAIMER",
    b.CLAIM_SYS_SUBSET,
    b.BILLING_PROVIDER_TIN
from
    DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL b

JOIN
    -- this query may return duplicates because clients may have more than one REDUCTION_CODE for AuditPro so selecting DISTINCT to avoid that
    (
    select
        DISTINCT
        b.ODS_CUSTOMER_ID,
        b.BILL_SITE_CODE,
        b.CLIENT_CODE,
        b.BILL_SEQ
    from
        DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL b
    -- only bills where at least one line has a "205"  or "270" ("270" added 9/2025) modifier for the AuditPro reduction
    -- distinct because AuditPro can have more than one reduction category
    JOIN (select distinct Sitecode, Code from WCSODS.DBO.TABLELOOKUP where TypeCode = 'AURC') as ap
        ON b.bill_site_code = ap.sitecode
    JOIN WCSODS.DBO.LINEMOD lm on b.ODS_CUSTOMER_ID = lm.ODSCUSTOMERID and b.CLIENT_CODE = lm.CLIENTCODE and b.BILL_SEQ = lm.BILLSEQ
                                    -- only look at auditpro reduction codes
                                    and ap.Code = lm.REDUCTIONCODE and lm.MODIFIER in ('205','270')
    where
        1=1
        AND AUDITPRO_SITE_CODE_FLAG = TRUE -- added new EDW column 1/23/2025, replaced old join to ODS LookupTable
        and b.BILL_STATUS in (1,8)
        and b.FIRST_BILL_IN_REEVAL_SEQUENCE = b.BILL_SEQ        --billseqorgrev is null in original code
        and ifnull(b.TOTAL_ALLOWED,0.0) = 0.0                   --full denial
        and ifnull(b.AUDITPRO_REDUCTION,0.0) > 0.0
        --and MODIFIER_SET
        AND b.Bill_SEQ > 0
        AND b.ods_customer_id NOT IN (502)
        AND b.BILL_SITE_CODE <> '@@@'
        AND YEAR(b.BILL_POST_DATE) >= YEAR(CURRENT_TIMESTAMP()) - 2
    )
    as fd on b.bill_site_code = fd.bill_site_code and b.client_code = fd.client_code and b.bill_seq = fd.bill_seq

-- find final re-evaluation billseq for original bill (missing in edw for original bill), -- added 1/23/2025
LEFT JOIN
    (
    select
        ODS_CUSTOMER_ID,
        BILL_SITE_CODE,
        CLIENT_CODE,
        FIRST_BILL_IN_REEVAL_SEQUENCE,
        MAX(BILL_SEQ) as  FinalBillSeq
    from
        DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL b
    where
        1=1
        and b.BILL_STATUS in (1,8)
        and b.FIRST_BILL_IN_REEVAL_SEQUENCE <> b.BILL_SEQ        --billseqorgrev is null in original code
        AND b.Bill_SEQ > 0
        AND b.BILL_SEQ < 900000000                          -- don't need historical bills
        AND b.ods_customer_id NOT IN (502)
        AND b.BILL_SITE_CODE <> '@@@'
        AND YEAR(b.BILL_POST_DATE) >= YEAR(CURRENT_TIMESTAMP()) - 2
        -- only AuditPro clients
        AND AUDITPRO_SITE_CODE_FLAG = TRUE -- added new EDW column 1/23/2025; replaced old join to ODS LookupTable
    group by
        ODS_CUSTOMER_ID,
        BILL_SITE_CODE,
        CLIENT_CODE,
        FIRST_BILL_IN_REEVAL_SEQUENCE
    ) as fbs on b.ODS_CUSTOMER_ID = fbs.ODS_CUSTOMER_ID and b.CLIENT_CODE = fbs.CLIENT_CODE and b.FIRST_BILL_IN_REEVAL_SEQUENCE = fbs.FIRST_BILL_IN_REEVAL_SEQUENCE

-- re-eval version of bill, if exists, need final ap reduction
LEFT JOIN
    (
    select
        ODS_CUSTOMER_ID,
        BILL_SITE_CODE,
        CLIENT_CODE,
        FIRST_BILL_IN_REEVAL_SEQUENCE,
        BILL_SEQ as FinalBillSeq ,
        BILL_POST_DATE as LastPostDate,
        BILL_REEVAL_COUNT as ReevalCount,
        AUDITPRO_REDUCTION as LastAuditProReduction
    from
        DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILL
    WHERE
        1=1
        AND AUDITPRO_SITE_CODE_FLAG = TRUE -- added new EDW column 1/23/2025;
        AND BILL_SEQ <> FIRST_BILL_IN_REEVAL_SEQUENCE
        AND BILL_STATUS in (1,8)
        and BILL_POST_DATE >'1/1/1900'
    )
    as rb on b.ODS_CUSTOMER_ID = rb.ODS_CUSTOMER_ID and b.CLIENT_CODE = rb.CLIENT_CODE and fbs.FinalBillSeq = rb.FinalBillSeq

where
    1=1
    and b.BILL_STATUS in (1,8)
    and b.FIRST_BILL_IN_REEVAL_SEQUENCE = b.BILL_SEQ        --billseqorgrev is null in original code
    and ifnull(b.TOTAL_ALLOWED,0.0) = 0.0                   --full denial
    and ifnull(b.AUDITPRO_REDUCTION,0.0) > 0.0
    AND b.Bill_SEQ > 0
    AND b.ods_customer_id NOT IN (502)
    AND b.BILL_SITE_CODE <> '@@@'
    AND YEAR(b.BILL_POST_DATE) >= YEAR(CURRENT_TIMESTAMP()) - 2
    -- only AuditPro clients
    AND AUDITPRO_SITE_CODE_FLAG = TRUE -- added new EDW column 1/23/2025; replaced old join to ODS LookupTable
/*
select * from ANALYSIS_SANDBOX.TEMP.VW_AUDITPRO_DocDenials
*/
;

-- AUDITPRO_STG.VW_AUDITPRO_RULES_PEND_LINE

CREATE OR REPLACE VIEW AUDITPRO_STG.VW_AUDITPRO_RULES_PEND_LINE
AS

  -- ProcCode AuditPro Report that uses the AUDITPRO_RULES table as a source

SELECT
    bl.BILL_SITE_CODE,
    bl.CLIENT_CODE,
    bl.BILL_SEQ,
    bl.LINE_SEQ,
    -- message code and description for auditpro reductions only
    blm.modifier,
    mes.MODDESCRIPTION as MODIFIER_DESCRIPTION,
    TO_DATE(bl.BILL_POST_DATE) AS BILL_POST_DATE,
    bl.FIRST_BILL_IN_REEVAL_SEQUENCE,
    bl.AUDITPRO_REDUCTION_TREND,
    bl.CLAIM_SYS_SUBSET,
    bl.CLAIM_SYSTEM_DESCRIPTION,
    CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION,0.0) <> 0.0 THEN 'Yes' ELSE 'No' END as LINE_HAS_AP_REDUCTION,
    CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION,0.0) <> 0.0 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) ELSE NULL END as UNIQUE_LINE_HAS_AP_REDUCTION,
    CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION,0.0) <> 0.0 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ)) ELSE NULL END as UNIQUE_BILL_HAS_AP_REDUCTION,
    CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION,0.0) = 0.0 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) ELSE NULL END as UNIQUE_LINE_HAS_NO_AP_REDUCTION,

    CASE WHEN bl.RE_EVAL_FLAG = 0 THEN CONCAT(TO_VARCHAR(bl.ods_customer_id),'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ)) ELSE NULL END as BILLID_NOREEVAL,  -- UNIQUE bill_id for NON REEVAL
    CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION,0.0) <> 0.0 and BL.RE_EVAL_FLAG = 1 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ)) ELSE NULL END as UNIQUE_REVAL_BILL_HAS_AP_REDUCTION,
    CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION,0.0) <> 0.0 and BL.RE_EVAL_FLAG = 0 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ)) ELSE NULL END as UNIQUE__NOREEVAL_BILL_HAS_AP_REDUCTION,
    CASE WHEN IFNULL(bl.AUDITPRO_REDUCTION,0.0) <> 0.0 and BL.RE_EVAL_FLAG = 1 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) ELSE NULL END as UNIQUE_REVAL_LINE_HAS_AP_REDUCTION,
    bl.MESSAGE_205_OR_270_FLAG,
    bl.MESSAGE_CODE_SET,
    CASE WHEN bl.AUDITPRO_REEVAL_FLAG > 0 OR bl.BILL_SEQ_ORG_REV IS NULL THEN 'Yes' ELSE 'No' END as NEW_LINE_OR_REEVAL_WITH_AP_REDUCTION,
    bl.PRIOR_MESSAGE_CODE_SET,
    ph.PENDTOID,
    ph.RULEID as AUDITPRO_RULE_ID,
    ph.AUDITPRO_RULE_DESCRIPTION,
    ph.AUDITPRO_PEND_GROUP,
    bl.RE_EVAL_FLAG,
    CASE WHEN bl.RE_EVAL_FLAG = 1 THEN 'Yes' ELSE 'No' END as RE_EVAL_FLAG_DESC,
    bl.BILL_REEVAL_COUNT,
    CASE WHEN bl.RE_EVAL_FLAG = 1 THEN CONCAT(TO_VARCHAR(bl.ods_customer_id),'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ)) ELSE NULL END as BILLID_REEVAL,  -- UNIQUE bill_id for re-eval
    CASE WHEN bl.BILL_STATUS in (1,8) and bl.TOTAL_ALLOWED = 0 THEN 'Yes' ELSE 'No' END as TOTAL_DENIAL,
    bl.AUDITPRO_REDUCTION,
    bl.AUDITPRO_REEVAL_FLAG,
    ifnull(bl.NET_AUDITPRO_REDUCTION,0.0) as NET_AUDITPRO_REDUCTION,
    ifnull(blF.AUDITPRO_REDUCTION,0.0) - ifnull(bL.AUDITPRO_REDUCTION,0.0) as AUDITPRO_GIVEBACK,
    case when bl.AUDITPRO_REEVAL_FLAG <> TRUE then bl.AUDITPRO_REDUCTION else ifnull(bl.NET_AUDITPRO_REDUCTION,0.0) end as REEVALNET_NOREEVALTOT_AUDITPROREDUCTION,
    bl.INCREMENT_VALUE, -- This is not complete logic for bill level nor line level counts (will have dups for every line and audit pro pend record)
    bl.BILL_STATUS,
    CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE, '-',TO_VARCHAR(bl.BILL_SEQ)) AS "UNIQUE_BILL",
    CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) AS "UNIQUE_LINE",
    CASE
        WHEN YEAR(bl.BILL_POST_DATE) >= (YEAR(CURRENT_TIMESTAMP()) - 2) THEN 1 ELSE 0 END AS "POSTED_WINDOW_FLAG",
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
        END AS REEVAL_APTREND,
    CASE WHEN bl.RE_EVAL_FLAG = 1 AND IFNULL(bl.NET_AUDITPRO_REDUCTION,0.0) <> 0.0 THEN CONCAT(bl.BILL_SITE_CODE,'-',bl.CLIENT_CODE,'-', TO_VARCHAR(bl.BILL_SEQ),'-', TO_VARCHAR(bl.LINE_SEQ)) ELSE NULL END as         UNIQUE_LINE_RE_EVAL_ADD_PAYMENT,
    CASE WHEN bl.RE_EVAL_FLAG = 1 THEN IFNULL(blf.AUDITPRO_REDUCTION,0.0) ELSE IFNULL(bl.AUDITPRO_REDUCTION,0.0) END AS AUDITPRO_ORIG_REDUCTIONS, -- first billseq ap reduction
    ROW_NUMBER() over (partition by "UNIQUE_LINE"
                         order by bl.BILL_SITE_CODE, ph.RULEPRIORITY, "UNIQUE_LINE") AS "ROWNUMBER_UNIQUE_LINE_RULEPRIORITY",
    ROW_NUMBER() over (partition by "UNIQUE_BILL"
                         order by bl.BILL_SITE_CODE, ph.RULEPRIORITY, "UNIQUE_BILL") AS "ROWNUMBER_UNIQUE_BILL_RULEPRIORITY",
    ph.RULEPRIORITY AS RULE_PRIORITY,
    bl.PROVIDER_CHARGES
FROM DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILLLINE bl
-- first version of each re-eval bill line - blf
left JOIN DATAWAREHOUSE.WCS.CLAIM_DETAIL_BILLLINE blf ON blf.ODS_CUSTOMER_ID = bl.ODS_CUSTOMER_ID and blf.CLIENT_CODE = bl.CLIENT_CODE and blf.BILL_SEQ = bl.FIRST_BILL_IN_REEVAL_SEQUENCE and blf.LINE_SEQ = bl.LINE_SEQ
JOIN WCSODS.ADM.CUSTOMER ac on ac.SITE_CODE = bl.BILL_SITE_CODE AND ac.CUSTOMER_ID = bl.ODS_CUSTOMER_ID
    -- EITHER PENDED FOR AUDITPRO TEAM OR HAS AN AUDITPRO REDUCTION
join  AUDITPRO_STG.AUDITPRO_RULES ph ON bl.ODS_CUSTOMER_ID = ph.ods_customer_id and bl.CLIENT_CODE = ph.client_code and bl.BILL_SEQ = ph.bill_seq and bl.line_seq = ph.line_seq
  -- only AuditPro Reduction related message codes
join WCSODS.DBO.TABLELOOKUP ap on bl.BILL_SITE_CODE = ap.SITECODE
        and ap.TypeCode = 'AURC'
left join WCSODS.DBO.LINEMOD blm
    on bl.ODS_CUSTOMER_ID = blm.ODSCUSTOMERID
        and bl.CLIENT_CODE = blm.CLIENTCODE
        and bl.BILL_SEQ = blm.BILLSEQ
        and bl.line_seq = blm.LINESEQ
        -- and bl.REDUCTIONCODE <> 0 -- not needed due to below condition
        and ap.CODE = blm.REDUCTIONCODE  -- only include AuditPro related messages
-- jurisdiction and sitecode specific
left join WCSODS.DBO.MODIFIER mes
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
;

-- Create task and resume it to refresh AUDITPRO tables daily at 3:05am PT
CREATE OR REPLACE TASK AUDITPRO.REFRESH_AUDITPRO_TABLES
	warehouse=WH_TAG_L
	schedule='USING CRON 5 3 * * * America/Los_Angeles'
	USER_TASK_TIMEOUT_MS=10800000
	AS CALL ADM.CREATE_TABLES_FROM_VIEWS('AUDITPRO_STG', 'AUDITPRO');

ALTER TASK AUDITPRO.REFRESH_AUDITPRO_TABLES RESUME;
