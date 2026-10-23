{{
    config(
        materialized='incremental',
        unique_key='CREDITS_ID'
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

credits AS (
    SELECT * FROM {{ ref('credits') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__process AS (
    SELECT * FROM {{ ref('stg_irmsods__process') }}
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
	(IT.TRNS_TYP_CD ='A' OR (IT.TRNS_TYP_CD ='C' AND IT.TRNS_AMNT < 0))
	--and substring(IT.MNTH_OF_SVC,1,4)::int>2021
	GROUP BY it.trns_id
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
	(IT.TRNS_TYP_CD ='A' OR (IT.TRNS_TYP_CD ='C' AND IT.TRNS_AMNT<0))
	GROUP BY it.trns_id
),

stg_irmsods__irms_transaction__filtered AS (
    SELECT *
	FROM stg_irmsods__irms_transaction IT
	WHERE (IT.TRNS_TYP_CD ='A' OR (IT.TRNS_TYP_CD ='C' AND IT.TRNS_AMNT < 0))
),


-- Final CTE
final AS (
	SELECT {{ dbt_utils.generate_surrogate_key(['P.ID']) }} AS ID,
		P.ID AS CREDITS_ID,
		PC.PRCS_ID,
		SEC.SEC_USR_ID,
		PC.PRCS_DESC,
		SEC.SEC_USR_NM,
		SEC.USR_LOGIN_NM_CD,
		IR.PYMT_STATUS_CD,
		rev.REVNU_TYP_CD,
		IT.BKNG_STATUS_CD,
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
		Pro.RSN_TYP_CD,
		IR.BAL,
		acgi.APPLCTN_COMNT_DESC_INT AS COMMENTS_INT
	FROM
		stg_irmsods__irms_transaction__filtered IT
		LEFT JOIN APP_CMNT_GRP_EXT ACGE ON ACGE.TRNS_ID=IT.TRNS_ID
		LEFT JOIN APP_CMNT_GRP_INT ACGI ON ACGI.TRNS_ID=IT.TRNS_ID
		LEFT JOIN credits P ON P.ORIGINAL_CREDIT_ID=IT.TRNS_ID
		LEFT JOIN stg_irmsods__run_log Rl ON IT.RUN_ID =Rl.RUN_ID
		LEFT JOIN stg_irmsods__sec_usr SEC ON SEC.SEC_USR_ID=Rl.SEC_USR_ID
		LEFT JOIN stg_irmsods__process PC ON PC.PRCS_ID =Rl.PRCS_ID
	LEFT JOIN stg_irmsods__product pro ON
		IT.irms_prodt_id = pro.irms_prodt_id
	LEFT JOIN stg_irmsods__irms_receivable ir ON
		IT.rcvbl_id = ir.rcvbl_id
	LEFT JOIN stg_irmsods__ns_cc_lctn_mpng NCLM ON
		Pro.COST_CNTR = NCLM.COST_CNTR
	LEFT JOIN stg_irmsods__ns_lctn_r NLR ON
		NLR.NS_LCTN_CD = NCLM.NS_LCTN_CD
	LEFT JOIN stg_irmsods__ns_dept_mpng NDM ON NDM.NS_GL_ACCT_CD=Pro.NS_GL_ACCT_CD
	LEFT JOIN stg_irmsods__ns_dept_r NDR ON NDR.NS_DEPT_CD=NDM.NS_DEPT_CD
	LEFT JOIN stg_irmsods__ns_class_r NCR ON Pro.NS_CLASS_CD = NCR.NS_CLASS_CD
	LEFT JOIN stg_irmsods__val_typ_bllng_calctn_mpng V ON
		pro.VAL_TYP_BLLNG_CALCTN_ID = V.VAL_TYP_BLLNG_CALCTN_ID
	LEFT JOIN stg_irmsods__lob_revnu_mpng rev ON
		pro.lob_revnu_id = rev.lob_revnu_id
	LEFT JOIN stg_irmsods__irms_trns_adjmt ita ON
		it.trns_id = ita.trns_id
	LEFT JOIN stg_irmsods__adjmt_rsn_r ARR ON
		ARR.ADJMT_RSN_CD = ita.ADJMT_RSN_CD
)

SELECT * FROM final
WHERE CREDITS_ID IS NOT NULL
