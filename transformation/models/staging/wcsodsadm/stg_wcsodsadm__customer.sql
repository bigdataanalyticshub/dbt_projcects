with source as (

    select * from {{ source('wcsodsadm', 'customer') }}

),

renamed as (

    select
        customer_id,
        customer_name,
        site_code,
        customer_database,
        server_name,
        is_active,
        is_self_hosted,
        is_from_smart_advisor,
        is_loaded_daily,
        use_for_reporting,
        include_in_industry,
        copy_to_qa_flag,
        is_data_deleted,
        data_deleted_date

    from source

)

select * from renamed