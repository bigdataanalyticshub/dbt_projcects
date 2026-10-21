with source as (select *
                from {{ source('cvtdwcommon', 'ntwrk_prodt_rptng_usr_src') }}),

     renamed as (SELECT dw_updated_dt,
                        mcps_prodt_cd,
                        dw_updated_by,
                        dw_created_dt,
                        dw_ntwrk_prodt_rptng_row_id,
                        ntwrk_prodt_rptng_desc,
                        comnt,
                        ntwrk_cd,
                        ntwrk_rptng_class_desc,
                        ntwrk_rptng_type,
                        ntwrk_src_type_desc
                 FROM source)
select *
from renamed