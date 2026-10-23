{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH

prospective_gl_download AS (
    SELECT * FROM {{ ref('prospective_gl_download') }}
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

stg_irmsods__trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
),

adjustments AS (
    SELECT
        z.be AS BE_ID,
        z.be_name AS BE_NAME,
        z.ae AS AE_ID,
        z.ae_name AS AE_NAME,
        'DME' AS LINE_SVC_TYP,
        z.src AS SRC_SYST_CD,
        z.lob AS LOB,
        z.revnu AS REVENUE_TYP,
        z.rsn AS REASON_TYP,
        ita.adjmt_rsn_cd,
        arr.adjmt_rsn_desc,
        z.vt AS VAL_TYP_CD,
        z.bc AS BLLNG_CALCTN_BASIS_CD,
        z.rx_code AS SVC_ITEM_CD,
        z.bill_id AS EXTRNL_INV_ID,
        z.rcvbl_num AS IRMS_RCVBL_NUM,
        to_char(z.acctg_dt, 'YYYYMM') AS ACCTG_PERIOD,
        z.acctg_dt AS BILLED_DT,
        z.acctg_dt,
        z.amnt AS TRNS_AMNT,
        z.run_id,
        p.prcs_desc,
        ac.applctn_comnt_desc AS ADJ_COMMENT,
        su.sec_usr_nm AS IRMS_USER,
        z.gl_acct,
        z.ns_class_desc
    FROM prospective_gl_download z
    LEFT JOIN stg_irmsods__irms_trns_adjmt ita ON z.trns_id = ita.trns_id
    LEFT JOIN stg_irmsods__adjmt_rsn_r arr ON arr.adjmt_rsn_cd = ita.adjmt_rsn_cd
    LEFT JOIN stg_irmsods__run_log rl ON z.run_id = rl.run_id
    LEFT JOIN stg_irmsods__sec_usr su ON rl.sec_usr_id = su.sec_usr_id
    LEFT JOIN stg_irmsods__process p ON rl.prcs_id = p.prcs_id
    LEFT JOIN stg_irmsods__trns_comnt tc ON z.trns_id = tc.trns_id
        AND tc.applctn_comnt_id = (
            SELECT MIN(tc2.applctn_comnt_id)
            FROM stg_irmsods__trns_comnt tc2
            WHERE tc2.trns_id = z.trns_id
        )
    LEFT JOIN stg_irmsods__applctn_comnt ac ON tc.applctn_comnt_id = ac.applctn_comnt_id
    WHERE z.trns_typ_cd = 'A'
)

SELECT * FROM adjustments