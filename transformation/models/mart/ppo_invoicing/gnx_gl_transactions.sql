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

stg_irmsods__process as (
    select * from {{ ref('stg_irmsods__process') }}
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

stg_irmsods__irms_trns_adjmt as (
    select * from {{ ref('stg_irmsods__irms_trns_adjmt') }}
),

stg_irmsods__ns_cc_lctn_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_cc_lctn_mpng') }}
),

stg_irmsods__ns_lctn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_lctn_r') }}
),


stg_irmsods__bus_ent as (
    select * from {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__run_log as (
    select * from {{ ref('stg_irmsods__run_log') }}
),

stg_irmsods__adjmt_rsn_r as (
    select * from {{ ref('stg_irmsods__adjmt_rsn_r') }}
),

stg_irmsods__usr_prcs_rqst as (
    select * from {{ ref('stg_irmsods__usr_prcs_rqst') }}
),

stg_irmsods__patient as (
    select * from {{ ref('stg_irmsods__patient') }}
),

stg_irmsods__irms_claim as (
    select * from {{ ref('stg_irmsods__irms_claim') }}
),

stg_irmsods__sec_usr as (
    select * from {{ ref('stg_irmsods__sec_usr') }}
),

stg_irmsods__trns_comnt as (
    select * from {{ ref('stg_irmsods__trns_comnt') }}
),

stg_irmsods__applctn_comnt as (
    select * from {{ ref('stg_irmsods__applctn_comnt') }}
),
mrt_ppo_invoicing__gnx_gl_t1 as (
    select * from {{ ref('gnx_gl_t1') }}
),
mrt_ppo_invoicing__gnx_gl_t2 as (
    select * from {{ ref('gnx_gl_t2') }}
),

-- Logical
gl_gnx_trns_202506_t2_le_info AS (
    SELECT distinct t1_acctg_period_id, rcvbl_num, le
    FROM mrt_ppo_invoicing__gnx_gl_t2 t
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t1_acctg_period_id, t.rcvbl_num ORDER BY t.le ) = 1
),

gl_gnx_trns_202506_t_final_1 AS (
    SELECT
        CASE WHEN r.rcvbl_num IS NOT NULL THEN r.le ELSE b.le END AS le,
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
    FROM mrt_ppo_invoicing__gnx_gl_t1 b
    LEFT JOIN gl_gnx_trns_202506_t2_le_info r ON b.rcvbl_num = r.rcvbl_num AND b.acctg_period_id = r.t1_acctg_period_id
),

-- update all le for t table again with the same logic


gl_gnx_trns_202506_t_final_2 AS (
    SELECT
        CASE WHEN lob = 'WCGNX' AND src != 'OAC' AND nvl(b.le,0) = 0 THEN 5 ELSE b.le END AS le,    -- after else is not 0! it inherent results from t2
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
    FROM gl_gnx_trns_202506_t_final_1 b
),

-- update le 5 : first identify all receivable numbers that have at least one record with le = 5
qualifying_red_for_le5_t1_2 AS (
    SELECT DISTINCT rcvbl_num
    FROM gl_gnx_trns_202506_t_final_2
    WHERE lob = 'WCGNX'
    AND le = 5
),

gl_gnx_trns_202506_t_final_2_le5 AS (
    SELECT
        CASE WHEN r.rcvbl_num IS NOT NULL AND lob = 'WCGNX' AND nvl(b.le,0) = 0 THEN 5 ELSE b.le END AS le,   -- also update le
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
    FROM gl_gnx_trns_202506_t_final_2 b
    LEFT JOIN qualifying_red_for_le5_t1_2 r ON b.rcvbl_num = r.rcvbl_num
),

-- update le for oac
legal_entity_mappings2 AS (
    SELECT DISTINCT
        m.lgl_ent_cd,
        a.bank_acct_num,
        'OAC' AS src_syst_cd
    FROM
        stg_irmsods__lgl_ent_mpng m
    JOIN
        stg_irmsods__bank_acct_lock_box_addr a ON m.bank_acct_num = a.bank_acct_num
    WHERE
        m.src_syst_cd = 'OAC'
),


bank_mappings2 AS (
    SELECT DISTINCT
        t.rcvbl_num,
        a.bank_acct_num
    FROM
        gl_gnx_trns_202506_t_final_2_le5 t
    JOIN
        stg_irmsods__remittance r ON t.trns_id = r.trns_id
    JOIN
        stg_irmsods__deposit p ON r.dpst_id = p.dpst_id
    JOIN
        stg_irmsods__bank_acct_lock_box_addr a ON p.bank_id = a.bank_id
                                        AND p.bank_acct_num = a.bank_acct_num
),

legal_entity_up2 AS (
    SELECT distinct
        rbm.rcvbl_num,
        lem.lgl_ent_cd as le
    FROM
        bank_mappings2 rbm
    JOIN
        legal_entity_mappings2 lem ON rbm.bank_acct_num = lem.bank_acct_num
    QUALIFY ROW_NUMBER() OVER (PARTITION BY rbm.rcvbl_num ORDER BY lem.lgl_ent_cd) = 1
),

-- here is complex. bank_acct_num could cause issue. it can link to non-oac src. some need put scr = 'oac' in the case when
gl_gnx_trns_202506_t_final_2_le_oac1 AS (
    SELECT
        CASE WHEN r.rcvbl_num IS NOT NULL and nvl(b.le,0) = 0 and b.src = 'OAC' THEN r.le ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le5 b
    LEFT JOIN legal_entity_up2 r ON b.rcvbl_num = r.rcvbl_num
),

lgl_distinct2 AS (
    SELECT DISTINCT
        oac_bus_ent_id,
        lgl_ent_cd AS le
    FROM
        stg_irmsods__lgl_ent_r
),

gl_gnx_trns_202506_t_final_2_le_oac2 AS (
    SELECT
        CASE WHEN r.oac_bus_ent_id IS NOT NULL and nvl(b.le,0) = 0 and b.src = 'OAC' THEN r.le ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le_oac1 b
    LEFT JOIN lgl_distinct2 r ON b.be = r.oac_bus_ent_id
),

-- update le 4

gl_gnx_trns_202506_t_final_2_le4 AS (
    SELECT
        CASE WHEN lob = 'CLNGNX'
                    AND src != 'OAC'
                    AND nvl(b.le,0) = 0
                    AND b.prodt in ('FCM','TCM','IME')
                    AND b.cc in ('0254','0797','0828')
                    THEN 4 ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le_oac2 b
),


qualifying_red_for_le4_2 AS (
    SELECT DISTINCT rcvbl_num
    FROM gl_gnx_trns_202506_t_final_2_le4
    WHERE lob = 'CLNGNX'
    AND le = 4
),

gl_gnx_trns_202506_t_final_2_le4_final AS (
    SELECT
        CASE WHEN r.rcvbl_num IS NOT NULL AND lob = 'CLNGNX' AND nvl(b.le,0) = 0 THEN 4 ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le4 b
    LEFT JOIN qualifying_red_for_le4_2 r ON b.rcvbl_num = r.rcvbl_num
),

-- update le 6

gl_gnx_trns_202506_t_final_2_le6 AS (
    SELECT
        CASE WHEN lob = 'CLNGNX'
                    AND src != 'OAC'
                    AND nvl(b.le,0) = 0
                    AND b.prodt = 'TCM'
                    AND b.cc = '0831'
                    THEN 6 ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le4_final b
),


qualifying_red_for_le6_2 AS (
    SELECT DISTINCT rcvbl_num
    FROM gl_gnx_trns_202506_t_final_2_le6
    WHERE lob = 'CLNGNX'
    AND le = 6
),

gl_gnx_trns_202506_t_final_2_le6_final AS (
    SELECT
        CASE WHEN r.rcvbl_num IS NOT NULL AND lob = 'CLNGNX' AND nvl(b.le,0) = 0 THEN 6 ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le6 b
    LEFT JOIN qualifying_red_for_le6_2 r ON b.rcvbl_num = r.rcvbl_num
),

-- update le 7

gl_gnx_trns_202506_t_final_2_le7 AS (
    SELECT
        CASE WHEN lob = 'CLNGNX'
                    AND src != 'OAC'
                    AND nvl(b.le,0) = 0
                    AND b.cc = '4001'
                    THEN 7 ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le6_final b
),


qualifying_red_for_le7_2 AS (
    SELECT DISTINCT rcvbl_num
    FROM gl_gnx_trns_202506_t_final_2_le7
    WHERE lob = 'CLNGNX'
    AND le = 7
),

gl_gnx_trns_202506_t_final_2_le7_final AS (
    SELECT
        CASE WHEN r.rcvbl_num IS NOT NULL AND lob = 'CLNGNX' AND nvl(b.le,0) = 0 THEN 7 ELSE b.le END AS le,
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
    FROM gl_gnx_trns_202506_t_final_2_le7 b
    LEFT JOIN qualifying_red_for_le7_2 r ON b.rcvbl_num = r.rcvbl_num
),

-- update le 5 again and again, and c_code, e_code, prodt

gl_gnx_trns_202506_t_final_2_le5_final_final AS (
    SELECT
        CASE WHEN nvl(b.le,0) = 0
                    THEN 5 ELSE b.le END AS le,
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
        CASE WHEN (src in ('MANR','OAC') or revnu = 'PAYMNT') then NULL else b.c_code end as c_code,
        CASE WHEN (src in ('MANR','OAC') or revnu = 'PAYMNT') then NULL else b.e_code end as e_code,
        b.cc,
        CASE WHEN (src in ('MANR','OAC') or revnu = 'PAYMNT') then NULL else b.prodt end as prodt,
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
    FROM gl_gnx_trns_202506_t_final_2_le7_final b
),

-- Add fields to support downstream reports
ns_dept_desc_lookup AS (
    SELECT dm.ns_gl_acct_cd, dr.ns_dept_desc
    FROM stg_irmsods__ns_dept_mpng dm
    INNER JOIN stg_irmsods__ns_dept_r dr ON dm.ns_dept_cd = dr.ns_dept_cd
),

process_run_log AS (
    SELECT l.run_id, c.prcs_desc
    FROM stg_irmsods__run_log l
    INNER JOIN stg_irmsods__process c ON l.prcs_id = c.prcs_id
),

sec_usr_run_log AS (
    SELECT l.run_id, s.sec_usr_nm
    FROM stg_irmsods__run_log l
    INNER JOIN stg_irmsods__sec_usr s ON l.sec_usr_id = s.sec_usr_id
),

patient_name AS (
    SELECT t.rcvbl_id, TRIM(COALESCE(n.first_nm,'') || ' ' || COALESCE(n.last_nm,'')) AS patnt_nm
    FROM stg_irmsods__irms_transaction t
    INNER JOIN stg_irmsods__clm_amnt a ON t.trns_id = a.trns_id
    INNER JOIN stg_irmsods__irms_claim c ON a.clm_id = c.clm_id
    INNER JOIN stg_irmsods__patient n ON c.patient_id = n.patient_id
    WHERE t.trns_typ_cd = 'C'
    AND t.glbl_mpng_typ_cd = 'C'
    QUALIFY ROW_NUMBER() OVER (PARTITION BY t.rcvbl_id ORDER BY n.patient_id DESC) = 1
),

remittance_deposit AS (
    SELECT i.trns_id, p.dpst_dt, r.strt_dt AS dpst_fnlzd_dt, i.check_num, i.check_dt, i.dpst_id
    FROM stg_irmsods__deposit p
    INNER JOIN stg_irmsods__remittance i ON i.dpst_id = p.dpst_id
    LEFT JOIN stg_irmsods__run_log r ON p.run_id = r.run_id AND p.dpst_finlzd_flg = 'Y'
),

trns_applctn_comnt AS (
    SELECT c.trns_id, trim(regexp_replace(replace(replace(a.applctn_comnt_desc,chr(13)),chr(10),'; '),'[[:space:]]+',' ')) AS pymt_comnt
    FROM stg_irmsods__trns_comnt c
    INNER JOIN stg_irmsods__applctn_comnt a ON a.applctn_comnt_id = c.applctn_comnt_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY c.trns_id ORDER BY a.applctn_comnt_id DESC) = 1
),

trns_adjmt_rsn AS (
    SELECT a.trns_id, a.adjmt_rsn_cd || ': ' || r.adjmt_rsn_desc as adjmt_rsn
    FROM stg_irmsods__irms_trns_adjmt a
    INNER JOIN stg_irmsods__adjmt_rsn_r r ON a.adjmt_rsn_cd = r.adjmt_rsn_cd
    WHERE r.adjmt_src_syst = 'IRMS'
),

last_run AS (
    SELECT l.run_id, u.run_id AS finalized_run_id
    FROM stg_irmsods__usr_prcs_rqst u
    INNER JOIN stg_irmsods__run_log l ON l.run_id = u.rqst_val_num
    WHERE l.prcs_id = 620
    AND u.run_id > l.run_id
    AND u.rqst_typ_cd = 'FNLZ'
    AND u.cmpltd_dt IS NOT NULL
    QUALIFY ROW_NUMBER() OVER (PARTITION BY l.run_id ORDER BY u.run_id DESC) = 1
),

base_model_w_fields_added_for_various_downstream_reports AS (
    SELECT
        b.le,
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
        b.acctg_period_id,  -- Same as the acctg_period_id in transaction table? Also, why is this TO_CHAR in original? Let's find out.
        b.run_id,
        l.lgl_ent_desc as legal_entity,
        d.ns_dept_desc as ns_dept,
        cr.ns_class_desc,
        be.bus_ent_nm AS be_name,
        ae.bus_ent_nm AS ae_name,
        p.prcs_desc,
        rd.dpst_dt,
        rd.dpst_fnlzd_dt,
        CASE WHEN TRIM(pn.patnt_nm) = '' THEN NULL ELSE  pn.patnt_nm END AS  patnt_nm,
        b.mnth_of_svc AS mos,
        regexp_replace(rd.check_num,'[[:space:]]*$','') as check_num,
        rd.check_dt,
        rd.dpst_id,
        s.sec_usr_nm,
        CASE WHEN TRIM(ac.pymt_comnt) = '' THEN NULL ELSE ac.pymt_comnt END AS pymt_comnt,
        ar.adjmt_rsn,
        lr.finalized_run_id,
        NLR.NS_LCTN_DESC
    FROM gl_gnx_trns_202506_t_final_2_le5_final_final b
    LEFT JOIN stg_irmsods__lgl_ent_r l ON b.le = l.lgl_ent_cd
    LEFT JOIN ns_dept_desc_lookup d ON b.gl_acct = d.ns_gl_acct_cd
    LEFT JOIN stg_irmsods__ns_class_r cr ON b.ns_class_cd = cr.ns_class_cd
    LEFT JOIN stg_irmsods__bus_ent be ON b.be = be.bus_ent_id
    LEFT JOIN stg_irmsods__bus_ent ae ON b.ae = ae.bus_ent_id
    LEFT JOIN process_run_log p ON b.run_id = p.run_id
    LEFT JOIN sec_usr_run_log s ON b.run_id = s.run_id
    LEFT JOIN remittance_deposit rd ON b.trns_id = rd.trns_id
    LEFT JOIN trns_applctn_comnt ac ON b.trns_id = ac.trns_id
    LEFT JOIN patient_name pn ON b.rcvbl_id = pn.rcvbl_id
    LEFT JOIN trns_adjmt_rsn ar ON b.trns_id = ar.trns_id
    LEFT JOIN last_run lr ON b.run_id = lr.run_id
    LEFT JOIN stg_irmsods__ns_cc_lctn_mpng NCLM ON
		b.cc = NCLM.COST_CNTR
	LEFT JOIN stg_irmsods__ns_lctn_r NLR ON
		NLR.NS_LCTN_CD = NCLM.NS_LCTN_CD
),

final AS (
    SELECT
        b.le,
        b.rcvbl_num,
        b.amnt,
        b.be,
        b.ae,
        date(b.acctg_dt) as acctg_dt,
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
        b.acctg_period_id AS acctg_period,
        b.run_id,
        b.legal_entity,
        b.ns_dept,
        b.ns_class_desc,
        b.be_name,
        b.ae_name,
        b.prcs_desc,
        b.dpst_dt,
        b.dpst_fnlzd_dt,
        b.patnt_nm,
        b.mos,
        b.check_num,
        b.check_dt,
        b.dpst_id,
        b.sec_usr_nm,
        b.pymt_comnt,
        b.adjmt_rsn,
        b.finalized_run_id,
        b.ns_lctn_desc
    FROM base_model_w_fields_added_for_various_downstream_reports b
)

-- Final
SELECT * FROM final



















