with source as (

    select * from {{ source('dwctsref', 'prospective_pos_ref') }}

),

renamed as (

    select
        service_category,
        service_line,
        pos_code,
        pos_description

    from source

)

select * from renamed