-- Adaptive version metadata (actuals vs plan versions, folders, plan windows).
-- One row per version id. Reference dimension (facts carry scenario directly).
with source as (
    select * from {{ source('adaptive', 'adaptive_versions_raw') }}
),

renamed as (
    select
        id            as version_id,
        name          as version_name,
        shortname     as version_short_name,
        type          as version_type,
        description   as version_description,
        isdefaultversion  as is_default_version,
        islocked          as is_locked,
        isvirtual         as is_virtual,
        ispredictive      as is_predictive,
        isfolder          as is_folder,
        version_path,
        startplan     as start_plan,
        endplan       as end_plan,
        load_timestamp as load_ts
    from source
)

select * from renamed
