{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}
-- Retro Line Detail Operational OAC Report
-- Converted from Oracle to Snowflake DBT model
-- Purpose: Generate retro line detail operational report for OAC transactions

-- Import CTEs for staging tables
WITH stg_oradba__transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_oradba__run_log AS (
    SELECT * FROM {{ ref('stg_irmsods__run_log') }}
),

stg_oradba__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_oradba__lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_oradba__sec_usr AS (
    SELECT * FROM {{ ref('stg_irmsods__sec_usr') }}
),

stg_oradba__receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
),

stg_oradba__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),

stg_oradba__edi_835s AS (
    SELECT * FROM {{ ref('stg_irmsods__edi_835s') }}
),

stg_oradba__edi_835b AS (
    SELECT * FROM {{ ref('stg_irmsods__edi_835b') }}
),

stg_oradba__remittance AS (
    SELECT * FROM {{ ref('stg_irmsods__remittance') }}
),

stg_oradba__trns_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__trns_comnt') }}
),

stg_oradba__applctn_comnt AS (
    SELECT * FROM {{ ref('stg_irmsods__applctn_comnt') }}
),

-- Extract and clean check numbers from remittance data
check_numbers AS (
    SELECT
        r.trns_id,
        -- Clean check number by removing carriage returns and line feeds
        REPLACE(REPLACE(TRIM(r.check_num), CHR(13), ''), CHR(10), '') AS check_num
    FROM stg_oradba__remittance r
    WHERE r.check_num IS NOT NULL
),

-- Aggregate transaction comments with proper formatting
transaction_comments AS (
    SELECT
        c.trns_id,
        -- Replace newlines with spaces in comment descriptions
        REGEXP_REPLACE(a.applctn_comnt_desc, '\\n', ' ') AS comnt
    FROM
        stg_oradba__trns_comnt c
        INNER JOIN stg_oradba__applctn_comnt a
            ON c.applctn_comnt_id = a.applctn_comnt_id
    -- Use QUALIFY to get only the first comment per transaction
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY c.trns_id
        ORDER BY a.applctn_comnt_id
    ) = 1
),

-- Main query combining all data sources
final_result AS (
    SELECT
        -- User and organizational information
        u.sec_usr_nm AS usr_nm,
        m.lin_of_bus_cd AS lob,
        t.glbl_mpng_cd AS oac_rcvbl,
        t.bill_to_bus_ent_id AS be,
        b.bus_ent_nm AS be_nm,
        t.bk_to_bus_ent_id AS ae,

        -- Date conversion for deposit date
        TO_DATE(TO_VARCHAR(t.acctg_dt, 'MM/DD/YYYY'), 'MM/DD/YYYY') AS dpst_dt,

        -- Payer and payment information
        eb.payr_nm AS payer_name,
        cn.check_num,
        es.adjt_prc_cd AS med_cd,

        -- Service date range
        es.svc_from_dt AS dos_from,
        es.svc_to_dt AS dos_to,

        -- Claim and patient information
        es.patnt_cntrl_nbr AS claim_num,
        eb.patnt_frst_nm AS patient_first_name,
        eb.patnt_lst_nm AS patient_last_name,

        -- Financial information
        t.trns_amnt AS pymt_amnt,
        r.bal,

        -- Comments
        tc.comnt

    FROM
        -- Core transaction data with required joins
        stg_oradba__transaction t
        INNER JOIN stg_oradba__run_log l
            ON t.run_id = l.run_id
        INNER JOIN stg_oradba__product d
            ON t.irms_prodt_id = d.irms_prodt_id
        INNER JOIN stg_oradba__lob_revnu_mpng m
            ON d.lob_revnu_id = m.lob_revnu_id
        INNER JOIN stg_oradba__sec_usr u
            ON l.sec_usr_id = u.sec_usr_id
        INNER JOIN stg_oradba__receivable r
            ON t.rcvbl_id = r.rcvbl_id
        INNER JOIN stg_oradba__bus_ent b
            ON t.bill_to_bus_ent_id = b.bus_ent_id

        -- Optional EDI and supplementary data
        LEFT JOIN stg_oradba__edi_835s es
            ON t.trns_id = es.trns_id
        LEFT JOIN stg_oradba__edi_835b eb
            ON es.run_id = eb.run_id
            AND es.bll_seq_num = eb.bll_seq_num
        LEFT JOIN check_numbers cn
            ON t.trns_id = cn.trns_id
        LEFT JOIN transaction_comments tc
            ON t.trns_id = tc.trns_id

    WHERE
        -- Filter criteria for OAC transactions
        t.src_syst_cd = 'OAC'
        AND m.lin_of_bus_cd = 'DMERD'
        AND m.revnu_typ_cd = 'PAYMNT'
        AND r.bal != 0  -- Only include records with non-zero balance
)

-- Final select with ordering
SELECT *
FROM final_result
ORDER BY dpst_dt DESC
