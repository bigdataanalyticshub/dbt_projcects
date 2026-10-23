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

stg_irmsods__remittance AS (
    SELECT * FROM {{ ref('stg_irmsods__remittance') }}
),

stg_irmsods__deposit AS (
    SELECT * FROM {{ ref('stg_irmsods__deposit') }}
),

stg_irmsods__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

irms_invoice_lookup AS (
    SELECT glbl_mpng_cd, bllng_id
    FROM stg_irmsods__irms_transaction
    QUALIFY ROW_NUMBER() OVER (PARTITION BY glbl_mpng_cd ORDER BY glbl_mpng_cd) = 1
)

SELECT
    d.dpst_dt,
    CASE WHEN d.dpst_finlzd_flg = 'Y'
        THEN r_log.strt_dt
        ELSE NULL
    END AS dpst_fnlzd_dt,
    REGEXP_REPLACE(i.check_num, '\\s+$', '') AS check_num,
    i.check_dt,
    i.dpst_id,
    z.rsn,
    z.amnt AS applied_amnt,
    z.rcvbl_num,
    z.bill_id,
    z.svc_item_id,
    z.rx_code,
    z.svc_typ,
    z.clm_num,
    z.patnt_first_nm,
    z.patnt_last_nm,
    z.be,
    be.bus_ent_nm AS be_name,
    z.ae,
    ae.bus_ent_nm AS ae_name,
    z.acctg_period_id,
    z.acctg_dt,
    z.src,
    z.lob,
    z.gl_acct,
    u.sec_usr_nm,
    inv.bllng_id AS irms_invoice,
    z.bill_date,
    z.rx_code AS hcpcs,
    z.svc_item_desc,
    z.client_billed_amt
FROM prospective_gl_download z
LEFT JOIN stg_irmsods__remittance i ON z.trns_id = i.trns_id
LEFT JOIN stg_irmsods__deposit d ON i.dpst_id = d.dpst_id
JOIN stg_irmsods__run_log r_log ON z.run_id = r_log.run_id
LEFT JOIN stg_irmsods__sec_usr u ON r_log.sec_usr_id = u.sec_usr_id
LEFT JOIN stg_irmsods__bus_ent be ON z.be = be.bus_ent_id
LEFT JOIN stg_irmsods__bus_ent ae ON z.ae = ae.bus_ent_id
LEFT JOIN irms_invoice_lookup inv ON inv.glbl_mpng_cd = z.rcvbl_num
WHERE z.le = 2
AND z.amnt != 0
AND z.revnu = 'PAYMNT'
