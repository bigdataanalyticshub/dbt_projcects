{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}
with

stg_irmsods__irms_transaction as (
    select * from {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__product as (
    select * from {{ ref('stg_irmsods__product') }}
),

stg_irmsods__lob_revnu_mpng as (
    select * from {{ ref('stg_irmsods__lob_revnu_mpng') }}
    where lin_of_bus_cd = 'DMERD'
),

stg_irmsods__val_typ_bllng_calctn_mpng as (
    select * from {{ ref('stg_irmsods__val_typ_bllng_calctn_mpng') }}
),

stg_irmsods__glbl_rcvbl_mpng as (
    select * from {{ ref('stg_irmsods__glbl_rcvbl_mpng') }}
),

stg_irmsods__retro_dme_stgng_que as (
    select
        src_clm_key,
        src_clm_seq_num,
        bill_id,
        csq_status_cd
    from {{ ref('stg_irmsods__retro_dme_stgng_que') }}
    where csq_status_cd = 'C'
),

stg_irmsods__retro_dme_stgng_que_dtl as (
    select * from {{ ref('stg_irmsods__retro_dme_stgng_que_dtl') }}
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

stg_irmsods__bus_ent as (
    select * from {{ ref('stg_irmsods__bus_ent') }}
),

stg_irmsods__rollup as (
    select * from {{ source('irmsods', 'rollup') }}
),

stg_irmsods__ns_gl_acct_r as (
    select * from {{ source('irmsods', 'ns_gl_acct_r') }}
),

-- First step: Create gl_trns_rd_t equivalent
gl_trns_rd_t as (
    select
        3 as le,
        t.glbl_mpng_cd as rcvbl_num,
        t.trns_amnt as amnt,
        t.bill_to_bus_ent_id as be,
        t.bk_to_bus_ent_id as ae,
        t.acctg_dt,
        t.acctg_period_id,
        t.src_syst_cd as src,
        m.lin_of_bus_cd as lob,
        m.revnu_typ_cd as revnu,
        d.rsn_typ_cd as rsn,
        x.val_typ_cd as vt,
        x.bllng_calctn_basis_cd as bc,
        d.ns_gl_acct_cd as gl_acct,
        d.ns_class_cd,
        d.cost_cntr as cc,
        t.glbl_mpng_cd as bill_id,
        t.rcvbl_id,
        t.trns_id,
        t.xref_trns_id,
        t.trns_typ_cd,
        t.ppa_flg,
        t.irms_prodt_id
    from stg_irmsods__irms_transaction t
    join stg_irmsods__product d on t.irms_prodt_id = d.irms_prodt_id
    join stg_irmsods__lob_revnu_mpng m on d.lob_revnu_id = m.lob_revnu_id
    join stg_irmsods__val_typ_bllng_calctn_mpng x on d.val_typ_bllng_calctn_id = x.val_typ_bllng_calctn_id
    where m.lin_of_bus_cd = 'DMERD'
),

-- Update bill_id for OAC and MANR
gl_trns_rd_t_update1 as (
    select
        *,
        case
            when src in ('OAC', 'MANR') then null
            else bill_id
        end as updated_bill_id
    from gl_trns_rd_t
),

-- Get data for MANR bill_id update
manr_bill_id_data as (
    select
        m.glbl_mpng_cd as orig_glbl_mpng_cd,
        x.glbl_mpng_cd as new_bill_id,
        row_number() over (partition by m.glbl_mpng_cd order by x.glbl_mpng_cd) as rn
    from stg_irmsods__glbl_rcvbl_mpng m
    join stg_irmsods__glbl_rcvbl_mpng x on m.rcvbl_id = x.rcvbl_id
    where x.extrnl_inv_src_cd = 'UKN'
      and x.glbl_mpng_typ_cd = 'H'
),

manr_bill_id_filtered as (
    select
        orig_glbl_mpng_cd,
        new_bill_id
    from manr_bill_id_data
    where rn = 1
),

-- Get data for MCPS bill_id update
mcps_bill_id_data as (
    select
        q.src_clm_key,
        q.bill_id,
        row_number() over (partition by q.src_clm_key order by q.bill_id) as rn
    from stg_irmsods__retro_dme_stgng_que q
    where q.csq_status_cd = 'C'
),

mcps_bill_id_filtered as (
    select
        src_clm_key,
        bill_id
    from mcps_bill_id_data
    where rn = 1
),

-- Update bill_id for MANR and MCPS
gl_trns_rd_t_update2 as (
    select
        t.*,
        case
            when t.src = 'MANR' and t.updated_bill_id is null then m.new_bill_id
            when t.src = 'MCPS' and t.updated_bill_id is null then mc.bill_id
            else t.updated_bill_id
        end as final_bill_id
    from gl_trns_rd_t_update1 t
    left join manr_bill_id_filtered m on t.rcvbl_num = m.orig_glbl_mpng_cd
    left join mcps_bill_id_filtered mc on t.rcvbl_num = mc.src_clm_key
),

-- Get je_catg for each gl_acct
gl_acct_je_catg as (
    select
        ns_gl_acct_cd,
        je_catg
    from stg_irmsods__ns_gl_acct_r
),

-- Optimize by pre-joining retro_dme_stgng_que_dtl
retro_dme_joined as (
    select
        l.trns_id,
        l.bill_ln_itm_id,
        l.svc_itm_ln_ordr,
        l.med_cd,
        l.src_clm_seq_num,
        l.src_clm_key
    from stg_irmsods__retro_dme_stgng_que_dtl l
),

-- Create gl_trns_rd_t2 equivalent - part 1 (records with matching retro_dme_stgng_que_dtl)
gl_trns_rd_t2_part1 as (
    select
        x.rcvbl_num,
        x.final_bill_id as bill_id,
        l.bill_ln_itm_id,
        l.svc_itm_ln_ordr,
        l.med_cd,
        x.be as trns_be,
        0 as ru_be,
        x.ae,
        x.acctg_dt,
        x.acctg_period_id,
        x.src,
        l.src_clm_seq_num as seq,
        x.lob,
        x.revnu,
        x.rsn,
        x.gl_acct,
        x.ns_class_cd as cls,
        x.rcvbl_id,
        x.trns_id,
        x.xref_trns_id,
        x.amnt,
        x.le,
        x.trns_typ_cd,
        r.je_catg
    from gl_trns_rd_t_update2 x
    join retro_dme_joined l on x.trns_id = l.trns_id
    join gl_acct_je_catg r on x.gl_acct = r.ns_gl_acct_cd
),

-- Create gl_trns_rd_t2 equivalent - part 2 (records without matching retro_dme_stgng_que_dtl)
not_in_retro_dme as (
    select x.trns_id
    from gl_trns_rd_t_update2 x
    left join retro_dme_joined l on x.trns_id = l.trns_id
    where l.trns_id is null
),

gl_trns_rd_t2_part2 as (
    select
        x.rcvbl_num,
        x.final_bill_id as bill_id,
        'NA' as bill_ln_itm_id,
        0 as svc_itm_ln_ordr,
        'NA' as med_cd,
        x.be as trns_be,
        0 as ru_be,
        x.ae,
        x.acctg_dt,
        x.acctg_period_id,
        x.src,
        null as seq,
        x.lob,
        x.revnu,
        x.rsn,
        x.gl_acct,
        x.ns_class_cd as cls,
        x.rcvbl_id,
        x.trns_id,
        x.xref_trns_id,
        x.amnt,
        x.le,
        x.trns_typ_cd,
        r.je_catg
    from gl_trns_rd_t_update2 x
    join gl_acct_je_catg r on x.gl_acct = r.ns_gl_acct_cd
    join not_in_retro_dme nir on x.trns_id = nir.trns_id
),

-- Create gl_trns_rd_t2 equivalent - part 3 (all other records)
gl_trns_rd_t2_part3 as (
    select
        x.rcvbl_num,
        x.final_bill_id as bill_id,
        'NA' as bill_ln_itm_id,
        0 as svc_itm_ln_ordr,
        'NA' as med_cd,
        x.be as trns_be,
        0 as ru_be,
        x.ae,
        x.acctg_dt,
        x.acctg_period_id,
        x.src,
        null as seq,
        x.lob,
        x.revnu,
        x.rsn,
        x.gl_acct,
        x.ns_class_cd as cls,
        x.rcvbl_id,
        x.trns_id,
        x.xref_trns_id,
        x.amnt,
        x.le,
        r.je_catg
    from gl_trns_rd_t_update2 x
    join gl_acct_je_catg r on x.gl_acct = r.ns_gl_acct_cd
),

-- Combine all parts to create gl_trns_rd_t2
gl_trns_rd_t2_combined as (
    select * from gl_trns_rd_t2_part1
    union all
    select * from gl_trns_rd_t2_part2
),

-- Update bill_ln_itm_id, svc_itm_ln_ordr, med_cd for je_catg = 'A'
je_catg_a_update_data as (
    select
        x.trns_id,
        case when x.src = 'MANR' then l2.bill_ln_itm_id else 'NA' end as updated_bill_ln_itm_id,
        l2.svc_itm_ln_ordr as updated_svc_itm_ln_ordr,
        l2.med_cd as updated_med_cd
    from gl_trns_rd_t2_combined x
    join gl_trns_rd_t_update2 t2 on x.trns_id = t2.trns_id
    join retro_dme_joined l2 on t2.trns_id = l2.trns_id
    where x.je_catg = 'A'
),

-- Update bill_ln_itm_id, svc_itm_ln_ordr, med_cd for je_catg = 'C'
je_catg_c_update_data as (
    select
        x.trns_id,
        case when x.src = 'MANR' then l2.bill_ln_itm_id else 'NA' end as updated_bill_ln_itm_id,
        l2.svc_itm_ln_ordr as updated_svc_itm_ln_ordr,
        l2.med_cd as updated_med_cd
    from gl_trns_rd_t2_combined x
    join gl_trns_rd_t_update2 t2 on x.trns_id = t2.trns_id
    join retro_dme_joined l2 on t2.xref_trns_id = l2.trns_id
    where x.je_catg = 'C'
),

-- Update bill_ln_itm_id, svc_itm_ln_ordr, med_cd for je_catg = 'B'
je_catg_b_update_data as (
    select
        x.trns_id,
        case when x.src = 'MANR' then l2.bill_ln_itm_id else 'NA' end as updated_bill_ln_itm_id,
        l2.svc_itm_ln_ordr as updated_svc_itm_ln_ordr,
        l2.med_cd as updated_med_cd
    from gl_trns_rd_t2_combined x
    join gl_trns_rd_t_update2 t2 on x.trns_id = t2.trns_id
    join retro_dme_joined l2 on t2.xref_trns_id = l2.trns_id
    where x.je_catg = 'B'
),

-- Combine all updates
all_updates as (
    select
        trns_id,
        updated_bill_ln_itm_id,
        updated_svc_itm_ln_ordr,
        updated_med_cd
    from je_catg_a_update_data

    union all

    select
        trns_id,
        updated_bill_ln_itm_id,
        updated_svc_itm_ln_ordr,
        updated_med_cd
    from je_catg_c_update_data

    union all

    select
        trns_id,
        updated_bill_ln_itm_id,
        updated_svc_itm_ln_ordr,
        updated_med_cd
    from je_catg_b_update_data
),

-- Aggregate updates
agg_updates as (
    select
        trns_id,
        max(updated_bill_ln_itm_id) as updated_bill_ln_itm_id,
        max(updated_svc_itm_ln_ordr) as updated_svc_itm_ln_ordr,
        max(updated_med_cd) as updated_med_cd
    from all_updates
    group by trns_id
),

-- Apply all updates to gl_trns_rd_t2
gl_trns_rd_t2_updated as (
    select
        t.*,
        coalesce(u.updated_bill_ln_itm_id,
                case when t.bill_ln_itm_id is null then 'NA' else t.bill_ln_itm_id end) as final_bill_ln_itm_id,
        coalesce(u.updated_svc_itm_ln_ordr,
                case when t.svc_itm_ln_ordr is null then 0 else t.svc_itm_ln_ordr end) as final_svc_itm_ln_ordr,
        coalesce(u.updated_med_cd,
                case when t.med_cd is null then 'NA' else t.med_cd end) as final_med_cd
    from gl_trns_rd_t2_combined t
    left join agg_updates u on t.trns_id = u.trns_id
),

-- Get rollup data for level 2
rollup_level_2 as (
    select
        child_num as ae,
        parnt_num as ru_be
    from stg_irmsods__rollup
    where purps_id = 2
      and rollup_lvl = 2
      and trmntn_dt is null
),

-- Get rollup data for level 1
rollup_level_1 as (
    select
        child_num as ae,
        child_num as ru_be
    from stg_irmsods__rollup
    where purps_id = 2
      and rollup_lvl = 1
      and trmntn_dt is null
),

-- Apply ru_be updates with level 2
gl_trns_rd_t2_with_level2 as (
    select
        t.*,
        r2.ru_be as level2_ru_be
    from gl_trns_rd_t2_updated t
    left join rollup_level_2 r2 on t.ae = r2.ae
),

-- Apply ru_be updates with level 1
gl_trns_rd_t2_final as (
    select
        t.*,
        coalesce(t.level2_ru_be, r1.ru_be, t.ru_be) as final_ru_be
    from gl_trns_rd_t2_with_level2 t
    left join rollup_level_1 r1 on t.ae = r1.ae
),

-- Get department description
ns_dept_data as (
    select
        dm.ns_gl_acct_cd,
        dr.ns_dept_desc
    from stg_irmsods__ns_dept_mpng dm
    join stg_irmsods__ns_dept_r dr on dm.ns_dept_cd = dr.ns_dept_cd
),

-- Pre-join department and class descriptions
enriched_data as (
    select
        z.*,
        l.lgl_ent_desc as legal_entity,
        be.bus_ent_nm as be_name,
        ae.bus_ent_nm as ae_name,
        nd.ns_dept_desc as ns_dept,
        nc.ns_class_desc
    from gl_trns_rd_t2_final z
    left join stg_irmsods__lgl_ent_r l on z.le = l.lgl_ent_cd
    left join stg_irmsods__bus_ent be on z.final_ru_be = be.bus_ent_id
    left join stg_irmsods__bus_ent ae on z.ae = ae.bus_ent_id
    left join ns_dept_data nd on z.gl_acct = nd.ns_gl_acct_cd
    left join stg_irmsods__ns_class_r nc on z.cls = nc.ns_class_cd
    where z.amnt != 0
),

-- Final output
final as (
    select
        legal_entity,
        le,
        rcvbl_num,
        amnt,
        final_ru_be as ru_be,
        be_name,
        ae,
        ae_name,
        acctg_dt,
        acctg_period_id,
        src,
        lob,
        revnu,
        rsn,
        gl_acct,
        ns_dept,
        cls as ns_class,
        ns_class_desc,
        bill_id,
        final_bill_ln_itm_id as line_item_id,
        final_svc_itm_ln_ordr as line_num,
        final_med_cd as med_cd,
        trns_typ_cd,
        rcvbl_id
    from enriched_data
)

select * from final
order by rcvbl_num, line_num, revnu, gl_acct desc