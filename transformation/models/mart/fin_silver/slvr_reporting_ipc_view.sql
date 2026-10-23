{{
    config(
        materialized='view'
    )
}}

WITH

-- Import CTEs
payments AS (
    SELECT * FROM {{ ref('payments') }}
),

payments_details AS (
    SELECT * FROM {{ ref('payments_details') }}
),

payments_irms_details AS (
    SELECT * FROM {{ ref('payments_irms_details') }}
),

line_of_business AS (
    SELECT * FROM {{ ref('line_of_business') }}
),

bill_to_accounts AS (
    SELECT * FROM {{ ref('bill_to_accounts') }}
),

products AS (
    SELECT * FROM {{ ref('products') }}
),

accounting_periods AS (
    SELECT * FROM {{ ref('accounting_periods') }}
),

credits AS (
    SELECT * FROM {{ ref('credits') }}
),

credits_irms_details AS (
    SELECT * FROM {{ ref('credits_irms_details') }}
),

transactions AS (
    SELECT * FROM {{ ref('transactions') }}
),

transaction_lines AS (
    SELECT * FROM {{ ref('transaction_lines') }}
),

irms_detail AS (
    SELECT * FROM {{ ref('irms_detail') }}
),

-- Logical CTEs

-- Final CTE
final AS (
    SELECT
    P.ID,
    ORIGINAL_PAYMENT_ID TRNS_ID,
    INVOICE_NO,
    AMOUNT,
    BA.BUS_ENT_ID BILL_TO_BUS_ENT_ID,
    AE,
    ACCTG_DT,
    SRC_SYST_CD,
    LOB.LIN_OF_BUS_CD LOB,
    PRO.ORIGINAL_PRODUCT_ID ,
    DPST_ID,
    AP.ORIGINAL_ACCOUNTING_ID ,
    PID.PRCS_DESC PRCS_DESC,
    P.AGNG_DT AGNG_DT,
    P.MNTH_OF_SVC MOS,
    PID.REVNU_TYP_CD REVNU,
    PID.VAL_TYP_CD VAL_TYP,
    PID.BLLNG_CALCTN_BASIS_CD BCB,
    PID.NS_LCTN_DESC LOCATION,
    PID.USR_LOGIN_NM_CD USER_CODE,
    PID.ADJMT_RSN_CD ADJMT_RSN_CD,
    PID.ADJMT_RSN_DESC ADJMT_RSN_DESC,
    P.RUN_ID FINALIZE_RUN_ID,
    PID.APPLCTN_COMNT_DESC COMMENTS,
    PD.DPST_DT ,
    PD.CHECK_DT ,
    PD.CHECK_NUM ,
    PID.STRT_DT,
    PID.PYMT_STATUS_CD,
    PID.BKNG_STATUS_CD,
    PID.PRCS_DT,
    PID.NS_DEPT_CD,
    PID.NS_CLASS_DESC,
    PID.NS_LCTN_DESC,
    PID.NS_DEPT_DESC,
    PID.NS_LCTN_CD,
    PID.RSN_TYP_CD,
    P.PPA_FLAG,
    PID.BAL,
    P.ACTV_DT,
    PID.COMMENTS_INT AS COMMENT_INT,
    P.XREF_TRNS_ID,
    P.TRNS_TYP_CD ,
    PD.BANK_ACCT_NUM ,
    P.RCVBL_ID,
    P.glbl_mpng_typ_cd,
    P.BLLNG_ID,
    P.src_clm_seq_num,
    PD.bank_id,
    'PAYMENT' SOURCE
    FROM payments P
    LEFT JOIN payments_details PD ON P.ID=PD.PAYMENTS_ID
    LEFT JOIN payments_irms_details PID ON P.ID=PID.PAYMENTS_ID
    LEFT JOIN line_of_business LOB ON P.LOB_ID =LOB.ID
    LEFT JOIN bill_to_accounts BA ON BA.ID=P.BILL_TO_BUS_ENT_ID
    LEFT JOIN products PRO ON PRO.ID=P.PRODUCT_ID
    LEFT JOIN accounting_periods AP ON AP.ID =P.ACCOUNTING_PERIOD_ID
    UNION
    SELECT
    C.ID,
    ORIGINAL_CREDIT_ID,
    INVOICE_NO,
    AMOUNT,
    BA.BUS_ENT_ID BILL_TO_BUS_ENT_ID,
    AE,
    ACCTG_DT,
    SRC_SYST_CD,
    LOB.LIN_OF_BUS_CD LOB,
    PRO.ORIGINAL_PRODUCT_ID ,
    NULL DPST_ID,
    AP.ORIGINAL_ACCOUNTING_ID ,
    CID.PRCS_DESC PRCS_DESC,
    C.AGNG_DT AGNG_DT,
    C.MNTH_OF_SVC MOS,
    CID.REVNU_TYP_CD REVNU,
    CID.VAL_TYP_CD VAL_TYP,
    CID.BLLNG_CALCTN_BASIS_CD BCB,
    CID.NS_LCTN_DESC LOCATION,
    CID.USR_LOGIN_NM_CD USER_CODE,
    CID.ADJMT_RSN_CD ADJMT_RSN_CD,
    CID.ADJMT_RSN_DESC ADJMT_RSN_DESC,
    C.RUN_ID FINALIZE_RUN_ID,
    CID.APPLCTN_COMNT_DESC COMMENTS,
    NULL DPST_DT ,
    NULL CHECK_DT ,
    NULL CHECK_NUM ,
    NULL STRT_DT,
    CID.PYMT_STATUS_CD,
    CID.BKNG_STATUS_CD,
    CID.PRCS_DT,
    CID.NS_DEPT_CD,
    CID.NS_CLASS_DESC,
    CID.NS_LCTN_DESC,
    CID.NS_DEPT_DESC,
    CID.NS_LCTN_CD,
    CID.RSN_TYP_CD,
    C.PPA_FLAG,
    CID.BAL,
    C.ACTV_DT,
    CID.COMMENTS_INT,
    C.XREF_TRNS_ID,
    C.TRNS_TYP_CD ,
    NULL BANK_ACCT_NUM ,
    C.RCVBL_ID ,
    C.glbl_mpng_typ_cd,
    C.BLLNG_ID,
    C.src_clm_seq_num,
    NULL bank_id,
    'CREDITS' SOURCE
    FROM credits C
    LEFT JOIN credits_irms_details CID ON C.ID=CID.CREDITS_ID
    LEFT JOIN line_of_business LOB ON C.LOB_ID =LOB.ID
    LEFT JOIN bill_to_accounts BA ON BA.ID=C.BILL_TO_BUS_ENT_ID
    LEFT JOIN products PRO ON PRO.ID=C.PRODUCT_ID
    LEFT JOIN accounting_periods AP ON AP.ID =C.ACCOUNTING_PERIOD_ID
    UNION
    SELECT
    T.ID,
    ORIGINAL_TRANSACTION_ID,
    INVOICE_NO,
    TL.UNIT_PRICE,
    BA.BUS_ENT_ID BILL_TO_BUS_ENT_ID,
    AE,
    ACCTG_DT,
    SRC_SYST_CD,
    LOB.LIN_OF_BUS_CD LOB,
    PRO.ORIGINAL_PRODUCT_ID ,
    NULL DPST_ID,
    AP.ORIGINAL_ACCOUNTING_ID,
    ID.PRCS_DESC PRCS_DESC,
    ID.AGNG_DT AGNG_DT,
    T.MNTH_OF_SVC MOS,
    ID.REVNU REVNU,
    ID.VT VAL_TYP,
    ID.BC BCB,
    ID.NS_LCTN_DESC LOCATION,
    ID.USR_LOGIN_NM_CD USER_CODE,
    ID.ADJMT_RSN_CD ADJMT_RSN_CD,
    ID.ADJMT_RSN_DESC ADJMT_RSN_DESC,
    ID.RUN_ID FINALIZE_RUN_ID,
    ID.COMMENTS COMMENTS,
    NULL DPST_DT ,
    NULL CHECK_DT ,
    NULL CHECK_NUM ,
    NULL STRT_DT,
    ID.PC,
    ID.TS,
    ID.PRCS_DT,
    ID.NS_DEPT_CD,
    ID.NS_CLASS_DESC,
    ID.NS_LCTN_DESC,
    ID.NS_DEPT_DESC,
    ID.NS_LCTN_CD,
    ID.RSN,
    ID.PPA_FLG,
    ID.BAL,
    T.ACTV_DT,
    ID.COMMENTS_INT,
    T.XREF_TRNS_ID,
    T.TRNS_TYP_CD,
    NULL BANK_ACCT_NUM ,
    TL.RECEIVABLE_CODE ,
    T.glbl_mpng_typ_cd,
    T.BLLNG_ID,
    T.src_clm_seq_num,
    NULL bank_id,
    'INVOICE' SOURCE
    FROM transactions T
    LEFT JOIN transaction_lines TL ON T.ID=TL.TRANSACTION_ID
    LEFT JOIN irms_detail ID ON T.ID=ID.TRANSACTION_ID
    LEFT JOIN line_of_business LOB ON ID.LOB=LOB.ID
    LEFT JOIN products PRO ON PRO.ID=TL.PRODUCT_ID
    LEFT JOIN accounting_periods AP ON AP.ID =T.ACCOUNTING_PERIOD_ID
    LEFT JOIN bill_to_accounts BA ON BA.ID=T.BILL_TO_BUS_ENT_ID
)

SELECT * FROM final