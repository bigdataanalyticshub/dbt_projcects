{{
    config(
        materialized='incremental',
        unique_key='PAYMENTS_ID'
    )
}}

WITH

-- Import CTEs
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__remittance AS (
    SELECT * FROM {{ ref('stg_irmsods__remittance') }}
),

stg_irmsods__deposit AS (
    SELECT * FROM {{ ref('stg_irmsods__deposit') }}
),

payments AS (
    SELECT * FROM {{ ref('payments') }}
),

-- Logical CTEs
stg_irmsods__irms_transaction__filtered AS (
    SELECT *
	FROM stg_irmsods__irms_transaction IT
	WHERE IT.TRNS_TYP_CD ='R'
),

-- Final CTE
final AS (
	SELECT  {{ dbt_utils.generate_surrogate_key(['P.ID']) }} AS ID,
		P.ID AS PAYMENTS_ID,
		R.DPST_ID,
		R.CHECK_NUM,
		R.CHECK_DT,
		D.DPST_DT,
		D.DPST_AMNT,
		D.DPST_DESC,
		D.DPST_BALNC,
		D.DPST_FINLZD_FLG,
		D.BANK_ACCT_NUM,
		D.BANK_ID
	FROM
		stg_irmsods__irms_transaction__filtered IT
		LEFT JOIN stg_irmsods__remittance R ON R.TRNS_ID=IT.TRNS_ID
		LEFT JOIN stg_irmsods__deposit D ON D.DPST_ID=R.DPST_ID
		LEFT JOIN payments P ON P.ORIGINAL_PAYMENT_ID=IT.TRNS_ID

)

SELECT * FROM final
WHERE PAYMENTS_ID IS NOT NULL
