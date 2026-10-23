{{
    config(
        materialized='table'
    )
}}

WITH
-- Import CTEs
stg_irmsods__clnc_clm_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__clnc_clm_stgng_que') }}
),

stg_irmsods__irms_claim AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_claim') }}
),

stg_irmsods__clm_amnt AS (
    SELECT * FROM {{ ref('stg_irmsods__clm_amnt') }}
),

slvr_reporting_ipc_view AS (
    SELECT * FROM {{ ref('slvr_reporting_ipc_view') }}
),

stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_irmsods__lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__ns_cc_lctn_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_cc_lctn_mpng') }}
),

stg_irmsods__ns_lctn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_lctn_r') }}
),

stg_irmsods__ns_dept_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_dept_mpng') }}
),

stg_irmsods__ns_dept_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_dept_r') }}
),

stg_irmsods__ns_class_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__process AS (
    SELECT * FROM {{ ref('stg_irmsods__process') }}
),
-- Logical CTEs
-- Final CTE
final AS (
	SELECT
		DISTINCT
		{{ dbt_utils.generate_surrogate_key(['CLSQ.SRC_CLM_KEY', 'CLSQ.RUN_ID', 'CLSQ.SRC_CLM_SEQ_NUM', 'T.TRNS_ID']) }} AS ID,
		CLSQ.INV_NUM,
		T.TRNS_ID transaction_id,
		CLSQ.ADJSTR_NM,
		NULL AS ADJSTR_EMAIL,
		NULL AS ADJSTR_FAX,
		NULL AS ADJSTR_PHONE,
		CLSQ.CLAIMANT_NM AS CLAIMANT_NAME,
		CLSQ.CLAIM_NUM AS CLAIM_NUMBER,
		CLSQ.employer_grp AS EMPLOYER,
		CLSQ.INJ_DT AS INJURY_DATE,
		CLSQ.REFERRAL_DT AS REFERRAL_DATE,
		CLSQ.BILL_FROM_DT AS PROVIDER_SERVICE_DATE_FROM,
		CLSQ.BILL_TO_DT AS PROVIDER_SERVICE_DATE_TO,
		CLSQ.REFERRAL_TYPE,
		CLSQ.BRAND_NM AS LINE_OF_INSURANCE,
		CLSQ.CLAIMANT_BENEFIT_ST AS CLAIMANT_BENEFIT_STATE,
		CLSQ.CUST_CLIENT_NUM AS CUSTOMER_CLIENT_NUMBER,
		CLSQ.CUST_CLIENT_SUBCLNT_NUM AS CUSTOMER_SUBCLIENT_NUMBER,
		CLSQ.CUST_CLIENT_LOC_NUM AS CUSTOMER_CLIENT_LOC_NUMBER,
		CLSQ.CUST_CLIENT_OTHLOC_NUM AS CUSTOMER_CLIENT_OTHER_LOC_NUMBER,
		CLSQ.CASE_TYPE,
		NULL PROVIDER_BILL_AMOUNT,
		NULL AS RECOMMENDED_ALLOWANCE,
		NULL AS BR_FEE,
		NULL AS PPO_FEE,
		CLSQ.SRC_CLM_SEQ_NUM AS IRMS_RCVBL_SEQ_NUM,
		CLSQ.NUM_OF_LINES AS INVOICE_LINE_COUNT,
		CLSQ.RECORD_TYPE,
		CLSQ.GL_PRODUCT,
		CLSQ.RUN_ID,
		CLSQ.ACCT_LOCATION,
		CLSQ.SRC_CLM_KEY,
		CLSQ.SHIP_TO_NM,
		CLSQ.WHLSL_RTL_FLG,
		CLSQ.INV_AMNT_WHLSL,
		CLSQ.CSQ_STATUS_CD,
		CLSQ.SRC_PRODT_CD,
		CLSQ.GL_LOCATION,
		NULL AS PYMT_STATUS_CD,
		NCR.NS_CLASS_DESC,
		NDR.NS_DEPT_DESC,
		NLR.NS_LCTN_DESC,
		PRO.PRCS_DESC,
		LRM.REVNU_TYP_CD ,
		P.PRODT_DESC,
		CLSQ.INV_DT,
		CLSQ.ACCTG_DT,
		CLSQ.ORIG_INV_NUM
	FROM
		stg_irmsods__clnc_clm_stgng_que CLSQ
	JOIN stg_irmsods__irms_claim c ON
		CLSQ.src_clm_key = c.src_clm_key
	JOIN  stg_irmsods__clm_amnt  ca ON
		ca.clm_id = c.clm_id
		AND CLSQ.src_clm_seq_num = ca.src_clm_seq_num
	JOIN slvr_reporting_ipc_view T ON nvl(T.XREF_TRNS_ID ,t.TRNS_ID) = ca.trns_id
	LEFT JOIN stg_irmsods__product P ON
		T.ORIGINAL_PRODUCT_ID = P.IRMS_PRODT_ID
	LEFT JOIN stg_irmsods__lob_revnu_mpng LRM ON P.LOB_REVNU_ID =LRM.LOB_REVNU_ID
	LEFT JOIN stg_irmsods__ns_cc_lctn_mpng NCLM ON
		SUBSTR(clsq.CUST_CLIENT_LOC_NUM,-4) = NCLM.COST_CNTR
	LEFT JOIN stg_irmsods__ns_lctn_r NLR ON
		NLR.NS_LCTN_CD = NCLM.NS_LCTN_CD
	LEFT JOIN stg_irmsods__ns_dept_mpng NDM ON
		NDM.NS_GL_ACCT_CD=P.NS_GL_ACCT_CD
	LEFT JOIN stg_irmsods__ns_dept_r NDR ON
		NDR.NS_DEPT_CD=NDM.NS_DEPT_CD
	LEFT JOIN stg_irmsods__ns_class_r NCR ON
		CLSQ.GL_PRODUCT=NCR.NS_CLASS_CD
	LEFT JOIN stg_irmsods__run_log RL ON
		RL.RUN_ID = CLSQ.RUN_ID
	LEFT JOIN stg_irmsods__process PRO ON
		PRO.PRCS_ID = RL.PRCS_ID
)

SELECT * FROM final