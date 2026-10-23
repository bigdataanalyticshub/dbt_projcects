{{ config(
    materialized = 'table',
    tags = ['cmo_prod', 'weekly_refresh']
) }}

WITH stg_nco AS (
    SELECT * FROM {{ ref('stg_dwctshex__nco_test_mapping') }}
),

stg_invoice AS (
    SELECT * FROM {{ ref('stg_psdwanalytics_ps_invoice_item') }}
),

stg_client AS (
    SELECT * FROM {{ ref('stg_psdwanalyticsods_tblclient') }}
)

SELECT
    COALESCE(nco.sp_name, 'N/A') AS sp_name,
    COALESCE(nco.salesforce_name, 'N/A') AS salesforce_name,
    nco.salesforce_id,
    nco.sf_link_id,
    ph.CLIENTEXTERNALID AS account_id,
    ph.REPORTINGCLIENTNAME AS account_name,
    ph.claimcoveragetypecode AS LOB,
    ph.INVOICEDATE,
    LPAD(MONTH(ph.INVOICEDATE), 2, '0') || YEAR(ph.INVOICEDATE) AS month_year,
    TO_CHAR(ph.INVOICEDATE, 'DD-MM-YYYY') AS invoice_date_formatted,
    COUNT(*) AS monthly_prescription_volume,
    SUM(ph.TOTALBILLABLE) AS monthly_billable_amount
FROM stg_invoice ph
LEFT JOIN stg_client cl ON ph.clientexternalid = cl.id
LEFT JOIN stg_nco nco
    ON nco.norm_other_names = COALESCE(REPLACE(LOWER(cl.clientname), ' ', ''), REPLACE(LOWER(ph.CLIENTNAME), ' ', ''))
    AND nco.rn_norm = 1
WHERE ph.invoicedate >= DATEADD(MONTH, -14, CURRENT_DATE)
  AND ph.INVOICEDATE IS NOT NULL
  AND ph.claimcoveragetypecode = 'WC'
GROUP BY nco.sp_name, nco.salesforce_name, nco.salesforce_id, nco.sf_link_id,
         ph.CLIENTEXTERNALID, ph.REPORTINGCLIENTNAME, ph.claimcoveragetypecode, ph.INVOICEDATE
ORDER BY ph.INVOICEDATE DESC, monthly_billable_amount DESC
