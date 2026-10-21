WITH source AS (SELECT * FROM {{ source('anlyssandboxcovtemp','client_config_map_v2')}}),

     renamed AS (SELECT contract_source,
                        ae_id,
                        ae_char,
                        product_decision,
                        product_intent
                 FROM source)
select *
from renamed