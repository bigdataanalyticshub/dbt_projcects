{{
    config(
        materialized='table'
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

transactions AS (
    SELECT * FROM {{ ref('transactions') }}
),

stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_irmsods__irms_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
),

line_of_business AS (
    SELECT * FROM {{ ref('line_of_business') }}
),

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
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
	it.trns_id = tc.trns_id and tc.INTRNL_EXTRNL_FLG = 'E'
LEFT JOIN stg_irmsods__applctn_comnt ac ON
	tc.applctn_comnt_id = ac.applctn_comnt_id
WHERE
	(IT.TRNS_TYP_CD in ('M','E','S') OR (IT.TRNS_TYP_CD ='C' and IT.TRNS_AMNT>=0))
		GROUP BY IT.TRNS_ID
),

APP_CMNT_GRP_INT AS (SELECT
	IT.TRNS_ID,
	LISTAGG(APPLCTN_COMNT_DESC) APPLCTN_COMNT_DESC_INT
FROM
	stg_irmsods__irms_transaction IT
LEFT JOIN stg_irmsods__trns_comnt tc ON
	it.trns_id = tc.trns_id and tc.INTRNL_EXTRNL_FLG = 'I'
LEFT JOIN stg_irmsods__applctn_comnt ac ON
	tc.applctn_comnt_id = ac.applctn_comnt_id
WHERE
	(IT.TRNS_TYP_CD in ('M','E','S') OR (IT.TRNS_TYP_CD ='C' and IT.TRNS_AMNT>=0))
	GROUP BY IT.TRNS_ID
),

stg_irmsods__irms_transaction__filtered AS (
    SELECT *
	FROM stg_irmsods__irms_transaction TTI
	WHERE (TTI.TRNS_TYP_CD in ('M','E','S') OR (TTI.TRNS_TYP_CD ='C' and TTI.TRNS_AMNT>=0))
),

-- Final CTE
final AS (
	SELECT
		{{ dbt_utils.generate_surrogate_key(['TL.ID']) }} AS ID,
		TL.ID AS TRANSACTION_ID,
		TTI.GLBL_MPNG_SEQ_NUM AS SOURCE_SEQUENCE,
		NULL AS E_CODE,
		NULL AS C_CODE,
		TTI.BLLNG_ID AS BR_BILL_ID,
		NULL AS PREV_ITERATION,
		TTI.SRC_SYST_CD AS SOURCE_SYSTEM,
		NULL AS LE,
		TTI.RCVBL_ID AS RCVBL_NUM,
		rev.revnu_typ_cd AS REVNU,
		P.RSN_TYP_CD AS RSN,
		V.VAL_TYP_CD AS VT,
		V.BLLNG_CALCTN_BASIS_CD AS BC,
		NULL AS PRODT,
		P.COST_CNTR AS CC,
		NULL AS IRMS_RCVBL_SEQ_NUM,
		acge.applctn_comnt_desc_ext AS COMMENTS,
		ita.adjmt_rsn_cd AS ADJMT_RSN_CD,
		LOB.ID AS LOB,
		NLR.NS_LCTN_DESC AS NS_LCTN_DESC,
		ir.agng_dt,
		TTI.MNTH_OF_SVC AS MNTH_OF_SVC,
		TTI.run_id AS RUN_ID,
		TTI.PPA_FLG ,
		arr.ADJMT_RSN_DESC AS ADJMT_RSN_DESC,
		pr.prcs_desc,
		su.sec_usr_nm AS USER_CODE,
		rl.STRT_DT AS PRCS_DT,
		IR.PYMT_STATUS_CD AS PC,
		tti.BKNG_STATUS_CD AS TS,
		NCR.NS_CLASS_DESC,
		NDM.NS_DEPT_CD,
		NDR.NS_DEPT_DESC,
		NLR.NS_LCTN_CD,
		IR.BAL,
		acgi.applctn_comnt_desc_int AS COMMENTS_INT,
		su.USR_LOGIN_NM_CD
	FROM
		stg_irmsods__irms_transaction__filtered TTI
	LEFT JOIN APP_CMNT_GRP_EXT ACGE ON ACGE.TRNS_ID=TTI.TRNS_ID
	LEFT JOIN APP_CMNT_GRP_INT ACGI ON ACGI.TRNS_ID=TTI.TRNS_ID
	LEFT JOIN transactions TL
		ON TL.ORIGINAL_TRANSACTION_ID=TTI.TRNS_ID
	LEFT JOIN stg_irmsods__product p ON
		TTI.irms_prodt_id = p.irms_prodt_id
	LEFT JOIN stg_irmsods__irms_receivable  ir ON
		TTI.rcvbl_id = ir.rcvbl_id
	LEFT JOIN line_of_business LOB ON LOB.LIN_OF_BUS_CD =IR.LIN_OF_BUS_CD
	LEFT JOIN stg_irmsods__bus_ent b ON
		TTI.bill_to_bus_ent_id = b.bus_ent_id
	LEFT JOIN  stg_irmsods__ns_cc_lctn_mpng NCLM ON
		P.COST_CNTR= NCLM.COST_CNTR
	LEFT JOIN  stg_irmsods__ns_lctn_r NLR ON
		NLR.NS_LCTN_CD = NCLM.NS_LCTN_CD
	LEFT JOIN  stg_irmsods__ns_dept_mpng NDM ON NDM.NS_GL_ACCT_CD=P.NS_GL_ACCT_CD
	LEFT JOIN  stg_irmsods__ns_dept_r NDR ON NDR.NS_DEPT_CD=NDM.NS_DEPT_CD
	LEFT JOIN  stg_irmsods__ns_class_r NCR ON P.NS_CLASS_CD = NCR.NS_CLASS_CD
	LEFT JOIN  stg_irmsods__val_typ_bllng_calctn_mpng V ON
		p.VAL_TYP_BLLNG_CALCTN_ID = V.VAL_TYP_BLLNG_CALCTN_ID
	LEFT JOIN  stg_irmsods__lob_revnu_mpng rev ON
		p.lob_revnu_id = rev.lob_revnu_id
	LEFT JOIN  stg_irmsods__irms_trns_adjmt ita ON
		TTI.trns_id = ita.trns_id
	LEFT JOIN  stg_irmsods__adjmt_rsn_r ARR ON
		ARR.ADJMT_RSN_CD = ita.ADJMT_RSN_CD
	LEFT JOIN  stg_irmsods__run_log rl ON
		TTI.run_id = rl.run_id
	LEFT JOIN  stg_irmsods__process pr ON
		rl.prcs_id = pr.prcs_id
	LEFT JOIN  stg_irmsods__sec_usr su ON
		rl.sec_usr_id = su.sec_usr_id
)

SELECT * FROM final
WHERE TRANSACTION_ID IS NOT NULL