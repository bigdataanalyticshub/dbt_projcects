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

stg_irmsods__trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
),

payments AS (
    SELECT * FROM {{ ref('payments') }}
),

stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_irmsods__irms_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
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

stg_irmsods__val_typ_bllng_calctn_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__val_typ_bllng_calctn_mpng') }}
),

stg_irmsods__lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__irms_trns_adjmt AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_trns_adjmt') }}
),

stg_irmsods__adjmt_rsn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__adjmt_rsn_r') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__remittance AS (
    SELECT * FROM {{ ref('stg_irmsods__remittance') }}
),

stg_irmsods__deposit AS (
    SELECT * FROM {{ ref('stg_irmsods__deposit') }}
),

stg_irmsods__process AS (
    SELECT * FROM {{ ref('stg_irmsods__process') }}
),

stg_irmsods__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

-- Logical CTEs
APP_CMNT_GRP_EXT AS (SELECT
	IT.TRNS_ID,
	LISTAGG(APPLCTN_COMNT_DESC) APPLCTN_COMNT_DESC_EXT
FROM
	stg_irmsods__irms_transaction IT
LEFT JOIN stg_irmsods__trns_comnt tc ON
	it.trns_id = tc.trns_id and tc.INTRNL_EXTRNL_FLG='E'
LEFT JOIN stg_irmsods__applctn_comnt ac ON
	tc.applctn_comnt_id = ac.applctn_comnt_id
WHERE
	IT.TRNS_TYP_CD = 'R'
	--AND substring(IT.MNTH_OF_SVC, 1, 4)::int>2021
	GROUP BY IT.TRNS_ID
),

 APP_CMNT_GRP_INT AS (SELECT
	IT.TRNS_ID,
	LISTAGG(APPLCTN_COMNT_DESC) APPLCTN_COMNT_DESC_INT
FROM
		stg_irmsods__irms_transaction IT
LEFT JOIN stg_irmsods__trns_comnt tc ON
	it.trns_id = tc.trns_id and tc.INTRNL_EXTRNL_FLG='I'
LEFT JOIN stg_irmsods__applctn_comnt ac ON
	tc.applctn_comnt_id = ac.applctn_comnt_id
WHERE
	IT.TRNS_TYP_CD = 'R'
	GROUP BY IT.TRNS_ID
),

stg_irmsods__irms_transaction__filtered AS (
    SELECT *
	FROM stg_irmsods__irms_transaction TTI
	WHERE TTI.TRNS_TYP_CD = 'R'
),

-- Final CTE
final AS (
	SELECT  {{ dbt_utils.generate_surrogate_key(['Pyt.ID']) }} AS ID,
		Pyt.ID AS PAYMENTS_ID,
		pr.PRCS_ID,
		su.SEC_USR_ID,
		pr.PRCS_DESC,
		su.SEC_USR_NM,
		su.USR_LOGIN_NM_CD,
		IR.PYMT_STATUS_CD,
		rev.REVNU_TYP_CD,
		rld.STRT_DT,
		TTI.BKNG_STATUS_CD,
		acge.APPLCTN_COMNT_DESC_EXT AS APPLCTN_COMNT_DESC,
		V.BLLNG_CALCTN_BASIS_CD,
		V.VAL_TYP_CD,
		arr.ADJMT_RSN_DESC,
		ita.ADJMT_RSN_CD,
		nlr.NS_LCTN_DESC,
		rl.STRT_DT prcs_dt,
		NCR.NS_CLASS_DESC,
		NDM.NS_DEPT_CD,
		NDR.NS_DEPT_DESC,
		NLR.NS_LCTN_CD,
		P.RSN_TYP_CD,
		IR.BAL,
		acgi.APPLCTN_COMNT_DESC_INT AS COMMENTS_INT
	FROM
		stg_irmsods__irms_transaction__filtered TTI
	LEFT JOIN APP_CMNT_GRP_EXT ACGE ON ACGE.TRNS_ID=TTI.TRNS_ID
	LEFT JOIN APP_CMNT_GRP_INT ACGI ON ACGI.TRNS_ID=TTI.TRNS_ID
	LEFT JOIN payments Pyt ON
		Pyt.ORIGINAL_PAYMENT_ID = TTI.TRNS_ID
	LEFT JOIN stg_irmsods__product  p ON
		TTI.irms_prodt_id = p.irms_prodt_id
	LEFT JOIN stg_irmsods__irms_receivable ir ON
		TTI.rcvbl_id = ir.rcvbl_id
	LEFT JOIN stg_irmsods__ns_cc_lctn_mpng NCLM ON
		P.COST_CNTR = NCLM.COST_CNTR
	LEFT JOIN stg_irmsods__ns_lctn_r NLR ON
		NLR.NS_LCTN_CD = NCLM.NS_LCTN_CD
	LEFT JOIN stg_irmsods__ns_dept_mpng NDM ON NDM.NS_GL_ACCT_CD=P.NS_GL_ACCT_CD
	LEFT JOIN stg_irmsods__ns_dept_r NDR ON NDR.NS_DEPT_CD=NDM.NS_DEPT_CD
	LEFT JOIN stg_irmsods__ns_class_r NCR ON P.NS_CLASS_CD = NCR.NS_CLASS_CD
	LEFT JOIN stg_irmsods__val_typ_bllng_calctn_mpng V ON
		p.VAL_TYP_BLLNG_CALCTN_ID = V.VAL_TYP_BLLNG_CALCTN_ID
	LEFT JOIN stg_irmsods__lob_revnu_mpng rev ON
		p.lob_revnu_id = rev.lob_revnu_id
	LEFT JOIN stg_irmsods__irms_trns_adjmt ita ON
		TTI.trns_id = ita.trns_id
	LEFT JOIN stg_irmsods__adjmt_rsn_r ARR ON
		ARR.ADJMT_RSN_CD = ita.ADJMT_RSN_CD
	LEFT JOIN  stg_irmsods__run_log rl ON
		TTI.run_id = rl.run_id
	LEFT JOIN stg_irmsods__remittance R ON
		R.TRNS_ID = TTI.TRNS_ID
	LEFT JOIN stg_irmsods__deposit D ON
		D.DPST_ID = R.DPST_ID
	LEFT JOIN stg_irmsods__run_log rld ON
		D.RUN_ID = rld.run_id
	LEFT JOIN stg_irmsods__process pr ON
		rl.prcs_id = pr.prcs_id
	LEFT JOIN stg_irmsods__sec_usr su ON
		rl.sec_usr_id = su.sec_usr_id
)

SELECT * FROM final
WHERE PAYMENTS_ID IS NOT NULL