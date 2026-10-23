{{
    config(
        materialized='incremental',
        unique_key='TRANSACTION_ID'
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

transactions AS (
    SELECT * FROM {{ ref('transactions') }}
),

products AS (
    SELECT * FROM {{ ref('products') }}
),

-- Logical CTEs
stg_irmsods__irms_transaction__filtered AS (
    SELECT *
	FROM stg_irmsods__irms_transaction IT
	WHERE (IT.TRNS_TYP_CD in ('M','E','S') OR (IT.TRNS_TYP_CD ='C' and IT.TRNS_AMNT>=0))
),

-- Final CTE
final AS (
	SELECT {{ dbt_utils.generate_surrogate_key(['T.ID']) }} AS ID,
		T.ID AS TRANSACTION_ID,
		NULL AS GL_ACCOUNT_ID,
		P.ID AS PRODUCT_ID,
		1 AS QUANTITY,
		IT.RCVBL_ID AS RECEIVABLE_CODE,
		IT.TRNS_AMNT AS UNIT_PRICE,
		1*IT.TRNS_AMNT AS SUBTOTAL,
		1 AS TAX,
		TAX+SUBTOTAL AS TOTAL
	FROM
		stg_irmsods__irms_transaction__filtered IT
		LEFT JOIN accounting_periods AP ON IT.ACCTG_PERIOD_ID=AP.ORIGINAL_ACCOUNTING_ID
		LEFT JOIN transactions T ON T.ORIGINAL_TRANSACTION_ID=IT.TRNS_ID
		LEFT JOIN products P ON P.ORIGINAL_PRODUCT_ID=IT.IRMS_PRODT_ID
)

SELECT * FROM final

