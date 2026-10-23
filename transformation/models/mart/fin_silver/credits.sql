{{
    config(
        materialized='incremental',
        unique_key='ORIGINAL_CREDIT_ID'
    )
}}

WITH
-- Import CTEs
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

bill_to_accounts AS (
    SELECT * FROM {{ ref('bill_to_accounts') }}
),

stg_irmsods__irms_trns_adjmt AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_trns_adjmt') }}
),

stg_irmsods__adjmt_rsn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__adjmt_rsn_r') }}
),

stg_irmsods__irms_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
),

line_of_business AS (
    SELECT * FROM {{ ref('line_of_business') }}
),

accounting_periods AS (
    SELECT * FROM {{ ref('accounting_periods') }}
),

products AS (
    SELECT * FROM {{ ref('products') }}
),

stg_irmsods__lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__clm_amnt AS (
    SELECT * FROM {{ ref('stg_irmsods__clm_amnt') }}
),

-- Logical CTEs

stg_irmsods__irms_transaction__filtered AS (
    SELECT *
	FROM stg_irmsods__irms_transaction IT
	WHERE (IT.TRNS_TYP_CD ='A' OR (IT.TRNS_TYP_CD ='C' AND IT.TRNS_AMNT < 0))
),

-- Final CTE
final AS (
	SELECT {{ dbt_utils.generate_surrogate_key(['IT.TRNS_ID']) }} AS ID,
		IT.TRNS_ID AS ORIGINAL_CREDIT_ID,
		BA.ID AS BILL_TO_BUS_ENT_ID,
		BLLNG_ID,
		GLBL_MPNG_CD AS INVOICE_NO,
		P.ID AS PRODUCT_ID,
		NULL ACCOUNT_ID,
		IT.RUN_ID,
		AP.ID AS ACCOUNTING_PERIOD_ID,
		MNTH_OF_SVC,
		IT.RCVBL_ID,
		IT.TRNS_AMNT AS AMOUNT,
		LOB.ID LOB_ID,
		revnu_typ_cd,
		ta.adjmt_rsn_cd,
		ar.ADJMT_RSN_DESC,
		SRC_SYST_CD,
		TRNS_TYP_CD,
		ACTV_DT,
		IT.ACCTG_DT,
		R.AGNG_DT,
		NULL AS DATE_LOAD_ID,
		NULL AS DATE,
		IT.BK_TO_BUS_ENT_ID AS AE,
		IT.PPA_FLG AS PPA_FLAG,
		IT.XREF_TRNS_ID,
		IT.GLBL_MPNG_TYP_CD,
		CA.SRC_CLM_SEQ_NUM
	FROM
		stg_irmsods__irms_transaction__filtered IT
		LEFT JOIN bill_to_accounts BA ON IT.BILL_TO_BUS_ENT_ID=BA.BUS_ENT_ID
		LEFT JOIN stg_irmsods__irms_trns_adjmt ta on IT.trns_id = ta.trns_id
		LEFT JOIN stg_irmsods__adjmt_rsn_r ar on ar.ADJMT_RSN_CD=ta.ADJMT_RSN_CD
		LEFT JOIN stg_irmsods__irms_receivable R ON R.RCVBL_ID=IT.RCVBL_ID
		LEFT JOIN line_of_business LOB ON LOB.LIN_OF_BUS_CD = R.LIN_OF_BUS_CD
		LEFT JOIN accounting_periods AP ON IT.ACCTG_PERIOD_ID=AP.ORIGINAL_ACCOUNTING_ID
		LEFT JOIN products P ON P.ORIGINAL_PRODUCT_ID=IT.IRMS_PRODT_ID
		LEFT JOIN stg_irmsods__lob_revnu_mpng rev on p.lob_revnu_id = rev.lob_revnu_id
		LEFT JOIN stg_irmsods__clm_amnt CA ON NVL(IT.XREF_TRNS_ID ,IT.TRNS_ID) = CA.TRNS_ID
)

SELECT * FROM final
WHERE ORIGINAL_CREDIT_ID IS NOT NULL