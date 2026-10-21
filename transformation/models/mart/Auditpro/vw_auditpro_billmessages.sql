{{ config(materialized='table',
    tags = ['auditpro']
) }}

WITH stg_dwwcs__claim_detail_bill AS (SELECT *
                                      FROM {{ ref('stg_dwwcs__claim_detail_bill') }}),

     stg_wcsodsdbo__tablelookup AS (SELECT *
                                    FROM {{ ref('stg_wcsodsdbo__tablelookup') }}),

     stg_wcsodsdbo__linemod AS (SELECT *
                                FROM {{ ref('stg_wcsodsdbo__linemod') }}),

     stg_wcsodsadm__customer AS (SELECT *
                                 FROM {{ ref('stg_wcsodsadm__customer') }}),

     stg_wcsodsdbo__modifier AS (SELECT *
                                 FROM {{ ref('stg_wcsodsdbo__modifier') }}),

     base AS (SELECT DISTINCT CONCAT(b.bill_site_code, '-', b.client_code, '-', TO_VARCHAR(b.bill_seq)) AS sa_bill_id,
                              b.ods_customer_id,
                              bl.modifier                                                               AS eorcode,
                              mes.moddescription                                                        AS eordescription
              FROM stg_dwwcs__claim_detail_bill b
                       JOIN stg_wcsodsdbo__tablelookup ap
                            ON b.bill_site_code = ap.sitecode
                                AND ap.typecode = 'AURC'
                       JOIN stg_wcsodsdbo__linemod bl
                            ON b.ods_customer_id = bl.odscustomerid
                                AND b.client_code = bl.clientcode
                                AND b.bill_seq = bl.billseq
                                AND ap.code = bl.reductioncode
                       JOIN stg_wcsodsadm__customer c
                            ON b.ods_customer_id = c.customer_id
                       LEFT JOIN stg_wcsodsdbo__modifier mes
                                 ON bl.modifier = mes.code
                                     AND c.server_name = mes.servername
                                     AND bl.modsubset = mes.jurisdiction
                                     AND bl.modsitecode = mes.sitecode
              WHERE 1 = 1
                        AND b.bill_status <> 12
                        AND b.ods_customer_id NOT IN (502)
                        AND b.bill_site_code <> '@@@'
                        AND YEAR (b.bill_post_date) >= (YEAR (CURRENT_TIMESTAMP ()) - 2)
    AND b.bill_seq > 0
    AND b.auditpro_site_code_flag = TRUE
    ), final_output AS (
SELECT
    sa_bill_id, ods_customer_id, LISTAGG(eorcode, ' ; ') WITHIN
GROUP (ORDER BY eorcode) AS ap_eor_codes,
    LISTAGG(eordescription, ' ; ') WITHIN
GROUP (ORDER BY eorcode) AS ap_eor_descriptions
FROM base
GROUP BY sa_bill_id, ods_customer_id
    )

SELECT *
FROM final_output
