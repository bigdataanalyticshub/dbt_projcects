with source as (select * from {{ source('cvtdwpporptng', 'prv_basedata_provider_part_class') }}),
     renamed as (SELECT bdpc_prv_id,
                        bdpc_directory_flag,
                        bdpc_effective_date,
                        bdpc_term_date,
                        bdpc_location_specific,
                        bdpc_loc_id,
                        bdpc_prod_id,
                        bdpc_prod_pcl_id,
                        bdpc_prod_prtcpt_class_cd,
                        bdpc_rate_pointer,
                        bdpc_rate_type,
                        bdpc_target_rate_code,
                        bdpc_tax_id,
                        dw_bdpc_row_id,
                        dw_created_dt,
                        dw_updated_dt
                 FROM source)
select *
from renamed