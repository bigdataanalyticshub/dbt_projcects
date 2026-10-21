{{
  config(
    materialized='table'
  )
}}


------------------------------------
--- THERE ARE 5 MAIN STEPS:
------------------------------------
--- step 1: create t with multiple updates
--- step 2: create t2 with multiple updates
--- step 3: update t2 by using t
--- step 4: update t by using t2
--- step 5: output t only
-------------------------------------

WITH
-- Import
stg_irmsods__irms_transaction as (
    select * from {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__product as (
    select * from {{ ref('stg_irmsods__product') }}
),

stg_irmsods__lob_revnu_mpng as (
    select * from {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__val_typ_bllng_calctn_mpng as (
    select * from {{ ref('stg_irmsods__val_typ_bllng_calctn_mpng') }}
),

stg_irmsods__clm_amnt as (
    select * from {{ ref('stg_irmsods__clm_amnt') }}
),

stg_irmsods__clm_stgng_que as (
    select * from {{ ref('stg_irmsods__clm_stgng_que') }}
),

stg_irmsods__clnc_clm_stgng_que as (
    select * from {{ ref('stg_irmsods__clnc_clm_stgng_que') }}
),

stg_irmsods__lgl_ent_r as (
    select * from {{ ref('stg_irmsods__lgl_ent_r') }}
),

stg_irmsods__ns_dept_mpng as (
    select * from {{ ref('stg_irmsods__ns_dept_mpng') }}
),

stg_irmsods__ns_dept_r as (
    select * from {{ ref('stg_irmsods__ns_dept_r') }}
),

stg_irmsods__ns_class_r as (
    select * from {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__glbl_rcvbl_mpng as (
    select * from {{ ref('stg_irmsods__glbl_rcvbl_mpng') }}
),

stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_irmsods__lgl_ent_mpng as (
    select * from {{ ref('stg_irmsods__lgl_ent_mpng') }}
),
stg_irmsods__bank_acct_lock_box_addr as (
    select * from {{ ref('stg_irmsods__bank_acct_lock_box_addr') }}
),
stg_irmsods__remittance as (
    select * from {{ ref('stg_irmsods__remittance') }}
),
stg_irmsods__deposit as (
    select * from {{ ref('stg_irmsods__deposit') }}
),
stg_irmsods__lgl_ent_r as (
    select * from {{ ref('stg_irmsods__lgl_ent_r') }}
),

-- Logical
-- base transactions
base_model as (
    SELECT CAST(0 AS NUMBER) as le,
        t.glbl_mpng_cd as rcvbl_num,
        t.trns_amnt as amnt,
        t.bill_to_bus_ent_id as be,
        t.bk_to_bus_ent_id as ae,
        'C-----' as c_code,
        'E-----' as e_code,
        t.acctg_dt,
        t.src_syst_cd as src,
        m.lin_of_bus_cd as lob,
        m.revnu_typ_cd as revnu,
        d.rsn_typ_cd as rsn,
        x.val_typ_cd as vt,
        x.bllng_calctn_basis_cd as bc,
        '-----' as prodt,
        d.ns_gl_acct_cd as gl_acct,
        d.ns_class_cd,
        d.cost_cntr as cc,
        t.glbl_mpng_cd as curr_clm_key,
        CAST(-1 AS NUMBER) as seq,
        '-' as rec_typ,
        t.rcvbl_id,
        t.trns_id,
        t.xref_trns_id,
        t.trns_typ_cd,
        t.ppa_flg,
        t.irms_prodt_id,
        t.acctg_period_id,
        t.run_id,
        t.mnth_of_svc
    FROM stg_irmsods__irms_transaction t
    INNER JOIN stg_irmsods__product d ON t.irms_prodt_id = d.irms_prodt_id
    INNER JOIN stg_irmsods__lob_revnu_mpng m ON d.lob_revnu_id = m.lob_revnu_id
    INNER JOIN stg_irmsods__val_typ_bllng_calctn_mpng x ON d.val_typ_bllng_calctn_id = x.val_typ_bllng_calctn_id
    WHERE m.lin_of_bus_cd like '%GNX'
),

-- update seq
seq AS (
    SELECT t1.trns_id, a1.src_clm_seq_num
    FROM base_model t1
    LEFT JOIN stg_irmsods__clm_amnt a1 ON a1.trns_id = nvl(t1.xref_trns_id,t1.trns_id)
    WHERE t1.src != 'OAC'
    and t1.src != 'MANR'
    and t1.trns_typ_cd = 'C'
),

base_model_w_seq AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        b.cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        CASE WHEN s.trns_id IS NOT NULL THEN s.src_clm_seq_num
             ELSE b.seq
        END AS seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
FROM base_model b
LEFT JOIN seq s ON b.TRNS_ID = s.TRNS_ID
),

-- update rec typ
rec_type_strata AS (
    SELECT t1.trns_id, q1.rec_typ
    from base_model_w_seq t1
    LEFT JOIN stg_irmsods__clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src != 'OAC'
    and t1.src = 'SAGNX'
    and t1.trns_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

rec_type_cognos AS (
    SELECT t1.trns_id, q1.record_type AS rec_typ
    FROM base_model_w_seq t1
    LEFT JOIN stg_irmsods__clnc_clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src != 'SAGNX'
    and t1.trns_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

rec_type_union_all AS (
    SELECT * FROM rec_type_strata
    UNION ALL
    SELECT * FROM rec_type_cognos
),


base_model_w_rec_type AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        b.cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.rec_typ ELSE b.rec_typ END AS rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_seq b
    LEFT JOIN rec_type_union_all r ON b.TRNS_ID = r.TRNS_ID
),

-- update ppa_flg
base_model_w_ppa_flg AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        b.cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        CASE WHEN b.ppa_flg != 'O' AND b.trns_typ_cd = 'C' AND b.rec_typ = 'I' THEN 'O' ELSE b.ppa_flg END AS ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_rec_type b
),

-- update curr_clm_key from clnc_clm_stgng_que and stg_irmsods__clnc_clm_stgng_que

curr_clm_key_1 AS (
    SELECT t1.trns_id, q1.clm_grp_num as curr_clm_key
    from base_model_w_ppa_flg t1
    LEFT JOIN stg_irmsods__clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src != 'OAC'
    and t1.src = 'SAGNX'
    and t1.trns_typ_cd = 'C'
    and t1.rec_typ in ('I','R')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

curr_clm_key_2 AS (
    SELECT t1.trns_id, q1.old_clm_id as curr_clm_key
    from base_model_w_ppa_flg t1
    LEFT JOIN stg_irmsods__clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src != 'OAC'
    and t1.src = 'SAGNX'
    and t1.trns_typ_cd = 'C'
    and t1.rec_typ = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

curr_clm_key_3 AS (
    SELECT t1.trns_id, q1.inv_num as curr_clm_key
    from base_model_w_ppa_flg t1
    LEFT JOIN stg_irmsods__clnc_clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src != 'OAC'
    and t1.src != 'SAGNX'
    and t1.trns_typ_cd = 'C'
    and t1.rec_typ in ('I','R')
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

curr_clm_key_4 AS (
    SELECT t1.trns_id, nvl(q1.orig_inv_num,q1.inv_num) as curr_clm_key
    from base_model_w_ppa_flg t1
    LEFT JOIN stg_irmsods__clnc_clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.src != 'OAC'
    and t1.src != 'SAGNX'
    and t1.trns_typ_cd = 'C'
    and t1.rec_typ = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

curr_clm_key_union_1234 AS (
    SELECT * FROM curr_clm_key_1
    UNION ALL
    SELECT * FROM curr_clm_key_2
    UNION ALL
    SELECT * FROM curr_clm_key_3
    UNION ALL
    SELECT * FROM curr_clm_key_4
),

base_model_w_curr_clm_key1234 AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        b.cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.curr_clm_key ELSE b.curr_clm_key END AS curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_ppa_flg b
    LEFT JOIN curr_clm_key_union_1234 r ON b.TRNS_ID = r.TRNS_ID
),

-- update curr_clm_key, seq, and rec_typ with the same logic

base_model_w_curr_clm_key_seq_rec_updated AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        b.cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        CASE WHEN src != 'OAC' AND trns_typ_cd != 'C' THEN NULL
             WHEN src in ('OAC','MANR') THEN NULL
             WHEN seq = -1 AND revnu = 'PAYMNT' THEN NULL
        ELSE b.curr_clm_key END AS curr_clm_key,
        CASE WHEN src != 'OAC' AND trns_typ_cd != 'C' THEN NULL
             WHEN src in ('OAC','MANR') THEN NULL
             WHEN seq = -1 AND revnu = 'PAYMNT' THEN NULL
        ELSE b.seq END AS seq,
        CASE WHEN src != 'OAC' AND trns_typ_cd != 'C' THEN NULL
             WHEN src in ('OAC','MANR') THEN NULL
             WHEN seq = -1 AND revnu = 'PAYMNT' THEN NULL
        ELSE b.rec_typ END AS rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_curr_clm_key1234 b
),

-- update c_code, e_code, cc, prodt
code_prodt_1 AS (
    SELECT t1.trns_id,
    q1.gnx_c_code as c_code, q1.gnx_e_code as e_code, q1.cost_cntr as cc, q1.src_prodt_cd as prodt
    from base_model_w_curr_clm_key_seq_rec_updated t1
    LEFT JOIN stg_irmsods__clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.lob = 'WCGNX'
    and t1.src != 'OAC'
    and t1.src != 'MANR'
    and t1.seq is not null
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

code_prodt_2 AS (
    SELECT t1.trns_id,
    q1.acct_location as c_code,
    substr(q1.cust_client_subclnt_num,0,6) as e_code,
    substr(q1.cust_client_loc_num,4,4) as cc,
    q1.src_prodt_cd as prodt
    FROM base_model_w_curr_clm_key_seq_rec_updated t1
    LEFT JOIN stg_irmsods__clnc_clm_stgng_que q1
    ON q1.src_clm_key = t1.rcvbl_num
    and q1.src_clm_seq_num = t1.seq
    and q1.csq_status_cd = 'C'
    WHERE t1.lob = 'CLNGNX'
    and t1.src != 'OAC'
    and t1.src != 'MANR'
    and t1.seq is not null
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1.trns_id ORDER BY q1.run_id DESC) = 1
),

code_prodt_union_all AS (
    SELECT * FROM code_prodt_1
    UNION ALL
    SELECT * FROM code_prodt_2
),


base_model_w_code_prodt_updated AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.c_code ELSE b.c_code END AS c_code,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.e_code ELSE b.e_code END AS e_code,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.cc ELSE b.cc END AS cc,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.prodt ELSE b.prodt END AS prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_curr_clm_key_seq_rec_updated b
    LEFT JOIN code_prodt_union_all r ON b.TRNS_ID = r.TRNS_ID
),

-- update cc based on earliest transaction

earliest_transactions AS (
    SELECT acctg_period_id,rcvbl_num, MIN(trns_id) AS min_trns_id
    FROM base_model_w_code_prodt_updated
    GROUP BY acctg_period_id,rcvbl_num
),
-- here is very complex! must use rcvbl_num to join back with base;
-- the idea is to update the same rcvbl_num which might have differen trns id
cost_centers AS (
    SELECT t.acctg_period_id, t.rcvbl_num, d.cost_cntr as cc
    FROM stg_irmsods__product d
    JOIN base_model_w_code_prodt_updated t ON t.irms_prodt_id = d.irms_prodt_id
    JOIN earliest_transactions e ON t.rcvbl_num = e.rcvbl_num AND t.trns_id = e.min_trns_id AND t.acctg_period_id = e.acctg_period_id
),

base_model_w_cc_updated AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        --- the NA condition can't be in the cost centers CTEs, which will exclude the other trans id which want to update
        --- RCVBL_NUM = '10371855' as an example
        CASE WHEN r.rcvbl_num IS NOT NULL and nvl(b.cc,'NA') = 'NA' and b.src != 'OAC'  and b.src = 'MANR' THEN r.cc ELSE b.cc END AS cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_code_prodt_updated b
    LEFT JOIN cost_centers r ON b.rcvbl_num = r.rcvbl_num AND b.acctg_period_id = r.acctg_period_id
),

-- update curr_clm_key for MANR and WCGNX

manr_curr_clm_key AS (
    SELECT o.glbl_mpng_cd AS curr_clm_key,
    t.trns_id
    FROM base_model_w_cc_updated t
    JOIN stg_irmsods__glbl_rcvbl_mpng m ON t.rcvbl_num = m.glbl_mpng_cd
    JOIN stg_irmsods__glbl_rcvbl_mpng o ON m.rcvbl_id = o.rcvbl_id
    WHERE m.glbl_mpng_typ_cd = 'B'
    AND o.glbl_mpng_typ_cd = 'H'
    AND t.lob = 'WCGNX'
    AND t.src = 'MANR'
    AND o.glbl_mpng_cd != m.glbl_mpng_cd
),

base_model_w_curr_clm_key_updated2 AS (
    SELECT b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        b.cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        CASE WHEN r.TRNS_ID IS NOT NULL THEN r.curr_clm_key ELSE b.curr_clm_key END AS curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_cc_updated b
    LEFT JOIN manr_curr_clm_key r ON b.TRNS_ID = r.TRNS_ID
),

gl_gnx_trns_202506_t AS (
    SELECT
        CAST(0 AS NUMBER) as le,   -- also update le to be 0 for all records
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        b.acctg_dt,
        b.src,
        b.lob,
        b.revnu,
        b.rsn,
        b.vt,
        b.bc,
        b.c_code,
        b.e_code,
        b.cc,
        b.prodt,
        b.gl_acct,
        b.ns_class_cd,
        b.curr_clm_key,
        b.seq,
        b.rec_typ,
        b.rcvbl_id,
        b.trns_id,
        b.xref_trns_id,
        b.trns_typ_cd,
        b.ppa_flg,
        b.irms_prodt_id,
        b.acctg_period_id,
        b.run_id,
        b.mnth_of_svc
    FROM base_model_w_curr_clm_key_updated2 b
)


select * from gl_gnx_trns_202506_t  -- step 1 stops here
