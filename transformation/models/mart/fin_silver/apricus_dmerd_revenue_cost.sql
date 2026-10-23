{{
    config(
        materialized='table',
        tags=['fin_silver_daily']
    )
}}

{% set ACCTG_START_DT = modules.datetime.date(2023, 4, 1) %}
{% set ACCTG_END_DT = modules.datetime.date(2050, 12, 31) %}

with

stg_irmsods__irms_transaction as (
    select * from {{ ref('stg_irmsods__irms_transaction') }}
),

stg_irmsods__irms_receivable as (
    select * from {{ ref('stg_irmsods__irms_receivable') }}
),

stg_irmsods__product as (
    select * from {{ ref('stg_irmsods__product') }}
),

stg_irmsods__lob_revnu_mpng as (
    select * from {{ ref('stg_irmsods__lob_revnu_mpng') }}
),

stg_irmsods__glbl_rcvbl_mpng as (
    select * from {{ ref('stg_irmsods__glbl_rcvbl_mpng') }}
),

stg_irmsods__ns_class_r as (
    select * from {{ ref('stg_irmsods__ns_class_r') }}
),

stg_irmsods__dme_rcvbl_po_mpng as (
    select * from {{ ref('stg_irmsods__dme_rcvbl_po_mpng') }}
),

stg_irmsods__retro_dme_stgng_que as (
    select * from {{ ref('stg_irmsods__retro_dme_stgng_que') }}
),

stg_irmsods__retro_dme_stgng_que_dtl as (
    select * from {{ ref('stg_irmsods__retro_dme_stgng_que_dtl') }}
),

stg_irmsods__bus_ent as (
    select * from {{ ref('stg_irmsods__bus_ent') }}
),

-- Base transaction data
trns_revenue_dme as (
    select
        t.trns_id,
        t.xref_trns_id,
        t.run_id,
        t.bill_to_bus_ent_id as be_id,
        t.bk_to_bus_ent_id as ae_id,
        t.acctg_period_id as acctg_period,
        t.glbl_mpng_cd,
        t.src_syst_cd,
        t.trns_amnt,
        t.acctg_dt,
        r.lin_of_bus_cd as lob,
        d.rsn_typ_cd as reason_typ,
        d.ns_gl_acct_cd as gl_accnt,
        d.ns_class_cd,
        m.revnu_typ_cd as revenue_typ,
        case when d.ns_gl_acct_cd = '4230' then t.trns_id else t.xref_trns_id end as grp_trns_id,
        null::varchar(20) as curr_clm_key,
        null::varchar(200) as ns_class_desc,
        null::date as acctg_dte,
        null::date as inv_blld_dt,
        null::bigint as rcvbl_po_id,
        0 as seq
    from stg_irmsods__irms_transaction t
    join stg_irmsods__irms_receivable r on t.rcvbl_id = r.rcvbl_id
    join stg_irmsods__product d on d.irms_prodt_id = t.irms_prodt_id
    join stg_irmsods__lob_revnu_mpng m on d.lob_revnu_id = m.lob_revnu_id
    where r.lin_of_bus_cd = 'DMERD'
      and d.ns_gl_acct_cd in ('4230','5130','5130RD')
),

-- Prepare data for curr_clm_key update
glbl_rcvbl_mpng_data as (
    select
        m.glbl_mpng_cd as orig_glbl_mpng_cd,
        max(x.glbl_mpng_cd) as new_curr_clm_key
    from stg_irmsods__glbl_rcvbl_mpng m
    join stg_irmsods__glbl_rcvbl_mpng x on m.rcvbl_id = x.rcvbl_id
    join stg_irmsods__irms_receivable r on x.rcvbl_id = r.rcvbl_id
    where m.glbl_mpng_typ_cd = 'B'
      and x.extrnl_inv_src_cd = 'UKN'
      and x.glbl_mpng_typ_cd = 'H'
      and r.lin_of_bus_cd = 'DMERD'
    group by m.glbl_mpng_cd
),

-- Update curr_clm_key
curr_clm_key_applied as (
    select
        tr.*,
        case
            when tr.src_syst_cd = 'MANR' and tr.curr_clm_key is null then grm.new_curr_clm_key
            else tr.curr_clm_key
        end as final_curr_clm_key
    from trns_revenue_dme tr
    left join glbl_rcvbl_mpng_data grm on grm.orig_glbl_mpng_cd = tr.glbl_mpng_cd
),

-- Update ns_class_desc
ns_class_desc_applied as (
    select
        tr.*,
        case when tr.ns_class_desc is null then cr.ns_class_desc else tr.ns_class_desc end as final_ns_class_desc
    from curr_clm_key_applied tr
    left join stg_irmsods__ns_class_r cr on cr.ns_class_cd = tr.ns_class_cd
),

-- Prepare data for acctg_dte update
min_acctg_dt_data as (
    select
        glbl_mpng_cd,
        src_syst_cd,
        min(acctg_dt) as min_acctg_dt
    from stg_irmsods__irms_transaction
    group by glbl_mpng_cd, src_syst_cd
),

-- Update acctg_dte
acctg_dte_applied as (
    select
        tr.*,
        case when tr.acctg_dte is null then mad.min_acctg_dt else tr.acctg_dte end as final_acctg_dte
    from ns_class_desc_applied tr
    left join min_acctg_dt_data mad on mad.glbl_mpng_cd = tr.glbl_mpng_cd and mad.src_syst_cd = tr.src_syst_cd
),

-- Prepare data for rcvbl_po_id update
max_po_id_data as (
    select
        rcvbl_num,
        max(po_id) as max_po_id
    from stg_irmsods__dme_rcvbl_po_mpng
    group by rcvbl_num
),

-- Update rcvbl_po_id
rcvbl_po_id_applied as (
    select
        tr.*,
        case when tr.rcvbl_po_id is null then mpd.max_po_id else tr.rcvbl_po_id end as final_rcvbl_po_id
    from acctg_dte_applied tr
    left join max_po_id_data mpd on mpd.rcvbl_num = tr.glbl_mpng_cd
),

-- Prepare data for seq update
max_seq_data as (
    select
        src_clm_key,
        max(src_clm_seq_num) as max_seq
    from stg_irmsods__retro_dme_stgng_que
    where csq_status_cd = 'C'
    group by src_clm_key
),

-- Update seq
seq_applied as (
    select
        tr.*,
        case
            when tr.curr_clm_key is null and tr.src_syst_cd not in ('OAC') then coalesce(msd.max_seq, tr.seq)
            else tr.seq
        end as final_seq
    from rcvbl_po_id_applied tr
    left join max_seq_data msd on msd.src_clm_key = tr.glbl_mpng_cd
),

-- Prepare data for inv_blld_dt update
min_inv_blld_dt_data as (
    select
        src_clm_key,
        min(inv_blld_dt) as min_inv_blld_dt
    from stg_irmsods__retro_dme_stgng_que
    where csq_status_cd = 'C'
    group by src_clm_key
),

-- Update inv_blld_dt
inv_blld_dt_applied as (
    select
        tr.*,
        case
            when tr.inv_blld_dt is null and tr.src_syst_cd not in ('OAC') then
                coalesce(mid_curr.min_inv_blld_dt, mid_glbl.min_inv_blld_dt)
            else tr.inv_blld_dt
        end as final_inv_blld_dt
    from seq_applied tr
    left join min_inv_blld_dt_data mid_curr on mid_curr.src_clm_key = tr.final_curr_clm_key
    left join min_inv_blld_dt_data mid_glbl on mid_glbl.src_clm_key = tr.glbl_mpng_cd
),

-- Prepare data for retro_dme_stgng_que
retro_dme_stgng_que_data as (
    select
        src_clm_key,
        max(wc_clm_id) as wc_clm_id,
        max(emplyr_nm) as emplyr_nm,
        max(clm_num) as clm_num,
        max(trim(patnt_first_nm)) as patnt_first_nm,
        max(trim(patnt_last_nm)) as patnt_last_nm,
        -- Create a combined patient name field
        max(trim(patnt_first_nm) || ' ' || trim(patnt_last_nm)) as patient_name,
        max(jursdctn_state_cd) as jursdctn_state_cd,
        max(inj_dt) as inj_dt,
        max(po_svc_typ) as po_svc_typ,
        max(po_id) as po_id,
        max(orig_clnt_bill_id) as orig_clnt_bill_id
    from stg_irmsods__retro_dme_stgng_que
    where csq_status_cd = 'C'
    group by src_clm_key
),

-- Create trns_revenue_dme_stg_t
trns_revenue_dme_stg as (
    select
        tr.*,
        coalesce(h.emplyr_nm, m.emplyr_nm) as employer,
        coalesce(h.clm_num, m.clm_num) as claim_num,
        coalesce(h.patnt_first_nm, m.patnt_first_nm) as patnt_first_nm,
        coalesce(h.patnt_last_nm, m.patnt_last_nm) as patnt_last_nm,
        coalesce(h.patient_name, m.patient_name) as patient_name,
        coalesce(h.jursdctn_state_cd, m.jursdctn_state_cd) as soj,
        coalesce(h.inj_dt, m.inj_dt) as injury_dt,
        coalesce(h.po_svc_typ, m.po_svc_typ) as po_svc_typ,
        coalesce(h.po_id, m.po_id) as po_id,
        coalesce(h.orig_clnt_bill_id, m.orig_clnt_bill_id) as mic_bill_id,
        coalesce(h.wc_clm_id, m.wc_clm_id) as wc_claim_id
    from inv_blld_dt_applied tr
    left join retro_dme_stgng_que_data h on h.src_clm_key = tr.final_curr_clm_key
    left join retro_dme_stgng_que_data m on m.src_clm_key = tr.glbl_mpng_cd
),

-- Prepare data for retro_dme_stgng_que_dtl
retro_dme_stgng_que_dtl_data as (
    select
        trns_id,
        src_clm_key,
        max(src_clm_seq_num) as src_clm_seq_num,
        max(svc_dt_from) as svc_dt_from,
        max(svc_dt_to) as svc_dt_to,
        max(svc_typ) as svc_typ,
        max(med_cd) as med_cd,
        max(rev_cd) as rev_cd,
        max(svc_itm_ln_ordr) as svc_itm_ln_ordr
    from stg_irmsods__retro_dme_stgng_que_dtl
    group by trns_id, src_clm_key
),

-- Create trns_revenue_dme_rpt_t
trns_revenue_dme_rpt as (
    select
        tr.*,
        coalesce(h.src_clm_seq_num, m.src_clm_seq_num) as clm_seq_num,
        coalesce(h.svc_dt_from, m.svc_dt_from) as dos_from,
        coalesce(h.svc_dt_to, m.svc_dt_to) as dos_to,
        coalesce(h.svc_typ, m.svc_typ) as line_svc_typ,
        coalesce(h.med_cd, m.med_cd) as med_cd,
        coalesce(h.rev_cd, m.rev_cd) as rev_cd,
        coalesce(h.svc_itm_ln_ordr, m.svc_itm_ln_ordr) as line_num
    from trns_revenue_dme_stg tr
    left join retro_dme_stgng_que_dtl_data h on h.trns_id = tr.grp_trns_id and h.src_clm_key = tr.final_curr_clm_key
    left join retro_dme_stgng_que_dtl_data m on m.trns_id = tr.grp_trns_id and m.src_clm_key = tr.glbl_mpng_cd
),

-- Get business entity names
be_name_data as (
    select
        bus_ent_id,
        bus_ent_nm
    from stg_irmsods__bus_ent
),

-- Final result with proper date handling
final as (
    select
        t.be_id,
        be.bus_ent_nm as be_name,
        t.ae_id,
        ae.bus_ent_nm as ae_name,
        t.employer,
        t.claim_num,
        t.wc_claim_id,
        t.patient_name,
        t.soj,
        t.dos_from::date as dos_from,
        t.dos_to::date as dos_to,
        t.injury_dt::date as injury_dt,
        t.po_svc_typ,
        t.line_svc_typ,
        t.line_num,
        coalesce(t.med_cd, t.rev_cd) as proc_cd,
        t.src_syst_cd,
        t.lob,
        t.revenue_typ,
        t.reason_typ,
        t.mic_bill_id,
        t.final_curr_clm_key as extrnl_inv_id,
        t.glbl_mpng_cd as irms_rcvbl_num,
        t.acctg_period,
        coalesce(t.final_inv_blld_dt, t.final_acctg_dte)::date as billed_date,
        t.acctg_dt::date as accntng_dt,
        t.clm_seq_num,
        sum(t.trns_amnt) as invoice_total,
        coalesce(t.final_rcvbl_po_id, t.po_id) as po_id,
        t.gl_accnt,
        t.final_ns_class_desc as ns_class_desc
    from trns_revenue_dme_rpt t
    left join be_name_data be on t.be_id = be.bus_ent_id
    left join be_name_data ae on t.ae_id = ae.bus_ent_id
    group by
        t.be_id,
        be.bus_ent_nm,
        t.ae_id,
        ae.bus_ent_nm,
        t.employer,
        t.claim_num,
        t.wc_claim_id,
        t.patient_name,
        t.soj,
        t.dos_from::date,
        t.dos_to::date,
        t.injury_dt::date,
        t.po_svc_typ,
        t.line_svc_typ,
        t.line_num,
        coalesce(t.med_cd, t.rev_cd),
        t.src_syst_cd,
        t.lob,
        t.revenue_typ,
        t.reason_typ,
        t.mic_bill_id,
        t.final_curr_clm_key,
        t.glbl_mpng_cd,
        t.acctg_period,
        coalesce(t.final_inv_blld_dt, t.final_acctg_dte)::date,
        t.acctg_dt::date,
        t.clm_seq_num,
        coalesce(t.final_rcvbl_po_id, t.po_id),
        t.gl_accnt,
        t.final_ns_class_desc
)

select * from final