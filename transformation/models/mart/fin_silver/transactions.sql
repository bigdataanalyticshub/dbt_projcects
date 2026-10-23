{{
    config(
        materialized='incremental',
        unique_key='ORIGINAL_TRANSACTION_ID'
    )
}}

WITH
-- Import CTEs
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

accounting_periods AS (
    SELECT * FROM {{ ref('accounting_periods') }}
),

bill_to_accounts AS (
    SELECT * FROM {{ ref('bill_to_accounts') }}
),

stg_irmsods__clm_amnt AS (
    SELECT * FROM {{ ref('stg_irmsods__clm_amnt') }}
),

-- Logical CTEs
stg_irmsods__irms_transaction__filtered AS (
    SELECT *
	FROM stg_irmsods__irms_transaction TTI
	WHERE (TTI.TRNS_TYP_CD in ('M','E','S') OR (TTI.TRNS_TYP_CD ='C' and TTI.TRNS_AMNT>=0))
),


-- Final CTE
final AS (
	select {{ dbt_utils.generate_surrogate_key(['TTI.TRNS_ID']) }} AS ID,
		TTI.TRNS_ID AS ORIGINAL_TRANSACTION_ID,
		BTA.ID AS BILL_TO_BUS_ENT_ID,
		TTI.BLLNG_ID,
		TTI.GLBL_MPNG_CD AS INVOICE_NO,
		NULL AS ACCOUNT_ID,
		TTI.RUN_ID,
		AP.ID AS ACCOUNTING_PERIOD_ID,
		TTI.MNTH_OF_SVC,
		TTI.SRC_SYST_CD,
		TTI.TRNS_TYP_CD,
		TTI.ACTV_DT,
		TTI.ACCTG_DT,
		DATEADD(MONTH,1,TTI.ACCTG_DT) AS DUE_DT,
		NULL AS DATE_LOAD_ID,
		NULL AS DATE,
		TTI.BK_TO_BUS_ENT_ID AS AE,
		TTI.XREF_TRNS_ID,
		TTI.GLBL_MPNG_TYP_CD,
		CA.SRC_CLM_SEQ_NUM
	from
		stg_irmsods__irms_transaction__filtered TTI
		LEFT JOIN accounting_periods AP ON TTI.ACCTG_PERIOD_ID=AP.ORIGINAL_ACCOUNTING_ID
		LEFT JOIN bill_to_accounts BTA ON TTI.BILL_TO_BUS_ENT_ID=BTA.BUS_ENT_ID
    	LEFT JOIN stg_irmsods__clm_amnt CA ON NVL(TTI.XREF_TRNS_ID ,TTI.TRNS_ID) = CA.TRNS_ID
)

SELECT * FROM final
