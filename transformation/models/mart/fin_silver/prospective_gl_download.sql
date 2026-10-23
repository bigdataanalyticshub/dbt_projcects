{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

WITH
-- Import CTEs
stg_irmsods__irms_transaction AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__irms_receivable AS (
    SELECT * FROM {{ ref('stg_irmsods__irms_receivable') }}
),

stg_irmsods__lob_revnu_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__product AS (
    SELECT * FROM {{ ref('stg_irmsods__product') }}
),

stg_irmsods__glbl_rcvbl_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__glbl_rcvbl_mpng') }}
),

stg_irmsods__retro_dme_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__retro_dme_stgng_que') }}
),

stg_irmsods__val_typ_bllng_calctn_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__val_typ_bllng_calctn_mpng') }}
),

stg_irmsods__dme_clm_stgng_que AS (
    SELECT * FROM {{ ref('stg_irmsods__dme_clm_stgng_que') }}
),

stg_irmsods__bus_ent AS (
    SELECT * FROM {{ ref('stg_irmsods__bus_ent') }}
),
stg_irmsods__lgl_ent_r AS (
    SELECT * FROM {{ ref('stg_irmsods__lgl_ent_r') }}
),

stg_irmsods__ns_dept_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_dept_r') }}
),

stg_irmsods__ns_class_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__ns_lctn_r AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_lctn_r') }}
),

stg_irmsods__ns_dept_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_dept_mpng') }}
),

stg_irmsods__ns_cc_lctn_mpng AS (
    SELECT * FROM {{ ref('stg_irmsods__ns_cc_lctn_mpng') }}
),

source_transactions as (
    select
        2 as le,
        t.glbl_mpng_cd as rcvbl_num,
        t.trns_amnt as amnt,
        t.bill_to_bus_ent_id as be,
        t.bk_to_bus_ent_id as ae,
        t.acctg_dt,
        t.src_syst_cd as src,
        m.lin_of_bus_cd as lob,
        m.revnu_typ_cd as revnu,
        d.rsn_typ_cd as rsn,
        x.val_typ_cd as vt,
        x.bllng_calctn_basis_cd as bc,
        d.ns_gl_acct_cd as gl_acct,
        d.ns_class_cd,
        d.cost_cntr as cc,
        t.mnth_of_svc as mos,
        t.glbl_mpng_cd as bill_id,
        t.glbl_mpng_cd as svc_item_id,
        t.rcvbl_id,
        t.trns_id,
        t.xref_trns_id,
        t.trns_typ_cd,
        t.ppa_flg,
        t.irms_prodt_id,
        t.run_id,
        t.acctg_period_id
    from stg_irmsods__irms_transaction t
    join stg_irmsods__product d on t.irms_prodt_id = d.irms_prodt_id
    join stg_irmsods__lob_revnu_mpng m on d.lob_revnu_id = m.lob_revnu_id
    join stg_irmsods__val_typ_bllng_calctn_mpng x on d.val_typ_bllng_calctn_id = x.val_typ_bllng_calctn_id
    where --t.acctg_period_id = 202505
     m.lin_of_bus_cd = 'DMESLF'
),

base_data as (
    select
        t.*,
        null as med_cd,
        null as svc_typ,
        null as paid_qty,
        null as clm_num,
        null as patnt_first_nm,
        null as patnt_last_nm,
        null as jur_st,
        null as bill_date,
        null as svc_item_desc,
        null as client_billed_amt
    from source_transactions t
),

update_bill_id_for_oac_manr as (
    select
        t.*,
        case when t.src in ('OAC', 'MANR') then null else t.bill_id end as bill_id_1
    from base_data t
),

update_manr_before_march as (
    select
        t.*,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.bill_id
            else t.bill_id_1
        end as bill_id_2,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then null
            else t.svc_item_id
        end as svc_item_id_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then null
            else t.med_cd
        end as med_cd_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then trim(q.dme_type)
            else t.svc_typ
        end as svc_typ_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.clm_num
            else t.clm_num
        end as clm_num_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.patnt_first_nm
            else t.patnt_first_nm
        end as patnt_first_nm_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.patnt_last_nm
            else t.patnt_last_nm
        end as patnt_last_nm_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.jursdctn_state_cd
            else t.jur_st
        end as jur_st_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.create_date
            else t.bill_date
        end as bill_date_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.svc_item_desc
            else t.svc_item_desc
        end as svc_item_desc_1,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt < '2024-03-01'
            then q.fee_sched_price
            else t.client_billed_amt
        end as client_billed_amt_1
    from update_bill_id_for_oac_manr t
    left join (
        select distinct
            g.glbl_mpng_cd,
            q.bill_id,
            q.dme_type,
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        from stg_irmsods__dme_clm_stgng_que q
        join (
            select
                replace(replace(x.glbl_mpng_cd, chr(13), ''), chr(10), '') as glbl_mpng_cd
            from stg_irmsods__glbl_rcvbl_mpng m
            join stg_irmsods__glbl_rcvbl_mpng x on m.rcvbl_id = x.rcvbl_id
            where trim(x.extrnl_inv_src_cd) = 'UKN'
            and trim(x.glbl_mpng_typ_cd) = 'H'
        ) g on g.glbl_mpng_cd = q.src_clm_key
        qualify row_number() over (partition by g.glbl_mpng_cd order by g.glbl_mpng_cd) = 1
    ) q on q.glbl_mpng_cd = t.rcvbl_num and t.trns_typ_cd = 'M' and t.src = 'MANR'
    --and t.acctg_dt < '2024-03-01'
),

update_manr_non_m_before_march as (
    select
        t.*,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.bill_id
            else t.bill_id_2
        end as bill_id_3,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then null
            else t.svc_item_id_1
        end as svc_item_id_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then null
            else t.med_cd_1
        end as med_cd_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then trim(q.dme_type)
            else t.svc_typ_1
        end as svc_typ_2,
        t.paid_qty as paid_qty_1,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.clm_num
            else t.clm_num_1
        end as clm_num_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.patnt_first_nm
            else t.patnt_first_nm_1
        end as patnt_first_nm_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.patnt_last_nm
            else t.patnt_last_nm_1
        end as patnt_last_nm_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.jursdctn_state_cd
            else t.jur_st_1
        end as jur_st_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.create_date
            else t.bill_date_1
        end as bill_date_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.svc_item_desc
            else t.svc_item_desc_1
        end as svc_item_desc_2,
        case
            when t.trns_typ_cd != 'M' and t.src = 'MANR' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt < '2024-03-01'
            ) then q.fee_sched_price
            else t.client_billed_amt_1
        end as client_billed_amt_2
    from update_manr_before_march t
    left join (
        select distinct
            g.glbl_mpng_cd,
            g.rcvbl_id,
            q.bill_id,
            q.dme_type,
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        from stg_irmsods__dme_clm_stgng_que q
        join (
            select
                replace(replace(m.glbl_mpng_cd, chr(13), ''), chr(10), '') as glbl_mpng_cd,
                m.rcvbl_id
            from stg_irmsods__glbl_rcvbl_mpng m
            where trim(m.extrnl_inv_src_cd) = 'UKN'
            and trim(m.glbl_mpng_typ_cd) = 'H'
        ) g on g.glbl_mpng_cd = q.src_clm_key
        qualify row_number() over (partition by g.rcvbl_id order by g.rcvbl_id) = 1
    ) q on q.rcvbl_id = t.rcvbl_id and t.trns_typ_cd != 'M' and t.src = 'MANR'
),

update_manr_after_march as (
    select
        t.*,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.bill_id
            else t.bill_id_3
        end as bill_id_4,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.svc_item_id
            else t.svc_item_id_2
        end as svc_item_id_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.svc_item_cd
            else t.med_cd_2
        end as med_cd_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then trim(q.dme_type)
            else t.svc_typ_2
        end as svc_typ_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.paid_qty
            else t.paid_qty_1
        end as paid_qty_2,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.clm_num
            else t.clm_num_2
        end as clm_num_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.patnt_first_nm
            else t.patnt_first_nm_2
        end as patnt_first_nm_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.patnt_last_nm
            else t.patnt_last_nm_2
        end as patnt_last_nm_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.jursdctn_state_cd
            else t.jur_st_2
        end as jur_st_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.create_date
            else t.bill_date_2
        end as bill_date_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.svc_item_desc
            else t.svc_item_desc_2
        end as svc_item_desc_3,
        case
            when t.trns_typ_cd = 'M' and t.src = 'MANR'
            --and t.acctg_dt >= '2024-03-01'
            then q.fee_sched_price
            else t.client_billed_amt_2
        end as client_billed_amt_3
    from update_manr_non_m_before_march t
    left join (
        select
            g.glbl_mpng_cd,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type) as dme_type,
            sum(to_number(q.paid_qty)) as paid_qty,
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        from stg_irmsods__dme_clm_stgng_que q
        join (
            select
                replace(replace(x.glbl_mpng_cd, chr(13), ''), chr(10), '') as glbl_mpng_cd
            from stg_irmsods__glbl_rcvbl_mpng m
            join stg_irmsods__glbl_rcvbl_mpng x on m.rcvbl_id = x.rcvbl_id
            where trim(x.extrnl_inv_src_cd) = 'UKN'
            and trim(x.glbl_mpng_typ_cd) = 'H'
        ) g on g.glbl_mpng_cd = q.src_clm_key
        group by
            g.glbl_mpng_cd,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type),
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        qualify row_number() over (partition by g.glbl_mpng_cd order by g.glbl_mpng_cd) = 1
    ) q on q.glbl_mpng_cd = t.rcvbl_num and t.trns_typ_cd = 'M' and t.src = 'MANR'
    --and t.acctg_dt >= '2024-03-01'
),

update_slsf_after_march as (
    select
        t.*,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.bill_id
            else t.bill_id_4
        end as bill_id_5,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.svc_item_id
            else t.svc_item_id_3
        end as svc_item_id_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.svc_item_cd
            else t.med_cd_3
        end as med_cd_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then trim(q.dme_type)
            else t.svc_typ_3
        end as svc_typ_4,
        t.paid_qty_2 as paid_qty_3,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.clm_num
            else t.clm_num_3
        end as clm_num_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.patnt_first_nm
            else t.patnt_first_nm_3
        end as patnt_first_nm_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.patnt_last_nm
            else t.patnt_last_nm_3
        end as patnt_last_nm_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.jursdctn_state_cd
            else t.jur_st_3
        end as jur_st_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.create_date
            else t.bill_date_3
        end as bill_date_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.svc_item_desc
            else t.svc_item_desc_3
        end as svc_item_desc_4,
        case
            when t.trns_typ_cd != 'M' and t.src = 'SLSF' and exists (
                select 1
                from stg_irmsods__irms_transaction x
                where x.rcvbl_id = t.rcvbl_id
                and x.trns_typ_cd = 'M'
                --and x.acctg_dt >= '2024-03-01'
            ) then q.fee_sched_price
            else t.client_billed_amt_3
        end as client_billed_amt_4
    from update_manr_after_march t
    left join (
        select
            g.glbl_mpng_cd,
            g.rcvbl_id,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type) as dme_type,
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        from stg_irmsods__dme_clm_stgng_que q
        join (
            select
                replace(replace(m.glbl_mpng_cd, chr(13), ''), chr(10), '') as glbl_mpng_cd,
                m.rcvbl_id
            from stg_irmsods__glbl_rcvbl_mpng m
            where trim(m.extrnl_inv_src_cd) = 'UKN'
            and trim(m.glbl_mpng_typ_cd) = 'H'
        ) g on g.glbl_mpng_cd = q.src_clm_key
        group by
            g.glbl_mpng_cd,
            g.rcvbl_id,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type),
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        qualify row_number() over (partition by g.rcvbl_id order by g.rcvbl_id) = 1
    ) q on q.rcvbl_id = t.rcvbl_id and t.trns_typ_cd != 'M' and t.src = 'SLSF'
),

update_slsf_c_after_march as (
    select
        t.*,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF'  then q.bill_id
            else t.bill_id_5
        end as bill_id_6,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF' then q.svc_item_id
            else t.svc_item_id_4
        end as svc_item_id_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF' then q.svc_item_cd
            else t.med_cd_4
        end as med_cd_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF' then trim(q.dme_type)
            else t.svc_typ_4
        end as svc_typ_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF'  then q.paid_qty
            else t.paid_qty_3
        end as paid_qty_4,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF'  then q.clm_num
            else t.clm_num_4
        end as clm_num_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF'  then q.patnt_first_nm
            else t.patnt_first_nm_4
        end as patnt_first_nm_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF'  then q.patnt_last_nm
            else t.patnt_last_nm_4
        end as patnt_last_nm_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF' then q.jursdctn_state_cd
            else t.jur_st_4
        end as jur_st_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF' then q.create_date
            else t.bill_date_4
        end as bill_date_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF' then q.svc_item_desc
            else t.svc_item_desc_4
        end as svc_item_desc_5,
        case
            when t.trns_typ_cd = 'C' and t.src = 'SLSF' then q.fee_sched_price
            else t.client_billed_amt_4
        end as client_billed_amt_5
    from update_slsf_after_march t
    left join (
        select
            q.src_clm_key,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type) as dme_type,
            sum(to_number(q.paid_qty)) as paid_qty,
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        from stg_irmsods__dme_clm_stgng_que q
        --where q.acctg_period_id = 202505
        group by
            q.src_clm_key,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type),
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        qualify row_number() over (partition by q.src_clm_key order by q.src_clm_key) = 1
    ) q on q.src_clm_key = t.rcvbl_num and t.trns_typ_cd = 'C' and t.src = 'SLSF'
    --and t.acctg_dt >= '2024-03-01'
),

update_slsf_other as (
    select
        t.*,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.bill_id
            else t.bill_id_6
        end as updated_bill_id,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.svc_item_id
            else t.svc_item_id_5
        end as  updated_svc_item_id,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.svc_item_cd
            else t.med_cd_5
        end as updated_med_cd,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then trim(q.dme_type)
            else t.svc_typ_5
        end as updated_svc_typ,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.paid_qty
            else t.paid_qty_4
        end as updated_paid_qty,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.clm_num
            else t.clm_num_5
        end as updated_clm_num,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.patnt_first_nm
            else t.patnt_first_nm_5
        end as updated_patnt_first_nm,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.patnt_last_nm
            else t.patnt_last_nm_5
        end as updated_patnt_last_nm,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.jursdctn_state_cd
            else t.jur_st_5
        end as updated_jur_st,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.create_date
            else t.bill_date_5
        end as updated_bill_date,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.svc_item_desc
            else t.svc_item_desc_5
        end as updated_svc_item_desc,
        case
            when t.trns_typ_cd != 'C' and t.src = 'SLSF' then q.fee_sched_price
            else t.client_billed_amt_5
        end as updated_client_billed_amt
    from update_slsf_c_after_march t
    left join (
        select
            q.src_clm_key,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type) as dme_type,
            sum(to_number(q.paid_qty)) as paid_qty,
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        from stg_irmsods__dme_clm_stgng_que q
        --where q.acctg_period_id = 202505
        group by
            q.src_clm_key,
            q.bill_id,
            q.svc_item_id,
            q.svc_item_cd,
            trim(q.dme_type),
            q.clm_num,
            q.patnt_first_nm,
            q.patnt_last_nm,
            q.jursdctn_state_cd,
            q.create_date,
            q.svc_item_desc,
            q.fee_sched_price
        qualify row_number() over (partition by q.src_clm_key order by q.src_clm_key) = 1
    ) q on q.src_clm_key = t.rcvbl_num and t.trns_typ_cd != 'C' and t.src = 'SLSF'
),

final_data as (
    select
        l.lgl_ent_desc as legal_entity,
        t.le,
        t.rcvbl_num,
        t.amnt,
        t.be,
        be.bus_ent_nm as be_name,
        t.ae,
        ae.bus_ent_nm as ae_name,
        t.acctg_dt,
        t.src,
        t.lob,
        t.revnu,
        t.rsn,
        t.vt,
        t.bc,
        t.gl_acct,
        dr.ns_dept_desc as ns_dept,
        t.ns_class_cd,
        cr.ns_class_desc as ns_class_desc,
        t.cc,
        lr.ns_lctn_desc as ns_lctn,
        t.updated_bill_id as bill_id,
        t.updated_svc_item_id as svc_item_id,
        t.updated_med_cd as rx_code,
        t.updated_paid_qty as paid_qty,
        t.updated_clm_num as clm_num,
        t.updated_patnt_first_nm as patnt_first_nm,
        t.updated_patnt_last_nm as patnt_last_nm,
        t.updated_jur_st as jur_st,
        t.updated_svc_typ as svc_typ,
        t.updated_bill_date as bill_date,
        t.updated_svc_item_desc as svc_item_desc,
        t.updated_client_billed_amt as client_billed_amt,
        t.trns_typ_cd,
        t.trns_id,
        t.run_id,
        t.acctg_period_id
    from update_slsf_other t
    join stg_irmsods__bus_ent be on t.be = be.bus_ent_id
    left join stg_irmsods__lgl_ent_r l on t.le = l.lgl_ent_cd
    left join stg_irmsods__bus_ent ae on t.ae = ae.bus_ent_id
    left join stg_irmsods__ns_dept_mpng dm on t.gl_acct = dm.ns_gl_acct_cd
    left join stg_irmsods__ns_dept_r dr on dm.ns_dept_cd = dr.ns_dept_cd
    left join stg_irmsods__ns_class_r cr on t.ns_class_cd = cr.ns_class_cd
    left join stg_irmsods__ns_cc_lctn_mpng cl on t.cc = cl.cost_cntr
    left join stg_irmsods__ns_lctn_r lr on cl.ns_lctn_cd = lr.ns_lctn_cd
    where t.le = 2
    and t.amnt != 0
)

select * from final_data