with source as (
    select * from {{ source('cvtdwapricusrptng', 'retro_par_pymt_v') }}
),

renamed as (
    select
        book_to_client,
        bill_to_client,
        client_acro,
        po_id,
        mcps_bill_id,
        client_claim_num,
        adjustment_indc,
        client_check_date,
        client_check_number,
        deposit_date,
        ar_paid_date,
        echo_process_date,
        echo_approval_date,
        echo_check_date,
        echo_check_number,
        echo_check_payee,
        triton_check_date,
        ar_tat_days,
        full_tat_days,
        triton_tat_days,
        calculated_tat_days,
        deposit_dt_key,
        ham_upld_dt,
        acctg_yr_month_num,
        dw_created_dt,
        dw_updated_dt
    from source
)

select * from renamed